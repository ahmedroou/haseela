import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:haseela/database.dart';
import 'package:haseela/domain.dart';
import 'package:haseela/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late List<Product> starterProducts;
  setUpAll(() => sqfliteFfiInit());
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('haseela_test_');
    db = await AppDatabase.open(
      path: '${dir.path}/data.db',
      factory: databaseFactoryFfi,
    );
    starterProducts = await db.products();
    await db.db.delete('products');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'starter products cost 185 SAR and remain editable and deletable',
    () async {
      expect(
        starterProducts.map((p) => p.name).toSet(),
        starterProductNames.toSet(),
      );
      expect(starterProducts.every((p) => p.sale == 18500), isTrue);
      // The fixture deleted them just as a user can. Reopening must not resurrect them.
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect(await db.products(), isEmpty);
      final id = await db.saveProduct(starterProductNames.first, 18500);
      final product = (await db.product(id))!;
      await db.saveProduct('منتج معدّل', 19900, old: product);
      expect((await db.product(id))!.sale, 19900);
      await db.deleteProduct(id);
      expect(await db.product(id), isNull);
    },
  );
  test(
    'v2 upgrade adds missing starter without duplicating or changing existing data',
    () async {
      final id = await db.saveProduct('بيبي جوي كرتون رقم ٤', 21000);
      final a = await db.saveAccount('حساب محفوظ');
      await db.saveOrder(
        accountId: a,
        productId: id,
        productName: 'بيبي جوي',
        quantity: 2,
        purchase: 40000,
        sale: 22000,
        status: OrderStatus.pending,
      );
      await db.db.setVersion(2);
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      final products = await db.products();
      expect(products.length, 2);
      expect((await db.product(id))!.sale, 21000);
      expect(
        products.singleWhere((p) => p.name == starterProductNames.last).sale,
        18500,
      );
      expect((await db.orders(a)).single.sale, 22000);
      await db.deleteProduct(
        products.singleWhere((p) => p.name == starterProductNames.last).id,
      );
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect((await db.products()).length, 1);
    },
  );

  Future<int> addOrder(
    int account,
    int? product, {
    int q = 2,
    int buy = 40000,
    int sell = 55000,
    OrderStatus status = OrderStatus.pending,
  }) => db.saveOrder(
    accountId: account,
    productId: product,
    productName: 'AirPods Pro',
    quantity: q,
    purchase: buy,
    sale: sell,
    status: status,
  );

  test(
    'SQL report matches reference including fractional money and loss',
    () async {
      final a = await db.saveAccount('سبتمبر');
      final p = await db.saveProduct('AirPods Pro', 55000);
      await addOrder(a, p);
      await addOrder(
        a,
        p,
        q: 3,
        buy: 30000,
        sell: 45000,
        status: OrderStatus.arrived,
      );
      await addOrder(
        a,
        p,
        q: 3,
        buy: 35000,
        sell: 50000,
        status: OrderStatus.cancelled,
      );
      var r = await db.report();
      expect(r.spent, 275000);
      expect(r.expectedProfit, 75000);
      expect(r.realizedProfit, 45000);
      expect(r.refund, 105000);
      expect(r.net, 170000);
      expect(r.expectedSales, 245000);
      final loss = await addOrder(
        a,
        p,
        q: 3,
        buy: 29,
        sell: 10,
        status: OrderStatus.arrived,
      );
      r = await db.report();
      expect(r.realizedProfit, 44943);
      await db.deleteOrder(loss);
      expect((await db.report()).realizedProfit, 45000);
    },
  );
  test(
    'editing or deleting catalog product preserves historical orders',
    () async {
      final a = await db.saveAccount('سبتمبر'),
          p = await db.saveProduct('AirPods Pro', 55000);
      await addOrder(a, p);
      final product = (await db.products()).single;
      await db.saveProduct('اسم جديد', 90000, old: product);
      var o = (await db.orders(a)).single;
      expect(o.productName, 'AirPods Pro');
      expect(o.sale, 55000);
      await db.deleteProduct(p);
      o = (await db.orders(a)).single;
      expect(o.productId, isNull);
      expect(o.productName, 'AirPods Pro');
      expect(o.sale, 55000);
      await db.saveOrder(
        accountId: a,
        productId: null,
        productName: 'اسم الطلب المعدّل',
        quantity: 3,
        purchase: 35000,
        sale: 60000,
        status: OrderStatus.arrived,
        old: o,
      );
      expect((await db.orders(a)).single.createdAt, o.createdAt);
      expect((await db.report()).realizedProfit, 75000);
    },
  );
  test(
    'status reversal and cascade delete update the unified report',
    () async {
      final a = await db.saveAccount('سبتمبر'),
          b = await db.saveAccount('أكتوبر');
      final o = await addOrder(a, null);
      await addOrder(b, null, q: 1, buy: 1000, sell: 2000);
      await db.changeStatus(o, OrderStatus.cancelled);
      expect((await db.report()).refund, 80000);
      await db.changeStatus(o, OrderStatus.arrived);
      expect((await db.report()).refund, 0);
      expect((await db.report()).realizedProfit, 30000);
      await db.deleteAccount(a);
      final r = await db.report();
      expect(r.accounts, 1);
      expect(r.orders, 1);
      expect(r.spent, 1000);
    },
  );
  test('persistent data and theme survive close and reopen', () async {
    final a = await db.saveAccount('سبتمبر');
    await addOrder(a, null);
    await db.setTheme('dark');
    final path = db.db.path;
    await db.close();
    db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    expect((await db.report()).spent, 80000);
    expect(await db.theme(), 'dark');
    expect((await db.accounts()).single.name, 'سبتمبر');
  });
  test(
    'backup replacement is complete and previous data is recoverable',
    () async {
      final a = await db.saveAccount('القديم');
      await addOrder(a, null);
      final original = await db.snapshot();
      final replacement = BackupData(
        products: const [],
        accounts: const [
          Account(id: 10, name: 'الجديد', createdAt: 1000, updatedAt: 1000),
        ],
        orders: const [],
        theme: 'dark',
      );
      await db.restore(replacement);
      expect((await db.accounts()).single.name, 'الجديد');
      expect((await db.report()).orders, 0);
      expect(await db.theme(), 'dark');
      final safety = await db.latestSafetyCopy();
      expect(safety, isNotNull);
      final saved = BackupData.decode(await File(safety!).readAsString());
      expect(saved.orders.single.cost, original.orders.single.cost);
      await db.restore(saved);
      expect((await db.report()).spent, 80000);
      final nextId = await db.saveAccount('بعد الاستعادة');
      expect(nextId, greaterThan(10));
    },
  );
  test('failed import leaves original database and theme untouched', () async {
    final a = await db.saveAccount('الأصل');
    await addOrder(a, null);
    final invalid = BackupData(
      products: const [],
      accounts: const [],
      orders: (await db.snapshot()).orders,
      theme: 'light',
    );
    await expectLater(db.restore(invalid), throwsFormatException);
    expect((await db.accounts()).single.name, 'الأصل');
    expect((await db.report()).orders, 1);
    expect(await db.latestSafetyCopy(), isNull);
  });
  test('SQL constraints and numeric bounds prevent invalid writes', () async {
    final a = await db.saveAccount('سبتمبر');
    await expectLater(addOrder(999, null), throwsA(anything));
    await expectLater(addOrder(a, null, q: 0), throwsFormatException);
    await expectLater(
      addOrder(a, null, q: 2, buy: maxMoney),
      throwsFormatException,
    );
    expect((await db.report()).orders, 0);
  });
  test('search treats percent and underscore as literal characters', () async {
    await db.saveProduct('خصم 10%', 100);
    await db.saveProduct('اسم_خاص', 200);
    await db.saveProduct('منتج', 300);
    expect((await db.products(search: '%')).single.name, 'خصم 10%');
    expect((await db.products(search: '_')).single.name, 'اسم_خاص');
  });
  test('controller refreshes report only after writes are committed', () async {
    final store = AppStore(db);
    await store.load();
    final oldRevision = store.revision;
    await store.mutate(() => db.saveAccount('جديد'));
    expect(store.report.accounts, 1);
    expect(store.revision, oldRevision + 1);
    expect(store.busy, false);
    await expectLater(
      store.mutate(() => db.saveProduct('', 100)),
      throwsFormatException,
    );
    expect(store.report.products, 0);
    expect(store.busy, false);
    store.dispose();
  });
  test('v1 to v3 migration keeps existing data and adds product index', () async {
    final a = await db.saveAccount('قبل التحديث');
    await addOrder(a, null);
    await db.setTheme('dark');
    await db.db.execute('DROP INDEX order_product');
    await db.db.setVersion(1);
    final path = db.db.path;
    await db.close();
    db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    expect(await db.db.getVersion(), 3);
    expect((await db.report()).spent, 80000);
    expect(await db.theme(), 'dark');
    expect(
      await db.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='order_product'",
      ),
      isNotEmpty,
    );
  });

  test('10000 orders aggregate and paginate without loading all rows', () async {
    final a = await db.saveAccount('حساب كبير');
    await db.db.transaction((tx) async {
      final batch = tx.batch();
      for (var i = 1; i <= 10000; i++) {
        batch.insert('orders', {
          'account_id': a,
          'product_id': null,
          'product_name': 'منتج $i',
          'quantity': 2,
          'purchase': 12345,
          'sale': 23456,
          'status': OrderStatus.values[i % 3].name,
          'created_at': 1000 + i,
          'updated_at': 1000 + i,
        });
      }
      await batch.commit(noResult: true);
    });
    final clock = Stopwatch()..start();
    final r = await db.report();
    final first = await db.orders(a), second = await db.orders(a, offset: 40);
    clock.stop();
    expect(r.orders, 10000);
    expect(r.pieces, 20000);
    expect(r.spent, 246900000);
    expect(first.length, 40);
    expect(first.first.productName, 'منتج 10000');
    expect(first.last.id, greaterThan(second.first.id));
    expect(second.length, 40);
    // Loose bound detects accidental per-row query regressions, not a device FPS claim.
    expect(clock.elapsedMilliseconds, lessThan(5000));
    // ignore: avoid_print
    print(
      '10000-order SQL report + 80 paged rows: ${clock.elapsedMilliseconds} ms (Windows test host)',
    );
  });
}
