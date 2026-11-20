import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, compute, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:intl/intl.dart' show DateFormat;

import 'design.dart';
import 'domain.dart';
import 'forms.dart';
import 'period_report_pdf.dart';
import 'screens.dart' show PagedList;
import 'store.dart';

Future<void> openPeriodReport(
  BuildContext context,
  AppStore store, {
  ({String label, PeriodReport report})? saved,
}) {
  final fromEdge = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: motion(context, 190),
    pageBuilder: (context, _, _) => LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          width: math.min(390, math.max(0, constraints.maxWidth - 18)),
          height: constraints.maxHeight,
          child: _PeriodReportPanel(store: store, saved: saved),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: Offset(fromEdge, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

enum _PeriodMode { dates, accounts }

enum _DatePreset { today, lastSevenDays, thisMonth, all }

enum _PeriodExport { pdf, share, csv }

const _reportSharing = MethodChannel('haseela/reports');

String _dateText(DateTime date) => DateFormat('yyyy/MM/dd', 'en').format(date);

class _PeriodReportPanel extends StatefulWidget {
  const _PeriodReportPanel({required this.store, required this.saved});
  final AppStore store;
  final ({String label, PeriodReport report})? saved;

  @override
  State<_PeriodReportPanel> createState() => _PeriodReportPanelState();
}

class _PeriodReportPanelState extends State<_PeriodReportPanel> {
  late DateTime endDate = DateUtils.dateOnly(DateTime.now());
  late DateTime startDate = DateTime(endDate.year, endDate.month);
  Account? startAccount, endAccount;
  _PeriodMode mode = _PeriodMode.dates;
  bool allDates = false;
  late PeriodReport? report = widget.saved?.report;
  bool generating = false, exporting = false;
  String? error, exportMessage;
  bool get busy => generating || exporting;

  void updatePeriod(VoidCallback change) {
    setState(() {
      change();
      report = null;
      error = null;
      exportMessage = null;
    });
  }

  Future<void> chooseDate({required bool start}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? startDate : endDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      helpText: start ? 'بداية الفترة' : 'نهاية الفترة',
    );
    if (!mounted || selected == null) return;
    updatePeriod(() {
      allDates = false;
      if (start) {
        startDate = selected;
        if (endDate.isBefore(startDate)) endDate = startDate;
      } else {
        endDate = selected;
        if (startDate.isAfter(endDate)) startDate = endDate;
      }
    });
  }

  void applyDatePreset(_DatePreset preset) {
    final today = DateUtils.dateOnly(DateTime.now());
    updatePeriod(() {
      allDates = preset == _DatePreset.all;
      if (allDates) return;
      endDate = today;
      startDate = switch (preset) {
        _DatePreset.lastSevenDays => DateTime(
          today.year,
          today.month,
          today.day - 6,
        ),
        _DatePreset.thisMonth => DateTime(today.year, today.month),
        _ => today,
      };
    });
  }

  Future<void> chooseAccount({required bool start}) async {
    final selected = await openSheet<Account>(
      context,
      PeriodAccountPicker(
        store: widget.store,
        title: start ? 'حساب البداية' : 'حساب النهاية',
      ),
    );
    if (!mounted || selected == null) return;
    updatePeriod(() {
      if (start) {
        startAccount = selected;
      } else {
        endAccount = selected;
      }
    });
  }

  String get periodLabel {
    final saved = widget.saved;
    if (saved != null) return saved.label;
    if (mode == _PeriodMode.dates) {
      if (allDates) return 'كامل السجل الحالي';
      return 'من ${_dateText(startDate)} إلى ${_dateText(endDate)}';
    }
    final bounds = [startAccount!, endAccount!]
      ..sort(Account.compareByCreation);
    return 'من ${bounds.first.name} إلى ${bounds.last.name}';
  }

  String get filterLabel => widget.saved != null
      ? 'فترة مؤرشفة'
      : mode == _PeriodMode.accounts
      ? 'بالحسابات'
      : allDates
      ? 'كل الطلبات'
      : 'بالتاريخ';

  Future<void> generate() async {
    if (busy) return;
    if (mode == _PeriodMode.accounts &&
        (startAccount == null || endAccount == null)) {
      setState(() => error = 'اختاري حساب البداية وحساب النهاية');
      return;
    }
    setState(() {
      generating = true;
      error = null;
      report = null;
      exportMessage = null;
    });
    try {
      final database = widget.store.database;
      final result = await (mode == _PeriodMode.accounts
          ? database.periodReportByAccounts(startAccount!.id, endAccount!.id)
          : allDates
          ? database.periodReportAll()
          : database.periodReportByDate(startDate, endDate));
      if (mounted) setState(() => report = result);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> export(PeriodReport result, _PeriodExport action) async {
    if (busy) return;
    setState(() {
      exporting = true;
      exportMessage = null;
    });
    try {
      final date = DateFormat('yyyy-MM-dd', 'en').format(DateTime.now());
      final extension = action == _PeriodExport.csv ? 'csv' : 'pdf';
      final filename = 'haseela-report-$date.$extension';
      final period = periodLabel;
      final Uint8List bytes;
      if (action == _PeriodExport.csv) {
        bytes = Uint8List.fromList(utf8.encode(result.toCsv(period)));
      } else {
        bytes = await compute(buildPeriodReportPdf, (
          report: result,
          period: period,
          filterLabel: filterLabel,
          regularFont: await rootBundle.load(
            'assets/fonts/Tajawal-Regular.ttf',
          ),
          boldFont: await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'),
        ));
      }
      if (!mounted) return;
      if (action == _PeriodExport.share) {
        await _reportSharing.invokeMethod<void>('sharePdf', {
          'name': filename,
          'bytes': bytes,
        });
        return;
      }
      final file = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ تقرير الفترة',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (mounted && file != null) {
        setState(() => exportMessage = 'تم حفظ التقرير');
      }
    } catch (failure) {
      if (mounted) setState(() => exportMessage = friendlyError(failure));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = report;
    final byDate = mode == _PeriodMode.dates;
    return Material(
      key: const ValueKey('period_report_panel'),
      color: scheme.surface,
      elevation: 10,
      shadowColor: plum.withValues(alpha: .18),
      borderRadius: const BorderRadiusDirectional.horizontal(
        start: Radius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: softTint(context, lilac, .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تقرير الفترة',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق تقرير الفترة',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.saved == null)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: softTint(context, lilac, .05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: .75,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SegmentedButton<_PeriodMode>(
                                    style: SegmentedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Tajawal',
                                      ),
                                    ),
                                    segments: const [
                                      ButtonSegment(
                                        value: _PeriodMode.dates,
                                        icon: Icon(
                                          Icons.date_range_rounded,
                                          size: 14,
                                        ),
                                        label: Text('بالتاريخ'),
                                      ),
                                      ButtonSegment(
                                        value: _PeriodMode.accounts,
                                        icon: Icon(
                                          Icons.folder_open_rounded,
                                          size: 14,
                                        ),
                                        label: Text('بالحسابات'),
                                      ),
                                    ],
                                    selected: {mode},
                                    showSelectedIcon: false,
                                    onSelectionChanged: busy
                                        ? null
                                        : (values) => updatePeriod(
                                            () => mode = values.single,
                                          ),
                                  ),
                                  if (byDate) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        _presetChip('اليوم', _DatePreset.today),
                                        _presetChip(
                                          '٧ أيام',
                                          _DatePreset.lastSevenDays,
                                        ),
                                        _presetChip(
                                          'هذا الشهر',
                                          _DatePreset.thisMonth,
                                        ),
                                        _presetChip('الكل', _DatePreset.all),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _periodField(
                                          start: true,
                                          byDate: byDate,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _periodField(
                                          start: false,
                                          byDate: byDate,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    key: const ValueKey(
                                      'generate_period_report',
                                    ),
                                    onPressed: busy ? null : generate,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(38),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                    ),
                                    icon: generating
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.analytics_outlined,
                                            size: 16,
                                          ),
                                    label: Text(
                                      generating
                                          ? 'جارٍ إنشاء التقرير…'
                                          : 'إنشاء التقرير',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  if (error != null) FormErrorText(error!),
                                ],
                              ),
                            ),
                          if (result != null) ...[
                            if (widget.saved == null) const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                              decoration: BoxDecoration(
                                color: softTint(context, rose, .06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: .7,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    periodLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (result.items.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        'لا توجد أصناف في هذه الفترة',
                                      ),
                                    )
                                  else ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'إجمالي المبلغ المطلوب',
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(fontSize: 12.5),
                                            ),
                                            const SizedBox(width: 6),
                                            MoneyLine(
                                              result.amount,
                                              size: 17,
                                              animated: false,
                                            ),
                                          ],
                                        ),
                                        Wrap(
                                          spacing: 5,
                                          children: [
                                            _statPill(
                                              context,
                                              '${result.items.length} صنف',
                                              lilac,
                                            ),
                                            _statPill(
                                              context,
                                              '${result.quantity} قطعة',
                                              sage,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 5,
                                    runSpacing: 4,
                                    children: [
                                      FilledButton.tonalIcon(
                                        key: const ValueKey('save_period_pdf'),
                                        onPressed: busy
                                            ? null
                                            : () => export(
                                                result,
                                                _PeriodExport.pdf,
                                              ),
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.picture_as_pdf_outlined,
                                          size: 15,
                                        ),
                                        label: const Text(
                                          'حفظ PDF',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      if (defaultTargetPlatform ==
                                          TargetPlatform.android)
                                        OutlinedButton.icon(
                                          key: const ValueKey(
                                            'share_period_pdf',
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () => export(
                                                  result,
                                                  _PeriodExport.share,
                                                ),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 5,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.share_outlined,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'مشاركة PDF',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      TextButton.icon(
                                        key: const ValueKey('save_period_csv'),
                                        onPressed: busy
                                            ? null
                                            : () => export(
                                                result,
                                                _PeriodExport.csv,
                                              ),
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 5,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.table_chart_outlined,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'حفظ CSV',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (exporting) ...[
                                    const SizedBox(height: 6),
                                    const LinearProgressIndicator(),
                                  ],
                                  if (exportMessage != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      exportMessage!,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (result.items.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              const _ReportRow(),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (result != null && result.items.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      sliver: SliverList.builder(
                        itemCount: result.items.length,
                        itemBuilder: (context, index) =>
                            _ReportRow(item: result.items[index], index: index),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, _DatePreset preset) => ActionChip(
    label: Text(label, style: const TextStyle(fontSize: 10.5)),
    visualDensity: const VisualDensity(horizontal: -3, vertical: -4),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    onPressed: busy ? null : () => applyDatePreset(preset),
  );

  Widget _statPill(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: softTint(context, color, .13),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).brightness == Brightness.dark
            ? Color.lerp(color, Colors.white, .3)
            : color,
      ),
    ),
  );

  Widget _periodField({required bool start, required bool byDate}) {
    final account = start ? startAccount : endAccount;
    final value = byDate
        ? allDates
              ? (start ? 'أول طلب' : 'آخر طلب')
              : _dateText(start ? startDate : endDate)
        : account?.name ?? 'اختاري حسابًا';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          start ? 'من' : 'إلى',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        OutlinedButton(
          key: ValueKey(start ? 'period_start' : 'period_end'),
          onPressed: busy
              ? null
              : () => byDate
                    ? chooseDate(start: start)
                    : chooseAccount(start: start),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size.fromHeight(34),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: byDate && !allDates ? TextDirection.ltr : null,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({this.item, this.index = 0});
  final PeriodReportItem? item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final row = item;
    final amount = row?.amount;
    final theme = Theme.of(context);
    final style = row == null
        ? theme.textTheme.titleSmall?.copyWith(fontSize: 11.5)
        : theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5);
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: row == null
            ? softTint(context, lilac, .12)
            : index.isEven
            ? softTint(context, lilac, .04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(row?.name ?? 'الصنف', style: style)),
          Expanded(
            flex: 2,
            child: Text(
              row == null ? 'العدد' : '${row.quantity}',
              style: style?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: row == null
                  ? Text('المبلغ (ريال)', style: style)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        amount == null ? '—' : moneyText(amount),
                        style: style?.copyWith(fontWeight: FontWeight.w700),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class PeriodAccountPicker extends StatefulWidget {
  const PeriodAccountPicker({
    super.key,
    required this.store,
    required this.title,
  });
  final AppStore store;
  final String title;

  @override
  State<PeriodAccountPicker> createState() => _ReportAccountPickerState();
}

class _ReportAccountPickerState extends State<PeriodAccountPicker> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * .6 - keyboard * .5).clamp(
          160,
          440,
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق اختيار الحساب',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey('period_account_search'),
                onChanged: (value) => setState(() => search = value),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'بحث باسم الحساب',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, size: 17),
                  prefixIconConstraints: BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: PagedList<Account>(
                  revision: widget.store.revision,
                  queryKey: search,
                  id: (account) => account.id,
                  load: (offset, limit) => widget.store.database.accounts(
                    search: search,
                    offset: offset,
                    limit: limit,
                  ),
                  padding: EdgeInsets.zero,
                  header: const SizedBox.shrink(),
                  empty: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('لا توجد حسابات مطابقة'),
                  ),
                  item: (account) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: InkWell(
                      key: ValueKey('period_account_${account.id}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, account),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: softTint(context, lilac, .05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: .7),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              account.isClosed
                                  ? Icons.lock_outline_rounded
                                  : account.isEmail
                                  ? Icons.alternate_email_rounded
                                  : Icons.folder_open_rounded,
                              size: 16,
                              color: account.isClosed
                                  ? scheme.onSurfaceVariant
                                  : lilac,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.name,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${account.orderCount} طلب · ${_dateText(DateTime.fromMillisecondsSinceEpoch(account.createdAt))}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (account.isClosed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: .5,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  'مغلق',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
