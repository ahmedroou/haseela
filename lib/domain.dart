import 'dart:convert';

enum OrderStatus {
  pending('قيد الانتظار'),
  arrived('وصل'),
  cancelled('ملغي');

  const OrderStatus(this.label);
  final String label;
}

enum AccountFilter { all, open, closed }

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
    this.closedAt,
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
  final int? closedAt;
  final int pieces, pending, arrived, cancelled;
  static int compareByCreation(Account first, Account second) {
    final dateOrder = first.createdAt.compareTo(second.createdAt);
    return dateOrder == 0 ? first.id.compareTo(second.id) : dateOrder;
  }

  bool get isEmail => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(name);
  factory Account.fromMap(Map<String, Object?> m) => Account(
    id: m['id'] as int,
    name: m['name'] as String,
    createdAt: m['created_at'] as int,
    updatedAt: m['updated_at'] as int,
    isClosed: m['is_closed'] == 1 || m['is_closed'] == true,
    closedAt: m['closed_at'] as int?,
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
    'closed_at': closedAt,
  };
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.purchase,
    required this.sale,
    this.purchaseTotal,
    this.unpriced = false,
  });
  final int? productId, purchaseTotal;
  final String productName;
  final int quantity, purchase, sale;
  final bool unpriced;
  int get cost => purchaseTotal ?? quantity * purchase;
  int get revenue => quantity * sale;

  void validate() {
    if (productName.trim().isEmpty || productName.length > 120) {
      throw const FormatException('اختاري اسم منتج من 1 إلى 120 حرفًا');
    }
    if (quantity < 1 || quantity > maxQuantity) {
      throw const FormatException('الكمية غير صالحة');
    }
    if (unpriced &&
        (productId != null ||
            purchase != 0 ||
            sale != 0 ||
            purchaseTotal != null)) {
      throw const FormatException('بيانات تسعير المنتج غير صالحة');
    }
    if (purchase < 0 ||
        sale < 0 ||
        cost < 0 ||
        purchase > maxMoney ||
        sale > maxMoney ||
        cost > maxMoney ||
        revenue > maxMoney) {
      throw const FormatException('إجمالي المبالغ أكبر من النطاق الآمن');
    }
    if (purchaseTotal != null && unitFromTotal(cost, quantity) != purchase) {
      throw const FormatException('سعر الوحدة لا يطابق إجمالي الشراء');
    }
  }

  factory OrderItem.fromMap(Map<String, Object?> m) => OrderItem(
    productId: m['product_id'] as int?,
    productName: m['product_name'] as String,
    quantity: m['quantity'] as int,
    purchase: m['purchase'] as int,
    sale: m['sale'] as int,
    purchaseTotal: m['purchase_total'] as int?,
    unpriced: _readUnpriced(m['is_unpriced']),
  );
  Map<String, Object?> toMap() => {
    'product_id': productId,
    'product_name': productName.trim(),
    'quantity': quantity,
    'purchase': purchase,
    'sale': sale,
    'purchase_total': purchaseTotal,
    'is_unpriced': unpriced ? 1 : 0,
  };
}

bool _readUnpriced(Object? value) => switch (value) {
  null || 0 => false,
  1 => true,
  _ => throw const FormatException('بيانات تسعير المنتج غير صالحة'),
};

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
    this.saleTotal,
    this.items = const [],
    this.unpriced = false,
  });
  final int id, accountId;
  final int? productId;
  final String productName;
  final String? accountName;
  final int quantity, purchase, sale, createdAt, updatedAt;
  final int? purchaseTotal;
  final int? saleTotal;
  final List<OrderItem> items;
  final bool unpriced;
  final OrderStatus status;
  int get cost => purchaseTotal ?? quantity * purchase;
  bool get approximateUnit =>
      purchaseTotal != null && cost != quantity * purchase;
  int get revenue => saleTotal ?? quantity * sale;
  int get profit => revenue - cost;
  String get displayName => items.isEmpty
      ? productName
      : items.map((item) => item.productName).join(' + ');
  List<OrderItem> get lines => items.isEmpty
      ? [
          OrderItem(
            productId: productId,
            productName: productName,
            quantity: quantity,
            purchase: purchase,
            sale: sale,
            purchaseTotal: purchaseTotal,
            unpriced: unpriced,
          ),
        ]
      : items;
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
    saleTotal: m['sale_total'] as int?,
    unpriced: _readUnpriced(m['is_unpriced']),
    items: (m['items'] as List? ?? const [])
        .map(
          (item) => OrderItem.fromMap(Map<String, Object?>.from(item as Map)),
        )
        .toList(),
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
    'sale_total': saleTotal,
    'is_unpriced': unpriced ? 1 : 0,
  };
  Map<String, Object?> toBackupMap() => {
    ...toMap(),
    'items': items.map((item) => item.toMap()).toList(),
  };
}

class ProfitShare {
  const ProfitShare({
    required this.name,
    required this.rate,
    required this.createdAt,
    required this.updatedAt,
  });

  static const maxRate = 5000;
  static const maxPercent = maxRate ~/ 100;
  final String name;
  // Hundredths of one percent: 5000 represents 50%.
  final int rate, createdAt, updatedAt;

  static bool validRate(int rate) => rate > 0 && rate <= maxRate;

  static int? parseRate(String input) {
    final value = parseMoney(input);
    return value != null && validRate(value) ? value : null;
  }

  int amountFor(int netProfit) =>
      netProfit <= 0 ? 0 : (netProfit * rate + 5000) ~/ 10000;

  factory ProfitShare.fromMap(Map<String, Object?> m) => ProfitShare(
    name: m['name'] as String,
    rate: m['rate'] as int,
    createdAt: m['created_at'] as int,
    updatedAt: m['updated_at'] as int,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'rate': rate,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

class PeriodReportItem {
  const PeriodReportItem(this.name, this.quantity, this.amount);

  final String name;
  final int quantity;
  final int? amount;
}

class PeriodReport {
  PeriodReport(Iterable<PeriodReportItem> items)
    : items = List.unmodifiable(items);

  factory PeriodReport.fromOrders(Iterable<PurchaseOrder> orders) {
    // Match SQLite NOCASE, which folds ASCII only, and keeps the smallest name.
    final asciiUppercase = RegExp('[A-Z]');
    final groups = <String, PeriodReportItem>{};
    for (final order in orders) {
      if (order.status == OrderStatus.cancelled) continue;
      for (final item in order.lines) {
        final key = item.productName.replaceAllMapped(
          asciiUppercase,
          (match) => match[0]!.toLowerCase(),
        );
        final prior = groups[key];
        groups[key] = PeriodReportItem(
          prior != null && prior.name.compareTo(item.productName) < 0
              ? prior.name
              : item.productName,
          (prior?.quantity ?? 0) + item.quantity,
          item.unpriced ? prior?.amount : (prior?.amount ?? 0) + item.revenue,
        );
      }
    }
    final keys = groups.keys.toList()..sort();
    return PeriodReport(keys.map((key) => groups[key]!));
  }

  final List<PeriodReportItem> items;
  int get quantity => items.fold(0, (total, item) => total + item.quantity);
  int get amount => items.fold(0, (total, item) => total + (item.amount ?? 0));

  String toCsv(String period) {
    final formulaPrefix = RegExp(r'^[\r\n\t]|^\s*[=+\-@]');
    String cell(String value) {
      final escaped = (formulaPrefix.hasMatch(value) ? "'$value" : value)
          .replaceAll('"', '""');
      return '"$escaped"';
    }

    return [
      '\uFEFF${cell('الفترة')},${cell(period)},',
      '${cell('الصنف')},${cell('العدد')},${cell('المبلغ المطلوب (ريال)')}',
      for (final item in items)
        '${cell(item.name)},${item.quantity},${item.amount == null ? '' : moneyInput(item.amount!)}',
      '${cell('الإجمالي')},$quantity,${moneyInput(amount)}',
    ].join('\r\n');
  }
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
    this.sideCosts = 0,
    this.expectedSales = 0,
    this.grossProfit = 0,
    this.profitShare,
    this.realizedProfit = 0,
    this.arrivedSales = 0,
    this.refund = 0,
  });
  final int accounts, products, orders, pieces, pending, arrived, cancelled;
  final int spent,
      sideCosts,
      expectedSales,
      grossProfit,
      realizedProfit,
      arrivedSales,
      refund;
  int get net => spent - refund;
  final ProfitShare? profitShare;
  int get thirdPartyProfit => profitShare?.amountFor(grossProfit) ?? 0;
  int get expectedProfit => grossProfit - thirdPartyProfit - realizedProfit;
  factory Report.fromOrders(
    Iterable<PurchaseOrder> items, {
    int accounts = 0,
    int products = 0,
    int receivedProfit = 0,
    int sideCosts = 0,
    ProfitShare? profitShare,
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
      spent: spent + sideCosts,
      sideCosts: sideCosts,
      expectedSales: expectedSales,
      grossProfit: expectedProfit - sideCosts,
      profitShare: profitShare,
      realizedProfit: receivedProfit,
      arrivedSales: arrivedSales,
      refund: refund,
    );
  }
  factory Report.fromMap(
    Map<String, Object?> m, {
    required int accounts,
    required int products,
    ProfitShare? profitShare,
  }) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    final sideCosts = n('side_costs');
    return Report(
      accounts: accounts,
      products: products,
      orders: n('orders'),
      pieces: n('pieces'),
      pending: n('pending'),
      arrived: n('arrived'),
      cancelled: n('cancelled'),
      spent: n('spent') + sideCosts,
      sideCosts: sideCosts,
      expectedSales: n('expected_sales'),
      grossProfit: n('expected_profit') - sideCosts,
      profitShare: profitShare,
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

class SideCost {
  const SideCost({
    required this.id,
    required this.amount,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });
  final int id, amount, createdAt, updatedAt;
  final String note;
  factory SideCost.fromMap(Map<String, Object?> row) => SideCost(
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

class PeriodArchiveInfo {
  const PeriodArchiveInfo(this.id, this.name, this.range, this.closedAt);

  final int id, closedAt;
  final String name, range;

  factory PeriodArchiveInfo.fromMap(Map<String, Object?> row) =>
      PeriodArchiveInfo(
        row['id'] as int,
        row['name'] as String,
        row['range_label'] as String,
        row['closed_at'] as int,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'range_label': range,
    'closed_at': closedAt,
  };
}

class ArchivedPeriod {
  const ArchivedPeriod(this.info, this.data);

  final PeriodArchiveInfo info;
  final BackupData data;

  Report get report => Report.fromOrders(
    data.orders,
    accounts: data.accounts.length,
    products: data.products.length,
    receivedProfit: data.receipts.fold(
      0,
      (sum, receipt) => sum + receipt.amount,
    ),
    sideCosts: data.sideCosts.fold(0, (sum, cost) => sum + cost.amount),
    profitShare: data.profitShare,
  );
}

class BackupData {
  const BackupData({
    required this.products,
    required this.accounts,
    required this.orders,
    required this.theme,
    this.receipts = const [],
    this.sideCosts = const [],
    this.profitShare,
    this.archives = const [],
  });
  final List<Product> products;
  final List<Account> accounts;
  final List<PurchaseOrder> orders;
  final String theme;
  final List<ProfitReceipt> receipts;
  final List<SideCost> sideCosts;
  final ProfitShare? profitShare;
  final List<ArchivedPeriod> archives;

  String encode({bool compact = false}) =>
      (compact ? const JsonEncoder() : const JsonEncoder.withIndent('  '))
          .convert(_toMap());

  Map<String, Object?> _toMap() => {
    'app': 'haseela',
    'version': archives.isEmpty ? 7 : 8,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'money_unit': 'halala',
    'theme': theme,
    'products': products.map((p) => p.toMap()).toList(),
    'accounts': accounts.map((a) => a.toMap()).toList(),
    'orders': orders.map((o) => o.toBackupMap()).toList(),
    'receipts': receipts.map((r) => r.toMap()).toList(),
    'side_costs': sideCosts.map((r) => r.toMap()).toList(),
    'profit_share': profitShare?.toMap(),
    if (archives.isNotEmpty)
      'archives': [
        for (final archive in archives)
          {...archive.info.toMap(), 'data': archive.data._toMap()},
      ],
  };

  static BackupData decode(String text) {
    try {
      return _decode(jsonDecode(text));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('ملف النسخة تالف أو غير صالح');
    }
  }

  static BackupData _decode(Object? root, {bool allowArchives = true}) {
    if (root is! Map<String, dynamic> ||
        root['app'] != 'haseela' ||
        ![
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          if (allowArchives) 8,
        ].contains(root['version']) ||
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
    final version = (root['version'] as num).toInt();
    final rr = version == 1 ? <Map<String, Object?>>[] : rows('receipts');
    final sr = version < 4 ? <Map<String, Object?>>[] : rows('side_costs');
    ProfitShare? profitShare;
    if (version >= 5) {
      if (!root.containsKey('profit_share')) {
        throw const FormatException('بيانات حصة الطرف الثالث ناقصة');
      }
      final saved = root['profit_share'];
      if (saved != null) {
        final row = Map<String, Object?>.from(saved as Map);
        validBase({...row, 'id': 1});
        name(row['name']);
        final rate = row['rate'];
        if (rate is! int || !ProfitShare.validRate(rate)) {
          throw const FormatException('نسبة الطرف الثالث غير صالحة');
        }
        profitShare = ProfitShare.fromMap(row);
      }
    }
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
    final sideCostIds = <int>{};
    var totalCost = 0;
    for (final r in sr) {
      validBase(r);
      price(r['amount']);
      final note = r['note'];
      totalCost += r['amount'] as int;
      if (note is! String ||
          note.length > 120 ||
          (r['amount'] as int) == 0 ||
          !sideCostIds.add(r['id'] as int) ||
          totalCost > maxMoney) {
        throw const FormatException('سجل تكاليف جانبية غير صالح');
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
      final closed = r['is_closed'] == 1 || r['is_closed'] == true;
      // Older backups did not record the closing time. Their last change is
      // the best available estimate, as in the database migration.
      if (version < 3) {
        r['closed_at'] = closed ? r['updated_at'] : null;
      }
      final closedAt = r['closed_at'];
      if (closed
          ? closedAt is! int ||
                closedAt < (r['created_at'] as int) ||
                closedAt > (r['updated_at'] as int)
          : closedAt != null) {
        throw const FormatException('تاريخ إغلاق الحساب غير صالح');
      }
    }
    final products = pr.map(Product.fromMap).toList();
    final accounts = ar.map(Account.fromMap).toList();
    final pids = products.map((p) => p.id).toSet(),
        aids = accounts.map((a) => a.id).toSet();
    if (pids.length != products.length || aids.length != accounts.length) {
      throw const FormatException('معرّفات مكررة');
    }
    var totalSales = 0;
    final orderIds = <int>{};
    for (final r in or) {
      if (version < 7) r.remove('is_unpriced');
      if (version < 6) {
        r.remove('items');
        r.remove('sale_total');
      }
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
      if (version >= 6) {
        if (r['items'] is! List) {
          throw const FormatException('تفاصيل منتجات الطلب ناقصة');
        }
        final order = PurchaseOrder.fromMap(r);
        if (order.items.isEmpty) {
          order.lines.single.validate();
          if (order.saleTotal != null) {
            throw const FormatException('إجمالي بيع الطلب غير صالح');
          }
        } else {
          var quantity = 0, cost = 0, revenue = 0;
          for (final item in order.items) {
            item.validate();
            if (item.productId != null && !pids.contains(item.productId)) {
              throw const FormatException('منتج الطلب غير موجود');
            }
            quantity += item.quantity;
            cost += item.cost;
            revenue += item.revenue;
          }
          if (order.items.length < 2 ||
              order.unpriced != order.items.every((item) => item.unpriced) ||
              quantity != order.quantity ||
              cost != order.purchaseTotal ||
              revenue != order.saleTotal ||
              order.productId != null ||
              order.productName != order.items.first.productName ||
              unitFromTotal(revenue, quantity) != order.sale) {
            throw const FormatException('إجماليات الطلب لا تطابق منتجاته');
          }
        }
      }
      totalCost += (r['purchase_total'] as int?) ?? q * (r['purchase'] as int);
      totalSales += (r['sale_total'] as int?) ?? q * (r['sale'] as int);
      if (totalCost > maxMoney || totalSales > maxMoney) {
        throw const FormatException('الإجماليات أكبر من النطاق الآمن');
      }
    }
    final archives = <ArchivedPeriod>[];
    if (version >= 8) {
      final ids = <int>{};
      for (final row in rows('archives')) {
        final info = PeriodArchiveInfo.fromMap(row);
        validBase({
          'id': info.id,
          'created_at': info.closedAt,
          'updated_at': info.closedAt,
        });
        name(info.name, limit: 300);
        name(info.range, limit: 300);
        if (!ids.add(info.id)) {
          throw const FormatException('معرّفات مكررة في أرشيف الفترات');
        }
        final data = _decode(row['data'], allowArchives: false);
        if (data.orders.any((row) => !orderIds.add(row.id)) ||
            data.receipts.any((row) => !receiptIds.add(row.id)) ||
            data.sideCosts.any((row) => !sideCostIds.add(row.id))) {
          throw const FormatException('توجد سجلات مكررة بين الفترات');
        }
        archives.add(ArchivedPeriod(info, data));
      }
    }
    return BackupData(
      products: products,
      accounts: accounts,
      orders: or.map(PurchaseOrder.fromMap).toList(),
      theme: root['theme'] as String,
      receipts: rr.map(ProfitReceipt.fromMap).toList(),
      sideCosts: sr.map(SideCost.fromMap).toList(),
      profitShare: profitShare,
      archives: archives,
    );
  }
}
