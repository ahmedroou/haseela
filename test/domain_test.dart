import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:haseela/domain.dart';

PurchaseOrder order(int id, int q, int buy, int sell, OrderStatus status) =>
    PurchaseOrder(
      id: id,
      accountId: 1,
      productId: null,
      productName: 'منتج',
      quantity: q,
      purchase: buy,
      sale: sell,
      status: status,
      createdAt: 1000,
      updatedAt: 1000,
    );

void main() {
  test('acceptance totals distinguish arrived, pending and cancelled', () {
    final report = Report.fromOrders(
      [
        order(1, 2, 40000, 55000, OrderStatus.pending),
        order(2, 3, 30000, 45000, OrderStatus.arrived),
        order(3, 3, 35000, 50000, OrderStatus.cancelled),
      ],
      accounts: 2,
      products: 3,
    );
    expect(report.spent, 275000);
    expect(report.expectedSales, 245000);
    expect(report.expectedProfit, 75000);
    expect(report.realizedProfit, 45000);
    expect(report.refund, 105000);
    expect(report.net, 170000);
    expect(report.arrivedSales, 135000);
    expect(report.pieces, 8);
    expect(report.orders, 3);
    expect(report.pending, 1);
    expect(report.arrived, 1);
    expect(report.cancelled, 1);
  });
  test('decimal money is exact and accepts Arabic and Persian digits', () {
    expect(parseMoney('٠٫١٠'), 10);
    expect(parseMoney('۱۲۳.۴۵'), 12345);
    expect(parseMoney('0.29'), 29);
    expect(parseMoney(' 12.5 '), 1250);
    expect(moneyText(1234567), '12,345.67');
    expect(moneyText(-29), '−0.29');
    expect(moneyInput(29), '0.29');
    for (final value in ['-1', '1.234', 'abc', '1e3', '', '1,5', 'NaN']) {
      expect(parseMoney(value), isNull);
    }
    expect(parseQuantity('٣'), 3);
    expect(parseQuantity('0'), isNull);
    expect(parseQuantity('1.5'), isNull);
    expect(parseQuantity('999999999999999'), isNull);
  });
  test('losses remain negative; empty report is zero', () {
    final r = Report.fromOrders([
      order(1, 3, 30000, 20000, OrderStatus.arrived),
    ]);
    expect(r.expectedProfit, -30000);
    expect(r.realizedProfit, -30000);
    expect(Report.fromOrders([]).net, 0);
  });
  test('cancellation can be reversed without double counting', () {
    for (final s in OrderStatus.values) {
      final r = Report.fromOrders([order(1, 3, 35000, 50000, s)]);
      expect(r.spent, 105000);
      expect(r.refund, s == OrderStatus.cancelled ? 105000 : 0);
      expect(r.expectedProfit, s == OrderStatus.cancelled ? 0 : 45000);
      expect(r.realizedProfit, s == OrderStatus.arrived ? 45000 : 0);
    }
  });
  final valid = BackupData(
    products: const [
      Product(
        id: 1,
        name: 'سماعة',
        sale: 45000,
        createdAt: 1000,
        updatedAt: 1000,
      ),
    ],
    accounts: const [
      Account(id: 1, name: 'سبتمبر', createdAt: 1000, updatedAt: 1000),
    ],
    orders: [order(1, 2, 30000, 45000, OrderStatus.pending)],
    theme: 'dark',
  );
  test('backup round trip keeps prices, snapshots and theme', () {
    final copy = BackupData.decode(valid.encode());
    expect(copy.theme, 'dark');
    expect(copy.orders.single.toMap(), valid.orders.single.toMap());
  });
  test(
    'rejects corrupt, duplicate, orphaned, unsafe and unsupported backups',
    () {
      final badChanges = <void Function(Map<String, dynamic>)>[
        (m) => m['version'] = 2,
        (m) => m['theme'] = 'invalid',
        (m) => m['products'] = [...m['products'], m['products'][0]],
        (m) => m['orders'][0]['account_id'] = 99,
        (m) => m['orders'][0]['product_id'] = 99,
        (m) => m['orders'][0]['quantity'] = 0,
        (m) => m['orders'][0]['sale'] = -1,
        (m) => m['orders'][0]['purchase'] = .1,
        (m) => m['orders'][0]['status'] = 'sold',
        (m) => m['orders'][0]['updated_at'] = 1,
        (m) => m['orders'][0]['sale'] = maxMoney,
        (m) => m['accounts'][0]['name'] = '',
      ];
      for (final change in badChanges) {
        final m = jsonDecode(valid.encode()) as Map<String, dynamic>;
        change(m);
        expect(() => BackupData.decode(jsonEncode(m)), throwsFormatException);
      }
      expect(() => BackupData.decode('not json'), throwsFormatException);
    },
  );
}
