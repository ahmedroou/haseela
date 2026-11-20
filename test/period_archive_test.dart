import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haseela/database.dart';
import 'package:haseela/domain.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('haseela_period_');
    db = await AppDatabase.open(
      path: p.join(dir.path, 'main.db'),
      factory: databaseFactoryFfi,
    );
    await db.db.delete('products');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> order(
    int account,
    String name, {
    int? product,
    int sale = 2500,
  }) => db.saveOrder(
    accountId: account,
    productId: product,
    productName: name,
    quantity: 1,
    purchase: 0,
    sale: sale,
    status: OrderStatus.pending,
  );

  Future<void> recordedAt(String table, int id, int timestamp) async {
    await db.db.update(
      table,
      {'created_at': timestamp, 'updated_at': timestamp},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  test(
    'closing all archives the full ledger and restores alongside later entries',
    () async {
      final account = await db.saveAccount('الحساب الأول');
      final product = await db.saveProduct('منتج محفوظ', 2500);
      await db.saveOrders(
        accountId: account,
        items: [
          OrderItem(
            productId: product,
            productName: 'منتج محفوظ',
            quantity: 2,
            purchase: 450,
            sale: 2500,
          ),
          const OrderItem(
            productId: null,
            productName: 'منتج يدوي',
            quantity: 1,
            purchase: 0,
            sale: 0,
            unpriced: true,
          ),
        ],
        status: OrderStatus.arrived,
      );
      final catalog = (await db.product(product))!;
      await db.saveProduct(catalog.name, 3200, old: catalog);
      await db.toggleAccountClosed(account, true);
      await db.saveReceipt(120, 'ربح مستلم');
      await db.saveSideCost(50, '');
      await db.saveProfitShare('الشريك', ProfitShare.maxRate);
      await db.setTheme('dark');

      final id = await db.closePeriod(name: 'دفعة نوفمبر');
      expect((await db.periodArchives()).single.name, 'دفعة نوفمبر');
      expect(await db.accounts(), isEmpty);
      expect(await db.products(), isEmpty);
      expect(await db.receipts(), isEmpty);
      expect(await db.sideCosts(), isEmpty);
      expect((await db.report()).profitShare, isNull);
      expect((await db.report()).expectedSales, 0);
      expect(await db.theme(), 'dark');
      final archive = await db.archivedPeriod(id);
      expect(archive.report.expectedSales, 5000);
      expect(archive.report.realizedProfit, 120);
      expect(archive.report.sideCosts, 50);
      expect(archive.data.accounts.single.isClosed, isTrue);
      expect(archive.data.orders.single.items.last.unpriced, isTrue);
      final periodReport = PeriodReport.fromOrders(
        archive.data.orders,
        catalogPrices: {
          for (final item in archive.data.products) item.id: item.sale,
        },
      );
      expect(periodReport.amount, 6400);
      expect(
        periodReport.items
            .firstWhere((item) => item.name == 'منتج محفوظ')
            .unitPrice,
        3200,
      );

      final next = await db.saveAccount('حساب جديد');
      await order(next, 'طلب جديد');
      await db.restorePeriod(id);
      expect(await db.periodArchives(), isEmpty);
      expect((await db.report()).expectedSales, 7500);
      expect((await db.report()).profitShare?.name, 'الشريك');
      expect((await db.account(account))?.isClosed, isTrue);
      expect((await db.orders(next)).single.productName, 'طلب جديد');
      await expectLater(db.restorePeriod(id), throwsStateError);
    },
  );

  test(
    'date cutoff splits orders of a shared account and keeps its active edits',
    () async {
      final day = DateTime(2025, 9, 8);
      final end = DateTime(2025, 9, 9).millisecondsSinceEpoch;
      final account = await db.saveAccount('اسم أصلي');
      final product = await db.saveProduct('منتج مشترك', 2500);
      await recordedAt('accounts', account, end - 1000);
      await recordedAt('products', product, end - 1000);
      await recordedAt(
        'orders',
        await order(account, 'قديم', product: product),
        end - 1,
      );
      await recordedAt(
        'orders',
        await order(account, 'أحدث', product: product),
        end,
      );
      await recordedAt(
        'side_costs',
        await db.saveSideCost(100, 'قبل الإغلاق'),
        end - 1,
      );
      await recordedAt(
        'profit_receipts',
        await db.saveReceipt(400, 'بعد الإغلاق'),
        end,
      );

      final id = await db.closePeriod(throughDate: day);
      final archive = await db.archivedPeriod(id);
      expect(archive.data.orders.single.productName, 'قديم');
      expect(archive.data.sideCosts.single.amount, 100);
      expect(archive.data.receipts, isEmpty);
      expect(archive.data.accounts.single.id, account);
      expect((await db.orders(account)).single.productName, 'أحدث');
      expect((await db.product(product))?.id, product);
      expect((await db.receipts()).single.amount, 400);
      await expectLater(db.closePeriod(throughDate: day), throwsStateError);

      await db.saveAccount('اسم محدّث', old: await db.account(account));
      await db.restorePeriod(id);
      expect((await db.account(account))?.name, 'اسم محدّث');
      expect((await db.orders(account)).map((row) => row.productName), [
        'أحدث',
        'قديم',
      ]);
    },
  );

  test(
    'account cutoff uses creation order and archive identifiers survive a backup import',
    () async {
      final timestamp = DateTime(2025, 4, 1).millisecondsSinceEpoch;
      final first = await db.saveAccount('الحساب الأول');
      final second = await db.saveAccount('الحساب الثاني');
      await recordedAt('accounts', first, timestamp);
      await recordedAt('accounts', second, timestamp);
      final oldOrder = await order(first, 'طلب في الحساب الأول');
      final liveOrder = await order(second, 'طلب في الحساب الثاني');
      final oldReceipt = await db.saveReceipt(400, 'قبل الإنهاء');
      final oldCost = await db.saveSideCost(125, 'تكلفة قديمة');
      await recordedAt('profit_receipts', oldReceipt, timestamp);
      await recordedAt('side_costs', oldCost, timestamp + 1);
      final firstArchive = await db.closePeriod(throughAccountId: first);
      expect((await db.accounts()).single.id, second);
      expect((await db.orders(second)).single.id, liveOrder);
      expect((await db.sideCosts()).single.id, oldCost);
      expect(
        (await db.archivedPeriod(firstArchive)).data.orders.single.id,
        oldOrder,
      );
      expect(
        (await db.archivedPeriod(firstArchive)).data.receipts.single.id,
        oldReceipt,
      );
      final secondArchive = await db.closePeriod();

      final copy = await AppDatabase.open(
        path: p.join(dir.path, 'fresh.db'),
        factory: databaseFactoryFfi,
      );
      try {
        final backup = BackupData.decode((await db.snapshot()).encode());
        await copy.restore(backup);
        expect((await copy.periodArchives()).map((row) => row.id), [
          secondArchive,
          firstArchive,
        ]);
        expect(
          await copy.saveAccount('حساب بعد استيراد النسخة'),
          greaterThan(second),
        );
        expect(await copy.saveReceipt(99, 'ربح جديد'), greaterThan(oldReceipt));
        await copy.restorePeriod(secondArchive);
        await copy.restorePeriod(firstArchive);
        expect((await copy.report()).orders, 2);
        expect((await copy.report()).accounts, 3);
        expect((await copy.report()).realizedProfit, 499);
        expect((await copy.report()).sideCosts, 125);
      } finally {
        await copy.close();
      }
    },
  );

  test(
    'large archived periods can be read and restored across multiple rows',
    () async {
      final account = await db.saveAccount('سجل كبير');
      final now = DateTime.now().millisecondsSinceEpoch;
      final productName = List.filled(50, 'أب').join();
      const count = 6000;
      final batch = db.db.batch();
      for (var i = 0; i < count; i++) {
        batch.insert('orders', {
          'account_id': account,
          'product_name': productName,
          'quantity': 1,
          'purchase': 0,
          'sale': 1,
          'status': 'pending',
          'created_at': now,
          'updated_at': now,
        });
      }
      await batch.commit(noResult: true);

      final id = await db.closePeriod();
      expect(
        await db.db.query('period_archive_chunks'),
        hasLength(greaterThan(16)),
      );
      final archive = await db.archivedPeriod(id);
      expect(archive.data.orders, hasLength(count));
      expect(archive.data.orders.last.productName, productName);
      await db.restorePeriod(id);
      expect((await db.report()).orders, count);
      expect(await db.db.query('period_archive_chunks'), isEmpty);
    },
  );

  test(
    'failed restoration rolls back all changes and retains the archived period',
    () async {
      final first = await db.saveAccount('قبل الإغلاق');
      await order(first, 'قديم', sale: maxMoney);
      final id = await db.closePeriod();
      final current = await db.saveAccount('بعد الإغلاق');
      await order(current, 'جديد');
      await expectLater(db.restorePeriod(id), throwsFormatException);
      expect((await db.periodArchives()).single.id, id);
      expect((await db.accounts()).single.id, current);
      expect((await db.report()).expectedSales, 2500);
    },
  );
}
