import 'package:flutter/material.dart';

import 'design.dart';
import 'domain.dart';
import 'forms.dart';
import 'period_report.dart';
import 'screens.dart' show shortDate;
import 'store.dart';

class PeriodArchivesPage extends StatefulWidget {
  const PeriodArchivesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<PeriodArchivesPage> createState() => _PeriodArchivesPageState();
}

class _PeriodArchivesPageState extends State<PeriodArchivesPage> {
  late Future<List<PeriodArchiveInfo>> periods = widget.store.database
      .periodArchives();

  void refresh() {
    final next = widget.store.database.periodArchives();
    setState(() {
      periods = next;
    });
  }

  Future<void> closePeriod() async {
    final closed = await openSheet<bool>(
      context,
      _ClosePeriodSheet(store: widget.store),
    );
    if (!mounted || closed != true) return;
    refresh();
    notice(context, 'تم إنهاء الفترة وحفظها في الأرشيف');
  }

  Future<void> openPeriod(PeriodArchiveInfo info) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ArchivedPeriodPage(store: widget.store, info: info),
      ),
    );
    if (!mounted || restored != true) return;
    refresh();
    notice(context, 'تمت استعادة الفترة إلى السجل الحالي');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('أرشيف الفترات')),
    body: SafeArea(
      child: FutureBuilder<List<PeriodArchiveInfo>>(
        future: periods,
        builder: (context, state) {
          final list = state.data ?? const <PeriodArchiveInfo>[];
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: 1 + (list.isEmpty ? 1 : list.length),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return FilledButton.icon(
                  key: const ValueKey('close_period'),
                  onPressed: closePeriod,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('إنهاء فترة'),
                );
              }
              if (list.isEmpty) {
                if (state.hasError) {
                  return TextButton(
                    onPressed: refresh,
                    child: const Text('إعادة تحميل الأرشيف'),
                  );
                }
                if (state.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'لا توجد فترات محفوظة',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              final info = list[index - 1];
              return SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: ListTile(
                  key: ValueKey('archived_period_${info.id}'),
                  dense: true,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: softTint(context, lilac, .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 19,
                      color: lilac,
                    ),
                  ),
                  title: Text(
                    info.name,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  subtitle: Text(
                    [
                      if (info.range != info.name) info.range,
                      'أُغلقت ${shortDate(info.closedAt)}',
                    ].join(' · '),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => openPeriod(info),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

enum _CloseMode { all, date, account }

class _ClosePeriodSheet extends StatefulWidget {
  const _ClosePeriodSheet({required this.store});

  final AppStore store;

  @override
  State<_ClosePeriodSheet> createState() => _ClosePeriodSheetState();
}

class _ClosePeriodSheetState extends State<_ClosePeriodSheet> {
  final name = TextEditingController();
  _CloseMode mode = _CloseMode.all;
  late DateTime date = DateUtils.dateOnly(DateTime.now());
  Account? account;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'آخر يوم في الفترة',
    );
    if (mounted && value != null) setState(() => date = value);
  }

  Future<void> chooseAccount() async {
    final value = await openSheet<Account>(
      context,
      PeriodAccountPicker(store: widget.store, title: 'آخر حساب في الفترة'),
    );
    if (mounted && value != null) {
      setState(() {
        account = value;
        error = null;
      });
    }
  }

  Future<void> save() async {
    if (saving) return;
    if (mode == _CloseMode.account && account == null) {
      setState(() => error = 'اختاري آخر حساب في الفترة');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.mutate(
        () => widget.store.database.closePeriod(
          name: name.text,
          throughDate: mode == _CloseMode.date ? date : null,
          throughAccountId: mode == _CloseMode.account ? account!.id : null,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = friendlyError(failure);
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'إنهاء فترة',
    subtitle: 'تُنقل البيانات المحددة إلى الأرشيف، ويمكن استعادتها في أي وقت.',
    button: 'حفظ في الأرشيف',
    saving: saving,
    save: save,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<_CloseMode>(
          key: const ValueKey('period_close_mode'),
          initialValue: mode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'نهاية الفترة'),
          items: const [
            DropdownMenuItem(value: _CloseMode.all, child: Text('كامل السجل')),
            DropdownMenuItem(value: _CloseMode.date, child: Text('حتى تاريخ')),
            DropdownMenuItem(
              value: _CloseMode.account,
              child: Text('حتى حساب'),
            ),
          ],
          onChanged: saving
              ? null
              : (value) => setState(() {
                  mode = value!;
                  error = null;
                }),
        ),
        if (mode != _CloseMode.all) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('period_close_boundary'),
            onPressed: saving
                ? null
                : mode == _CloseMode.date
                ? chooseDate
                : chooseAccount,
            icon: Icon(
              mode == _CloseMode.date
                  ? Icons.event_outlined
                  : Icons.folder_outlined,
            ),
            label: Text(
              mode == _CloseMode.date
                  ? shortDate(date.millisecondsSinceEpoch)
                  : account?.name ?? 'اختيار آخر حساب',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (mode == _CloseMode.account)
            Text(
              'يشمل الحساب المحدد وكل الحسابات الأقدم. تُؤرشف التكاليف والأرباح المسجّلة حتى وقت إنشاء الحساب المحدد.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('period_archive_name'),
          controller: name,
          enabled: !saving,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'اسم الفترة (اختياري)',
            counterText: '',
          ),
        ),
        if (error != null) FormErrorText(error!),
      ],
    ),
  );
}

class _ArchivedPeriodPage extends StatefulWidget {
  const _ArchivedPeriodPage({required this.store, required this.info});

  final AppStore store;
  final PeriodArchiveInfo info;

  @override
  State<_ArchivedPeriodPage> createState() => _ArchivedPeriodPageState();
}

class _ArchivedPeriodPageState extends State<_ArchivedPeriodPage> {
  late Future<ArchivedPeriod> period = widget.store.database.archivedPeriod(
    widget.info.id,
  );
  bool restoring = false;

  Future<void> restore() async {
    if (restoring) return;
    final accepted = await confirm(
      context,
      'استعادة الفترة؟',
      'ستعود بيانات «${widget.info.name}» إلى السجل الحالي مع البيانات المسجّلة فيه.',
      button: 'استعادة',
      destructive: false,
    );
    if (!mounted || !accepted || restoring) return;
    setState(() => restoring = true);
    try {
      await widget.store.mutate(
        () => widget.store.database.restorePeriod(widget.info.id),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() => restoring = false);
        notice(context, friendlyError(failure));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !restoring,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.info.name)),
      body: SafeArea(
        child: FutureBuilder<ArchivedPeriod>(
          future: period,
          builder: (context, state) {
            final archive = state.data;
            if (archive == null) {
              return Center(
                child: state.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(friendlyError(state.error!)),
                      )
                    : const CircularProgressIndicator(),
              );
            }
            return _details(context, archive);
          },
        ),
      ),
    ),
  );

  Widget _details(BuildContext context, ArchivedPeriod archive) {
    final data = archive.data;
    final report = archive.report;
    final info = archive.info;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.range != info.name) ...[
                Text(
                  info.range,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
              ],
              Text(
                '${report.orders} طلب · ${report.pieces} قطعة · ${report.accounts} حساب  (${report.pending} معلّقة · ${report.arrived} وصلت · ${report.cancelled} ملغية)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 16),
              _ArchiveAmount('إجمالي المبلغ المطلوب', report.expectedSales),
              _ArchiveAmount('إجمالي المبلغ المنفق', report.spent),
              if (report.sideCosts > 0)
                _ArchiveAmount('التكاليف الجانبية', report.sideCosts),
              if (report.realizedProfit > 0)
                _ArchiveAmount('الأرباح المحققة', report.realizedProfit),
              _ArchiveAmount('المبالغ المستردة', report.refund),
              if (report.profitShare case final share?)
                _ArchiveAmount('حصة ${share.name}', report.thirdPartyProfit),
              _ArchiveAmount('صافي الربح المتوقع', report.expectedProfit),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          child: ListTile(
            key: const ValueKey('archived_period_report'),
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: softTint(context, lilac, .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 17,
                color: lilac,
              ),
            ),
            title: const Text('تقرير الفترة'),
            trailing: const Icon(Icons.chevron_left_rounded),
            enabled: !restoring,
            onTap: () => openPeriodReport(
              context,
              widget.store,
              saved: (
                label: info.name == info.range
                    ? info.name
                    : '${info.name} · ${info.range}',
                report: PeriodReport.fromOrders(data.orders),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _entry(context, Icons.folder_outlined, 'الحسابات', data.accounts.length, (
          context,
          index,
        ) {
          final account = data.accounts[index];
          return ListTile(
            title: Text(account.name),
            subtitle: Text(
              '${account.isClosed ? 'مغلق' : 'مفتوح'} · ${shortDate(account.createdAt)}',
            ),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => _openAccount(context, account, data.orders),
          );
        }),
        _entry(
          context,
          Icons.shopping_bag_outlined,
          'المنتجات',
          data.products.length,
          (context, index) {
            final product = data.products[index];
            return _journalRow(product.name, product.createdAt, product.sale);
          },
        ),
        _entry(
          context,
          Icons.payments_outlined,
          'التكاليف الجانبية',
          data.sideCosts.length,
          (context, index) {
            final cost = data.sideCosts[index];
            return _journalRow(
              cost.note.isEmpty ? 'تكلفة جانبية' : cost.note,
              cost.createdAt,
              cost.amount,
            );
          },
          total: report.sideCosts,
        ),
        _entry(
          context,
          Icons.savings_outlined,
          'الأرباح المستلمة',
          data.receipts.length,
          (context, index) {
            final receipt = data.receipts[index];
            return _journalRow(receipt.note, receipt.createdAt, receipt.amount);
          },
          total: report.realizedProfit,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('restore_period'),
          onPressed: restoring ? null : restore,
          icon: const Icon(Icons.restore_rounded),
          label: Text(
            restoring ? 'جارٍ الاستعادة…' : 'استعادة إلى السجل الحالي',
          ),
        ),
      ],
    );
  }

  ListTile _entry(
    BuildContext context,
    IconData icon,
    String title,
    int count,
    IndexedWidgetBuilder builder, {
    int? total,
  }) => ListTile(
    leading: Icon(icon),
    title: Text('$title ($count)'),
    subtitle: total == null
        ? null
        : MoneyLine(total, size: 14, animated: false),
    trailing: const Icon(Icons.chevron_left_rounded),
    enabled: count > 0 && !restoring,
    onTap: () => _openEntries(context, title, count, builder),
  );
}

void _openEntries(
  BuildContext context,
  String title,
  int count,
  IndexedWidgetBuilder builder,
) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: count == 0
              ? const Center(child: Text('لا توجد طلبات في هذه الفترة'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: count,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: builder,
                ),
        ),
      ),
    ),
  );
}

void _openAccount(
  BuildContext context,
  Account account,
  List<PurchaseOrder> archivedOrders,
) {
  final orders =
      archivedOrders.where((order) => order.accountId == account.id).toList()
        ..sort((a, b) {
          final byDate = b.createdAt.compareTo(a.createdAt);
          return byDate == 0 ? b.id.compareTo(a.id) : byDate;
        });
  _openEntries(context, account.name, orders.length, (context, index) {
    final order = orders[index];
    return ExpansionTile(
      title: Text(order.displayName),
      subtitle: Text(
        '${order.status.label} · ${order.quantity} قطعة · ${shortDate(order.createdAt)}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in order.lines) ...[
          Text(
            '${item.productName} · ${item.quantity} قطعة',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (!item.unpriced) ...[
            _ArchiveAmount('إجمالي الشراء', item.cost),
            _ArchiveAmount('إجمالي البيع', item.revenue),
          ],
          const SizedBox(height: 6),
        ],
      ],
    );
  });
}

Widget _journalRow(String title, int date, int amount) => ListTile(
  title: Text(title),
  subtitle: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(shortDate(date)),
      MoneyLine(amount, size: 15, animated: false),
    ],
  ),
);

class _ArchiveAmount extends StatelessWidget {
  const _ArchiveAmount(this.label, this.amount);

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MoneyLine(amount, size: 17, animated: false),
          ),
        ),
      ],
    ),
  );
}
