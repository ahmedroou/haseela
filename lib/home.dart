import 'package:flutter/material.dart';
import 'design.dart';
import 'domain.dart';
import 'forms.dart';
import 'screens.dart';
import 'store.dart';

Future<void> quickOrder(BuildContext context, AppStore store) async {
  final Account? account;
  if (store.report.accounts == 0) {
    account = await accountSheet(context, store);
  } else {
    account = await openSheet<Account>(context, AccountPicker(store: store));
  }
  if (account != null && context.mounted) {
    await orderSheet(context, store, account.id);
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.openAccount});
  final AppStore store;
  final ValueChanged<Account> openAccount;
  @override
  Widget build(BuildContext context) => PagedList<Account>(
    id: (a) => a.id,
    revision: store.revision,
    load: (offset, limit) =>
        store.database.accounts(offset: offset, limit: limit),
    header: Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'أهلًا بكِ في حصيلة',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'جاهزة لطلب جديد؟',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            color: softTint(context, lilac, .08),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const FlowerMark(size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'سجّلي طلبك، ببساطة.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('home_new_order'),
                  onPressed: store.busy
                      ? null
                      : () => quickOrder(context, store),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('تسجيل طلب'),
                ),
                const SizedBox(height: 5),
                TextButton.icon(
                  onPressed: store.busy
                      ? null
                      : () => accountSheet(context, store),
                  icon: const Icon(Icons.alternate_email_rounded, size: 18),
                  label: const Text('إضافة حساب'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('حساباتك، جاهزة للتسجيل'),
        ],
      ),
    ),
    empty: EmptyState(
      title: 'ابدئي بإضافة أول حساب ✨',
      subtitle: 'بريد إلكتروني أو اسم تختارينه، ثم أضيفي طلبك.',
      icon: Icons.mark_email_unread_outlined,
      button: 'إضافة حساب',
      action: () => accountSheet(context, store),
    ),
    item: (a) => Padding(
      key: ValueKey(a.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Entrance(
        child: AccountTile(
          account: a,
          store: store,
          onOpen: () => openAccount(a),
        ),
      ),
    ),
  );
}

class AccountPicker extends StatefulWidget {
  const AccountPicker({super.key, required this.store});
  final AppStore store;
  @override
  State<AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<AccountPicker> {
  final query = TextEditingController();
  final scroll = ScrollController();
  List<Account> accounts = [];
  bool loading = false, more = true, adding = false;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    load(reset: true);
    scroll.addListener(() {
      if (scroll.position.extentAfter < 220) load();
    });
  }

  Future<void> load({bool reset = false}) async {
    if (!reset && (loading || !more)) return;
    final token = reset ? ++generation : generation;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        accounts = [];
        more = true;
      }
    });
    try {
      final result = await widget.store.database.accounts(
        search: query.text,
        openOnly: true,
        offset: accounts.length,
      );
      if (!mounted || token != generation) return;
      setState(() {
        accounts = [...accounts, ...result];
        more = result.length == 40;
        loading = false;
      });
    } catch (e) {
      if (mounted && token == generation) {
        setState(() {
          error = friendlyError(e);
          loading = false;
        });
      }
    }
  }

  Future<void> add() async {
    if (adding) return;
    setState(() => adding = true);
    final result = await accountSheet(context, widget.store);
    if (!mounted) return;
    setState(() => adding = false);
    if (result != null) Navigator.pop(context, result);
  }

  @override
  void dispose() {
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SizedBox(
      height:
          (MediaQuery.sizeOf(context).height * .62 -
                  MediaQuery.viewInsetsOf(context).bottom * .5)
              .clamp(220, 650),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('لأي حساب؟', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('account_picker_search'),
            controller: query,
            onChanged: (_) => load(reset: true),
            decoration: const InputDecoration(
              hintText: 'البريد أو اسم الحساب',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: error != null
                ? Center(
                    child: TextButton(
                      onPressed: () => load(reset: true),
                      child: Text(error!),
                    ),
                  )
                : accounts.isEmpty && !loading
                ? const Center(child: Text('لا توجد حسابات مطابقة'))
                : ListView.builder(
                    controller: scroll,
                    itemCount: accounts.length + (more || loading ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == accounts.length) {
                        return loading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: load,
                                child: const Text('عرض المزيد'),
                              );
                      }
                      final account = accounts[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Pressable(
                          onTap: () {
                            if (account.isClosed) {
                              notice(
                                context,
                                'الحساب مغلق؛ لا يمكن إضافة طلب له',
                              );
                              return;
                            }
                            Navigator.pop(context, account);
                          },
                          child: SurfaceCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  account.isClosed
                                      ? Icons.lock_outline_rounded
                                      : account.isEmail
                                      ? Icons.alternate_email_rounded
                                      : Icons.folder_open_rounded,
                                  color: account.isClosed
                                      ? Theme.of(context).colorScheme.outline
                                      : lilac,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              account.name,
                                              textDirection: account.isEmail
                                                  ? TextDirection.ltr
                                                  : null,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                            ),
                                          ),
                                          if (account.isClosed) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outlineVariant
                                                    .withValues(alpha: .5),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                'مغلق',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${account.orderCount} طلب · ${account.pieces} قطعة',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_left_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('add_account_from_picker'),
            onPressed: adding || widget.store.busy ? null : add,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة حساب جديد'),
          ),
        ],
      ),
    ),
  );
}
