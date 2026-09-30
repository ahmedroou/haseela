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
    ReceiptForm(store: store, receipt: receipt),
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

class ReceiptForm extends StatefulWidget {
  const ReceiptForm({super.key, required this.store, this.receipt});
  final AppStore store;
  final ProfitReceipt? receipt;
  @override
  State<ReceiptForm> createState() => _ReceiptFormState();
}

class _ReceiptFormState extends State<ReceiptForm> {
  final key = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.receipt == null ? '' : moneyInput(widget.receipt!.amount),
  );
  late final note = TextEditingController(text: widget.receipt?.note ?? '');
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
      await widget.store.mutate(
        () => widget.store.database.saveReceipt(
          parseMoney(amount.text)!,
          note.text.trim().isEmpty ? 'أرباح مستلمة' : note.text,
          old: widget.receipt,
        ),
      );
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
    title: widget.receipt == null
        ? 'تسجيل أرباح مستلمة'
        : 'تعديل المبلغ المستلم',
    subtitle: 'تزيد الأرباح المحققة، وتُخصم من المتوقع المتبقي.',
    saving: saving,
    save: save,
    child: Form(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          completeTextField(
            key: const ValueKey('received_profit_amount'),
            controller: amount,
            enabled: !saving,
            validator: (v) =>
                parseMoney(v ?? '') == null || parseMoney(v ?? '') == 0
                ? 'أدخلي مبلغًا أكبر من صفر'
                : null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            inputFormatters: [numberInputFormatter],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'الربح الذي استلمتِه',
              suffixIcon: currencySuffix,
            ),
          ),
          const SizedBox(height: 16),
          completeTextField(
            key: const ValueKey('received_profit_note'),
            controller: note,
            enabled: !saving,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'ملاحظة اختيارية',
              hintText: 'مثلًا: أرباح دفعة سبتمبر',
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
        item: (receipt) => Padding(
          key: ValueKey(receipt.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: Deletable(
            child: (remove) => Pressable(
              onTap: () => receiptSheet(context, store, receipt: receipt),
              child: SurfaceCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receipt.note,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            shortDate(receipt.createdAt),
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
                        receipt.amount,
                        size: 17,
                        animated: false,
                        color: sage,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات المبلغ',
                      icon: const Icon(Icons.more_horiz_rounded, size: 19),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          await receiptSheet(context, store, receipt: receipt);
                        } else if (await confirm(
                          context,
                          'حذف المبلغ المستلم؟',
                          'سيُحذف ${moneyText(receipt.amount)} ريال من المحقق، ويعود إلى الربح المتوقع المتبقي.',
                        )) {
                          if (!context.mounted) return;
                          await remove(
                            () => store.mutate(
                              () => store.database.deleteReceipt(receipt.id),
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('تعديل'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('حذف'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
