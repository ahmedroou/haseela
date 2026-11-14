import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'design.dart';
import 'domain.dart';
import 'forms.dart';
import 'screens.dart';
import 'store.dart';

void openFinancePage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: motion(context, 240),
      reverseTransitionDuration: motion(context, 200),
      pageBuilder: (_, a, b) => page,
      transitionsBuilder: (_, a, b, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.02, .025),
            end: Offset.zero,
          ).animate(a),
          child: child,
        ),
      ),
    ),
  );
}

Future<void> receiptSheet(
  BuildContext context,
  AppStore store, {
  ProfitReceipt? receipt,
}) async {
  final saved = await openSheet<bool>(
    context,
    _AmountForm(
      fieldKey: 'received_profit',
      amount: receipt?.amount,
      note: receipt?.note,
      title: receipt == null ? 'تسجيل أرباح مستلمة' : 'تعديل المبلغ المستلم',
      subtitle: 'تزيد الأرباح المحققة، وتُخصم من المتوقع المتبقي.',
      amountLabel: 'الربح الذي استلمتِه',
      noteHint: 'مثلًا: أرباح دفعة سبتمبر',
      onSave: (amount, note) => store.mutate(
        () => store.database.saveReceipt(
          amount,
          note.isEmpty ? 'أرباح مستلمة' : note,
          old: receipt,
        ),
      ),
    ),
  );
  if (saved == true && context.mounted) {
    notice(
      context,
      receipt == null
          ? 'سُجّلت الأرباح المستلمة وتحدّث التقرير ✨'
          : 'تم حفظ المبلغ وتحديث التقرير',
    );
  }
}

Future<void> sideCostSheet(
  BuildContext context,
  AppStore store, {
  SideCost? cost,
}) async {
  final saved = await openSheet<bool>(
    context,
    _AmountForm(
      fieldKey: 'side_cost',
      amount: cost?.amount,
      note: cost?.note,
      title: cost == null ? 'إضافة تكلفة جانبية' : 'تعديل تكلفة جانبية',
      subtitle: 'تُضاف إلى المنفق وتُخصم من الربح المتوقع المتبقي.',
      amountLabel: 'مبلغ التكلفة',
      noteHint: 'مثل الشحن أو التغليف',
      onSave: (amount, note) => store.mutate(
        () => store.database.saveSideCost(amount, note, old: cost),
      ),
    ),
  );
  if (saved == true && context.mounted) {
    notice(context, 'حُفظت التكلفة وتحدّث التقرير');
  }
}

class _AmountForm extends StatefulWidget {
  const _AmountForm({
    required this.fieldKey,
    required this.amount,
    required this.note,
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.noteHint,
    required this.onSave,
  });
  final int? amount;
  final String? note;
  final String fieldKey, title, subtitle, amountLabel, noteHint;
  final Future<void> Function(int amount, String note) onSave;
  @override
  State<_AmountForm> createState() => _AmountFormState();
}

class _AmountFormState extends State<_AmountForm> {
  final key = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.amount == null ? '' : moneyInput(widget.amount!),
  );
  late final note = TextEditingController(text: widget.note ?? '');
  bool saving = false;
  String? error;
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !key.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(parseMoney(amount.text)!, note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: widget.title,
    subtitle: widget.subtitle,
    saving: saving,
    save: save,
    child: Form(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          completeTextField(
            key: ValueKey('${widget.fieldKey}_amount'),
            controller: amount,
            enabled: !saving,
            validator: (v) => (parseMoney(v ?? '') ?? 0) > 0
                ? null
                : 'أدخلي مبلغًا أكبر من صفر',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            inputFormatters: [numberInputFormatter],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: widget.amountLabel,
              suffixIcon: currencySuffix,
            ),
          ),
          const SizedBox(height: 16),
          completeTextField(
            key: ValueKey('${widget.fieldKey}_note'),
            controller: note,
            enabled: !saving,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: 'ملاحظة اختيارية',
              hintText: widget.noteHint,
              counterText: '',
            ),
          ),
          if (error != null) FormErrorText(error!),
        ],
      ),
    ),
  );
}

class ReceiptHistoryPage extends StatelessWidget {
  const ReceiptHistoryPage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('الأرباح المستلمة'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: store.busy ? null : () => receiptSheet(context, store),
        icon: const Icon(Icons.add_rounded),
        label: const Text('تسجيل أرباح'),
      ),
      body: PagedList<ProfitReceipt>(
        id: (r) => r.id,
        revision: store.revision,
        load: (offset, limit) =>
            store.database.receipts(offset: offset, limit: limit),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'إجمالي ما استلمتِه',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Flexible(
                child: MoneyLine(
                  store.report.realizedProfit,
                  size: 23,
                  color: sage,
                ),
              ),
            ],
          ),
        ),
        empty: EmptyState(
          title: 'لم تُسجّلي أرباحًا مستلمة بعد',
          subtitle: 'سجّلي ما استلمتِه فعلًا ليظهر كمحقق.',
          icon: Icons.savings_outlined,
          button: 'تسجيل أرباح',
          action: () => receiptSheet(context, store),
        ),
        item: (receipt) => _AmountTile(
          key: ValueKey(receipt.id),
          title: receipt.note,
          amount: receipt.amount,
          createdAt: receipt.createdAt,
          color: sage,
          onEdit: () => receiptSheet(context, store, receipt: receipt),
          deleteTitle: 'حذف المبلغ المستلم؟',
          deleteDetail:
              'سيُحذف ${moneyText(receipt.amount)} ريال من المحقق، ويعود إلى الربح المتوقع المتبقي.',
          onDelete: () =>
              store.mutate(() => store.database.deleteReceipt(receipt.id)),
        ),
      ),
    ),
  );
}

class SideCostsPage extends StatelessWidget {
  const SideCostsPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('التكاليف الجانبية'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add_side_cost_from_history'),
        onPressed: store.busy ? null : () => sideCostSheet(context, store),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة تكلفة'),
      ),
      body: PagedList<SideCost>(
        id: (cost) => cost.id,
        revision: store.revision,
        load: (offset, limit) =>
            store.database.sideCosts(offset: offset, limit: limit),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'إجمالي التكاليف الجانبية',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Flexible(child: MoneyLine(store.report.sideCosts, size: 23)),
            ],
          ),
        ),
        empty: const EmptyState(
          title: 'لا توجد تكاليف جانبية مسجّلة',
          subtitle: 'أضيفي مصاريف مثل الشحن أو التغليف.',
          icon: Icons.payments_outlined,
        ),
        item: (cost) => _AmountTile(
          key: ValueKey(cost.id),
          title: cost.note.isEmpty ? 'تكلفة جانبية' : cost.note,
          amount: cost.amount,
          createdAt: cost.createdAt,
          onEdit: () => sideCostSheet(context, store, cost: cost),
          deleteTitle: 'حذف التكلفة الجانبية؟',
          deleteDetail:
              'سيُخصم ${moneyText(cost.amount)} ريال من المنفق ويُضاف إلى الربح المتوقع المتبقي.',
          onDelete: () =>
              store.mutate(() => store.database.deleteSideCost(cost.id)),
        ),
      ),
    ),
  );
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    super.key,
    required this.title,
    required this.amount,
    required this.createdAt,
    required this.onEdit,
    required this.deleteTitle,
    required this.deleteDetail,
    required this.onDelete,
    this.color,
  });
  final String title, deleteTitle, deleteDetail;
  final int amount, createdAt;
  final Future<void> Function() onEdit, onDelete;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Deletable(
      child: (remove) => Pressable(
        onTap: onEdit,
        child: SurfaceCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      shortDate(createdAt),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: MoneyLine(
                  amount,
                  size: 17,
                  animated: false,
                  color: color,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'خيارات المبلغ',
                icon: const Icon(Icons.more_horiz_rounded, size: 19),
                onSelected: (value) async {
                  if (value == 'edit') {
                    await onEdit();
                  } else if (await confirm(
                    context,
                    deleteTitle,
                    deleteDetail,
                  )) {
                    if (!context.mounted) return;
                    await remove(onDelete);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class RefundHistoryPage extends StatelessWidget {
  const RefundHistoryPage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('المفترض استرداده'),
        ),
      ),
      body: PagedList<PurchaseOrder>(
        id: (o) => o.id,
        revision: store.revision,
        load: (offset, limit) =>
            store.database.cancelledOrders(offset: offset, limit: limit),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${store.report.cancelled} طلب ملغي · جميع الحسابات',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: MoneyLine(store.report.refund, size: 19, color: rose),
              ),
            ],
          ),
        ),
        empty: const EmptyState(
          title: 'لا توجد مبالغ لاستردادها',
          subtitle: 'طلباتك الملغية ستظهر هنا مع مبلغ كل طلب.',
          icon: Icons.undo_rounded,
        ),
        item: (order) => Padding(
          key: ValueKey(order.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: Pressable(
            onTap: () =>
                orderSheet(context, store, order.accountId, order: order),
            child: SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.productName,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(fontSize: 13),
                        ),
                        Text(
                          order.accountName ?? '',
                          textDirection:
                              RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(order.accountName ?? '')
                              ? TextDirection.ltr
                              : null,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                        Text(
                          '${order.quantity} قطعة · ${DateFormat('d/M/yyyy').format(DateTime.fromMillisecondsSinceEpoch(order.createdAt))}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 108,
                    child: MoneyLine(
                      order.cost,
                      size: 16,
                      animated: false,
                      color: rose,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_left_rounded, size: 16, color: rose),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
