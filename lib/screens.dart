import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'design.dart';
import 'domain.dart';
import 'forms.dart';
import 'store.dart';
import 'account_card.dart';
import 'finance.dart';
export 'account_card.dart';

String shortDate(int ms) => DateFormat(
  'd MMMM yyyy',
  'ar',
).format(DateTime.fromMillisecondsSinceEpoch(ms));

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.badge,
  });
  final String title, subtitle;
  final Widget? action;
  final Widget? badge;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  if (badge != null) ...[const SizedBox(width: 8), badge!],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14, top: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

typedef Dashboard = ReportsPage;

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) {
    final r = store.report;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      key: const PageStorageKey('dashboard'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'التقرير العام',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'حصيلتك، بكل وضوح.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: softTint(context, rose, .07),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const FlowerMark(size: 42),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('record_received_profit'),
            onPressed: store.busy ? null : () => receiptSheet(context, store),
            icon: const Icon(Icons.savings_outlined, size: 19),
            label: const Text('تسجيل أرباح مستلمة'),
          ),
          const SizedBox(height: 14),
          Entrance(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: dark
                      ? [const Color(0xFF4B355E), const Color(0xFF352941)]
                      : [const Color(0xFFECE2F3), const Color(0xFFF6EDF1)],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  children: [
                    Positioned(
                      left: -25,
                      top: -25,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: .15,
                          child: FlowerMark(size: 170),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'إجمالي المبلغ المنفق',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          MoneyLine(r.spent, size: 39),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '${r.pending} معلّقة  ·  ${r.arrived} وصلت  ·  ${r.cancelled} ملغية',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columns = constraints.maxWidth >= 330 && scale < 1.4
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              final cards = [
                FinanceCard(
                  title: 'الربح المتوقع المتبقي',
                  value: r.expectedProfit,
                  icon: Icons.trending_up_rounded,
                  color: lilac,
                  detail:
                      'ربح الطلبات غير الملغية ناقص الأرباح المستلمة المسجّلة',
                ),
                FinanceCard(
                  key: const ValueKey('received_profit_report_card'),
                  title: 'الأرباح المحققة',
                  value: r.realizedProfit,
                  icon: Icons.verified_outlined,
                  color: sage,
                  detail: 'الأرباح المستلمة المسجّلة فعلًا؛ اضغطي لفتح سجلها',
                  onTap: () => openFinancePage(
                    context,
                    ReceiptHistoryPage(store: store),
                  ),
                ),
                FinanceCard(
                  key: const ValueKey('refund_report_card'),
                  title: 'المفترض استرداده',
                  value: r.refund,
                  icon: Icons.undo_rounded,
                  color: rose,
                  detail: 'اضغطي لعرض سجل مبالغ جميع الطلبات الملغية',
                  onTap: () =>
                      openFinancePage(context, RefundHistoryPage(store: store)),
                ),
                FinanceCard(
                  title: 'الصافي بعد الاسترداد',
                  value: r.net,
                  icon: Icons.savings_outlined,
                  color: peach,
                  detail: 'المنفق ناقص الاسترداد المتوقع',
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                  cards.length,
                  (i) => SizedBox(
                    width: width,
                    child: Entrance(delay: 60 + i * 45, child: cards[i]),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 25),
          const SectionLabel('طلباتك، باختصار'),
          Entrance(
            delay: 150,
            child: SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final stacked =
                          MediaQuery.textScalerOf(context).scale(14) > 20 ||
                          c.maxWidth < 270;
                      final children = [
                        StatusSummary(
                          status: OrderStatus.pending,
                          count: r.pending,
                        ),
                        StatusSummary(
                          status: OrderStatus.arrived,
                          count: r.arrived,
                        ),
                        StatusSummary(
                          status: OrderStatus.cancelled,
                          count: r.cancelled,
                        ),
                      ];
                      return stacked
                          ? Wrap(
                              spacing: 20,
                              runSpacing: 16,
                              children: children,
                            )
                          : Row(
                              children: children
                                  .map((w) => Expanded(child: w))
                                  .toList(),
                            );
                    },
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 6,
                      child: r.orders == 0
                          ? ColoredBox(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            )
                          : Row(
                              children: [
                                if (r.pending > 0)
                                  Expanded(
                                    flex: r.pending,
                                    child: ColoredBox(
                                      color: lilac.withValues(alpha: .55),
                                    ),
                                  ),
                                if (r.arrived > 0)
                                  Expanded(
                                    flex: r.arrived,
                                    child: ColoredBox(
                                      color: sage.withValues(alpha: .55),
                                    ),
                                  ),
                                if (r.cancelled > 0)
                                  Expanded(
                                    flex: r.cancelled,
                                    child: ColoredBox(
                                      color: rose.withValues(alpha: .55),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 25),
          const SectionLabel('تفاصيل حصيلتك'),
          SurfaceCard(
            child: Column(
              children: [
                _detail(
                  context,
                  'قيمة البيع المتوقعة',
                  r.expectedSales,
                  Icons.sell_outlined,
                ),
                const Divider(height: 28),
                _detail(
                  context,
                  'قيمة الطلبات التي وصلت',
                  r.arrivedSales,
                  Icons.inventory_2_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 330 ? 4 : 2,
                  w = (c.maxWidth - (cols - 1) * 8) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                          ('حساب', r.accounts, Icons.folder_outlined),
                          ('طلب', r.orders, Icons.receipt_long_outlined),
                          ('قطعة', r.pieces, Icons.layers_outlined),
                          ('منتج', r.products, Icons.shopping_bag_outlined),
                        ]
                        .map(
                          (v) => SizedBox(
                            width: w,
                            child: SurfaceCard(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 8,
                              ),
                              child: Column(
                                children: [
                                  Icon(v.$3, size: 18, color: lilac),
                                  const SizedBox(height: 8),
                                  Text(
                                    v.$2.toString(),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    v.$1,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _detail(
    BuildContext context,
    String title,
    int value,
    IconData icon,
  ) => Row(
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.bodySmall),
      ),
      const SizedBox(width: 8),
      Flexible(child: MoneyLine(value, size: 19)),
    ],
  );
}

class FinanceCard extends StatelessWidget {
  const FinanceCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.detail,
    this.onTap,
  });
  final String title, detail;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: detail,
    child: Pressable(
      onTap: onTap ?? () => notice(context, detail),
      child: SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: softTint(context, color),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                size: 19,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Color.lerp(color, Colors.white, .25)
                    : color,
              ),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            MoneyLine(value, size: 25),
          ],
        ),
      ),
    ),
  );
}

class StatusSummary extends StatelessWidget {
  const StatusSummary({super.key, required this.status, required this.count});
  final OrderStatus status;
  final int count;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: 15, color: statusColor(status)),
          const SizedBox(width: 5),
          Text(count.toString(), style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        status == OrderStatus.pending
            ? 'معلّقة'
            : status == OrderStatus.arrived
            ? 'وصلت'
            : 'ملغية',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class Deletable extends StatefulWidget {
  const Deletable({super.key, required this.child});
  final Widget Function(Future<void> Function(Future<void> Function()) remove)
  child;
  @override
  State<Deletable> createState() => _DeletableState();
}

class _DeletableState extends State<Deletable> {
  bool removing = false;
  Future<void> remove(Future<void> Function() action) async {
    if (removing) return;
    setState(() => removing = true);
    await Future<void>.delayed(motion(context, 180));
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => removing = false);
        notice(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: removing ? .93 : 1,
    duration: motion(context, 180),
    child: AnimatedOpacity(
      opacity: removing ? 0 : 1,
      duration: motion(context, 180),
      child: widget.child(remove),
    ),
  );
}

class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.revision,
    required this.load,
    required this.id,
    required this.item,
    required this.header,
    required this.empty,
    this.queryKey = '',
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 110),
  });
  final int revision;
  final String queryKey;
  final Future<List<T>> Function(int offset, int limit) load;
  final Object Function(T) id;
  final Widget Function(T) item;
  final Widget header, empty;
  final EdgeInsets padding;
  @override
  State<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<PagedList<T>> {
  final scroll = ScrollController();
  List<T> items = [];
  bool loading = false, more = true, loaded = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    scroll.addListener(onScroll);
    load(reset: true);
  }

  void onScroll() {
    if (scroll.hasClients &&
        scroll.position.extentAfter < 400 &&
        more &&
        !loading &&
        error == null) {
      load();
    }
  }

  @override
  void didUpdateWidget(PagedList<T> old) {
    super.didUpdateWidget(old);
    if (old.queryKey != widget.queryKey) {
      if (scroll.hasClients) scroll.jumpTo(0);
      load(reset: true, clear: true);
    } else if (old.revision != widget.revision) {
      load(reset: true);
    }
  }

  Future<void> load({bool reset = false, bool clear = false}) async {
    final token = reset ? ++generation : generation;
    if (clear) {
      items = [];
      loaded = false;
    }
    final limit = reset ? math.max(40, items.length) : 40,
        offset = reset ? 0 : items.length;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.load(offset, limit);
      if (!mounted || token != generation) return;
      setState(() {
        items = reset ? page : [...items, ...page];
        more = page.length == limit;
        loading = false;
        loaded = true;
      });
    } catch (e) {
      if (mounted && token == generation) {
        setState(() {
          loading = false;
          error = friendlyError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: scroll,
    slivers: [
      SliverToBoxAdapter(child: widget.header),
      if (loaded && items.isEmpty && error == null)
        SliverToBoxAdapter(child: widget.empty),
      SliverPadding(
        padding: widget.padding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => KeyedSubtree(
              key: ValueKey(widget.id(items[index])),
              child: widget.item(items[index]),
            ),
            findChildIndexCallback: (key) {
              if (key is! ValueKey) return null;
              final index = items.indexWhere(
                (item) => widget.id(item) == key.value,
              );
              return index < 0 ? null : index;
            },
            childCount: items.length,
          ),
        ),
      ),
      if (loading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      if (error != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(error!, textAlign: TextAlign.center),
                TextButton(
                  onPressed: () => load(reset: !loaded),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      if (more && !loading && error == null && loaded)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 100),
            child: TextButton(
              onPressed: () => load(),
              child: const Text('عرض المزيد'),
            ),
          ),
        ),
    ],
  );
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({
    super.key,
    required this.store,
    required this.openAccount,
  });
  final AppStore store;
  final ValueChanged<Account> openAccount;
  @override
  Widget build(BuildContext context) => PagedList<Account>(
    id: (a) => a.id,
    revision: store.revision,
    load: (offset, limit) =>
        store.database.accounts(offset: offset, limit: limit),
    header: PageHeading(
      title: 'حساباتك',
      subtitle: 'كل مجموعة طلبات، في مساحة خاصة.',
    ),
    empty: EmptyState(
      title: 'ابدئي بإضافة أول حساب ✨',
      subtitle: 'شهر جديد، شحنة جديدة، أو اسم تحبينه.',
      icon: Icons.folder_open_rounded,
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

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.store});
  final AppStore store;
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String search = '';
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PagedList<Product>(
    id: (p) => p.id,
    revision: widget.store.revision,
    queryKey: search,
    load: (offset, limit) => widget.store.database.products(
      search: search,
      offset: offset,
      limit: limit,
    ),
    header: Column(
      children: [
        const PageHeading(
          title: 'منتجاتك',
          subtitle: 'مجموعتك الصغيرة، جاهزة لأي طلب.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: null,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(
              hintText: 'ابحثي عن منتج…',
              hintMaxLines: 2,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: () {
                        controller.clear();
                        setState(() => search = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
            ),
          ),
        ),
      ],
    ),
    empty: EmptyState(
      title: search.isEmpty ? 'أضيفي أول منتج لتبدئي 💕' : 'لا توجد نتائج',
      subtitle: search.isEmpty ? 'اسم وسعر، وكل شيء جاهز.' : 'جرّبي اسمًا آخر.',
      icon: Icons.shopping_bag_outlined,
      button: search.isEmpty ? 'إضافة منتج' : null,
      action: search.isEmpty ? () => productSheet(context, widget.store) : null,
    ),
    item: (p) => Padding(
      key: ValueKey(p.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Entrance(
        child: Deletable(
          child: (remove) => Pressable(
            onTap: () => productSheet(context, widget.store, product: p),
            child: SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: softTint(context, rose, .1),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: rose,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        MoneyLine(p.sale, size: 20, animated: false),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'خيارات المنتج',
                    enabled: !widget.store.busy,
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await productSheet(context, widget.store, product: p);
                      } else if (await confirm(
                        context,
                        'حذف «${p.name}»؟',
                        'سيُحذف من قائمة المنتجات. الطلبات السابقة وأسعارها ستبقى محفوظة.',
                      )) {
                        if (!context.mounted) return;
                        await remove(() async {
                          await widget.store.mutate(
                            () => widget.store.database.deleteProduct(p.id),
                          );
                          if (context.mounted) {
                            notice(context, 'تم حذف المنتج؛ الطلبات محفوظة');
                          }
                        });
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      const PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.store, required this.account});
  final AppStore store;
  final Account account;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late Account account = widget.account;
  bool missing = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(refresh);
  }

  Future<void> refresh() async {
    if (widget.store.busy) return;
    final token = ++generation;
    final found = await widget.store.database.account(account.id);
    if (mounted && token == generation) {
      setState(() {
        if (found == null) {
          missing = true;
        } else {
          account = found;
        }
      });
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('تفاصيل الحساب'),
        ),
        actions: [
          if (!missing)
            IconButton(
              tooltip: account.isEmail
                  ? 'نسخ البريد الإلكتروني'
                  : 'نسخ اسم الحساب',
              onPressed: () => copyAccount(context, account),
              icon: const Icon(Icons.content_copy_rounded, size: 19),
            ),
          if (!missing) ...[
            IconButton(
              tooltip: account.isClosed ? 'إعادة فتح الحساب' : 'إغلاق الحساب',
              onPressed: widget.store.busy
                  ? null
                  : () async {
                      final newStatus = !account.isClosed;
                      await widget.store.mutate(
                        () => widget.store.database.toggleAccountClosed(
                          account.id,
                          newStatus,
                        ),
                      );
                      if (context.mounted) {
                        notice(
                          context,
                          newStatus ? 'تم إغلاق الحساب' : 'تم إعادة فتح الحساب',
                        );
                      }
                    },
              icon: Icon(
                account.isClosed
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                size: 20,
              ),
            ),
            IconButton(
              tooltip: 'تعديل الحساب',
              onPressed: widget.store.busy
                  ? null
                  : () => accountSheet(context, widget.store, account: account),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: missing || account.isClosed
          ? null
          : Pressable(
              onTap: widget.store.busy
                  ? null
                  : () => orderSheet(context, widget.store, account.id),
              child: FloatingActionButton.extended(
                onPressed: widget.store.busy
                    ? null
                    : () => orderSheet(context, widget.store, account.id),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة طلب'),
              ),
            ),
      body: missing
          ? const EmptyState(
              title: 'لم يعد هذا الحساب موجودًا',
              subtitle: 'ارجعي لقائمة الحسابات.',
              icon: Icons.folder_off_outlined,
            )
          : PagedList<PurchaseOrder>(
              id: (o) => o.id,
              revision: widget.store.revision,
              load: (offset, limit) => widget.store.database.orders(
                account.id,
                offset: offset,
                limit: limit,
              ),
              header: PageHeading(
                title: account.name,
                subtitle:
                    '${account.orderCount} طلب · أُنشئ ${shortDate(account.createdAt)}',
                badge: account.isClosed
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'مغلق',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      )
                    : null,
              ),
              empty: EmptyState(
                title: account.isClosed
                    ? 'الحساب مغلق'
                    : 'لا توجد طلبات هنا بعد',
                subtitle: account.isClosed
                    ? 'هذا الحساب مغلق حاليًا. يمكنك إعادة فتحه في أي وقت لإضافة طلبات.'
                    : 'أضيفي أول طلب، وستظهر أرقامه فورًا في حصيلتك.',
                icon: account.isClosed
                    ? Icons.lock_outline_rounded
                    : Icons.receipt_long_outlined,
                button: account.isClosed ? 'إعادة فتح الحساب' : 'إضافة طلب',
                action: account.isClosed
                    ? () async {
                        await widget.store.mutate(
                          () => widget.store.database.toggleAccountClosed(
                            account.id,
                            false,
                          ),
                        );
                        if (context.mounted) {
                          notice(context, 'تم إعادة فتح الحساب');
                        }
                      }
                    : () => orderSheet(context, widget.store, account.id),
              ),
              item: (o) => Padding(
                key: ValueKey(o.id),
                padding: const EdgeInsets.only(bottom: 14),
                child: Entrance(
                  child: OrderTile(order: o, store: widget.store),
                ),
              ),
            ),
    ),
  );
}

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.store});
  final PurchaseOrder order;
  final AppStore store;
  @override
  Widget build(BuildContext context) => Deletable(
    child: (remove) => Pressable(
      onTap: store.busy
          ? null
          : () => orderSheet(context, store, order.accountId, order: order),
      child: SurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.productName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        shortDate(order.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'خيارات الطلب',
                  enabled: !store.busy,
                  icon: const Icon(Icons.more_horiz_rounded, size: 21),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await orderSheet(
                        context,
                        store,
                        order.accountId,
                        order: order,
                      );
                    } else if (await confirm(
                      context,
                      'حذف الطلب؟',
                      'سيُحذف طلب «${order.productName}» وتُزال مبالغه من التقرير.',
                    )) {
                      if (!context.mounted) return;
                      await remove(() async {
                        await store.mutate(
                          () => store.database.deleteOrder(order.id),
                        );
                        if (context.mounted) notice(context, 'تم حذف الطلب');
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    const PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: softTint(context, lilac, .06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${order.quantity} قطعة',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StatusBadge(
                  status: order.status,
                  enabled: !store.busy,
                  onChanged: (s) async {
                    if (s == order.status) return;
                    try {
                      await store.mutate(
                        () => store.database.changeStatus(order.id, s),
                      );
                      if (context.mounted) {
                        notice(
                          context,
                          s == OrderStatus.arrived
                              ? 'وصل الطلب، حصيلة جميلة ✨'
                              : 'تم تغيير حالة الطلب',
                        );
                      }
                    } catch (e) {
                      if (context.mounted) notice(context, friendlyError(e));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                _price(
                  context,
                  order.approximateUnit ? 'شراء الوحدة ≈' : 'شراء الوحدة',
                  order.purchase,
                ),
                _price(context, 'بيع الوحدة', order.sale),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 18,
              runSpacing: 14,
              children: [
                _price(context, 'إجمالي الشراء', order.cost),
                _price(context, 'إجمالي البيع', order.revenue),
                _price(
                  context,
                  order.status == OrderStatus.cancelled
                      ? 'الربح النشط'
                      : 'ربح الطلب',
                  order.status == OrderStatus.cancelled ? 0 : order.profit,
                  color: order.status == OrderStatus.cancelled
                      ? rose
                      : order.profit < 0
                      ? rose
                      : sage,
                ),
              ],
            ),
            if (order.status == OrderStatus.cancelled) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: softTint(context, rose, .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.undo_rounded, size: 16, color: rose),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'المفترض استرداده: ${moneyText(order.cost)} SAR',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'هذا الطلب لا يدخل في المبيعات والأرباح النشطة.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _price(
    BuildContext context,
    String label,
    int value, {
    Color? color,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 5),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: MoneyLine(value, size: 17, color: color, animated: false),
      ),
    ],
  );
}
