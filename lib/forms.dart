import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'domain.dart';
import 'store.dart';
import 'order_form.dart';
export 'order_form.dart';

final numberInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
    return newValue;
  }
  final text = normalizeDigits(newValue.text);
  return newValue.copyWith(
    text: text,
    selection: TextSelection.collapsed(
      offset: newValue.selection.extentOffset.clamp(0, text.length),
    ),
    composing: TextRange.empty,
  );
});

const currencySuffix = SizedBox(
  width: 48,
  child: Center(
    child: Text(
      'SAR',
      textDirection: TextDirection.ltr,
      style: TextStyle(fontSize: 11, color: lilac),
    ),
  ),
);

Widget completeTextField({
  Key? key,
  required TextEditingController controller,
  FormFieldValidator<String>? validator,
  bool enabled = true,
  int? maxLength,
  TextInputType? keyboardType,
  TextDirection? textDirection,
  List<TextInputFormatter>? inputFormatters,
  TextInputAction? textInputAction,
  ValueChanged<String>? onFieldSubmitted,
  required InputDecoration decoration,
  bool compact = false,
}) => LayoutBuilder(
  builder: (context, constraints) {
    final numeric =
        keyboardType == TextInputType.number ||
        keyboardType == const TextInputType.numberWithOptions(decimal: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (decoration.labelText != null) ...[
          Text(
            decoration.labelText!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: compact ? 4 : 9),
        ],
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            var style = Theme.of(context).textTheme.bodyLarge!;
            if (compact) style = style.copyWith(fontSize: 14);
            if (numeric && value.text.isNotEmpty) {
              final available =
                  (constraints.maxWidth -
                          (compact ? 24 : 36) -
                          (decoration.prefixIcon == null
                              ? 0
                              : (compact ? 36 : 48)) -
                          (decoration.suffixIcon == null
                              ? 0
                              : (compact ? 36 : 48)))
                      .clamp(1.0, double.infinity);
              final painter = TextPainter(
                text: TextSpan(text: value.text, style: style),
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: textDirection ?? Directionality.of(context),
              )..layout();
              if (painter.width > available) {
                style = style.copyWith(
                  fontSize: style.fontSize! * available / painter.width * .97,
                );
              }
              painter.dispose();
            }
            return TextFormField(
              key: key,
              controller: controller,
              validator: validator,
              enabled: enabled,
              maxLength: maxLength,
              keyboardType: keyboardType,
              textDirection:
                  textDirection ??
                  (keyboardType == TextInputType.emailAddress &&
                          value.text.contains('@')
                      ? TextDirection.ltr
                      : null),
              inputFormatters: inputFormatters,
              textInputAction: textInputAction,
              onFieldSubmitted: onFieldSubmitted,
              style: style,
              minLines: 1,
              maxLines: numeric ? 1 : null,
              decoration: InputDecoration(
                isDense: compact,
                contentPadding: compact
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 11)
                    : null,
                prefixIconConstraints: compact
                    ? const BoxConstraints(minWidth: 36, minHeight: 40)
                    : null,
                suffixIconConstraints: compact
                    ? const BoxConstraints(minWidth: 36, minHeight: 40)
                    : null,
                hintText: decoration.hintText,
                hintMaxLines: 3,
                counterText: decoration.counterText,
                prefixIcon: decoration.prefixIcon,
                suffixIcon: decoration.suffixIcon,
                errorMaxLines: 4,
              ),
            );
          },
        ),
      ],
    );
  },
);

void notice(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
}

String friendlyError(Object error) {
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message;
  return 'تعذّر إتمام العملية. تأكدي من مساحة الجهاز وحاولي مرة أخرى.';
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String button = 'حذف',
  bool destructive = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(button),
          ),
        ],
      ),
    ) ??
    false;

Future<T?> openSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: AnimationStyle(
        duration: motion(context, 260),
        reverseDuration: motion(context, 220),
      ),
      builder: (context) => child,
    );

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.saving,
    required this.save,
    this.button = 'حفظ',
  });
  final String title, subtitle, button;
  final Widget child;
  final bool saving;
  final VoidCallback save;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .87,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              child,
              const SizedBox(height: 24),
              Pressable(
                onTap: saving ? null : save,
                child: FilledButton(
                  key: const ValueKey('save_form'),
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(button),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String? nameValidator(String? text) => text == null || text.trim().isEmpty
    ? 'اكتبي الاسم أولًا'
    : text.length > 120
    ? 'الاسم طويل؛ الحد 120 حرفًا'
    : null;
String? priceValidator(String? text) => parseMoney(text ?? '') == null
    ? 'أدخلي سعرًا صحيحًا، حتى منزلتين عشريتين'
    : null;

Future<Account?> accountSheet(
  BuildContext context,
  AppStore store, {
  Account? account,
}) async {
  final saved = await openSheet<int>(
    context,
    AccountForm(store: store, account: account),
  );
  if (saved != null && context.mounted) {
    notice(
      context,
      account == null ? 'أُضيف الحساب، بداية جميلة ✨' : 'تم حفظ الحساب',
    );
  }
  if (saved == null) return null;
  try {
    return await store.database.account(saved);
  } catch (e) {
    if (context.mounted) notice(context, friendlyError(e));
    return null;
  }
}

class AccountForm extends StatefulWidget {
  const AccountForm({super.key, required this.store, this.account});
  final AppStore store;
  final Account? account;
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.account?.name ?? '');
  late bool isClosed = widget.account?.isClosed ?? false;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !key.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await widget.store.mutate(
        () => widget.store.database.saveAccount(
          name.text,
          old: widget.account,
          isClosed: isClosed,
        ),
      );
      if (mounted) Navigator.pop(context, id);
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
    title: widget.account == null ? 'حساب جديد' : 'تعديل الحساب',
    subtitle: 'بريدك الإلكتروني، أو أي اسم يجمع طلباتك.',
    saving: saving,
    save: save,
    child: Form(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          completeTextField(
            key: const ValueKey('account_name'),
            controller: name,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'أدخلي البريد أو اسم الحساب'
                : v.length > 254
                ? 'الحد 254 حرفًا'
                : null,
            enabled: !saving,
            maxLength: 254,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => save(),
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني أو اسم الحساب',
              hintText: 'example@email.com',
              counterText: '',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: saving ? null : () => setState(() => isClosed = !isClosed),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isClosed ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 17,
                    color: isClosed
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'حساب مغلق',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        Text(
                          'إيقاف إضافة طلبات جديدة لهذا الحساب',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: isClosed,
                      onChanged: saving
                          ? null
                          : (v) => setState(() => isClosed = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) FormErrorText(error!),
        ],
      ),
    ),
  );
}

Future<Product?> productSheet(
  BuildContext context,
  AppStore store, {
  Product? product,
}) async {
  final saved = await openSheet<int>(
    context,
    ProductForm(store: store, product: product),
  );
  if (saved != null && context.mounted) {
    notice(
      context,
      product == null ? 'أُضيف المنتج إلى مجموعتك 💕' : 'تم حفظ المنتج',
    );
  }
  if (saved == null) return null;
  try {
    return await store.database.product(saved);
  } catch (e) {
    if (context.mounted) notice(context, friendlyError(e));
    return null;
  }
}

class ProductForm extends StatefulWidget {
  const ProductForm({super.key, required this.store, this.product});
  final AppStore store;
  final Product? product;
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.product?.name ?? '');
  late final price = TextEditingController(
    text: widget.product == null ? '' : moneyInput(widget.product!.sale),
  );
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    price.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !key.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await widget.store.mutate(
        () => widget.store.database.saveProduct(
          name.text,
          parseMoney(price.text)!,
          old: widget.product,
        ),
      );
      if (mounted) Navigator.pop(context, id);
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
    title: widget.product == null ? 'منتج جديد' : 'تعديل المنتج',
    subtitle: 'سعره الافتراضي يساعدك على إضافة الطلبات أسرع.',
    saving: saving,
    save: save,
    child: Form(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          completeTextField(
            key: const ValueKey('product_name'),
            controller: name,
            validator: nameValidator,
            enabled: !saving,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'اسم المنتج',
              hintText: 'مثلًا: AirPods Pro',
              counterText: '',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(height: 16),
          completeTextField(
            key: const ValueKey('product_price'),
            controller: price,
            validator: priceValidator,
            enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            inputFormatters: [numberInputFormatter],
            onFieldSubmitted: (_) => save(),
            decoration: const InputDecoration(
              labelText: 'سعر البيع الافتراضي',
              suffixIcon: currencySuffix,
            ),
          ),
          if (widget.product != null) ...[
            const SizedBox(height: 14),
            const Text(
              'تعديل السعر لا يغيّر أسعار الطلبات السابقة.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (error != null) FormErrorText(error!),
        ],
      ),
    ),
  );
}

Future<void> orderSheet(
  BuildContext context,
  AppStore store,
  int accountId, {
  PurchaseOrder? order,
}) async {
  if (order == null) {
    final acc = await store.database.account(accountId);
    if (acc != null && acc.isClosed) {
      if (context.mounted) {
        notice(context, 'الحساب مغلق؛ لا يمكن إضافة طلبات جديدة إليه');
      }
      return;
    }
  }
  if (!context.mounted) return;
  final saved = await openSheet<bool>(
    context,
    OrderForm(store: store, accountId: accountId, order: order),
  );
  if (saved == true && context.mounted) {
    notice(context, order == null ? 'تمت إضافة الطلب ✨' : 'تم حفظ الطلب');
  }
}

class ProductPicker extends StatefulWidget {
  const ProductPicker({super.key, required this.store});
  final AppStore store;
  @override
  State<ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<ProductPicker> {
  final search = TextEditingController();
  List<Product> products = [];
  bool loading = true, more = true;
  int generation = 0;
  String? error;
  bool adding = false;

  Future<void> addProduct() async {
    if (adding || widget.store.busy) return;
    setState(() => adding = true);
    final product = await productSheet(context, widget.store);
    if (!mounted) return;
    setState(() => adding = false);
    if (product != null) {
      Navigator.pop(context, product);
    }
  }

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    final token = reset ? ++generation : generation;
    if (reset) {
      products = [];
      more = true;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final items = await widget.store.database.products(
        search: search.text,
        offset: products.length,
        limit: 40,
      );
      if (mounted && token == generation) {
        setState(() {
          products.addAll(items);
          more = items.length == 40;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && token == generation) {
        setState(() {
          error = friendlyError(e);
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'اختاري المنتج',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            minLines: 1,
            maxLines: null,
            textInputAction: TextInputAction.search,
            controller: search,
            onChanged: (_) => load(reset: true),
            decoration: const InputDecoration(
              hintText: 'ابحثي عن منتج…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: error != null
                ? Center(
                    child: TextButton(
                      onPressed: () => load(reset: true),
                      child: Text(error!),
                    ),
                  )
                : products.isEmpty && !loading
                ? const Center(child: Text('لا توجد منتجات مطابقة'))
                : ListView.builder(
                    itemCount: products.length + ((more || loading) ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == products.length) {
                        return loading
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : TextButton(
                                onPressed: () => load(),
                                child: const Text('عرض المزيد'),
                              );
                      }
                      final p = products[index];
                      return Pressable(
                        onTap: () => Navigator.pop(context, p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: softTint(context, rose),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: rose,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 5),
                                    MoneyLine(
                                      p.sale,
                                      size: 16,
                                      animated: false,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.add_circle_outline_rounded,
                                color: lilac,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('add_product_from_picker'),
              onPressed: adding ? null : addProduct,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة منتج جديد'),
            ),
          ),
        ],
      ),
    ),
  );
}

class FormErrorText extends StatelessWidget {
  const FormErrorText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 13,
      ),
    ),
  );
}

String encodeBackup(BackupData backup) => backup.encode();
Future<void> exportBackup(
  BuildContext context,
  AppStore store, {
  String? text,
}) async {
  try {
    final String content =
        text ??
        await compute<BackupData, String>(
          encodeBackup,
          await store.database.snapshot(),
        );
    final now = DateTime.now();
    final file = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ نسخة حصيلة',
      fileName: 'haseela_${now.toIso8601String().substring(0, 10)}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (file != null && context.mounted) {
      notice(context, 'تم حفظ النسخة الاحتياطية 💕');
    }
  } catch (e) {
    if (context.mounted) notice(context, friendlyError(e));
  }
}

Future<void> restoreBackup(
  BuildContext context,
  AppStore store, {
  bool safety = false,
}) async {
  try {
    String? content;
    if (safety) {
      final path = await store.database.latestSafetyCopy();
      if (path == null) {
        if (context.mounted) notice(context, 'لا توجد نسخة أمان سابقة بعد');
        return;
      }
      content = await File(path).readAsString();
    } else {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختيار نسخة حصيلة',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        throw const FormatException('تعذّر قراءة الملف');
      }
    }
    final backup = await compute(BackupData.decode, content);
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      'استعادة النسخة؟',
      'تحتوي على ${backup.accounts.length} حساب و${backup.products.length} منتج و${backup.orders.length} طلب و${backup.receipts.length} سجل أرباح مستلمة.\n\nستستبدل بياناتك الحالية. سنحفظ نسخة أمان قبل الاستبدال، ويمكنك استعادتها من القائمة.',
      button: 'استعادة',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    await store.mutate(() => store.database.restore(backup));
    if (context.mounted) notice(context, 'تمت الاستعادة وتحديث حصيلتك ✨');
  } catch (e) {
    if (context.mounted) notice(context, friendlyError(e));
  }
}
