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
        version: 3,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          sale INTEGER NOT NULL CHECK(sale >= 0),
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
          await db.execute('''CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
          await db.execute('''CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
          product_name TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity > 0),
          purchase INTEGER NOT NULL CHECK(purchase >= 0),
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

  Future<void> close() => db.close();
  Future<Product?> product(int id) async {
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.single);
  }

  static void _name(String name) {
    if (name.trim().isEmpty || name.length > 120) {
      throw const FormatException('اكتبي اسمًا من 1 إلى 120 حرفًا');
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

  Future<int> saveAccount(String name, {Account? old}) async {
    _name(name);
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = {
      'name': name.trim(),
      'created_at': old?.createdAt ?? now,
      'updated_at': now,
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

  Future<int> saveOrder({
    required int accountId,
    required int? productId,
    required String productName,
    required int quantity,
    required int purchase,
    required int sale,
    required OrderStatus status,
    PurchaseOrder? old,
  }) async {
    _name(productName);
    _price(purchase);
    _price(sale);
    if (quantity < 1 || quantity > maxQuantity) {
      throw const FormatException('الكمية غير صالحة');
    }
    return db.transaction((tx) async {
      final sums = (await tx.rawQuery(
        '''SELECT COALESCE(SUM(quantity * purchase),0) cost,
        COALESCE(SUM(quantity * sale),0) revenue FROM orders WHERE id != ?''',
        [old?.id ?? -1],
      )).single;
      if ((sums['cost'] as int) + quantity * purchase > maxMoney ||
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
        'sale': sale,
        'status': status.name,
        'created_at': old?.createdAt ?? now,
        'updated_at': now,
      };
      if (old == null) return tx.insert('orders', values);
      final changed = await tx.update(
        'orders',
        values,
        where: 'id = ?',
        whereArgs: [old.id],
      );
      if (changed == 0) throw StateError('الطلب لم يعد موجودًا');
      return old.id;
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
    int offset = 0,
    int limit = 40,
  }) async => (await db.rawQuery(
    '''SELECT a.*, (SELECT COUNT(*) FROM orders o WHERE o.account_id = a.id) order_count
      FROM accounts a ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?''',
    [limit, offset],
  )).map(Account.fromMap).toList();
  Future<Account?> account(int id) async {
    final rows = await db.rawQuery(
      '''SELECT a.*, (SELECT COUNT(*) FROM orders o WHERE o.account_id = a.id) order_count
      FROM accounts a WHERE a.id = ?''',
      [id],
    );
    return rows.isEmpty ? null : Account.fromMap(rows.single);
  }

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
      SUM(quantity * purchase) spent,
      SUM(CASE WHEN status!='cancelled' THEN quantity * sale ELSE 0 END) expected_sales,
      SUM(CASE WHEN status!='cancelled' THEN quantity * (sale-purchase) ELSE 0 END) expected_profit,
      SUM(CASE WHEN status='arrived' THEN quantity * (sale-purchase) ELSE 0 END) realized_profit,
      SUM(CASE WHEN status='arrived' THEN quantity * sale ELSE 0 END) arrived_sales,
      SUM(CASE WHEN status='cancelled' THEN quantity * purchase ELSE 0 END) refund
      FROM orders''',
    )).single;
    return Report.fromMap(
      row,
      accounts: counts['accounts'] as int,
      products: counts['products'] as int,
    );
  });
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
      await tx.delete('orders');
      await tx.delete('products');
      await tx.delete('accounts');
      final batch = tx.batch();
      for (final p in verified.products) {
        batch.insert('products', p.toMap());
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
