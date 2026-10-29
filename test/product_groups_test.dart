import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/product_groups.dart';

void main() {
  group('Gộp danh mục thành nhóm lớn', () {
    test('danh mục có sẵn trong dữ liệu thật', () {
      const cases = <String, ProductGroup>{
        'Rau củ': ProductGroup.fresh,
        'Thịt & cá': ProductGroup.fresh,
        'Sữa & bơ': ProductGroup.fresh,
        'Lương thực': ProductGroup.dry,
        'Gạo & ngũ cốc': ProductGroup.dry,
        'Mì & đồ khô': ProductGroup.dry,
        'Bánh kẹo': ProductGroup.dry,
        'Gia vị': ProductGroup.spice,
        'Nước giải khát': ProductGroup.drink,
        'Đồ uống': ProductGroup.drink,
        'Gia dụng': ProductGroup.home,
        'Hóa phẩm': ProductGroup.home,
        'Chăm sóc cá nhân': ProductGroup.home,
      };
      cases.forEach((category, expected) {
        expect(
          groupOf(category: category, name: 'x'),
          expected,
          reason: category,
        );
      });
    });

    test('"Thực phẩm" quá chung nên đoán theo tên', () {
      expect(
        groupOf(category: 'Thực phẩm', name: 'Trứng gà'),
        ProductGroup.fresh,
      );
      expect(
        groupOf(category: 'Thực phẩm', name: 'Mì Hảo Hảo'),
        ProductGroup.dry,
      );
    });

    test('không có danh mục thì đoán theo tên', () {
      expect(groupOf(name: 'cá khô'), ProductGroup.dry);
      expect(groupOf(name: 'Cá hồi phi lê'), ProductGroup.fresh);
      expect(groupOf(name: 'Cà phê G7'), ProductGroup.drink);
      expect(groupOf(name: 'Bia Saigon'), ProductGroup.drink);
      expect(groupOf(name: 'Tương ớt Chinsu 250g'), ProductGroup.spice);
      expect(groupOf(name: 'Nước tương'), ProductGroup.spice);
      expect(groupOf(name: 'nến'), ProductGroup.home);
      expect(groupOf(name: 'Bột giặt OMO'), ProductGroup.home);
      expect(groupOf(name: 'Sữa đặc Ông Thọ'), ProductGroup.dry);
      expect(groupOf(name: 'Sữa chua Vinamilk'), ProductGroup.fresh);
      expect(groupOf(name: 'chanh'), ProductGroup.other);
      // "Phô mai" là đồ tươi, không nhầm với "phở".
      expect(groupOf(name: 'Phô mai Con Bò Cười'), ProductGroup.fresh);
      expect(groupOf(name: 'Phở bò ăn liền'), ProductGroup.dry);
    });

    test('mỹ phẩm không bị nhầm với gia vị: "dưỡng" khác "đường", "son" khác "sơn"', () {
      expect(groupOf(name: 'son dưỡng'), ProductGroup.beauty);
      expect(groupOf(name: 'Son môi'), ProductGroup.beauty);
      expect(groupOf(name: 'Sữa rửa mặt'), ProductGroup.beauty);
      expect(groupOf(name: 'toner'), ProductGroup.beauty);
      expect(groupOf(name: 'Kem dưỡng da'), ProductGroup.beauty);
      expect(groupOf(name: 'đường cát'), ProductGroup.spice);
      expect(groupOf(name: 'Đường'), ProductGroup.spice);
      expect(groupOf(name: 'Sữa tươi'), ProductGroup.fresh);
    });

    test('mỹ phẩm & chăm sóc: nhận đúng dù tên có "dưỡng", "son", "phấn"', () {
      const beauty = [
        'Sữa dưỡng thể',
        'Serum dưỡng da',
        'Kem dưỡng ẩm',
        'Dưỡng môi',
        'Dầu dưỡng tóc',
        'Body lotion',
        'Kem chống nắng',
        'Nước tẩy trang',
        'Phấn phủ',
        'Mascara',
        'Kẻ mắt',
        'Má hồng',
        'Kem nền',
        'Cushion',
        'Sơn móng tay',
        'Xịt khoáng',
        'Tẩy tế bào chết',
        'Muối tắm',
        'Tinh dầu',
        'Sáp vuốt tóc',
        'Kem trị mụn',
        'Nước hoa hồng',
      ];
      for (final n in beauty) {
        expect(groupOf(name: n), ProductGroup.beauty, reason: n);
      }
    });

    test('tên mỹ phẩm thắng danh mục thực phẩm/chung chung do AI gắn sai', () {
      for (final c in [
        'Gia vị',
        'Thực phẩm',
        'Đồ khô',
        'Khác',
        'Chăm sóc cá nhân',
      ]) {
        expect(
          groupOf(category: c, name: 'Serum dưỡng da'),
          ProductGroup.beauty,
          reason: c,
        );
      }
      expect(
        groupOf(category: 'Gia vị', name: 'Muối tắm'),
        ProductGroup.beauty,
      );
      expect(groupOf(category: 'Mỹ phẩm', name: 'x'), ProductGroup.beauty);
      expect(groupOf(category: 'Skincare', name: 'x'), ProductGroup.beauty);
      expect(
        groupOf(category: 'Chăm sóc cá nhân', name: 'Dầu gội'),
        ProductGroup.home,
      );
      expect(
        groupOf(category: 'Chăm sóc cá nhân', name: 'x'),
        ProductGroup.home,
      );
    });

    test('thực phẩm dễ nhầm vẫn xếp đúng', () {
      expect(groupOf(name: 'Đường cát'), ProductGroup.spice);
      expect(groupOf(name: 'Dầu ăn Neptune'), ProductGroup.spice);
      expect(groupOf(name: 'Dầu olive'), ProductGroup.spice);
      expect(groupOf(name: 'Mật ong'), ProductGroup.spice);
      expect(groupOf(name: 'Muối ăn'), ProductGroup.spice);
      expect(groupOf(name: 'Rau muống'), ProductGroup.fresh);
      expect(groupOf(name: 'Sữa hạt óc chó'), ProductGroup.fresh);
      expect(groupOf(name: 'Sữa bột Dielac'), ProductGroup.dry);
      expect(groupOf(name: 'Bim bim Oishi'), ProductGroup.dry);
      expect(groupOf(name: 'Trà sữa'), ProductGroup.drink);
      expect(groupOf(name: 'Dao cạo râu'), ProductGroup.home);
      expect(groupOf(name: 'Bỉm Huggies'), ProductGroup.home);
      expect(groupOf(name: 'Gel rửa tay'), ProductGroup.home);
    });

    test('mỗi nhóm có tên và mô tả để người dùng đọc là hiểu', () {
      for (final group in ProductGroup.values) {
        expect(group.label, isNotEmpty);
        expect(group.hint, isNotEmpty);
        expect(group.emoji, isNotEmpty);
      }
    });

    test('bỏ dấu tiếng Việt', () {
      expect(normalizeVi('Tương ớt Đà Lạt'), 'tuong ot da lat');
    });
  });
}
