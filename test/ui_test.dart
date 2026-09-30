import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haseela/database.dart';
import 'package:haseela/design.dart';
import 'package:haseela/domain.dart';
import 'package:haseela/forms.dart';
import 'package:haseela/main.dart';
import 'package:haseela/screens.dart';
import 'package:haseela/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late AppStore store;
  setUpAll(() async {
    sqfliteFfiInit();
    final font = FontLoader('Tajawal')
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('haseela_ui_');
    db = await AppDatabase.open(
      path: '${dir.path}/ui.db',
      factory: databaseFactoryFfi,
    );
    await db.db.delete('products');
    store = AppStore(db);
    await store.load();
  });
  tearDown(() async {
    store.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<void> seed() async {
    final a = await db.saveAccount('طلبات سبتمبر');
    final b = await db.saveAccount('دفعة أمازون');
    final p = await db.saveProduct('AirPods Pro', 55000);
    await db.saveProduct('عطر روز بلَش', 32000);
    await db.saveOrder(
      accountId: a,
      productId: p,
      productName: 'AirPods Pro',
      quantity: 2,
      purchase: 40000,
      sale: 55000,
      status: OrderStatus.pending,
    );
    await db.saveOrder(
      accountId: a,
      productId: null,
      productName: 'حقيبة ليلك',
      quantity: 3,
      purchase: 30000,
      sale: 45000,
      status: OrderStatus.arrived,
    );
    await db.saveOrder(
      accountId: b,
      productId: null,
      productName: 'ساعة روز',
      quantity: 3,
      purchase: 35000,
      sale: 50000,
      status: OrderStatus.cancelled,
    );
    await store.load();
  }

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 12)),
      );
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
  }

  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: HaseelaApp(store: store),
          ),
        ),
      ),
    );
    await flush(tester);
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    await tester.pump();
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory('artifacts/screenshots');
      await out.create(recursive: true);
      await File(
        '${out.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    debugDisableShadows = oldShadows;
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'dashboard, dark mode, products and account render without overflow',
    (tester) async {
      await tester.runAsync(seed);
      await launch(tester);
      expect(find.text('2,750'), findsOneWidget);
      expect(find.text('750'), findsOneWidget);
      await screenshot(tester, 'home-light');
      await tester.runAsync(() => store.setTheme('dark'));
      await flush(tester);
      await screenshot(tester, 'home-dark');
      await tester.runAsync(() => store.setTheme('light'));
      await flush(tester);
      await tester.tap(find.text('المنتجات').hitTestable());
      await flush(tester);
      await screenshot(tester, 'products-light');
      await tester.tap(find.text('الحسابات').hitTestable());
      await flush(tester);
      await tester.tap(find.text('طلبات سبتمبر').hitTestable());
      await flush(tester);
      await screenshot(tester, 'account-light');
      expect(find.byType(OrderTile).evaluate().length, greaterThan(0));
      await tester.tap(find.text('قيد الانتظار').hitTestable());
      await flush(tester);
      await tester.tap(find.widgetWithText(PopupMenuItem<OrderStatus>, 'وصل'));
      await flush(tester);
      expect(store.report.realizedProfit, 75000);
      expect(store.report.pending, 0);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  testWidgets(
    'product and account creation, search, order pricing and cancellation',
    (tester) async {
      await launch(tester);
      expect(find.text('ابدئي بإضافة أول حساب ✨'), findsOneWidget);
      await tester.tap(find.text('المنتجات').hitTestable());
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('add_item')));
      await flush(tester);
      await tester.enterText(
        find.byKey(const ValueKey('product_name')),
        'سماعة روز',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product_price')),
        '٥٥٠٫٢٥',
      );
      await tester.tap(find.byKey(const ValueKey('save_form')));
      await flush(tester);
      expect(store.report.products, 1);
      await tester.enterText(find.byType(TextField).hitTestable(), 'غير موجود');
      await flush(tester);
      expect(find.text('لا توجد نتائج').hitTestable(), findsOneWidget);
      await tester.enterText(find.byType(TextField).hitTestable(), '');
      await flush(tester);
      await tester.tap(find.text('الحسابات').hitTestable());
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('add_item')));
      await flush(tester);
      await tester.enterText(
        find.byKey(const ValueKey('account_name')),
        'حسابي',
      );
      await tester.tap(find.byKey(const ValueKey('save_form')));
      await flush(tester);
      expect(store.report.accounts, 1);
      await tester.tap(find.text('حسابي').hitTestable());
      await flush(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'إضافة طلب'));
      await flush(tester);
      await tester.tap(find.text('اختاري من قائمة المنتجات'));
      await flush(tester);
      await tester.tap(find.text('سماعة روز').hitTestable());
      await flush(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('order_sale')))
            .controller!
            .text,
        '550.25',
      );
      await tester.enterText(find.byKey(const ValueKey('order_quantity')), '٢');
      await tester.enterText(
        find.byKey(const ValueKey('order_purchase')),
        '٤٠٠٫١٠',
      );
      // Scroll within the sheet so save stays reachable with long forms.
      await tester.ensureVisible(find.byKey(const ValueKey('save_form')));
      await tester.pumpAndSettle();
      await screenshot(tester, 'order-sheet');
      await tester.tap(find.byKey(const ValueKey('save_form')));
      await flush(tester);
      expect(store.report.orders, 1);
      expect(store.report.spent, 80020);
      expect(store.report.expectedProfit, 30030);
      await tester.tap(find.text('قيد الانتظار').hitTestable());
      await flush(tester);
      await tester.tap(find.widgetWithText(PopupMenuItem<OrderStatus>, 'ملغي'));
      await flush(tester);
      expect(store.report.refund, 80020);
      expect(store.report.expectedProfit, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  testWidgets(
    'small screen, large text, reduced motion and keyboard insets stay usable',
    (tester) async {
      await tester.runAsync(seed);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await launch(tester, size: const Size(320, 640), scale: 1.6);
      await screenshot(tester, 'small-large-text');
      expect(find.byType(MoneyCounter).evaluate().isNotEmpty, true);
      await tester.tap(find.text('المنتجات').hitTestable());
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('add_item')));
      await flush(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('product_name')),
        'منتج',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('product_price')));
      await tester.pumpAndSettle();
      await screenshot(tester, 'keyboard-small');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  testWidgets('10000-order list builds visible cards and scrolls lazily', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final a = await db.saveAccount('حساب كبير');
      await db.db.transaction((tx) async {
        final batch = tx.batch();
        for (var i = 1; i <= 10000; i++) {
          batch.insert('orders', {
            'account_id': a,
            'product_id': null,
            'product_name': 'منتج $i',
            'quantity': 1,
            'purchase': 10000,
            'sale': 15000,
            'status': 'pending',
            'created_at': 1000 + i,
            'updated_at': 1000 + i,
          });
        }
        await batch.commit(noResult: true);
      });
      await store.load();
    });
    await launch(tester);
    await tester.tap(find.text('الحسابات').hitTestable());
    await flush(tester);
    await tester.tap(find.text('حساب كبير').hitTestable());
    await flush(tester);
    expect(find.text('منتج 10000'), findsOneWidget);
    expect(find.byType(OrderTile).evaluate().length, lessThan(15));
    final scroll = find.byType(CustomScrollView).hitTestable();
    for (var i = 0; i < 6; i++) {
      await tester.drag(scroll, const Offset(0, -2200));
      await flush(tester);
    }
    expect(find.byType(OrderTile).evaluate().length, lessThan(15));
    expect(store.report.orders, 10000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets(
    'starter products populate sale; add another product directly from order',
    (tester) async {
      await tester.runAsync(() async {
        for (final name in starterProductNames) {
          await db.saveProduct(name, 18500);
        }
        await db.saveAccount('طلباتي');
        await store.load();
      });
      await launch(tester);
      await tester.tap(find.text('الحسابات').hitTestable());
      await flush(tester);
      await tester.tap(find.text('طلباتي').hitTestable());
      await flush(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'إضافة طلب'));
      await flush(tester);
      await tester.tap(find.text('اختاري من قائمة المنتجات'));
      await flush(tester);
      expect(find.text(starterProductNames.first), findsOneWidget);
      expect(find.text(starterProductNames.last), findsOneWidget);
      await screenshot(tester, 'product-picker');
      await tester.tap(find.text(starterProductNames.first));
      await flush(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('order_sale')))
            .controller!
            .text,
        '185.00',
      );
      await tester.tap(find.text(starterProductNames.first));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('add_product_from_picker')));
      await flush(tester);
      await tester.enterText(
        find.byKey(const ValueKey('product_name')),
        'منتج أضفته من الطلب',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product_price')),
        '225.50',
      );
      final productSave = find.descendant(
        of: find.byType(ProductForm),
        matching: find.byKey(const ValueKey('save_form')),
      );
      await tester.ensureVisible(productSave);
      await tester.pumpAndSettle();
      await tester.tap(productSave);
      await flush(tester);
      expect(find.byType(ProductPicker), findsNothing);
      expect(find.text('منتج أضفته من الطلب'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('order_sale')))
            .controller!
            .text,
        '225.50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('order_purchase')),
        '100',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save_form')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save_form')));
      await flush(tester);
      expect(store.report.orders, 1);
      expect(store.report.products, 3);
      expect(store.report.expectedProfit, 12550);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  testWidgets(
    'long names and numeric fields remain fully visible on narrow screen',
    (tester) async {
      final longName = List.filled(10, 'منتج طويل').join(' ');
      await tester.runAsync(() async {
        await db.saveProduct(longName, maxMoney);
        await store.load();
      });
      await launch(tester, size: const Size(320, 640), scale: 1.8);
      await tester.tap(find.text('المنتجات').hitTestable());
      await flush(tester);
      final name = find.text(longName);
      expect(name, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
        isFalse,
      );
      await screenshot(tester, 'long-product-name');
      final menu = find.byTooltip('خيارات المنتج');
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تعديل').hitTestable());
      await flush(tester);
      expect(find.text('سعر البيع الافتراضي'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('product_price')));
      await tester.pumpAndSettle();
      final edit = find.descendant(
        of: find.byKey(const ValueKey('product_price')),
        matching: find.byType(EditableText),
      );
      final editable = tester.state<EditableTextState>(edit).renderEditable;
      expect(editable.maxScrollExtent, lessThanOrEqualTo(1));
      await screenshot(tester, 'full-field-labels');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );

  testWidgets('failed save preserves fields and shows actionable error', (
    tester,
  ) async {
    await launch(tester);
    final context = tester.element(find.byType(AppShell));
    openSheet(context, ProductForm(store: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('product_name')),
      'يبقى محفوظًا',
    );
    await tester.enterText(find.byKey(const ValueKey('product_price')), '100');
    await tester.runAsync(() => db.close());
    await tester.tap(find.byKey(const ValueKey('save_form')));
    await flush(tester);
    expect(find.text('يبقى محفوظًا'), findsOneWidget);
    expect(find.byType(FormErrorText), findsOneWidget);
    expect(find.byType(ProductForm), findsOneWidget);
    expect(store.report.products, 0);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    await tester.runAsync(() async {
      db = await AppDatabase.open(
        path: '${dir.path}/ui.db',
        factory: databaseFactoryFfi,
      );
    });
  });
}
