import 'dart:convert';

enum OrderStatus {
  pending('قيد الانتظار'),
  arrived('وصل'),
  cancelled('ملغي');

  const OrderStatus(this.label);
  final String label;
}

String normalizeDigits(String text) {
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  return text.trim().replaceAll('٫', '.');
}

// Numeric safety bounds, not record count limits.
const maxMoney = 9000000000000;
const maxQuantity = 1000000;
int? parseMoney(String input) {
  final text = normalizeDigits(input);
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null || whole > maxMoney ~/ 100) return null;
  final fraction = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final value = whole * 100 + fraction;
  return value <= maxMoney ? value : null;
}

int? parseQuantity(String text) {
  final normalized = normalizeDigits(text);
  if (!RegExp(r'^\d+$').hasMatch(normalized)) return null;
  final value = int.tryParse(normalized);
  return value != null && value > 0 && value <= maxQuantity ? value : null;
}

String moneyInput(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
int unitFromTotal(int total, int quantity) =>
    (total + quantity ~/ 2) ~/ quantity;
String moneyText(int cents) {
  final absolute = cents.abs();
  final whole = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]!},',
  );
  final fraction = absolute % 100;
  return (cents < 0 ? '−' : '') +
      whole +
      (fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}');
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sale,
    required this.createdAt,
    required this.updatedAt,
    this.lastPurchase,
  });
  final int id;
  final String name;
  final int sale, createdAt, updatedAt;
  final int? lastPurchase;
  factory Product.fromMap(Map<String, Object?> m) => Product(
    id: m['id'] as int,
    name: m['name'] as String,
    sale: m['sale'] as int,
    createdAt: m['created_at'] as int,
    updatedAt: m['updated_at'] as int,
    lastPurchase: m['last_purchase'] as int?,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'sale': sale,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'last_purchase': lastPurchase,
  };
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.isClosed = false,
    this.orderCount = 0,
    this.pieces = 0,
    this.pending = 0,
    this.arrived = 0,
    this.cancelled = 0,
  });
  final int id;
  final String name;
  final int createdAt, updatedAt, orderCount;
  final bool isClosed;
  final int pieces, pending, arrived, cancelled;
  bool get isEmail => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(name);
  factory Account.fromMap(Map<String, Object?> m) => Account(
    id: m['id'] as int,
    name: m['name'] as String,
    createdAt: m['created_at'] as int,
    updatedAt: m['updated_at'] as int,
    isClosed: m['is_closed'] == 1 || m['is_closed'] == true,
    orderCount: m['order_count'] as int? ?? 0,
    pieces: (m['pieces'] as num?)?.toInt() ?? 0,
    pending: (m['pending'] as num?)?.toInt() ?? 0,
    arrived: (m['arrived'] as num?)?.toInt() ?? 0,
    cancelled: (m['cancelled'] as num?)?.toInt() ?? 0,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'is_closed': isClosed ? 1 : 0,
  };
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.accountId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.purchase,
    required this.sale,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.purchaseTotal,
    this.accountName,
  });
  final int id, accountId;
  final int? productId;
  final String productName;
  final String? accountName;
  final int quantity, purchase, sale, createdAt, updatedAt;
  final int? purchaseTotal;
  final OrderStatus status;
  int get cost => purchaseTotal ?? quantity * purchase;
  bool get approximateUnit =>
      purchaseTotal != null && cost != quantity * purchase;
  int get revenue => quantity * sale;
  int get profit => revenue - cost;
  factory PurchaseOrder.fromMap(Map<String, Object?> m) => PurchaseOrder(
    id: m['id'] as int,
    accountId: m['account_id'] as int,
    productId: m['product_id'] as int?,
    productName: m['product_name'] as String,
    quantity: m['quantity'] as int,
    purchase: m['purchase'] as int,
    sale: m['sale'] as int,
    status: OrderStatus.values.byName(m['status'] as String),
    createdAt: m['created_at'] as int,
    updatedAt: m['updated_at'] as int,
    purchaseTotal: m['purchase_total'] as int?,
    accountName: m['account_name'] as String?,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'account_id': accountId,
    'product_id': productId,
    'product_name': productName,
    'quantity': quantity,
    'purchase': purchase,
    'sale': sale,
    'status': status.name,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'purchase_total': purchaseTotal,
  };
}

class Report {
  const Report({
    this.accounts = 0,
    this.products = 0,
    this.orders = 0,
    this.pieces = 0,
    this.pending = 0,
    this.arrived = 0,
    this.cancelled = 0,
    this.spent = 0,
    this.expectedSales = 0,
    this.expectedProfit = 0,
    this.realizedProfit = 0,
    this.arrivedSales = 0,
    this.refund = 0,
  });
  final int accounts, products, orders, pieces, pending, arrived, cancelled;
  final int spent,
      expectedSales,
      expectedProfit,
      realizedProfit,
      arrivedSales,
      refund;
  int get net => spent - refund;
  int get grossProfit => expectedProfit + realizedProfit;
  factory Report.fromOrders(
    Iterable<PurchaseOrder> items, {
    int accounts = 0,
    int products = 0,
    int receivedProfit = 0,
  }) {
    var count = 0, pieces = 0, pending = 0, arrived = 0, cancelled = 0;
    var spent = 0, expectedSales = 0, expectedProfit = 0;
    var arrivedSales = 0, refund = 0;
    for (final o in items) {
      count++;
      pieces += o.quantity;
      spent += o.cost;
      switch (o.status) {
        case OrderStatus.cancelled:
          cancelled++;
          refund += o.cost;
        case OrderStatus.pending:
          pending++;
          expectedSales += o.revenue;
          expectedProfit += o.profit;
        case OrderStatus.arrived:
          arrived++;
          expectedSales += o.revenue;
          expectedProfit += o.profit;
          arrivedSales += o.revenue;
      }
    }
    return Report(
      accounts: accounts,
      products: products,
      orders: count,
      pieces: pieces,
      pending: pending,
      arrived: arrived,
      cancelled: cancelled,
      spent: spent,
      expectedSales: expectedSales,
      expectedProfit: expectedProfit - receivedProfit,
      realizedProfit: receivedProfit,
      arrivedSales: arrivedSales,
      refund: refund,
    );
  }
  factory Report.fromMap(
    Map<String, Object?> m, {
    required int accounts,
    required int products,
  }) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return Report(
      accounts: accounts,
      products: products,
      orders: n('orders'),
      pieces: n('pieces'),
      pending: n('pending'),
      arrived: n('arrived'),
      cancelled: n('cancelled'),
      spent: n('spent'),
      expectedSales: n('expected_sales'),
      expectedProfit: n('expected_profit') - n('received_profit'),
      realizedProfit: n('received_profit'),
      arrivedSales: n('arrived_sales'),
      refund: n('refund'),
    );
  }
}

class ProfitReceipt {
  const ProfitReceipt({
    required this.id,
    required this.amount,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });
  final int id, amount, createdAt, updatedAt;
  final String note;
  factory ProfitReceipt.fromMap(Map<String, Object?> row) => ProfitReceipt(
    id: row['id'] as int,
    amount: row['amount'] as int,
    note: row['note'] as String,
    createdAt: row['created_at'] as int,
    updatedAt: row['updated_at'] as int,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'amount': amount,
    'note': note,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

class BackupData {
  const BackupData({
    required this.products,
    required this.accounts,
    required this.orders,
    required this.theme,
    this.receipts = const [],
  });
  final List<Product> products;
  final List<Account> accounts;
  final List<PurchaseOrder> orders;
  final String theme;
  final List<ProfitReceipt> receipts;
  String encode() => const JsonEncoder.withIndent('  ').convert({
    'app': 'haseela',
    'version': 2,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'money_unit': 'halala',
    'theme': theme,
    'products': products.map((p) => p.toMap()).toList(),
    'accounts': accounts.map((a) => a.toMap()).toList(),
    'orders': orders.map((o) => o.toMap()).toList(),
    'receipts': receipts.map((r) => r.toMap()).toList(),
  });
  static BackupData decode(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map<String, dynamic> ||
          root['app'] != 'haseela' ||
          ![1, 2].contains(root['version']) ||
          root['money_unit'] != 'halala' ||
          !['system', 'light', 'dark'].contains(root['theme'])) {
        throw const FormatException('ملف النسخة غير مدعوم');
      }
      List<Map<String, Object?>> rows(String key) {
        final v = root[key];
        if (v is! List) throw const FormatException('بيانات ناقصة');
        return v.map((e) => Map<String, Object?>.from(e as Map)).toList();
      }

      void validBase(Map<String, Object?> r) {
        final id = r['id'], c = r['created_at'], u = r['updated_at'];
        if (id is! int ||
            id <= 0 ||
            id > 2147483647 ||
            c is! int ||
            u is! int ||
            c <= 0 ||
            u < c ||
            u > 8640000000000000) {
          throw const FormatException('معرّف أو تاريخ غير صالح');
        }
      }

      void name(Object? v, {int limit = 120}) {
        if (v is! String || v.trim().isEmpty || v.length > limit) {
          throw const FormatException('اسم غير صالح');
        }
      }

      void price(Object? v) {
        if (v is! int || v < 0 || v > maxMoney) {
          throw const FormatException('سعر غير صالح');
        }
      }

      final pr = rows('products'), ar = rows('accounts'), or = rows('orders');
      final rr = root['version'] == 1
          ? <Map<String, Object?>>[]
          : rows('receipts');
      final receiptIds = <int>{};
      var receivedTotal = 0;
      for (final r in rr) {
        validBase(r);
        name(r['note']);
        price(r['amount']);
        receivedTotal += r['amount'] as int;
        if ((r['amount'] as int) == 0 ||
            !receiptIds.add(r['id'] as int) ||
            receivedTotal > maxMoney) {
          throw const FormatException('سجل أرباح مستلمة غير صالح');
        }
      }
      for (final r in pr) {
        validBase(r);
        name(r['name']);
        price(r['sale']);
        if (r['last_purchase'] != null) price(r['last_purchase']);
      }
      for (final r in ar) {
        validBase(r);
        name(r['name'], limit: 254);
        if (r['is_closed'] != null &&
            ![0, 1, false, true].contains(r['is_closed'])) {
          throw const FormatException('حالة الحساب غير صالحة');
        }
      }
      final products = pr.map(Product.fromMap).toList();
      final accounts = ar.map(Account.fromMap).toList();
      final pids = products.map((p) => p.id).toSet(),
          aids = accounts.map((a) => a.id).toSet();
      if (pids.length != products.length || aids.length != accounts.length) {
        throw const FormatException('معرّفات مكررة');
      }
      var totalCost = 0, totalSales = 0;
      final orderIds = <int>{};
      for (final r in or) {
        validBase(r);
        name(r['product_name']);
        price(r['sale']);
        price(r['purchase']);
        final q = r['quantity'], pid = r['product_id'];
        if (q is! int ||
            q < 1 ||
            q > maxQuantity ||
            r['account_id'] is! int ||
            !aids.contains(r['account_id']) ||
            (pid != null && (pid is! int || !pids.contains(pid))) ||
            !OrderStatus.values.map((s) => s.name).contains(r['status']) ||
            !orderIds.add(r['id'] as int)) {
          throw const FormatException('طلب أو علاقة غير صالحة');
        }
        if (r['purchase_total'] != null) {
          price(r['purchase_total']);
          if (unitFromTotal(r['purchase_total'] as int, q) != r['purchase']) {
            throw const FormatException('سعر الوحدة لا يطابق إجمالي الشراء');
          }
        }
        totalCost +=
            (r['purchase_total'] as int?) ?? q * (r['purchase'] as int);
        totalSales += q * (r['sale'] as int);
        if (totalCost > maxMoney || totalSales > maxMoney) {
          throw const FormatException('الإجماليات أكبر من النطاق الآمن');
        }
      }
      return BackupData(
        products: products,
        accounts: accounts,
        orders: or.map(PurchaseOrder.fromMap).toList(),
        theme: root['theme'] as String,
        receipts: rr.map(ProfitReceipt.fromMap).toList(),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('ملف النسخة تالف أو غير صالح');
    }
  }
}
