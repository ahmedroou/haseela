import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:haseela/database.dart';
import 'package:haseela/domain.dart';
import 'package:haseela/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<int> totals(Report r) => [
  r.accounts,
  r.products,
  r.orders,
  r.pieces,
  r.pending,
  r.arrived,
  r.cancelled,
  r.spent,
  r.expectedSales,
  r.expectedProfit,
  r.realizedProfit,
  r.arrivedSales,
  r.refund,
  r.net,
];

void main() {
  late AppDatabase db;
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('haseela_closed_');
    db = await AppDatabase.open(
      path: '${dir.path}/data.db',
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'closing, renaming with stale data and reopening retain orders and totals',
    () async {
      final id = await db.saveAccount('حساب محفوظ');
      final original = (await db.account(id))!;
      for (final status in OrderStatus.values) {
        await db.saveOrder(
          accountId: id,
          productId: null,
          productName: 'منتج',
          quantity: 3,
          purchase: 3333,
          purchaseTotal: 10000,
          sale: 5000,
          status: status,
        );
      }
      await db.saveReceipt(2000, 'ربح مستلم');
      final before = totals(await db.report());
      final orders = (await db.orders(id)).map((o) => o.toMap()).toList();
      await db.toggleAccountClosed(id, true);
      final closed = (await db.account(id))!;
      expect(closed.closedAt, isNotNull);
      expect(closed.closedAt, closed.updatedAt);
      expect(closed.createdAt, original.createdAt);
      expect(await db.accounts(filter: AccountFilter.open), isEmpty);
      expect((await db.accounts(filter: AccountFilter.closed)).single.id, id);
      final store = AppStore(db);
      await store.load();
      expect(store.recent, isEmpty);
      store.dispose();

      // A name-only save must use the persisted state rather than a stale model.
      await db.saveAccount('اسم معدل', old: original);
      expect((await db.account(id))!.closedAt, closed.closedAt);
      expect((await db.account(id))!.isClosed, isTrue);
      await db.toggleAccountClosed(id, true);
      expect((await db.account(id))!.closedAt, closed.closedAt);
      expect(totals(await db.report()), before);
      expect((await db.orders(id)).map((o) => o.toMap()).toList(), orders);

      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect((await db.account(id))!.closedAt, closed.closedAt);
      expect(totals(await db.report()), before);
      expect((await db.orders(id)).map((o) => o.toMap()).toList(), orders);
      await db.toggleAccountClosed(id, false);
      expect((await db.account(id))!.closedAt, isNull);
      expect((await db.accounts(filter: AccountFilter.open)).single.id, id);
      expect(await db.accounts(filter: AccountFilter.closed), isEmpty);
      expect(totals(await db.report()), before);
    },
  );

  test(
    'closure transitions through saveAccount preserve the date until reopened',
    () async {
      final id = await db.saveAccount('يبدأ مغلقًا', isClosed: true);
      final closed = (await db.account(id))!;
      expect(closed.closedAt, closed.createdAt);
      await db.saveAccount('اسم جديد', old: closed, isClosed: true);
      expect((await db.account(id))!.closedAt, closed.closedAt);
      await db.saveAccount('مفتوح', old: closed, isClosed: false);
      expect((await db.account(id))!.closedAt, isNull);
      // Set an old creation date to make a new closing time unambiguous.
      await db.db.update(
        'accounts',
        {'created_at': 1000, 'updated_at': 1000},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.saveAccount(
        'مغلق مجددًا',
        old: (await db.account(id))!,
        isClosed: true,
      );
      final again = (await db.account(id))!;
      expect(again.closedAt, greaterThan(1000));
      expect(again.closedAt, again.updatedAt);
      expect(again.createdAt, 1000);
      await db.toggleAccountClosed(id, false);
      await db.toggleAccountClosed(id, true);
      expect((await db.account(id))!.closedAt, isNotNull);
    },
  );

  test(
    'closed sorting uses closing time and id, search and 40-row pages',
    () async {
      final open = await db.saveAccount('مفتوح');
      final ids = <int>[];
      for (var i = 0; i < 85; i++) {
        final id = await db.saveAccount('محفوظ $i', isClosed: true);
        ids.add(id);
        await db.db.update(
          'accounts',
          {
            'created_at': 1000 + (84 - i),
            'closed_at': 2000 + i ~/ 2,
            'updated_at': 3000,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      final first = await db.accounts(filter: AccountFilter.closed);
      final second = await db.accounts(
        filter: AccountFilter.closed,
        offset: 40,
      );
      final third = await db.accounts(filter: AccountFilter.closed, offset: 80);
      expect([first.length, second.length, third.length], [40, 40, 5]);
      expect([...first, ...second, ...third].map((a) => a.id).toList(), ids);
      expect((await db.accounts(filter: AccountFilter.open)).single.id, open);
      expect(
        (await db.accounts(
          filter: AccountFilter.closed,
          search: 'محفوظ 84',
        )).single.id,
        ids.last,
      );
      expect(
        await db.accounts(filter: AccountFilter.closed, search: 'مفتوح'),
        isEmpty,
      );
      // Editing the oldest closed account keeps its place; re-closing moves it last.
      await db.saveAccount('معدل', old: first.first);
      expect(
        (await db.accounts(filter: AccountFilter.closed)).first.id,
        ids.first,
      );
      await db.toggleAccountClosed(ids.first, false);
      await db.toggleAccountClosed(ids.first, true);
      expect(
        (await db.accounts(filter: AccountFilter.closed, offset: 80)).last.id,
        ids.first,
      );
    },
  );

  test(
    'real v5 schema gains estimated closure times without altering data',
    () async {
      final a = await db.saveAccount('قديم', isClosed: true);
      final b = await db.saveAccount('مفتوح');
      await db.db.update(
        'accounts',
        {'created_at': 1000, 'updated_at': 2000},
        where: 'id = ?',
        whereArgs: [a],
      );
      await db.saveOrder(
        accountId: b,
        productId: null,
        productName: 'قديم',
        quantity: 2,
        purchase: 100,
        sale: 200,
        status: OrderStatus.arrived,
      );
      await db.saveReceipt(100, 'محفوظ');
      await db.setTheme('dark');
      final before = totals(await db.report());
      final snapshot = await db.snapshot();
      await db.db.execute('DROP INDEX account_closed_date');
      await db.db.execute('ALTER TABLE accounts DROP COLUMN closed_at');
      await db.db.setVersion(5);
      final path = db.db.path;
      await db.close();
      db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
      expect(await db.db.getVersion(), 7);
      expect((await db.account(a))!.closedAt, 2000);
      expect((await db.account(a))!.updatedAt, 2000);
      expect((await db.account(b))!.closedAt, isNull);
      expect(totals(await db.report()), before);
      expect(await db.theme(), 'dark');
      expect(
        (await db.snapshot()).orders.map((o) => o.toMap()).toList(),
        snapshot.orders.map((o) => o.toMap()).toList(),
      );
      final queryPlan = await db.db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM accounts WHERE is_closed=1 ORDER BY closed_at ASC, id ASC LIMIT 40',
      );
      expect(queryPlan.toString(), contains('account_closed_date'));
    },
  );

  test(
    'backups v3 and v4 preserve dates; v1/v2 use last change, invalid dates abort restore',
    () async {
      final a = await db.saveAccount('مغلق', isClosed: true);
      await db.db.update(
        'accounts',
        {'created_at': 1000, 'closed_at': 2000, 'updated_at': 3000},
        where: 'id = ?',
        whereArgs: [a],
      );
      await db.saveAccount('مفتوح');
      final snapshot = await db.snapshot();
      final root = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      expect(root['version'], 4);
      await db.restore(BackupData.decode(snapshot.encode()));
      expect((await db.account(a))!.closedAt, 2000);
      expect(await db.latestSafetyCopy(), isNotNull);
      root['version'] = 3;
      root.remove('side_costs');
      await db.restore(BackupData.decode(jsonEncode(root)));
      expect((await db.account(a))!.closedAt, 2000);
      for (final version in [1, 2]) {
        final legacy = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
        legacy['version'] = version;
        for (final row in legacy['accounts'] as List) {
          (row as Map).remove('closed_at');
        }
        if (version == 1) legacy.remove('receipts');
        await db.restore(BackupData.decode(jsonEncode(legacy)));
        expect((await db.account(a))!.closedAt, 3000);
        expect(
          (await db.accounts(filter: AccountFilter.open)).single.closedAt,
          isNull,
        );
      }
      for (final value in [null, '2000', 0, 999, 3001, 8640000000000001]) {
        final bad = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
        bad['accounts'][0]['closed_at'] = value;
        expect(() => BackupData.decode(jsonEncode(bad)), throwsFormatException);
      }
      final bad = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      bad['accounts'][1]['closed_at'] = 2000;
      expect(() => BackupData.decode(jsonEncode(bad)), throwsFormatException);
      final invalid = BackupData(
        products: snapshot.products,
        orders: snapshot.orders,
        accounts: [
          const Account(
            id: 1,
            name: 'غير صالح',
            createdAt: 1000,
            updatedAt: 3000,
            isClosed: true,
            closedAt: 999,
          ),
        ],
        theme: 'light',
      );
      final before = (await db.snapshot()).encode();
      await expectLater(db.restore(invalid), throwsFormatException);
      expect(
        (await db.snapshot()).accounts.map((a) => a.toMap()).toList(),
        BackupData.decode(before).accounts.map((a) => a.toMap()).toList(),
      );
    },
  );

  test(
    'last purchase and status changes update timestamps and keep creation times',
    () async {
      final a = await db.saveAccount('طلب');
      final p = (await db.products()).first;
      await db.db.update(
        'products',
        {'created_at': 1000, 'updated_at': 1000},
        where: 'id = ?',
        whereArgs: [p.id],
      );
      final id = await db.saveOrder(
        accountId: a,
        productId: p.id,
        productName: p.name,
        quantity: 1,
        purchase: 100,
        sale: 200,
        status: OrderStatus.pending,
      );
      expect((await db.product(p.id))!.createdAt, 1000);
      expect((await db.product(p.id))!.updatedAt, greaterThan(1000));
      final productTime = (await db.product(p.id))!.updatedAt;
      await expectLater(
        db.saveOrder(
          accountId: 99999,
          productId: p.id,
          productName: p.name,
          quantity: 1,
          purchase: 300,
          sale: 400,
          status: OrderStatus.pending,
        ),
        throwsA(anything),
      );
      expect((await db.product(p.id))!.updatedAt, productTime);
      await db.db.update(
        'orders',
        {'created_at': 1000, 'updated_at': 1000},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.changeStatus(id, OrderStatus.arrived);
      final order = (await db.orders(a)).single;
      expect(order.createdAt, 1000);
      expect(order.updatedAt, greaterThan(1000));
    },
  );
}
