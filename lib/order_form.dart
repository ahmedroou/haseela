import 'package:flutter/material.dart';
import 'design.dart';
import 'domain.dart';
import 'forms.dart';
import 'store.dart';

class OrderForm extends StatefulWidget {
  const OrderForm({
    super.key,
    required this.store,
    required this.accountId,
    this.order,
  });
  final AppStore store;
  final int accountId;
  final PurchaseOrder? order;
  @override
  State<OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<OrderForm> {
  final key = GlobalKey<FormState>();
  late final quantity = TextEditingController(
    text: widget.order?.quantity.toString() ?? '1',
  );
  late bool totalMode = widget.order?.purchaseTotal != null;
  late final purchase = TextEditingController(
    text: widget.order == null
        ? ''
        : moneyInput(totalMode ? widget.order!.cost : widget.order!.purchase),
  );
  late final sale = TextEditingController(
    text: widget.order == null ? '' : moneyInput(widget.order!.sale),
  );
  late final snapshotName = TextEditingController(
    text: widget.order?.productName ?? '',
  );
  late int? productId = widget.order?.productId;
  late OrderStatus status = widget.order?.status ?? OrderStatus.pending;
  int? preservedTotal, preservedQuantity, lastPurchase;
  bool saving = false, converting = false;
  String? error;
  int get count => parseQuantity(quantity.text) ?? 0;
  int get entered => parseMoney(purchase.text) ?? 0;
  int get cost => totalMode
      ? entered
      : preservedTotal != null && preservedQuantity == count
      ? preservedTotal!
      : entered * count;
  int get unit =>
      totalMode && count > 0 ? unitFromTotal(entered, count) : entered;

  @override
  void initState() {
    super.initState();
    quantity.addListener(recalculate);
    sale.addListener(recalculate);
    purchase.addListener(purchaseChanged);
  }

  void recalculate() {
    if (mounted) setState(() {});
  }

  void purchaseChanged() {
    if (!converting) preservedTotal = null;
    recalculate();
  }

  @override
  void dispose() {
    for (final c in [quantity, purchase, sale, snapshotName]) {
      c.dispose();
    }
    super.dispose();
  }

  void switchMode(bool value) {
    if (totalMode == value || saving) return;
    final previousCost = cost;
    final valid = parseMoney(purchase.text) != null && count > 0;
    converting = true;
    setState(() {
      totalMode = value;
      if (valid) {
        purchase.text = moneyInput(
          value ? previousCost : unitFromTotal(previousCost, count),
        );
        preservedTotal =
            value || unitFromTotal(previousCost, count) * count == previousCost
            ? null
            : previousCost;
        preservedQuantity = count;
      }
    });
    converting = false;
  }

  Future<void> selectProduct() async {
    final selected = await openSheet<Product>(
      context,
      ProductPicker(store: widget.store),
    );
    if (selected == null || !mounted) return;
    // Fetch the saved value, including purchase memory, rather than a stale tile.
    Product? product;
    try {
      product = await widget.store.database.product(selected.id);
    } catch (e) {
      if (mounted) notice(context, friendlyError(e));
      return;
    }
    if (!mounted || product == null) return;
    final p = product;
    setState(() {
      productId = p.id;
      snapshotName.text = p.name;
      sale.text = moneyInput(p.sale);
      lastPurchase = p.lastPurchase;
      preservedTotal = null;
      purchase.text = p.lastPurchase == null
          ? ''
          : moneyInput(
              totalMode
                  ? p.lastPurchase! * (count > 0 ? count : 1)
                  : p.lastPurchase!,
            );
    });
  }

  Future<void> save() async {
    if (saving || !key.currentState!.validate()) return;
    if (snapshotName.text.trim().isEmpty) {
      setState(() => error = 'اختاري المنتج أولًا');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.mutate(
        () => widget.store.database.saveOrder(
          accountId: widget.accountId,
          productId: productId,
          productName: snapshotName.text,
          quantity: count,
          purchase: unit,
          purchaseTotal:
              totalMode || preservedTotal != null && preservedQuantity == count
              ? cost
              : null,
          sale: parseMoney(sale.text)!,
          status: status,
          old: widget.order,
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
  Widget build(BuildContext context) {
    final revenue = (parseMoney(sale.text) ?? 0) * count;
    final profit = status == OrderStatus.cancelled ? 0 : revenue - cost;
    final approximate = count > 0 && cost != unit * count;
    return _CompactFrame(
      title: widget.order == null ? 'طلب جديد' : 'تعديل الطلب',
      saving: saving,
      save: save,
      child: Form(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Pressable(
              key: const ValueKey('order_product_picker'),
              onTap: saving ? null : selectProduct,
              child: SurfaceCard(
                color: softTint(context, lilac, .07),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      color: lilac,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: widget.order == null
                          ? Text(
                              snapshotName.text.isEmpty
                                  ? 'اختاري من قائمة المنتجات'
                                  : snapshotName.text,
                              style: Theme.of(context).textTheme.titleSmall,
                            )
                          : TextFormField(
                              controller: snapshotName,
                              validator: nameValidator,
                              enabled: !saving,
                              maxLength: 120,
                              maxLines: null,
                              style: Theme.of(context).textTheme.titleSmall,
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                hintText: 'اسم المنتج',
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: lilac,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: completeTextField(
                    key: const ValueKey('order_quantity'),
                    controller: quantity,
                    compact: true,
                    enabled: !saving,
                    validator: (v) =>
                        parseQuantity(v ?? '') == null ? 'كمية صحيحة' : null,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [numberInputFormatter],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'الكمية'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: completeTextField(
                    key: const ValueKey('order_sale'),
                    controller: sale,
                    compact: true,
                    enabled: !saving,
                    validator: priceValidator,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textDirection: TextDirection.ltr,
                    inputFormatters: [numberInputFormatter],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'بيع الوحدة',
                      suffixIcon: _currency,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _mode('شراء الوحدة', false),
                _mode('إجمالي شراء الكمية', true),
              ],
            ),
            const SizedBox(height: 5),
            completeTextField(
              key: const ValueKey('order_purchase'),
              controller: purchase,
              compact: true,
              enabled: !saving,
              validator: priceValidator,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              inputFormatters: [numberInputFormatter],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                labelText: totalMode
                    ? 'ما دفعتِه للكمية كاملة'
                    : 'سعر شراء الوحدة',
                suffixIcon: _currency,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                totalMode
                    ? 'سعر الوحدة ${approximate ? '≈ ' : ''}${moneyText(unit)} ريال · الإجمالي محفوظ كما أدخلتِه'
                    : lastPurchase != null
                    ? 'آخر شراء: ${moneyText(lastPurchase!)} ريال للوحدة · يمكنك تعديله'
                    : 'سعر البيع خاص بهذا الطلب.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: OrderStatus.values
                  .map(
                    (s) => ChoiceChip(
                      label: Text(
                        s.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: status == s,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      onSelected: saving
                          ? null
                          : (_) => setState(() => status = s),
                      showCheckmark: false,
                      avatar: Icon(
                        statusIcon(s),
                        size: 15,
                        color: statusColor(s),
                      ),
                      selectedColor: softTint(context, statusColor(s), .17),
                      side: BorderSide(
                        color: status == s
                            ? statusColor(s).withValues(alpha: .3)
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (context, c) {
                final columns = MediaQuery.textScalerOf(context).scale(12) > 19
                    ? 1
                    : 3;
                final width = (c.maxWidth - (columns - 1) * 6) / columns;
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _summary('إجمالي الشراء', cost, width, lilac),
                    _summary(
                      status == OrderStatus.cancelled
                          ? 'الاسترداد'
                          : 'إجمالي البيع',
                      status == OrderStatus.cancelled ? cost : revenue,
                      width,
                      peach,
                    ),
                    _summary(
                      'ربح الطلب',
                      profit,
                      width,
                      profit < 0 ? rose : sage,
                    ),
                  ],
                );
              },
            ),
            if (error != null) FormErrorText(error!),
          ],
        ),
      ),
    );
  }

  Widget _mode(String title, bool value) => ChoiceChip(
    key: ValueKey(value ? 'purchase_total_mode' : 'purchase_unit_mode'),
    label: Text(title, style: const TextStyle(fontSize: 12)),
    selected: totalMode == value,
    onSelected: saving ? null : (_) => switchMode(value),
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    selectedColor: softTint(context, lilac, .16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
  Widget _summary(String title, int value, double width, Color color) =>
      SizedBox(
        width: width,
        child: SurfaceCard(
          color: softTint(context, color, .07),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 4),
              MoneyLine(value, size: 16, color: color, animated: false),
            ],
          ),
        ),
      );
}

const _currency = SizedBox(
  width: 36,
  child: Center(
    child: Text(
      'SAR',
      textDirection: TextDirection.ltr,
      style: TextStyle(fontSize: 10, color: lilac),
    ),
  ),
);

/// The save button stays outside the scroll region. Standard phone layouts fit
/// in one sheet; keyboard/accessibility/long names retain a safe scroll fallback.
class _CompactFrame extends StatelessWidget {
  const _CompactFrame({
    required this.title,
    required this.child,
    required this.saving,
    required this.save,
  });
  final String title;
  final Widget child;
  final bool saving;
  final VoidCallback save;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (constraints.maxHeight - keyboard).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                14 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: SingleChildScrollView(
                      key: const ValueKey('order_fields_scroll'),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    key: const ValueKey('save_form'),
                    onPressed: saving ? null : save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('حفظ الطلب'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
