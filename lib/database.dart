import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'domain.dart';

const starterProductNames = ['بيبي جوي كرتون رقم 4', 'بيبي جوي كرتون رقم 5'];

class AppDatabase {
  AppDatabase._(this.db);
  final Database db;
  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final location = path ?? p.join(await f.getDatabasesPath(), 'haseela.db');
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 5,
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
          is_closed INTEGER NOT NULL DEFAULT 0)''');
          await db.execute('''CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
          product_name TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity > 0),
          purchase INTEGER NOT NULL CHECK(purchase >= 0),
          purchase_total INTEGER CHECK(purchase_total IS NULL OR purchase_total >= 0),
          sale INTEGER NOT NULL CHECK(sale >= 0),
          status TEXT NOT NULL CHECK(status IN ('pending','arrived','cancelled')),
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
          await db.execute(
            'CREATE INDEX order_account_date ON orders(account_id, created_at DESC, id DESC)',
          );
          await db.execute('CREATE INDEX order_status ON orders(status)');
          await db.execute('CREATE INDEX order_product ON orders(product_id)');
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
        },
        onDowngrade: (db, oldVersion, newVersion) async =>
            throw StateError('قاعدة البيانات من إصدار أحدث؛ حدّثي التطبيق'),
      ),
    );
    return AppDatabase._(db);
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final closed = isClosed ?? old?.isClosed ?? false;
    final values = {
      'name': name.trim(),
      'created_at': old?.createdAt ?? now,
      'updated_at': now,
      'is_closed': closed ? 1 : 0,
    };
    if (old == null) return db.insert('accounts', values);
    final changed = await db.update(
      'accounts',
      values,
      where: 'id = ?',
      whereArgs: [old.id],
    );
    if (changed == 0) throw StateError('الحساب لم يعد موجودًا');
    return old.id;
  }

  Future<void> toggleAccountClosed(int id, bool isClosed) async {
    final changed = await db.update(
      'accounts',
      {
        'is_closed': isClosed ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed == 0) throw StateError('الحساب لم يعد موجودًا');
  }

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
  }) async {
    _name(productName);
    _price(purchase);
    _price(sale);
    if (quantity < 1 || quantity > maxQuantity) {
      throw const FormatException('الكمية غير صالحة');
    }
    if (purchaseTotal != null) {
      _price(purchaseTotal);
      if (unitFromTotal(purchaseTotal, quantity) != purchase) {
        throw const FormatException('سعر الوحدة لا يطابق إجمالي الشراء');
      }
    }
    final cost = purchaseTotal ?? quantity * purchase;
    return db.transaction((tx) async {
      final sums = (await tx.rawQuery(
        '''SELECT COALESCE(SUM(COALESCE(purchase_total, quantity * purchase)),0) cost,
        COALESCE(SUM(quantity * sale),0) revenue FROM orders WHERE id != ?''',
        [old?.id ?? -1],
      )).single;
      if ((sums['cost'] as int) + cost > maxMoney ||
          (sums['revenue'] as int) + quantity * sale > maxMoney) {
        throw const FormatException('إجمالي المبالغ أكبر من النطاق الآمن');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = {
        'account_id': accountId,
        'product_id': productId,
        'product_name': productName.trim(),
        'quantity': quantity,
        'purchase': purchase,
        'purchase_total': purchaseTotal,
        'sale': sale,
        'status': status.name,
        'created_at': old?.createdAt ?? now,
        'updated_at': now,
      };
      final int id;
      if (old == null) {
        final acc = await tx.query(
          'accounts',
          columns: ['is_closed'],
          where: 'id = ?',
          whereArgs: [accountId],
        );
        if (acc.isNotEmpty && (acc.first['is_closed'] as int? ?? 0) == 1) {
          throw StateError('الحساب مغلق؛ لا يمكن إضافة طلبات جديدة إليه');
        }
        id = await tx.insert('orders', values);
      } else {
        final changed = await tx.update(
          'orders',
          values,
          where: 'id = ?',
          whereArgs: [old.id],
        );
        if (changed == 0) throw StateError('الطلب لم يعد موجودًا');
        id = old.id;
      }
      if (productId != null) {
        await tx.update(
          'products',
          {'last_purchase': purchase},
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
      return id;
    });
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
    bool openOnly = false,
    int offset = 0,
    int limit = 40,
  }) async => (await db.rawQuery(
    '''SELECT a.*, $_accountSummary
      FROM (SELECT * FROM accounts WHERE 1=1 ${openOnly ? 'AND is_closed=0' : ''} ${search.trim().isEmpty ? '' : "AND name LIKE ? ESCAPE '\\'"}
        ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?) a
      LEFT JOIN orders o ON o.account_id = a.id
      GROUP BY a.id ORDER BY a.created_at DESC, a.id DESC''',
    [
      if (search.trim().isNotEmpty) '%${_escapeLike(search.trim())}%',
      limit,
      offset,
    ],
  )).map(Account.fromMap).toList();
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
  }) async => (await db.query(
    'orders',
    where: 'account_id = ?',
    whereArgs: [accountId],
    orderBy: 'created_at DESC, id DESC',
    limit: limit,
    offset: offset,
  )).map(PurchaseOrder.fromMap).toList();

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
      SUM(CASE WHEN status!='cancelled' THEN quantity * sale ELSE 0 END) expected_sales,
      SUM(CASE WHEN status!='cancelled' THEN quantity * sale-COALESCE(purchase_total,quantity * purchase) ELSE 0 END) expected_profit,
      (SELECT COALESCE(SUM(amount),0) FROM profit_receipts) received_profit,
      SUM(CASE WHEN status='arrived' THEN quantity * sale ELSE 0 END) arrived_sales,
      SUM(CASE WHEN status='cancelled' THEN COALESCE(purchase_total,quantity * purchase) ELSE 0 END) refund
      FROM orders''',
    )).single;
    return Report.fromMap(
      row,
      accounts: counts['accounts'] as int,
      products: counts['products'] as int,
    );
  });
  Future<int> saveReceipt(int amount, String note, {ProfitReceipt? old}) async {
    _price(amount);
    if (amount == 0) throw const FormatException('أدخلي مبلغًا أكبر من صفر');
    _name(note);
    return db.transaction((tx) async {
      final sum =
          (await tx.rawQuery(
                'SELECT COALESCE(SUM(amount),0) total FROM profit_receipts WHERE id != ?',
                [old?.id ?? -1],
              )).single['total']
              as int;
      if (sum + amount > maxMoney) {
        throw const FormatException('المبلغ أكبر من النطاق الآمن');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = {
        'amount': amount,
        'note': note.trim(),
        'created_at': old?.createdAt ?? now,
        'updated_at': now,
      };
      if (old == null) return tx.insert('profit_receipts', values);
      final changed = await tx.update(
        'profit_receipts',
        values,
        where: 'id = ?',
        whereArgs: [old.id],
      );
      if (changed == 0) throw StateError('سجل الأرباح لم يعد موجودًا');
      return old.id;
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
  Future<List<PurchaseOrder>> cancelledOrders({
    int offset = 0,
    int limit = 40,
  }) async => (await db.rawQuery(
    '''SELECT o.*, a.name account_name FROM orders o
    JOIN accounts a ON a.id = o.account_id WHERE o.status='cancelled'
    ORDER BY o.created_at DESC, o.id DESC LIMIT ? OFFSET ?''',
    [limit, offset],
  )).map(PurchaseOrder.fromMap).toList();
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

  Future<BackupData> snapshot() => db.transaction((tx) async {
    final settings = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['theme'],
    );
    return BackupData(
      products: (await tx.query('products')).map(Product.fromMap).toList(),
      accounts: (await tx.query('accounts')).map(Account.fromMap).toList(),
      orders: (await tx.query('orders')).map(PurchaseOrder.fromMap).toList(),
      theme: settings.isEmpty ? 'system' : settings.single['value'] as String,
      receipts: (await tx.query(
        'profit_receipts',
      )).map(ProfitReceipt.fromMap).toList(),
    );
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
      await tx.delete('orders');
      await tx.delete('products');
      await tx.delete('accounts');
      final batch = tx.batch();
      for (final p in verified.products) {
        batch.insert('products', p.toMap());
      }
      for (final r in verified.receipts) {
        batch.insert('profit_receipts', r.toMap());
      }
      for (final a in verified.accounts) {
        batch.insert('accounts', a.toMap());
      }
      for (final o in verified.orders) {
        batch.insert('orders', o.toMap());
      }
      batch.insert('settings', {
        'key': 'theme',
        'value': verified.theme,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }
}
