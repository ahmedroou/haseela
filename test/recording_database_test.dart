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

  List<OrderItem> mixedItems({int? secondProductId}) => [
    OrderItem(
      productId: product,
      productName: 'منتج أول',
      quantity: 3,
      purchase: 3333,
      purchaseTotal: 10000,
      sale: 5000,
    ),
    OrderItem(
      productId: secondProductId,
      productName: 'منتج ثانٍ',
      quantity: 2,
      purchase: 725,
      sale: 1101,
    ),
  ];

  test(
    'combined products retain exact costs, sales, counts and status',
    () async {
      final second = await db.saveProduct('ثانٍ', 1101);
      final ids = await db.saveOrders(
        accountId: account,
        items: mixedItems(secondProductId: second),
        status: OrderStatus.pending,
      );
      expect(ids, hasLength(1));
      final order = (await db.orders(account)).single;
      expect(order.items, hasLength(2));
      expect(order.quantity, 5);
      expect(order.cost, 11450);
      expect(order.revenue, 17202);
      expect(order.profit, 5752);
      expect((await db.product(product))!.lastPurchase, 3333);
      expect((await db.product(second))!.lastPurchase, 725);
      await db.saveSideCost(505, 'شحن');
      await db.saveReceipt(1000, 'مستلم');
      await db.saveProfitShare('نور', 1250);
      final report = await db.report();
      final reference = Report.fromOrders(
        [order],
        sideCosts: 505,
        receivedProfit: 1000,
        profitShare: report.profitShare,
      );
      expect(report.orders, 1);
      expect(report.pieces, 5);
      expect(report.expectedSales, reference.expectedSales);
      expect(report.expectedProfit, reference.expectedProfit);
      expect(report.thirdPartyProfit, reference.thirdPartyProfit);
      expect((await db.account(account))!.orderCount, 1);
      expect((await db.account(account))!.pieces, 5);

      await db.changeStatus(ids.single, OrderStatus.arrived);
      expect((await db.report()).arrivedSales, 17202);
      await db.changeStatus(ids.single, OrderStatus.cancelled);
      expect((await db.report()).refund, 11450);
      expect((await db.report()).expectedSales, 0);
      expect((await db.cancelledOrders()).single.items, hasLength(2));
      await db.changeStatus(ids.single, OrderStatus.pending);
      expect((await db.report()).expectedProfit, report.expectedProfit);

      await db.deleteProduct(second);
      final retained = (await db.orders(account)).single;
      expect(retained.items.last.productId, isNull);
      expect(retained.items.last.productName, 'منتج ثانٍ');
      expect(retained.revenue, 17202);
      await db.deleteAccount(account);
      expect(await db.db.query('order_items'), isEmpty);
    },
  );

  test('separate products save together and reverse independently', () async {
    final ids = await db.saveOrders(
      accountId: account,
      items: mixedItems(),
      status: OrderStatus.pending,
      separate: true,
    );
    expect(ids, hasLength(2));
    expect((await db.report()).orders, 2);
    expect((await db.report()).pieces, 5);
    expect((await db.report()).expectedSales, 17202);
    expect((await db.report()).spent, 11450);
    expect((await db.orders(account)).every((o) => o.items.isEmpty), isTrue);
    await db.changeStatus(ids.first, OrderStatus.cancelled);
    expect((await db.report()).refund, 10000);
    expect((await db.report()).expectedSales, 2202);
    await db.deleteOrder(ids.last);
    expect((await db.report()).orders, 1);
  });

  test('failed batches roll back every product and purchase memory', () async {
    for (final separate in [false, true]) {
      await expectLater(
        db.saveOrders(
          accountId: account,
          items: mixedItems(secondProductId: 999999),
          status: OrderStatus.pending,
          separate: separate,
        ),
        throwsA(anything),
      );
      expect(await db.orders(account), isEmpty);
      expect(await db.db.query('order_items'), isEmpty);
      expect((await db.product(product))!.lastPurchase, isNull);
    }
    await db.saveSideCost(maxMoney - 11449, 'حد المبالغ');
    await expectLater(
      db.saveOrders(
        accountId: account,
        items: mixedItems(),
        status: OrderStatus.pending,
        separate: true,
      ),
      throwsFormatException,
    );
    expect(await db.orders(account), isEmpty);
    await db.toggleAccountClosed(account, true);
    await db.deleteSideCost((await db.sideCosts()).single.id);
    await expectLater(
      db.saveOrders(
        accountId: account,
        items: mixedItems(),
        status: OrderStatus.pending,
      ),
      throwsStateError,
    );
  });

  test(
    'combined orders survive restart, backup and edits down to one product',
    () async {
      await db.saveOrders(
        accountId: account,
        items: mixedItems(),
        status: OrderStatus.pending,
      );
      final original = (await db.orders(account)).single;
      final snapshot = await db.snapshot();
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect(
        (await db.orders(account)).single.toBackupMap(),
        original.toBackupMap(),
      );
      for (final field in ['quantity', 'sale', 'product_id']) {
        final invalid = jsonDecode(snapshot.encode()) as Map;
        invalid['orders'][0]['items'][0][field] = 999999;
        expect(
          () => BackupData.decode(jsonEncode(invalid)),
          throwsFormatException,
        );
      }
      await db.restore(BackupData.decode(snapshot.encode()));
      expect(
        (await db.orders(account)).single.toBackupMap(),
        original.toBackupMap(),
      );
      await db.saveOrders(
        accountId: account,
        items: [mixedItems().last],
        status: OrderStatus.arrived,
        old: original,
      );
      final edited = (await db.orders(account)).single;
      expect(edited.id, original.id);
      expect(edited.createdAt, original.createdAt);
      expect(edited.items, isEmpty);
      expect(edited.saleTotal, isNull);
      expect(edited.revenue, 2202);
      expect((await db.report()).spent, 1450);
      expect(await db.db.query('order_items'), isEmpty);
      await expectLater(
        db.saveOrders(
          accountId: account,
          items: mixedItems(),
          status: OrderStatus.pending,
          old: original,
          separate: true,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'v8 migration and legacy v5 backups retain single product orders',
    () async {
      await add(quantity: 3, purchase: 3333, total: 10000, sale: 5000);
      final legacy = jsonDecode((await db.snapshot()).encode()) as Map;
      legacy['version'] = 5;
      (legacy['orders'][0] as Map).remove('items');
      (legacy['orders'][0] as Map).remove('sale_total');
      await db.db.execute('DROP TABLE order_items');
      await db.db.execute('ALTER TABLE orders DROP COLUMN sale_total');
      await db.db.setVersion(8);
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect(await db.db.getVersion(), 10);
      expect((await db.report()).spent, 10000);
      expect((await db.report()).expectedSales, 15000);
      expect((await db.orders(account)).single.items, isEmpty);
      await db.restore(BackupData.decode(jsonEncode(legacy)));
      expect((await db.report()).expectedProfit, 5000);
      expect(
        (await db.orders(account)).single.lines.single.purchaseTotal,
        10000,
      );
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
    'side costs affect spending and expected profit, with optional notes and backup restore',
    () async {
      await add();
      await add(purchase: 5000, status: OrderStatus.cancelled);
      await db.saveReceipt(1000, 'مبلغ مستلم');
      final shipping = await db.saveSideCost(2505, '  الشحن  ');
      final extra = await db.saveSideCost(8000, '');
      final report = await db.report();
      expect(report.sideCosts, 10505);
      expect(report.spent, 25505);
      expect(report.refund, 5000);
      expect(report.net, 20505);
      expect(report.expectedProfit, -3005);
      expect(report.realizedProfit, 1000);

      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      final costs = await db.sideCosts();
      expect(costs.map((cost) => cost.id), [extra, shipping]);
      expect(costs.map((cost) => cost.note), ['', 'الشحن']);
      final snapshot = BackupData.decode((await db.snapshot()).encode());

      await db.saveSideCost(1505, '', old: costs.last);
      await db.deleteSideCost(extra);
      expect((await db.report()).expectedProfit, 5995);
      expect((await db.sideCosts()).single.note, isEmpty);
      expect((await db.sideCosts()).single.createdAt, costs.last.createdAt);
      await db.restore(snapshot);
      expect((await db.report()).sideCosts, report.sideCosts);
      expect((await db.report()).expectedProfit, report.expectedProfit);

      final backup = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      (backup['side_costs'] as List).first['amount'] = 0;
      expect(
        () => BackupData.decode(jsonEncode(backup)),
        throwsFormatException,
      );
      await expectLater(db.saveSideCost(0, ''), throwsFormatException);

      await db.deleteAccount(account);
      final costsWithoutOrders = await db.report();
      expect(costsWithoutOrders.spent, 10505);
      expect(costsWithoutOrders.expectedProfit, -11505);
    },
  );

  test(
    'v7 upgrade and backups preserve named profit sharing without affecting expenses',
    () async {
      final orderId = await add(purchase: 10000, sale: 30000);
      await db.saveSideCost(2000, 'شحن');
      await db.saveReceipt(3000, 'ربح مستلم');
      await db.db.execute('DROP TABLE profit_share');
      await db.db.setVersion(7);
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect(await db.db.getVersion(), 10);
      expect((await db.report()).expectedProfit, 15000);
      expect((await db.report()).profitShare, isNull);
      final legacy = jsonDecode((await db.snapshot()).encode()) as Map;
      legacy['version'] = 4;
      legacy.remove('profit_share');

      await db.saveProfitShare('  نور  ', 5000);
      await expectLater(
        db.saveProfitShare('مرفوض', 5001),
        throwsFormatException,
      );
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      final report = await db.report();
      expect(report.profitShare!.name, 'نور');
      expect(report.thirdPartyProfit, 9000);
      expect(report.expectedProfit, 6000);
      expect(report.spent, 12000);
      expect(report.realizedProfit, 3000);

      final snapshot = BackupData.decode((await db.snapshot()).encode());
      await db.changeStatus(orderId, OrderStatus.cancelled);
      expect((await db.report()).thirdPartyProfit, 0);
      expect((await db.report()).expectedProfit, -5000);
      await db.restore(BackupData.decode(jsonEncode(legacy)));
      expect((await db.report()).profitShare, isNull);
      expect((await db.report()).expectedProfit, 15000);
      await db.restore(snapshot);
      expect(
        (await db.report()).profitShare!.toMap(),
        report.profitShare!.toMap(),
      );
      expect((await db.report()).expectedProfit, 6000);
      final invalid = jsonDecode(snapshot.encode()) as Map;
      invalid['profit_share']['rate'] = 5001;
      expect(
        () => BackupData.decode(jsonEncode(invalid)),
        throwsFormatException,
      );

      await db.saveProfitShare('نور', 1200);
      expect((await db.report()).thirdPartyProfit, 2160);
      expect(
        (await db.report()).profitShare!.createdAt,
        report.profitShare!.createdAt,
      );
      await db.removeProfitShare();
      expect((await db.report()).expectedProfit, 15000);
    },
  );

  test(
    'v9 database with old 3500 CHECK constraint upgrades to allow up to 5000 while keeping share',
    () async {
      await db.db.execute('DROP TABLE profit_share');
      await db.db.execute('''CREATE TABLE profit_share (
        id INTEGER PRIMARY KEY CHECK(id = 1), name TEXT NOT NULL,
        rate INTEGER NOT NULL CHECK(rate BETWEEN 1 AND 3500),
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
      await db.db.insert('profit_share', {
        'id': 1,
        'name': 'نور',
        'rate': 3500,
        'created_at': 1000,
        'updated_at': 2000,
      });
      await db.db.setVersion(9);
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect(await db.db.getVersion(), 10);
      final kept = (await db.report()).profitShare!;
      expect(kept.name, 'نور');
      expect(kept.rate, 3500);
      expect(kept.createdAt, 1000);
      expect(kept.updatedAt, 2000);
      await db.saveProfitShare('نور', 5000);
      expect((await db.report()).profitShare!.rate, 5000);
    },
  );

  test(
    'v6 database gains side costs without changing existing totals',
    () async {
      await add();
      await db.saveReceipt(1500, 'قديم');
      await db.db.execute('DROP TABLE side_costs');
      await db.db.setVersion(6);
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect((await db.report()).spent, 10000);
      expect((await db.report()).expectedProfit, 7000);
      expect(await db.sideCosts(), isEmpty);
      await db.saveSideCost(2000, 'تغليف');
      expect((await db.report()).expectedProfit, 5000);
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
      expect(
        (await db.accounts(filter: AccountFilter.open)).single.id,
        another,
      );
    },
  );
  test(
    'format 3 backups keep exact totals, last price, closure and receipts; format 1 stays readable',
    () async {
      await add(quantity: 3, purchase: 3333, total: 10000, sale: 5000);
      await db.saveReceipt(2500, 'أرباح فعلية');
      await db.toggleAccountClosed(account, true);
      final snapshot = await db.snapshot();
      final data = BackupData.decode(snapshot.encode());
      await db.saveAccount('حساب سيُستبدل');
      await db.restore(data);
      expect((await db.account(account))!.isClosed, isTrue);
      expect(
        (await db.account(account))!.closedAt,
        snapshot.accounts.single.closedAt,
      );
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
      expect(await db.db.getVersion(), 10);
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
