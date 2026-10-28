import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';

/// Hợp đồng với backend: dữ liệu mẫu là phản hồi THẬT của
/// GET /v1/workspaces/:id/bootstrap (chụp từ server), app phải đọc được hết.
Bootstrap _load(String name) {
  final json = jsonDecode(File('test/fixtures/$name').readAsStringSync());
  return Bootstrap.fromJson((json as Map).cast<String, Object?>());
}

void main() {
  for (final name in ['bootstrap_person.json', 'bootstrap_store.json']) {
    group('đọc phản hồi thật $name', () {
      late Bootstrap b;
      setUp(() => b = _load(name));

      test('tổng quan khớp với danh sách kho', () {
        expect(b.home.totalProducts, b.inventory.length);
        expect(
          b.home.inStockCount,
          b.inventory.where((i) => i.status == 'in_stock').length,
        );
        expect(
          b.home.outCount,
          b.inventory.where((i) => i.status == 'out').length,
        );
        expect(b.inventoryTotal, b.inventory.length);
      });

      test('mọi sản phẩm có tên, đơn vị và mức hạn hợp lệ', () {
        const levels = {'ok', 'attention', 'soon', 'urgent', 'expired'};
        for (final item in b.inventory) {
          expect(item.productId, isNotEmpty);
          expect(item.name, isNotEmpty);
          expect(levels, contains(item.expiryLevel));
          expect(item.name.contains('�'), isFalse, reason: item.name);
          expect(item.name.contains('?'), isFalse, reason: item.name);
        }
      });

      test('số món cần mua khớp với danh sách mua sắm', () {
        final needed = b.shoppingItems.where((s) => s.status == 'needed');
        expect(b.home.shoppingNeededCount, needed.length);
      });

      test('thông báo: số chưa đọc đúng và id ổn định', () {
        expect(b.unreadCount, b.notifications.where((n) => !n.read).length);
        for (final n in b.notifications) {
          expect(n.id, startsWith('expiry.'));
          expect(n.title, isNotEmpty);
        }
        expect(
          b.notifications.length,
          b.home.expired.length + b.home.expiringSoon.length,
        );
      });
    });
  }
}
