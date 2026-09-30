import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'database.dart';
import 'domain.dart';
import 'design.dart';
import 'forms.dart';
import 'screens.dart';
import 'store.dart';
import 'updates.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HaseelaBootstrap());
}

class HaseelaBootstrap extends StatefulWidget {
  const HaseelaBootstrap({super.key});
  @override
  State<HaseelaBootstrap> createState() => _HaseelaBootstrapState();
}

class _HaseelaBootstrapState extends State<HaseelaBootstrap> {
  AppStore? store;
  String? error;
  bool opening = false;
  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open() async {
    if (opening) return;
    setState(() {
      opening = true;
      error = null;
    });
    AppDatabase? db;
    try {
      db = await AppDatabase.open();
      final next = AppStore(db);
      await next.load();
      if (mounted) {
        setState(() => store = next);
      } else {
        next.dispose();
        await db.close();
      }
    } catch (e) {
      await db?.close();
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  void dispose() {
    store?.dispose();
    store?.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => store != null
      ? HaseelaApp(store: store!)
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FlowerMark(size: 76),
                    const SizedBox(height: 22),
                    const Text(
                      'حصيلة',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (error == null)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: opening ? null : open,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
}

class HaseelaApp extends StatelessWidget {
  const HaseelaApp({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: 'حصيلة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: store.themeMode,
      home: AppShell(store: store),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});
  final AppStore store;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int selected = 0;
  final storage = PageStorageBucket();
  final updates = UpdateController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(updates.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(updates.check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updates.dispose();
    super.dispose();
  }

  void accountRoute(Account account) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: motion(context, 260),
        reverseTransitionDuration: motion(context, 220),
        pageBuilder: (context, a, b) =>
            AccountPage(store: widget.store, account: account),
        transitionsBuilder: (context, a, b, child) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(.025, .035),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> settings(String value) async {
    if (widget.store.busy) return;
    if (['system', 'light', 'dark'].contains(value)) {
      try {
        await widget.store.setTheme(value);
      } catch (e) {
        if (mounted) notice(context, friendlyError(e));
      }
    } else if (value == 'updates') {
      await updateSheet(context, updates);
    } else if (value == 'export') {
      await exportBackup(context, widget.store);
    } else if (value == 'restore') {
      await restoreBackup(context, widget.store);
    } else if (value == 'safety') {
      await restoreBackup(context, widget.store, safety: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      HomePage(store: widget.store, openAccount: accountRoute),
      AccountsPage(store: widget.store, openAccount: accountRoute),
      ProductsPage(store: widget.store),
      ReportsPage(store: widget.store),
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 62,
          titleSpacing: 24,
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowerMark(size: 27),
                SizedBox(width: 8),
                Text(
                  'حصيلة',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          actions: [
            AnimatedBuilder(
              animation: updates,
              builder: (context, _) => IconButton(
                key: const ValueKey('app_updates'),
                tooltip: 'تحديث التطبيق',
                onPressed: () => updateSheet(context, updates),
                icon: Badge(
                  isLabelVisible: updates.available != null,
                  smallSize: 7,
                  child: const Icon(Icons.system_update_rounded, size: 22),
                ),
              ),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('app_settings'),
              enabled: !widget.store.busy,
              tooltip: 'المظهر والنسخ الاحتياطي',
              icon: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.tune_rounded, size: 20),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              onSelected: settings,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'updates',
                  child: Row(
                    children: [
                      Icon(Icons.system_update_rounded, size: 19),
                      SizedBox(width: 12),
                      Expanded(child: Text('تحديث التطبيق')),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  enabled: false,
                  child: Text('المظهر', style: TextStyle(fontSize: 12)),
                ),
                ...[
                  ('system', 'حسب الجهاز', Icons.brightness_auto_outlined),
                  ('light', 'فاتح', Icons.light_mode_outlined),
                  ('dark', 'داكن', Icons.dark_mode_outlined),
                ].map(
                  (v) => PopupMenuItem(
                    value: v.$1,
                    child: Row(
                      children: [
                        Icon(v.$3, size: 19),
                        const SizedBox(width: 12),
                        Expanded(child: Text(v.$2)),
                        if (widget.store.theme == v.$1) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.file_download_outlined, size: 19),
                      SizedBox(width: 12),
                      Expanded(child: Text('حفظ نسخة احتياطية')),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.restore_rounded, size: 19),
                      SizedBox(width: 12),
                      Expanded(child: Text('استعادة من ملف')),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'safety',
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 19),
                      SizedBox(width: 12),
                      Expanded(child: Text('استعادة آخر نسخة أمان')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: PageStorage(
            bucket: storage,
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: updates,
                  builder: (context, _) => updates.available == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                          child: Pressable(
                            key: const ValueKey('update_banner'),
                            onTap: () => updateSheet(context, updates),
                            child: SurfaceCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'تحديث جديد ${updates.available!.version} ✨\nاضغطي لتنزيله وتثبيته',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_left_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: Stack(
                    children: List.generate(
                      pages.length,
                      (i) => Offstage(
                        offstage: selected != i,
                        child: TickerMode(
                          enabled: selected == i,
                          child: AnimatedOpacity(
                            opacity: selected == i ? 1 : 0,
                            duration: motion(context, 220),
                            child: pages[i],
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
        floatingActionButton: selected == 0 || selected == 3
            ? null
            : Pressable(
                onTap: widget.store.busy
                    ? null
                    : () => selected == 1
                          ? accountSheet(context, widget.store)
                          : productSheet(context, widget.store),
                child: FloatingActionButton.extended(
                  key: const ValueKey('add_item'),
                  onPressed: widget.store.busy
                      ? null
                      : () => selected == 1
                            ? accountSheet(context, widget.store)
                            : productSheet(context, widget.store),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(selected == 1 ? 'إضافة حساب' : 'إضافة منتج'),
                ),
              ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .65),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: List.generate(4, (i) {
                  final active = selected == i;
                  final label = [
                    'الرئيسية',
                    'الحسابات',
                    'المنتجات',
                    'التقارير',
                  ][i];
                  final icon = [
                    Icons.space_dashboard_outlined,
                    Icons.folder_open_rounded,
                    Icons.shopping_bag_outlined,
                    Icons.insights_rounded,
                  ][i];
                  return Expanded(
                    child: Semantics(
                      selected: active,
                      button: true,
                      label: label,
                      child: Pressable(
                        key: ValueKey('nav_$i'),
                        onTap: () => setState(() => selected = i),
                        radius: 18,
                        child: AnimatedContainer(
                          duration: motion(context, 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? softTint(context, lilac, .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedScale(
                                scale: active ? 1.06 : 1,
                                duration: motion(context, 180),
                                child: Icon(
                                  icon,
                                  size: 22,
                                  color: active
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 5),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: active
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
