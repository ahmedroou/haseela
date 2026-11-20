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

class _OrderDraft {
  _OrderDraft(OrderItem? item, VoidCallback changed) {
    quantity.text = item?.quantity.toString() ?? '1';
    totalMode = item?.purchaseTotal != null;
    purchase.text = item == null || item.unpriced
        ? ''
        : moneyInput(totalMode ? item.cost : item.purchase);
    sale.text = item == null || item.unpriced ? '' : moneyInput(item.sale);
    snapshotName.text = item?.productName ?? '';
    productId = item?.productId;
    manual = item != null && item.productId == null;
    hasPrices = item?.unpriced != true;
    quantity.addListener(changed);
    sale.addListener(changed);
    snapshotName.addListener(changed);
    purchase.addListener(() {
      if (!converting) preservedTotal = null;
      changed();
    });
  }
  final quantity = TextEditingController();
  final purchase = TextEditingController();
  final sale = TextEditingController();
  final snapshotName = TextEditingController();
  final nameFocus = FocusNode();
  int? productId;
  bool manual = false, hasPrices = true;
  bool totalMode = false, converting = false;
  int? preservedTotal, preservedQuantity, lastPurchase;
  int get count => parseQuantity(quantity.text) ?? 0;
  int get entered => parseMoney(purchase.text) ?? 0;
  int get cost => !hasPrices
      ? 0
      : totalMode
      ? entered
      : preservedTotal != null && preservedQuantity == count
      ? preservedTotal!
      : entered * count;
  int get unit =>
      totalMode && count > 0 ? unitFromTotal(entered, count) : entered;
  int get revenue => hasPrices ? (parseMoney(sale.text) ?? 0) * count : 0;
  bool get valid =>
      snapshotName.text.trim().isNotEmpty &&
      snapshotName.text.length <= 120 &&
      parseQuantity(quantity.text) != null &&
      (!hasPrices ||
          parseMoney(purchase.text) != null && parseMoney(sale.text) != null);
  OrderItem toItem() => OrderItem(
    productId: productId,
    productName: snapshotName.text,
    quantity: count,
    purchase: hasPrices ? unit : 0,
    purchaseTotal:
        hasPrices &&
            (totalMode || preservedTotal != null && preservedQuantity == count)
        ? cost
        : null,
    sale: hasPrices ? parseMoney(sale.text)! : 0,
    unpriced: !hasPrices,
  );

  void selectCatalogProduct(Product product) {
    manual = false;
    hasPrices = true;
    productId = product.id;
    snapshotName.text = product.name;
    sale.text = moneyInput(product.sale);
    lastPurchase = product.lastPurchase;
    preservedTotal = null;
    final remembered = product.lastPurchase;
    purchase.text = remembered == null
        ? ''
        : moneyInput(totalMode && count > 0 ? remembered * count : remembered);
  }

  void dispose() {
    nameFocus.dispose();
    for (final c in [quantity, purchase, sale, snapshotName]) {
      c.dispose();
    }
  }

  void switchMode(bool value) {
    if (totalMode == value) return;
    final previousCost = cost;
    final valid = parseMoney(purchase.text) != null && count > 0;
    converting = true;
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
    converting = false;
  }
}

class _OrderFormState extends State<OrderForm> {
  final key = GlobalKey<FormState>();
  final fieldsScroll = ScrollController();
  final drafts = <_OrderDraft>[];
  final removedDrafts = <_OrderDraft>[];
  int selectedIndex = 0;
  late OrderStatus status = widget.order?.status ?? OrderStatus.pending;
  bool separate = false, saving = false;
  String? error;
  _OrderDraft get draft => drafts[selectedIndex];
  TextEditingController get quantity => draft.quantity;
  TextEditingController get purchase => draft.purchase;
  TextEditingController get sale => draft.sale;
  TextEditingController get snapshotName => draft.snapshotName;
  bool get totalMode => draft.totalMode;
  int get count => draft.count;
  int get unit => draft.unit;
  int get cost => draft.cost;
  int? get lastPurchase => draft.lastPurchase;

  @override
  void initState() {
    super.initState();
    final items = widget.order?.lines;
    if (items == null) {
      drafts.add(_OrderDraft(null, recalculate));
    } else {
      drafts.addAll(items.map((item) => _OrderDraft(item, recalculate)));
    }
  }

  void recalculate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final draft in [...drafts, ...removedDrafts]) {
      draft.dispose();
    }
    fieldsScroll.dispose();
    super.dispose();
  }

  void selectDraft(int index) {
    FocusScope.of(context).unfocus();
    setState(() {
      selectedIndex = index;
      error = null;
    });
    showProductFields();
  }

  void showProductFields() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && fieldsScroll.hasClients) fieldsScroll.jumpTo(0);
    });
  }

  void removeDraft() {
    FocusScope.of(context).unfocus();
    setState(() {
      removedDrafts.add(drafts.removeAt(selectedIndex));
      selectedIndex = selectedIndex.clamp(0, drafts.length - 1);
      error = null;
    });
    showProductFields();
  }

  void switchMode(bool value) {
    if (saving) return;
    setState(() => draft.switchMode(value));
  }

  void addManualProduct() {
    setState(() {
      if (draft.productId != null || snapshotName.text.trim().isNotEmpty) {
        drafts.add(_OrderDraft(null, recalculate));
        selectedIndex = drafts.length - 1;
      }
      draft.manual = true;
      draft.hasPrices = false;
      error = null;
    });
    final manualDraft = draft;
    showProductFields();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && draft == manualDraft) manualDraft.nameFocus.requestFocus();
    });
  }

  Future<void> selectProduct({bool add = false}) async {
    FocusScope.of(context).unfocus();
    final emptyDraft =
        draft.productId == null && snapshotName.text.trim().isEmpty;
    final selected = await openSheet<List<Product>>(
      context,
      ProductPicker(store: widget.store, multiple: add || emptyDraft),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    // Refresh the price and purchase memory before applying the selection.
    final List<Product?> products;
    try {
      products = await Future.wait(
        selected.map((product) => widget.store.database.product(product.id)),
      );
      if (products.contains(null)) {
        throw StateError('أحد المنتجات المحددة لم يعد موجودًا');
      }
    } catch (e) {
      if (mounted) notice(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      final replacesCurrent = !add || emptyDraft;
      final firstAdded = replacesCurrent ? selectedIndex : drafts.length;
      for (final (index, product) in products.indexed) {
        final entry = index == 0 && replacesCurrent
            ? draft
            : _OrderDraft(null, recalculate);
        entry.selectCatalogProduct(product!);
        if (index > 0 || !replacesCurrent) drafts.add(entry);
      }
      selectedIndex = firstAdded;
      error = null;
    });
    showProductFields();
  }

  Future<void> save() async {
    if (saving) return;
    final invalid = drafts.indexWhere((draft) => !draft.valid);
    if (invalid != -1) {
      selectDraft(invalid);
      setState(
        () => error = snapshotName.text.trim().isEmpty
            ? (draft.manual ? 'اكتبي اسم المنتج' : 'اختاري المنتج أولًا')
            : 'راجعي بيانات «${snapshotName.text}»',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) key.currentState?.validate();
      });
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final route = ModalRoute.of(context);
    try {
      await widget.store.mutate(
        () => widget.store.database.saveOrders(
          accountId: widget.accountId,
          items: drafts.map((draft) => draft.toItem()).toList(),
          separate: separate && widget.order == null,
          status: status,
          old: widget.order,
        ),
      );
      if (mounted && route?.isCurrent == true) Navigator.pop(context, true);
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
    final revenue = drafts.fold(0, (sum, draft) => sum + draft.revenue);
    final totalCost = drafts.fold(0, (sum, draft) => sum + draft.cost);
    final profit = status == OrderStatus.cancelled ? 0 : revenue - totalCost;
    final approximate = count > 0 && cost != unit * count;
    final multiple = drafts.length > 1;
    final showTotals = drafts.any((draft) => draft.hasPrices);
    return CompactSheetFrame(
      title: widget.order == null ? 'طلب جديد' : 'تعديل الطلب',
      saving: saving,
      save: save,
      scrollController: fieldsScroll,
      scrollKey: const ValueKey('order_fields_scroll'),
      saveLabel: multiple && separate
          ? 'حفظ الطلبات (${drafts.length})'
          : 'حفظ الطلب',
      child: Form(
        key: key,
        child: Column(
          key: ObjectKey(draft),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (multiple) ...[
              if (widget.order == null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('orders_together'),
                      label: const Text('طلب واحد'),
                      selected: !separate,
                      onSelected: saving
                          ? null
                          : (_) => setState(() => separate = false),
                    ),
                    ChoiceChip(
                      key: const ValueKey('orders_separate'),
                      label: const Text('طلبات منفصلة'),
                      selected: separate,
                      onSelected: saving
                          ? null
                          : (_) => setState(() => separate = true),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Text(
                separate
                    ? 'كل منتج يُحفظ كطلب مستقل داخل هذا الحساب.'
                    : 'تُحفظ المنتجات في طلب واحد بحالة مشتركة.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var index = 0; index < drafts.length; index++)
                    InputChip(
                      key: ValueKey('order_item_$index'),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 210),
                        child: Text(
                          drafts[index].snapshotName.text.isEmpty
                              ? 'اختيار المنتج'
                              : drafts[index].snapshotName.text,
                        ),
                      ),
                      selected: selectedIndex == index,
                      onPressed: saving ? null : () => selectDraft(index),
                      onDeleted: saving
                          ? null
                          : () {
                              selectedIndex = index;
                              removeDraft();
                            },
                      deleteButtonTooltipMessage: 'إزالة المنتج من النموذج',
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: draft.manual
                      ? TextFormField(
                          key: const ValueKey('order_manual_name'),
                          controller: snapshotName,
                          focusNode: draft.nameFocus,
                          validator: nameValidator,
                          enabled: !saving,
                          maxLength: 120,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'اسم المنتج',
                            counterText: '',
                          ),
                        )
                      : _catalogPicker(context),
                ),
                if (draft.manual)
                  IconButton(
                    tooltip: 'اختيار من قائمة المنتجات',
                    onPressed: saving ? null : () => selectProduct(),
                    icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                  ),
                IconButton(
                  key: const ValueKey('order_add_manual_product'),
                  tooltip: 'إضافة منتج يدوي',
                  onPressed: saving ? null : addManualProduct,
                  icon: const Icon(Icons.edit_note_rounded, size: 22),
                ),
              ],
            ),
            if (draft.manual)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChip(
                  key: const ValueKey('order_manual_prices'),
                  label: const Text('إضافة أسعار'),
                  selected: draft.hasPrices,
                  onSelected: saving
                      ? null
                      : (value) => setState(() {
                          draft.hasPrices = value;
                          error = null;
                        }),
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
                if (draft.hasPrices) ...[
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
              ],
            ),
            if (draft.hasPrices) ...[
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
            ],
            const SizedBox(height: 7),
            if (multiple)
              Text(
                'حالة جميع المنتجات عند الحفظ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
            if (showTotals) ...[
              const SizedBox(height: 9),
              LayoutBuilder(
                builder: (context, c) {
                  final columns =
                      MediaQuery.textScalerOf(context).scale(12) > 19 ? 1 : 3;
                  final width = (c.maxWidth - (columns - 1) * 6) / columns;
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _summary('إجمالي الشراء', totalCost, width, lilac),
                      _summary(
                        status == OrderStatus.cancelled
                            ? 'الاسترداد'
                            : 'إجمالي البيع',
                        status == OrderStatus.cancelled ? totalCost : revenue,
                        width,
                        peach,
                      ),
                      _summary(
                        separate && multiple ? 'إجمالي الربح' : 'ربح الطلب',
                        profit,
                        width,
                        profit < 0 ? rose : sage,
                      ),
                    ],
                  );
                },
              ),
            ],
            TextButton.icon(
              key: const ValueKey('order_add_product'),
              onPressed: saving ? null : () => selectProduct(add: true),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('إضافة منتج آخر'),
            ),
            if (error != null) FormErrorText(error!),
          ],
        ),
      ),
    );
  }

  Widget _catalogPicker(BuildContext context) => Pressable(
    key: const ValueKey('order_product_picker'),
    onTap: saving ? null : () => selectProduct(),
    child: SurfaceCard(
      color: softTint(context, lilac, .07),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined, color: lilac, size: 20),
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
          const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: lilac),
        ],
      ),
    ),
  );

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
