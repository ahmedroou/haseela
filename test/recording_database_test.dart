import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:haseela/database.dart';
import 'package:haseela/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late AppDatabase db;
  late int account, product;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'haseela-recording-test-',
    );
    db = await AppDatabase.open(
      path: '${directory.path}/data.db',
      factory: databaseFactoryFfi,
    );
    account = await db.saveAccount('riham@example.com');
    product = (await db.products()).first.id;
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<int> add({
    int quantity = 1,
    int purchase = 10000,
    int? total,
    int sale = 18500,
    OrderStatus status = OrderStatus.pending,
    int? accountId,
    int? productId,
  }) => db.saveOrder(
    accountId: accountId ?? account,
    productId: productId ?? product,
    productName: 'بيبي جوي',
    quantity: quantity,
    purchase: purchase,
    purchaseTotal: total,
    sale: sale,
    status: status,
  );

  test(
    'last purchase is per product, survives order deletion/restart and rolls back on failure',
    () async {
      final first = await add(purchase: 12345);
      final secondProduct = await db.saveProduct('منتج آخر', 20000);
      await add(productId: secondProduct, purchase: 8000);
      expect((await db.product(product))!.lastPurchase, 12345);
      expect((await db.product(secondProduct))!.lastPurchase, 8000);
      await expectLater(
        add(accountId: 99999, purchase: 999),
        throwsA(anything),
      );
      expect((await db.product(product))!.lastPurchase, 12345);
      await db.deleteOrder(first);
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect((await db.product(product))!.lastPurchase, 12345);
      final p = (await db.product(product))!;
      await db.saveProduct('اسم جديد', 19000, old: p);
      expect((await db.product(product))!.lastPurchase, 12345);
    },
  );
  test(
    'total divided among three units preserves every halala in costs, profits and refunds',
    () async {
      final id = await add(
        quantity: 3,
        purchase: 3333,
        total: 10000,
        sale: 5000,
      );
      final order = (await db.orders(account)).single;
      expect(order.cost, 10000);
      expect(order.purchase, 3333);
      expect(order.approximateUnit, isTrue);
      expect(order.profit, 5000);
      expect((await db.report()).expectedProfit, 5000);
      await db.changeStatus(id, OrderStatus.arrived);
      expect((await db.report()).realizedProfit, 0);
      await db.saveReceipt(1000, 'مبلغ مستلم');
      expect((await db.report()).realizedProfit, 1000);
      expect((await db.report()).expectedProfit, 4000);
      await db.changeStatus(id, OrderStatus.cancelled);
      expect((await db.report()).spent, 10000);
      expect((await db.report()).refund, 10000);
      expect((await db.report()).net, 0);
      expect((await db.report()).realizedProfit, 1000);
      await expectLater(
        add(quantity: 3, purchase: 3334, total: 10000),
        throwsFormatException,
      );
    },
  );
  test(
    'manual receipts add actual profit and subtract exactly once from expected; edit/delete reverse amounts',
    () async {
      await add(quantity: 2, purchase: 40000, sale: 55000);
      await add(
        quantity: 3,
        purchase: 30000,
        sale: 45000,
        status: OrderStatus.arrived,
      );
      await add(
        quantity: 3,
        purchase: 35000,
        sale: 50000,
        status: OrderStatus.cancelled,
      );
      expect((await db.report()).grossProfit, 75000);
      expect((await db.report()).realizedProfit, 0);
      final a = await db.saveReceipt(20000, 'أول دفعة');
      final b = await db.saveReceipt(25000, 'ثاني دفعة');
      expect((await db.report()).realizedProfit, 45000);
      expect((await db.report()).expectedProfit, 30000);
      final record = (await db.receipts()).singleWhere((r) => r.id == a);
      await db.saveReceipt(10000, 'تعديل الدفعة', old: record);
      expect((await db.report()).realizedProfit, 35000);
      expect((await db.report()).expectedProfit, 40000);
      await db.deleteReceipt(b);
      expect((await db.report()).realizedProfit, 10000);
      expect((await db.report()).expectedProfit, 65000);
      await db.deleteAccount(account);
      expect((await db.report()).realizedProfit, 10000);
      expect((await db.report()).expectedProfit, -10000);
      await expectLater(db.saveReceipt(0, 'صفر'), throwsFormatException);
    },
  );
  test(
    'email and named account summaries/search stay isolated and complete',
    () async {
      await add(quantity: 2);
      await add(quantity: 3, status: OrderStatus.arrived);
      await add(quantity: 4, status: OrderStatus.cancelled);
      final another = await db.saveAccount('شحنة أخرى');
      await add(accountId: another, quantity: 8);
      final a = (await db.account(account))!;
      expect(a.isEmail, isTrue);
      expect(a.orderCount, 3);
      expect(a.pieces, 9);
      expect([a.pending, a.arrived, a.cancelled], [1, 1, 1]);
      expect((await db.accounts(search: 'example.com')).single.id, account);
      expect((await db.account(another))!.isEmail, isFalse);
      expect((await db.account(another))!.pieces, 8);
      await db.toggleAccountClosed(account, true);
      expect((await db.accounts(openOnly: true)).single.id, another);
    },
  );
  test(
    'format 2 backups keep exact totals, last price, closure and receipts; format 1 stays readable',
    () async {
      await add(quantity: 3, purchase: 3333, total: 10000, sale: 5000);
      await db.saveReceipt(2500, 'أرباح فعلية');
      await db.toggleAccountClosed(account, true);
      final snapshot = await db.snapshot();
      final data = BackupData.decode(snapshot.encode());
      await db.saveAccount('حساب سيُستبدل');
      await db.restore(data);
      expect((await db.account(account))!.isClosed, isTrue);
      expect((await db.product(product))!.lastPurchase, 3333);
      expect((await db.orders(account)).single.cost, 10000);
      expect((await db.report()).realizedProfit, 2500);
      expect((await db.report()).expectedProfit, 2500);
      final legacy = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      legacy['version'] = 1;
      legacy.remove('receipts');
      for (final p in legacy['products'] as List) {
        (p as Map).remove('last_purchase');
      }
      for (final o in legacy['orders'] as List) {
        (o as Map).remove('purchase_total');
      }
      for (final a in legacy['accounts'] as List) {
        (a as Map).remove('is_closed');
      }
      await db.restore(BackupData.decode(jsonEncode(legacy)));
      expect((await db.orders(account)).single.cost, 9999);
      expect((await db.report()).realizedProfit, 0);
      expect((await db.account(account))!.isClosed, isFalse);
      final corrupt = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      corrupt['receipts'][0]['amount'] = -1;
      expect(
        () => BackupData.decode(jsonEncode(corrupt)),
        throwsFormatException,
      );
      expect((await db.report()).spent, 9999);
    },
  );
  test(
    'real v3 schema migrates without losing orders and infers previous purchase price',
    () async {
      await db.close();
      final path = '${directory.path}/legacy.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (database, version) async {
            await database.execute(
              'CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT NOT NULL, sale INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
            );
            await database.execute(
              'CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
            );
            await database.execute(
              'CREATE TABLE orders (id INTEGER PRIMARY KEY, account_id INTEGER, product_id INTEGER, product_name TEXT NOT NULL, quantity INTEGER, purchase INTEGER, sale INTEGER, status TEXT NOT NULL, created_at INTEGER, updated_at INTEGER)',
            );
            await database.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await database.insert('products', {
              'id': 1,
              'name': 'منتج محفوظ',
              'sale': 18500,
              'created_at': 1000,
              'updated_at': 1000,
            });
            await database.insert('accounts', {
              'id': 1,
              'name': 'saved@example.com',
              'created_at': 1000,
              'updated_at': 1000,
            });
            for (var i = 1; i <= 2; i++) {
              await database.insert('orders', {
                'id': i,
                'account_id': 1,
                'product_id': 1,
                'product_name': 'منتج محفوظ',
                'quantity': 1,
                'purchase': i == 1 ? 7500 : 8000,
                'sale': 18500,
                'status': 'arrived',
                'created_at': 1000 + i,
                'updated_at': 1000 + i,
              });
            }
          },
        ),
      );
      await old.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect(await db.db.getVersion(), 5);
      expect((await db.product(1))!.lastPurchase, 8000);
      expect((await db.orders(1)).length, 2);
      expect((await db.report()).spent, 15500);
      expect((await db.report()).realizedProfit, 0);
      expect((await db.account(1))!.isClosed, isFalse);
      expect(await db.receipts(), isEmpty);
    },
  );
  test(
    'refund journal includes all cancelled orders across accounts with exact cost and pagination',
    () async {
      final other = await db.saveAccount('other@example.com');
      for (var i = 0; i < 85; i++) {
        await add(
          accountId: i.isEven ? account : other,
          quantity: 3,
          purchase: 3333,
          total: 10000,
          status: OrderStatus.cancelled,
        );
      }
      await add(status: OrderStatus.pending);
      final a = await db.cancelledOrders(),
          b = await db.cancelledOrders(offset: 40),
          c = await db.cancelledOrders(offset: 80);
      expect([a.length, b.length, c.length], [40, 40, 5]);
      expect(
        {
          ...a.map((r) => r.id),
          ...b.map((r) => r.id),
          ...c.map((r) => r.id),
        }.length,
        85,
      );
      expect(
        a.every(
          (r) =>
              r.status == OrderStatus.cancelled &&
              r.cost == 10000 &&
              r.accountName != null,
        ),
        isTrue,
      );
      expect((await db.report()).refund, 850000);
    },
  );
}
