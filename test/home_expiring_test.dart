import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/date_format.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/home/presentation/home_page.dart';

InventoryItem _item(
  String name,
  String level,
  String? expiry, {
  String status = 'in_stock',
}) => InventoryItem(
  productId: name,
  name: name,
  category: null,
  quantity: 1,
  unit: 'cái',
  expiryDate: expiry,
  expiryLevel: level,
  status: status,
);

void main() {
  group('Trang chủ: danh sách sắp hết hạn cùng nguồn với Tủ đồ', () {
    test('gồm cả món còn 8-30 ngày (attention), gần hạn nhất đứng trước', () {
      final result = expiringItems([
        _item('ok', 'ok', '2030-01-01'),
        _item('nước ngọt', 'attention', '2026-10-30'),
        _item('sữa', 'soon', '2026-10-17'),
        _item('cá', 'urgent', '2026-10-13'),
        _item('bánh', 'expired', '2026-10-01'),
      ]);
      expect(result.map((i) => i.name), ['bánh', 'cá', 'sữa', 'nước ngọt']);
    });

    test('bỏ món đã hết hàng và món không có hạn dùng', () {
      final result = expiringItems([
        _item('hết hàng', 'soon', '2026-10-17', status: 'out'),
        _item('không hạn', 'attention', null),
        _item('còn', 'soon', '2026-10-17'),
      ]);
      expect(result.map((i) => i.name), ['còn']);
    });
  });

  test('ngày hiển thị theo kiểu Việt Nam', () {
    expect(formatDay('2026-10-30'), '30/10/2026');
    expect(formatDay(null), '');
    expect(formatDay('không phải ngày'), 'không phải ngày');
  });
}
