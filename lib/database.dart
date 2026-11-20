import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'domain.dart';

const starterProductNames = ['بيبي جوي كرتون رقم 4', 'بيبي جوي كرتون رقم 5'];

class AppDatabase {
  AppDatabase._(this.db);
  final Database db;
  static const _unpricedColumn =
      'is_unpriced INTEGER NOT NULL DEFAULT 0 CHECK(is_unpriced IN (0,1))';
  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final location = path ?? p.join(await f.getDatabasesPath(), 'haseela.db');
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 12,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          sale INTEGER NOT NULL CHECK(sale >= 0),
          last_purchase INTEGER CHECK(last_purchase IS NULL OR last_purchase >= 0),
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
          await db.execute('''CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          is_closed INTEGER NOT NULL DEFAULT 0, closed_at INTEGER)''');
          await _createAccountIndexes(db);
          await db.execute('''CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
          product_name TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity > 0),
          purchase INTEGER NOT NULL CHECK(purchase >= 0),
          purchase_total INTEGER CHECK(purchase_total IS NULL OR purchase_total >= 0),
          sale INTEGER NOT NULL CHECK(sale >= 0),
          sale_total INTEGER CHECK(sale_total IS NULL OR sale_total >= 0),
          $_unpricedColumn,
          status TEXT NOT NULL CHECK(status IN ('pending','arrived','cancelled')),
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
          await db.execute(
            'CREATE INDEX order_account_date ON orders(account_id, created_at DESC, id DESC)',
          );
          await db.execute('CREATE INDEX order_status ON orders(status)');
          await db.execute('CREATE INDEX order_product ON orders(product_id)');
          await _createOrderItems(db);
          await db.execute(
            'CREATE INDEX account_date ON accounts(created_at DESC, id DESC)',
          );
          await db.execute(
            'CREATE INDEX product_date ON products(created_at DESC, id DESC)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await _createReceipts(db);
          await _createSideCosts(db);
          await _createProfitShare(db);
          await _createPeriodArchives(db);
          await _seedProducts(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // sqflite runs migration callbacks inside the opening transaction.
          if (oldVersion < 2) {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS order_product ON orders(product_id)',
            );
          }
          if (oldVersion < 3) await _seedProducts(db);
          if (oldVersion < 5) {
            await _createReceipts(db);
            // A fixture/newer table may already contain these columns; real v3
            // databases gain them without replacing orders or products.
            final productColumns = await db.rawQuery(
              'PRAGMA table_info(products)',
            );
            if (!productColumns.any((r) => r['name'] == 'last_purchase')) {
              await db.execute(
                'ALTER TABLE products ADD COLUMN last_purchase INTEGER CHECK(last_purchase IS NULL OR last_purchase >= 0)',
              );
            }
            final orderColumns = await db.rawQuery('PRAGMA table_info(orders)');
            if (!orderColumns.any((r) => r['name'] == 'purchase_total')) {
              await db.execute(
                'ALTER TABLE orders ADD COLUMN purchase_total INTEGER CHECK(purchase_total IS NULL OR purchase_total >= 0)',
              );
            }
            await db.execute('''UPDATE products SET last_purchase = (
              SELECT purchase FROM orders WHERE product_id = products.id
              ORDER BY updated_at DESC, id DESC LIMIT 1)
              WHERE last_purchase IS NULL''');
          }
          if (oldVersion < 5) {
            final accountColumns = await db.rawQuery(
              'PRAGMA table_info(accounts)',
            );
            if (!accountColumns.any((r) => r['name'] == 'is_closed')) {
              await db.execute(
                'ALTER TABLE accounts ADD COLUMN is_closed INTEGER NOT NULL DEFAULT 0',
              );
            }
          }
          if (oldVersion < 6) {
            final columns = await db.rawQuery('PRAGMA table_info(accounts)');
            if (!columns.any((r) => r['name'] == 'closed_at')) {
              await db.execute(
                'ALTER TABLE accounts ADD COLUMN closed_at INTEGER',
              );
            }
            // The original closing time is unknown for pre-v6 accounts.
            await db.execute('''UPDATE accounts SET closed_at = updated_at
              WHERE is_closed = 1 AND closed_at IS NULL''');
            await _createAccountIndexes(db);
          }
          if (oldVersion < 7) await _createSideCosts(db);
          if (oldVersion < 8) await _createProfitShare(db);
          if (oldVersion < 9) {
            final columns = await db.rawQuery('PRAGMA table_info(orders)');
            if (!columns.any((row) => row['name'] == 'sale_total')) {
              await db.execute(
                'ALTER TABLE orders ADD COLUMN sale_total INTEGER CHECK(sale_total IS NULL OR sale_total >= 0)',
              );
            }
            await _createOrderItems(db);
          }
          if (oldVersion >= 8 && oldVersion < 10) {
            await _migrateProfitShareMaxRate(db);
          }
          if (oldVersion < 11) {
            for (final table in ['orders', 'order_items']) {
              final columns = await db.rawQuery('PRAGMA table_info($table)');
              if (!columns.any((column) => column['name'] == 'is_unpriced')) {
                await db.execute(
                  'ALTER TABLE $table ADD COLUMN $_unpricedColumn',
                );
              }
            }
          }
          if (oldVersion < 12) await _createPeriodArchives(db);
        },
        onDowngrade: (db, oldVersion, newVersion) async =>
            throw StateError('قاعدة البيانات من إصدار أحدث؛ حدّثي التطبيق'),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createOrderItems(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS order_items (
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
      product_name TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity > 0),
      purchase INTEGER NOT NULL CHECK(purchase >= 0),
      sale INTEGER NOT NULL CHECK(sale >= 0),
      purchase_total INTEGER CHECK(purchase_total IS NULL OR purchase_total >= 0),
      $_unpricedColumn,
      PRIMARY KEY(order_id, position))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS order_item_product ON order_items(product_id)',
    );
  }

  static Future<void> _seedProducts(DatabaseExecutor db) async {
    final existing = (await db.query(
      'products',
      columns: ['name'],
    )).map((row) => normalizeDigits(row['name'] as String)).toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final name in starterProductNames) {
      if (!existing.contains(name)) {
        await db.insert('products', {
          'name': name,
          'sale': 18500,
          'created_at': now,
          'updated_at': now,
        });
      }
    }
  }

  static Future<void> _createReceipts(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS profit_receipts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER NOT NULL CHECK(amount > 0),
      note TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS receipt_date ON profit_receipts(created_at DESC, id DESC)',
    );
  }

  static Future<void> _createSideCosts(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS side_costs (
      id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER NOT NULL CHECK(amount > 0),
      note TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS side_cost_date ON side_costs(created_at DESC, id DESC)',
    );
  }

  static Future<void> _createProfitShare(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE IF NOT EXISTS profit_share (
      id INTEGER PRIMARY KEY CHECK(id = 1), name TEXT NOT NULL,
      rate INTEGER NOT NULL CHECK(rate BETWEEN 1 AND ${ProfitShare.maxRate}),
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');

  static Future<void> _createPeriodArchives(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS period_archives (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      range_label TEXT NOT NULL, closed_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS period_archive_chunks (
      archive_id INTEGER NOT NULL REFERENCES period_archives(id) ON DELETE CASCADE,
      position INTEGER NOT NULL, data BLOB NOT NULL,
      PRIMARY KEY(archive_id, position))''');
  }

  static Future<void> _migrateProfitShareMaxRate(DatabaseExecutor db) async {
    // SQLite embeds the old CHECK bound in the table DDL; rebuild the table to raise it.
    await _createProfitShare(db);
    await db.execute('ALTER TABLE profit_share RENAME TO profit_share_old');
    await _createProfitShare(db);
    await db.execute(
      'INSERT INTO profit_share (id, name, rate, created_at, updated_at) '
      'SELECT id, name, rate, created_at, updated_at FROM profit_share_old',
    );
    await db.execute('DROP TABLE profit_share_old');
  }

  static Future<void> _createAccountIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS account_closed_date ON accounts(is_closed, closed_at ASC, id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS account_open_date ON accounts(is_closed, created_at DESC, id DESC)',
    );
  }

  Future<void> close() => db.close();
  Future<Product?> product(int id) async {
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.single);
  }

  static void _name(String name, {int limit = 120}) {
    if (name.trim().isEmpty || name.length > limit) {
      throw FormatException('اكتبي اسمًا من 1 إلى $limit حرفًا');
    }
  }

  static void _price(int price) {
    if (price < 0 || price > maxMoney) {
      throw const FormatException('السعر خارج النطاق المسموح');
    }
  }

  Future<int> saveProduct(String name, int sale, {Product? old}) async {
    _name(name);
    _price(sale);
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = {
      'name': name.trim(),
      'sale': sale,
      'created_at': old?.createdAt ?? now,
      'updated_at': now,
    };
    if (old == null) return db.insert('products', values);
    final changed = await db.update(
      'products',
      values,
      where: 'id = ?',
      whereArgs: [old.id],
    );
    if (changed == 0) throw StateError('المنتج لم يعد موجودًا');
    return old.id;
  }

  Future<int> saveAccount(String name, {Account? old, bool? isClosed}) async {
    _name(name, limit: 254);
    return db.transaction((tx) async {
      final current = old == null ? null : await _accountRow(tx, old.id);
      final now = DateTime.now().millisecondsSinceEpoch;
      final closed = isClosed ?? current?.isClosed ?? false;
      final values = _accountRowValues(
        name,
        isClosed: closed,
        now: now,
        current: current,
      );
      if (old == null) return tx.insert('accounts', values);
      await tx.update('accounts', values, where: 'id = ?', whereArgs: [old.id]);
      return old.id;
    });
  }

  /// Inserts one or more new accounts atomically inside a single transaction.
  Future<List<int>> saveAccounts(
    List<({String name, bool isClosed})> entries,
  ) async {
    final accounts = entries.toList(growable: false);
    if (accounts.isEmpty) {
      throw const FormatException('أضيفي حسابًا واحدًا على الأقل');
    }
    for (final entry in accounts) {
      _name(entry.name, limit: 254);
    }
    return db.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final ids = <int>[];
      for (final entry in accounts) {
        ids.add(
          await tx.insert(
            'accounts',
            _accountRowValues(entry.name, isClosed: entry.isClosed, now: now),
          ),
        );
      }
      return ids;
    });
  }

  static Map<String, Object?> _accountRowValues(
    String name, {
    required bool isClosed,
    required int now,
    Account? current,
  }) => {
    'name': name.trim(),
    'created_at': current?.createdAt ?? now,
    'updated_at': now,
    'is_closed': isClosed ? 1 : 0,
    'closed_at': isClosed
        ? (current?.isClosed == true ? current!.closedAt : now)
        : null,
  };

  static Future<Account> _accountRow(DatabaseExecutor tx, int id) async {
    final rows = await tx.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('الحساب لم يعد موجودًا');
    return Account.fromMap(rows.single);
  }

  Future<void> toggleAccountClosed(int id, bool isClosed) =>
      db.transaction((tx) async {
        final current = await _accountRow(tx, id);
        if (current.isClosed == isClosed) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        await tx.update(
          'accounts',
          {
            'is_closed': isClosed ? 1 : 0,
            'closed_at': isClosed ? now : null,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      });

  Future<int> saveOrder({
    required int accountId,
    required int? productId,
    required String productName,
    required int quantity,
    required int purchase,
    required int sale,
    required OrderStatus status,
    int? purchaseTotal,
    PurchaseOrder? old,
  }) async => (await saveOrders(
    accountId: accountId,
    items: [
      OrderItem(
        productId: productId,
        productName: productName,
        quantity: quantity,
        purchase: purchase,
        sale: sale,
        purchaseTotal: purchaseTotal,
      ),
    ],
    status: status,
    old: old,
  )).single;

  Future<List<int>> saveOrders({
    required int accountId,
    required List<OrderItem> items,
    required OrderStatus status,
    bool separate = false,
    PurchaseOrder? old,
  }) async {
    final lines = List<OrderItem>.of(items);
    if (lines.isEmpty) {
      throw const FormatException('أضيفي منتجًا واحدًا على الأقل');
    }
    if (old != null && separate) {
      throw const FormatException('احفظي تعديل المنتجات ضمن الطلب نفسه');
    }
    var cost = 0, revenue = 0, quantity = 0;
    for (final item in lines) {
      item.validate();
      cost += item.cost;
      revenue += item.revenue;
      quantity += item.quantity;
    }
    if (!separate && quantity > maxQuantity) {
      throw const FormatException('إجمالي كمية الطلب أكبر من النطاق المسموح');
    }
    return db.transaction((tx) async {
      final sums = (await tx.rawQuery(
        '''SELECT COALESCE(SUM(COALESCE(purchase_total, quantity * purchase)),0)
          + (SELECT COALESCE(SUM(amount),0) FROM side_costs) cost,
        COALESCE(SUM(COALESCE(sale_total, quantity * sale)),0) revenue FROM orders WHERE id != ?''',
        [old?.id ?? -1],
      )).single;
      if ((sums['cost'] as int) + cost > maxMoney ||
          (sums['revenue'] as int) + revenue > maxMoney) {
        throw const FormatException('إجمالي المبالغ أكبر من النطاق الآمن');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final account = await _accountRow(tx, accountId);
      if (old == null && account.isClosed) {
        throw StateError('الحساب مغلق؛ لا يمكن إضافة طلبات جديدة إليه');
      }
      final groups = separate ? lines.map((item) => [item]) : [lines];
      final ids = <int>[];
      for (final group in groups) {
        ids.add(await _saveOrder(tx, accountId, group, status, now, old));
      }
      for (final item in lines) {
        if (item.productId == null) continue;
        await tx.update(
          'products',
          {'last_purchase': item.purchase, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [item.productId],
        );
      }
      return ids;
    });
  }

  Future<int> _saveOrder(
    Transaction tx,
    int accountId,
    List<OrderItem> items,
    OrderStatus status,
    int now,
    PurchaseOrder? old,
  ) async {
    final multiple = items.length > 1;
    final quantity = items.fold(0, (sum, item) => sum + item.quantity);
    final cost = items.fold(0, (sum, item) => sum + item.cost);
    final revenue = items.fold(0, (sum, item) => sum + item.revenue);
    final values = {
      ...items.first.toMap(),
      'account_id': accountId,
      'product_id': multiple ? null : items.first.productId,
      'quantity': quantity,
      'purchase': multiple
          ? unitFromTotal(cost, quantity)
          : items.first.purchase,
      'purchase_total': multiple ? cost : items.first.purchaseTotal,
      'sale': multiple ? unitFromTotal(revenue, quantity) : items.first.sale,
      'sale_total': multiple ? revenue : null,
      'is_unpriced': items.every((item) => item.unpriced) ? 1 : 0,
      'status': status.name,
      'updated_at': now,
    };
    final int id;
    if (old == null) {
      id = await tx.insert('orders', {...values, 'created_at': now});
    } else {
      final changed = await tx.update(
        'orders',
        values,
        where: 'id = ?',
        whereArgs: [old.id],
      );
      if (changed == 0) throw StateError('الطلب لم يعد موجودًا');
      id = old.id;
      await tx.delete('order_items', where: 'order_id = ?', whereArgs: [id]);
    }
    if (multiple) {
      final batch = tx.batch();
      for (var position = 0; position < items.length; position++) {
        batch.insert('order_items', {
          'order_id': id,
          'position': position,
          ...items[position].toMap(),
        });
      }
      await batch.commit(noResult: true);
    }
    return id;
  }

  Future<void> changeStatus(int id, OrderStatus status) async {
    final changed = await db.update(
      'orders',
      {
        'status': status.name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed == 0) throw StateError('الطلب لم يعد موجودًا');
  }

  Future<void> deleteProduct(int id) async =>
      db.delete('products', where: 'id = ?', whereArgs: [id]);
  Future<void> deleteAccount(int id) async =>
      db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  Future<void> deleteOrder(int id) async =>
      db.delete('orders', where: 'id = ?', whereArgs: [id]);

  Future<List<Product>> products({
    String search = '',
    int offset = 0,
    int limit = 40,
  }) async {
    final rows = await db.query(
      'products',
      where: search.trim().isEmpty ? null : "name LIKE ? ESCAPE '\\'",
      whereArgs: search.trim().isEmpty
          ? null
          : ['%${_escapeLike(search.trim())}%'],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Product.fromMap).toList();
  }

  String _escapeLike(String text) => text
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
  Future<List<Account>> accounts({
    String search = '',
    AccountFilter filter = AccountFilter.all,
    int offset = 0,
    int limit = 40,
  }) async {
    final condition = switch (filter) {
      AccountFilter.all => '',
      AccountFilter.open => 'AND is_closed=0',
      AccountFilter.closed => 'AND is_closed=1',
    };
    final date = filter == AccountFilter.closed ? 'closed_at' : 'created_at';
    final direction = filter == AccountFilter.closed ? 'ASC' : 'DESC';
    return (await db.rawQuery(
      '''SELECT a.*, $_accountSummary
      FROM (SELECT * FROM accounts WHERE 1=1 $condition ${search.trim().isEmpty ? '' : "AND name LIKE ? ESCAPE '\\'"}
        ORDER BY $date $direction, id $direction LIMIT ? OFFSET ?) a
      LEFT JOIN orders o ON o.account_id = a.id
      GROUP BY a.id ORDER BY a.$date $direction, a.id $direction''',
      [
        if (search.trim().isNotEmpty) '%${_escapeLike(search.trim())}%',
        limit,
        offset,
      ],
    )).map(Account.fromMap).toList();
  }

  Future<Account?> account(int id) async {
    final rows = await db.rawQuery(
      '''SELECT a.*, $_accountSummary FROM accounts a
      LEFT JOIN orders o ON o.account_id = a.id WHERE a.id = ? GROUP BY a.id''',
      [id],
    );
    return rows.isEmpty ? null : Account.fromMap(rows.single);
  }

  static const _accountSummary = '''COUNT(o.id) order_count,
    COALESCE(SUM(o.quantity),0) pieces,
    COALESCE(SUM(CASE WHEN o.status='pending' THEN 1 ELSE 0 END),0) pending,
    COALESCE(SUM(CASE WHEN o.status='arrived' THEN 1 ELSE 0 END),0) arrived,
    COALESCE(SUM(CASE WHEN o.status='cancelled' THEN 1 ELSE 0 END),0) cancelled''';

  Future<List<PurchaseOrder>> orders(
    int accountId, {
    int offset = 0,
    int limit = 40,
  }) => db.transaction(
    (tx) async => _ordersWithItems(
      tx,
      await tx.query(
        'orders',
        where: 'account_id = ?',
        whereArgs: [accountId],
        orderBy: 'created_at DESC, id DESC',
        limit: limit,
        offset: offset,
      ),
    ),
  );

  static Future<List<PurchaseOrder>> _ordersWithItems(
    DatabaseExecutor tx,
    List<Map<String, Object?>> rows,
  ) async {
    final items = <int, List<Map<String, Object?>>>{};
    // Keep parameter counts below SQLite's limit, including full backup exports.
    for (var start = 0; start < rows.length; start += 400) {
      final ids = rows.skip(start).take(400).map((row) => row['id']).toList();
      final details = await tx.query(
        'order_items',
        where: 'order_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
        orderBy: 'order_id, position',
      );
      for (final item in details) {
        items.putIfAbsent(item['order_id'] as int, () => []).add(item);
      }
    }
    return rows
        .map(
          (row) => PurchaseOrder.fromMap({
            ...row,
            'items': items[row['id']] ?? const [],
          }),
        )
        .toList();
  }

  Future<Report> report() => db.transaction((tx) async {
    final counts = (await tx.rawQuery('''SELECT
      (SELECT COUNT(*) FROM accounts) accounts,
      (SELECT COUNT(*) FROM products) products''')).single;
    final row = (await tx.rawQuery(
      '''SELECT COUNT(*) orders, SUM(quantity) pieces,
      SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) pending,
      SUM(CASE WHEN status='arrived' THEN 1 ELSE 0 END) arrived,
      SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) cancelled,
      SUM(COALESCE(purchase_total,quantity * purchase)) spent,
      SUM(CASE WHEN status!='cancelled' THEN COALESCE(sale_total,quantity * sale) ELSE 0 END) expected_sales,
      SUM(CASE WHEN status!='cancelled' THEN COALESCE(sale_total,quantity * sale)-COALESCE(purchase_total,quantity * purchase) ELSE 0 END) expected_profit,
      (SELECT COALESCE(SUM(amount),0) FROM profit_receipts) received_profit,
      (SELECT COALESCE(SUM(amount),0) FROM side_costs) side_costs,
      SUM(CASE WHEN status='arrived' THEN COALESCE(sale_total,quantity * sale) ELSE 0 END) arrived_sales,
      SUM(CASE WHEN status='cancelled' THEN COALESCE(purchase_total,quantity * purchase) ELSE 0 END) refund
      FROM orders''',
    )).single;
    return Report.fromMap(
      row,
      accounts: counts['accounts'] as int,
      products: counts['products'] as int,
      profitShare: await _profitShare(tx),
    );
  });

  Future<PeriodReport> periodReportByDate(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day + 1);
    if (!start.isBefore(end)) {
      throw const FormatException(
        'اختاري تاريخ نهاية يوافق البداية أو يأتي بعدها',
      );
    }
    return _periodReport(db, 'o.created_at >= ? AND o.created_at < ?', [
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    ]);
  }

  Future<PeriodReport> periodReportAll() => _periodReport(db, '1', const []);

  Future<PeriodReport> periodReportByAccounts(int fromId, int toId) =>
      db.transaction((tx) async {
        final bounds = [
          await _accountRow(tx, fromId),
          await _accountRow(tx, toId),
        ]..sort(Account.compareByCreation);
        final first = bounds.first, last = bounds.last;
        return _periodReport(
          tx,
          '''
          (a.created_at > ? OR (a.created_at = ? AND a.id >= ?)) AND
          (a.created_at < ? OR (a.created_at = ? AND a.id <= ?))''',
          [
            first.createdAt,
            first.createdAt,
            first.id,
            last.createdAt,
            last.createdAt,
            last.id,
          ],
        );
      });

  static Future<PeriodReport> _periodReport(
    DatabaseExecutor executor,
    String condition,
    List<Object> args,
  ) async {
    final rows = await executor.rawQuery(
      '''
      WITH selected_orders AS (
        SELECT o.* FROM orders o JOIN accounts a ON a.id = o.account_id
        WHERE o.status != 'cancelled' AND ($condition)
      ), lines AS (
        SELECT product_id, product_name, quantity, sale, is_unpriced
        FROM selected_orders WHERE sale_total IS NULL
        UNION ALL
        SELECT i.product_id, i.product_name, i.quantity, i.sale, i.is_unpriced
        FROM order_items i JOIN selected_orders o ON o.id = i.order_id
      ), priced_lines AS (
        SELECT lines.product_name, lines.quantity,
          CASE WHEN lines.is_unpriced = 0 THEN COALESCE(p.sale, lines.sale) END unit_price
        FROM lines LEFT JOIN products p ON p.id = lines.product_id
      )
      SELECT MIN(product_name) name, SUM(quantity) quantity, unit_price
      FROM priced_lines GROUP BY product_name COLLATE NOCASE, unit_price''',
      args,
    );
    return PeriodReport.fromPricedLines(
      rows.map(
        (row) => (
          name: row['name'] as String,
          quantity: row['quantity'] as int,
          price: row['unit_price'] as int?,
        ),
      ),
    );
  }

  static Future<ProfitShare?> _profitShare(DatabaseExecutor tx) async {
    final rows = await tx.query('profit_share', limit: 1);
    return rows.isEmpty ? null : ProfitShare.fromMap(rows.single);
  }

  Future<void> saveProfitShare(String name, int rate) async {
    final cleaned = name.trim();
    _name(cleaned);
    if (!ProfitShare.validRate(rate)) {
      throw const FormatException(
        'النسبة يجب أن تكون أكبر من صفر وحتى ${ProfitShare.maxPercent}٪',
      );
    }
    await db.transaction((tx) async {
      final previous = await _profitShare(tx);
      final now = DateTime.now().millisecondsSinceEpoch;
      final share = ProfitShare(
        name: cleaned,
        rate: rate,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
      );
      await tx.insert('profit_share', {
        'id': 1,
        ...share.toMap(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> removeProfitShare() async {
    await db.delete('profit_share');
  }

  Future<int> saveReceipt(int amount, String note, {ProfitReceipt? old}) async {
    _name(note);
    return _saveAmount(
      'profit_receipts',
      amount,
      note,
      id: old?.id,
      createdAt: old?.createdAt,
      missingMessage: 'سجل الأرباح لم يعد موجودًا',
    );
  }

  Future<int> saveSideCost(int amount, String note, {SideCost? old}) async {
    if (note.length > 120) {
      throw const FormatException('اكتبي ملاحظة من 120 حرفًا أو أقل');
    }
    return _saveAmount(
      'side_costs',
      amount,
      note,
      id: old?.id,
      createdAt: old?.createdAt,
      missingMessage: 'التكلفة الجانبية لم تعد موجودة',
    );
  }

  Future<int> _saveAmount(
    String table,
    int amount,
    String note, {
    required int? id,
    required int? createdAt,
    required String missingMessage,
  }) async {
    _price(amount);
    if (amount == 0) throw const FormatException('أدخلي مبلغًا أكبر من صفر');
    return db.transaction((tx) async {
      final orderCosts = table == 'side_costs'
          ? '+ (SELECT COALESCE(SUM(COALESCE(purchase_total, quantity * purchase)),0) FROM orders)'
          : '';
      final sum =
          (await tx.rawQuery(
                'SELECT COALESCE(SUM(amount),0) $orderCosts total FROM $table WHERE id != ?',
                [id ?? -1],
              )).single['total']
              as int;
      if (sum + amount > maxMoney) {
        throw const FormatException('المبلغ أكبر من النطاق الآمن');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = {
        'amount': amount,
        'note': note.trim(),
        'created_at': createdAt ?? now,
        'updated_at': now,
      };
      if (id == null) return tx.insert(table, values);
      final changed = await tx.update(
        table,
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed == 0) throw StateError(missingMessage);
      return id;
    });
  }

  Future<void> deleteReceipt(int id) async =>
      db.delete('profit_receipts', where: 'id = ?', whereArgs: [id]);
  Future<List<ProfitReceipt>> receipts({
    int offset = 0,
    int limit = 40,
  }) async => (await db.query(
    'profit_receipts',
    orderBy: 'created_at DESC, id DESC',
    offset: offset,
    limit: limit,
  )).map(ProfitReceipt.fromMap).toList();

  Future<void> deleteSideCost(int id) async =>
      db.delete('side_costs', where: 'id = ?', whereArgs: [id]);

  Future<List<SideCost>> sideCosts({int offset = 0, int limit = 40}) async =>
      (await db.query(
        'side_costs',
        orderBy: 'created_at DESC, id DESC',
        offset: offset,
        limit: limit,
      )).map(SideCost.fromMap).toList();

  Future<List<PurchaseOrder>> cancelledOrders({
    int offset = 0,
    int limit = 40,
  }) => db.transaction(
    (tx) async => _ordersWithItems(
      tx,
      await tx.rawQuery(
        '''SELECT o.*, a.name account_name FROM orders o
    JOIN accounts a ON a.id = o.account_id WHERE o.status='cancelled' AND o.is_unpriced=0
    ORDER BY o.created_at DESC, o.id DESC LIMIT ? OFFSET ?''',
        [limit, offset],
      ),
    ),
  );
  Future<String> theme() async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['theme'],
    );
    final value = rows.isEmpty ? 'system' : rows.single['value'] as String;
    return ['system', 'light', 'dark'].contains(value) ? value : 'system';
  }

  Future<void> setTheme(String value) async {
    if (!['system', 'light', 'dark'].contains(value)) {
      throw const FormatException('مظهر غير صالح');
    }
    await db.insert('settings', {
      'key': 'theme',
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BackupData> snapshot() =>
      db.transaction((tx) => _snapshot(tx, includeArchives: true));

  static Future<BackupData> _snapshot(
    Transaction tx, {
    bool includeArchives = false,
  }) async {
    final settings = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['theme'],
    );
    return BackupData(
      products: (await tx.query('products')).map(Product.fromMap).toList(),
      accounts: (await tx.query('accounts')).map(Account.fromMap).toList(),
      orders: await _ordersWithItems(tx, await tx.query('orders')),
      theme: settings.isEmpty ? 'system' : settings.single['value'] as String,
      receipts: (await tx.query(
        'profit_receipts',
      )).map(ProfitReceipt.fromMap).toList(),
      sideCosts: (await tx.query('side_costs')).map(SideCost.fromMap).toList(),
      profitShare: await _profitShare(tx),
      archives: includeArchives
          ? [
              for (final info in await _archiveInfos(tx))
                await _loadArchiveData(tx, info),
            ]
          : const [],
    );
  }

  Future<List<PeriodArchiveInfo>> periodArchives() => _archiveInfos(db);

  static Future<List<PeriodArchiveInfo>> _archiveInfos(
    DatabaseExecutor db,
  ) async => (await db.query(
    'period_archives',
    orderBy: 'closed_at DESC, id DESC',
  )).map(PeriodArchiveInfo.fromMap).toList();

  Future<ArchivedPeriod> archivedPeriod(int id) =>
      db.transaction((tx) => _loadArchive(tx, id));

  static Future<ArchivedPeriod> _loadArchive(
    DatabaseExecutor db,
    int id,
  ) async {
    final rows = await db.query(
      'period_archives',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('الفترة لم تعد في الأرشيف');
    return _loadArchiveData(db, PeriodArchiveInfo.fromMap(rows.single));
  }

  static Future<ArchivedPeriod> _loadArchiveData(
    DatabaseExecutor db,
    PeriodArchiveInfo info,
  ) async {
    final chunks = await db.query(
      'period_archive_chunks',
      columns: ['data'],
      where: 'archive_id = ?',
      whereArgs: [info.id],
      orderBy: 'position',
    );
    final bytes = BytesBuilder(copy: false);
    for (final row in chunks) {
      bytes.add(row['data'] as Uint8List);
    }
    return ArchivedPeriod(
      info,
      BackupData.decode(utf8.decode(bytes.takeBytes())),
    );
  }

  static void _insertArchiveData(Batch batch, int id, String content) {
    // Keep each row well below Android SQLite's cursor window size.
    const chunkSize = 128 * 1024;
    final bytes = utf8.encode(content);
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      batch.insert('period_archive_chunks', {
        'archive_id': id,
        'position': offset ~/ chunkSize,
        'data': Uint8List.sublistView(
          bytes,
          offset,
          math.min(offset + chunkSize, bytes.length),
        ),
      });
    }
  }

  Future<int> closePeriod({
    String name = '',
    DateTime? throughDate,
    int? throughAccountId,
  }) async {
    if (name.trim().isNotEmpty) _name(name.trim());
    if (throughDate != null && throughAccountId != null) {
      throw const FormatException('اختاري تاريخًا أو حسابًا لنهاية الفترة');
    }
    return db.transaction((tx) async {
      final boundary = throughAccountId == null
          ? null
          : await _accountRow(tx, throughAccountId);
      final cutoff = throughDate != null
          ? DateTime(
              throughDate.year,
              throughDate.month,
              throughDate.day + 1,
            ).millisecondsSinceEpoch
          : boundary == null
          ? null
          : boundary.createdAt + 1;
      bool beforeEnd(int createdAt) => cutoff == null || createdAt < cutoff;
      final range = throughDate != null
          ? 'حتى ${DateTime(throughDate.year, throughDate.month, throughDate.day).toIso8601String().split('T').first}'
          : boundary == null
          ? 'كامل السجل'
          : 'حتى حساب ${boundary.name}';

      final active = await _snapshot(tx);
      final eligibleAccounts = {
        for (final account in active.accounts)
          if (boundary == null
              ? beforeEnd(account.createdAt)
              : Account.compareByCreation(account, boundary) <= 0)
            account.id,
      };
      final moving = <PurchaseOrder>[];
      final remaining = <PurchaseOrder>[];
      for (final order in active.orders) {
        final eligible = boundary == null
            ? beforeEnd(order.createdAt)
            : eligibleAccounts.contains(order.accountId);
        (eligible ? moving : remaining).add(order);
      }
      final remainingAccounts = remaining
          .map((order) => order.accountId)
          .toSet();
      final removedAccounts = eligibleAccounts.difference(remainingAccounts);
      final savedAccounts = {
        ...removedAccounts,
        ...moving.map((order) => order.accountId),
      };
      final remainingProducts = _orderProductIds(remaining);
      final removedProducts = {
        for (final product in active.products)
          if (beforeEnd(product.createdAt) &&
              !remainingProducts.contains(product.id))
            product.id,
      };
      final savedProducts = {...removedProducts, ..._orderProductIds(moving)};
      final receipts = active.receipts
          .where((row) => beforeEnd(row.createdAt))
          .toList();
      final costs = active.sideCosts
          .where((row) => beforeEnd(row.createdAt))
          .toList();
      final clearShare =
          beforeEnd(active.profitShare?.createdAt ?? 0) &&
          removedAccounts.length == active.accounts.length &&
          remaining.isEmpty &&
          receipts.length == active.receipts.length &&
          costs.length == active.sideCosts.length;
      if (savedAccounts.isEmpty &&
          savedProducts.isEmpty &&
          moving.isEmpty &&
          receipts.isEmpty &&
          costs.isEmpty &&
          !(clearShare && active.profitShare != null)) {
        throw StateError('لا توجد بيانات في الفترة المحددة');
      }

      final data = BackupData(
        theme: active.theme,
        accounts: active.accounts
            .where((row) => savedAccounts.contains(row.id))
            .toList(),
        products: active.products
            .where((row) => savedProducts.contains(row.id))
            .toList(),
        orders: moving,
        receipts: receipts,
        sideCosts: costs,
        profitShare: active.profitShare,
      );
      final encoded = data.encode(compact: true);
      // Validate the archive with the same reader used during restoration.
      BackupData.decode(encoded);
      final id = await tx.insert('period_archives', {
        'name': name.trim().isEmpty ? range : name.trim(),
        'range_label': range,
        'closed_at': DateTime.now().millisecondsSinceEpoch,
      });
      final batch = tx.batch();
      _insertArchiveData(batch, id, encoded);
      _deleteByIds(batch, 'orders', moving.map((order) => order.id));
      _deleteByIds(batch, 'accounts', removedAccounts);
      _deleteByIds(batch, 'products', removedProducts);
      _deleteByIds(batch, 'profit_receipts', receipts.map((row) => row.id));
      _deleteByIds(batch, 'side_costs', costs.map((row) => row.id));
      if (clearShare) batch.delete('profit_share');
      await batch.commit(noResult: true);
      return id;
    });
  }

  static Set<int> _orderProductIds(Iterable<PurchaseOrder> orders) => {
    for (final order in orders)
      for (final line in order.lines) ?line.productId,
  };

  static void _deleteByIds(Batch batch, String table, Iterable<int> ids) {
    final entries = ids.toList();
    for (var start = 0; start < entries.length; start += 400) {
      final group = entries.skip(start).take(400).toList();
      batch.delete(
        table,
        where: 'id IN (${List.filled(group.length, '?').join(',')})',
        whereArgs: group,
      );
    }
  }

  Future<void> restorePeriod(int id) => db.transaction((tx) async {
    final archive = await _loadArchive(tx, id);
    final batch = tx.batch();
    _insertRecords(batch, archive.data, merge: true);
    await batch.commit(noResult: true);
    final totals = (await tx.rawQuery('''SELECT
      COALESCE(SUM(COALESCE(purchase_total, quantity * purchase)), 0)
        + (SELECT COALESCE(SUM(amount), 0) FROM side_costs) AS cost,
      COALESCE(SUM(COALESCE(sale_total, quantity * sale)), 0) AS sales,
      (SELECT COALESCE(SUM(amount), 0) FROM profit_receipts) AS receipts
      FROM orders''')).single;
    if (totals.values.any((amount) => (amount as int) > maxMoney)) {
      throw const FormatException(
        'إجمالي المبالغ بعد الاستعادة أكبر من النطاق الآمن',
      );
    }
    await tx.delete('period_archives', where: 'id = ?', whereArgs: [id]);
  });
  Future<File> saveSafetyCopy() async {
    final backup = await snapshot();
    final directory = Directory(p.join(p.dirname(db.path), 'haseela_safety'));
    await directory.create(recursive: true);
    final file = File(
      p.join(
        directory.path,
        'before_restore_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    );
    await file.writeAsString(backup.encode(), flush: true);
    return file;
  }

  Future<String?> latestSafetyCopy() async {
    final directory = Directory(p.join(p.dirname(db.path), 'haseela_safety'));
    if (!await directory.exists()) return null;
    final files = await directory
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.isEmpty ? null : files.first.path;
  }

  Future<void> restore(BackupData backup) async {
    // Revalidate even when called without the file picker.
    final verified = BackupData.decode(backup.encode());
    await saveSafetyCopy(); // A failed safety copy aborts restoration.
    await db.transaction((tx) async {
      await tx.delete('profit_receipts');
      await tx.delete('side_costs');
      await tx.delete('profit_share');
      await tx.delete('orders');
      await tx.delete('products');
      await tx.delete('accounts');
      await tx.delete('period_archives');
      final batch = tx.batch();
      _insertRecords(batch, verified);
      for (final archive in verified.archives) {
        batch.insert('period_archives', archive.info.toMap());
        _insertArchiveData(
          batch,
          archive.info.id,
          archive.data.encode(compact: true),
        );
      }
      batch.insert('settings', {
        'key': 'theme',
        'value': verified.theme,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
      await _reserveArchivedIds(tx, verified.archives);
    });
  }

  static void _insertRecords(
    Batch batch,
    BackupData data, {
    bool merge = false,
  }) {
    final shared = merge ? ConflictAlgorithm.ignore : ConflictAlgorithm.abort;
    for (final product in data.products) {
      batch.insert('products', product.toMap(), conflictAlgorithm: shared);
    }
    for (final account in data.accounts) {
      batch.insert('accounts', account.toMap(), conflictAlgorithm: shared);
    }
    for (final receipt in data.receipts) {
      batch.insert('profit_receipts', receipt.toMap());
    }
    for (final cost in data.sideCosts) {
      batch.insert('side_costs', cost.toMap());
    }
    final share = data.profitShare;
    if (share != null) {
      batch.insert('profit_share', {
        'id': 1,
        ...share.toMap(),
      }, conflictAlgorithm: shared);
    }
    for (final order in data.orders) {
      batch.insert('orders', order.toMap());
      for (var position = 0; position < order.items.length; position++) {
        batch.insert('order_items', {
          'order_id': order.id,
          'position': position,
          ...order.items[position].toMap(),
        });
      }
    }
  }

  static Future<void> _reserveArchivedIds(
    Transaction tx,
    List<ArchivedPeriod> archives,
  ) async {
    // A backup can be restored onto a fresh installation. Keep its archived
    // identifiers reserved even when they are absent from the active tables.
    final maxima = <String, int>{};
    void reserve(String table, Iterable<int> ids) {
      for (final id in ids) {
        if (id > (maxima[table] ?? 0)) maxima[table] = id;
      }
    }

    for (final archive in archives) {
      final data = archive.data;
      reserve('accounts', data.accounts.map((row) => row.id));
      reserve('products', data.products.map((row) => row.id));
      reserve('orders', data.orders.map((row) => row.id));
      reserve('profit_receipts', data.receipts.map((row) => row.id));
      reserve('side_costs', data.sideCosts.map((row) => row.id));
    }
    for (final entry in maxima.entries) {
      final changed = await tx.rawUpdate(
        'UPDATE sqlite_sequence SET seq = MAX(seq, ?) WHERE name = ?',
        [entry.value, entry.key],
      );
      if (changed == 0) {
        await tx.insert('sqlite_sequence', {
          'name': entry.key,
          'seq': entry.value,
        });
      }
    }
  }
}
