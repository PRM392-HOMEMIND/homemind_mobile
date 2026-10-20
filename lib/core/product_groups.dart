import 'l10n/app_text.dart';

/// Nhóm sản phẩm lớn dùng để lọc và hiển thị cho dễ hiểu.
///
/// Danh mục trong dữ liệu (Rau củ, Thịt & cá, Lương thực, Thực phẩm...) rất
/// nhiều và chồng chéo, người dùng khó biết món nào nằm ở đâu. Ta gộp lại
/// thành vài nhóm lớn, mỗi nhóm có mô tả ngắn liệt kê các loại bên trong.
enum ProductGroup { fresh, dry, spice, drink, home, beauty, other }

extension ProductGroupInfo on ProductGroup {
  String get emoji => switch (this) {
    ProductGroup.fresh => '🥬',
    ProductGroup.dry => '🍚',
    ProductGroup.spice => '🧂',
    ProductGroup.drink => '🥤',
    ProductGroup.home => '🧴',
    ProductGroup.beauty => '💄',
    ProductGroup.other => '📦',
  };

  String get label => switch (this) {
    ProductGroup.fresh => tr('Đồ tươi'),
    ProductGroup.dry => tr('Đồ khô & lương thực'),
    ProductGroup.spice => tr('Gia vị'),
    ProductGroup.drink => tr('Đồ uống'),
    ProductGroup.home => tr('Đồ dùng gia đình'),
    ProductGroup.beauty => tr('Mỹ phẩm & làm đẹp'),
    ProductGroup.other => tr('Khác'),
  };

  /// Gợi ý các loại nằm trong nhóm, để người dùng đọc là biết món của mình
  /// thuộc nhóm nào.
  String get hint => switch (this) {
    ProductGroup.fresh => tr('Rau, củ, thịt, cá, trứng, sữa'),
    ProductGroup.dry => tr('Gạo, mì, bún, bánh kẹo, cá khô, đồ hộp'),
    ProductGroup.spice => tr('Nước mắm, dầu ăn, đường, muối, tương'),
    ProductGroup.drink => tr('Nước ngọt, nước suối, bia, trà, cà phê'),
    ProductGroup.home => tr(
      'Bột giặt, giấy vệ sinh, dầu gội, kem đánh răng, pin',
    ),
    ProductGroup.beauty => tr('Sữa rửa mặt, toner, kem dưỡng, son, nước hoa'),
    ProductGroup.other => tr('Những món chưa xếp được vào nhóm nào'),
  };
}

const _accents = {
  'à': 'a',
  'á': 'a',
  'ả': 'a',
  'ã': 'a',
  'ạ': 'a',
  'ă': 'a',
  'ằ': 'a',
  'ắ': 'a',
  'ẳ': 'a',
  'ẵ': 'a',
  'ặ': 'a',
  'â': 'a',
  'ầ': 'a',
  'ấ': 'a',
  'ẩ': 'a',
  'ẫ': 'a',
  'ậ': 'a',
  'è': 'e',
  'é': 'e',
  'ẻ': 'e',
  'ẽ': 'e',
  'ẹ': 'e',
  'ê': 'e',
  'ề': 'e',
  'ế': 'e',
  'ể': 'e',
  'ễ': 'e',
  'ệ': 'e',
  'ì': 'i',
  'í': 'i',
  'ỉ': 'i',
  'ĩ': 'i',
  'ị': 'i',
  'ò': 'o',
  'ó': 'o',
  'ỏ': 'o',
  'õ': 'o',
  'ọ': 'o',
  'ô': 'o',
  'ồ': 'o',
  'ố': 'o',
  'ổ': 'o',
  'ỗ': 'o',
  'ộ': 'o',
  'ơ': 'o',
  'ờ': 'o',
  'ớ': 'o',
  'ở': 'o',
  'ỡ': 'o',
  'ợ': 'o',
  'ù': 'u',
  'ú': 'u',
  'ủ': 'u',
  'ũ': 'u',
  'ụ': 'u',
  'ư': 'u',
  'ừ': 'u',
  'ứ': 'u',
  'ử': 'u',
  'ữ': 'u',
  'ự': 'u',
  'ỳ': 'y',
  'ý': 'y',
  'ỷ': 'y',
  'ỹ': 'y',
  'ỵ': 'y',
  'đ': 'd',
};

/// Chữ thường, bỏ dấu tiếng Việt, chỉ giữ chữ-số và khoảng trắng.
String normalizeVi(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

const _byCategory = <String, ProductGroup>{
  'rau cu': ProductGroup.fresh,
  'thit ca': ProductGroup.fresh,
  'sua bo': ProductGroup.fresh,
  'trung': ProductGroup.fresh,
  'do tuoi': ProductGroup.fresh,
  'luong thuc': ProductGroup.dry,
  'gao ngu coc': ProductGroup.dry,
  'mi do kho': ProductGroup.dry,
  'banh keo': ProductGroup.dry,
  'do hop': ProductGroup.dry,
  'gia vi': ProductGroup.spice,
  'nuoc giai khat': ProductGroup.drink,
  'do uong': ProductGroup.drink,
  'gia dung': ProductGroup.home,
  'hoa pham': ProductGroup.home,
  've sinh': ProductGroup.home,
  'my pham': ProductGroup.beauty,
  'lam dep': ProductGroup.beauty,
  'cham soc da': ProductGroup.beauty,
  'cham soc toc': ProductGroup.beauty,
  'cham soc sac dep': ProductGroup.beauty,
  'trang diem': ProductGroup.beauty,
  'skincare': ProductGroup.beauty,
  'makeup': ProductGroup.beauty,
  'make up': ProductGroup.beauty,
  'cosmetics': ProductGroup.beauty,
  'beauty': ProductGroup.beauty,
};

// "Chăm sóc cá nhân" gồm cả dầu gội/kem đánh răng (đồ dùng) lẫn mỹ phẩm: để
// tên sản phẩm quyết định, mặc định là đồ dùng gia đình.
const _ambiguousCategory = 'cham soc ca nhan';

// Chữ gốc còn dấu quyết định những cặp bỏ dấu thì trùng nhau. Thay bằng mã
// riêng TRƯỚC khi bỏ dấu để các luật bên dưới không nhầm:
//  dưỡng (kem dưỡng) / đường (gia vị)   râu (cạo râu) / rau (rau củ)
//  sơn (sơn nhà)      / son (son môi)   phấn (phấn phủ) / phân (phân bón)
String _prepare(String raw) {
  var t = raw.toLowerCase();
  t = t
      .replaceAll(RegExp(r'dưỡng'), ' xcarex ')
      .replaceAll(RegExp(r'đường'), ' xsugarx ')
      .replaceAll(RegExp(r'râu'), ' xbeardx ')
      .replaceAll(RegExp(r'sơn'), ' xpaintx ')
      .replaceAll(RegExp(r'phấn'), ' xpowderx ')
      .replaceAll(RegExp(r'(^|\s)son(\s|$)'), ' xlipx ');
  return normalizeVi(t);
}

// ── Nhóm phi thực phẩm: tên sản phẩm đủ rõ để thắng cả danh mục chung chung
// (ví dụ AI gắn "Gia vị" cho "serum dưỡng da").
final _beauty = RegExp(
  r'\b(xcarex|xlipx|xpowderx|sua rua mat|rua mat|toner|serum|essence|ampoule|tinh chat|'
  r'kem chong nang|chong nang|tay trang|mat na|nuoc hoa|nuoc hoa hong|body mist|lotion|'
  r'my pham|kem nen|kem lot|cushion|mascara|eyeliner|ke mat|ke may|ma hong|highlight|'
  r'tay te bao chet|xit khoang|kem tri mun|tri mun|tri nam|kem body|kem tay|kem chan|'
  r'kem u toc|nhuom toc|sap vuot toc|gel vuot toc|wax toc|xit toc|keo xit toc|'
  r'tinh dau|dau massage|muoi tam|bot tam|son moi|son li|son kem|son tint|son thoi|'
  r'son mong|xpaintx mong|tay mong|lip balm|lip gloss|lip tint|bong tay trang|'
  r'sua tam trang|lam sach da|sua duong|kem trang da|kem mat|kem xcarex)\b',
);
final _home = RegExp(
  r'\b(bot giat|nuoc giat|nuoc rua|nuoc xa|nuoc lau|giay ve sinh|khan giay|khan uot|'
  r'khan giay uot|dau goi|dau xa|sua tam|kem danh rang|ban chai|chi nha khoa|'
  r'nuoc suc mieng|dao cao|xbeardx|bang ve sinh|(?<!bim )bim(?! bim)|ta lot|tam bong|gel rua tay|rua tay|'
  r'xa phong|xa bong|pin|khau trang|tui rac|nen|bao tay|giay an|mang boc|tui zip|'
  r'xit phong|xit muoi|thuoc diet|tay rua|nuoc tay|xpaintx|bong den)\b',
);

// ── Thực phẩm. Thứ tự kiểm tra có chủ ý: "cà phê" phải thành đồ uống trước khi
// "cà/cá" bị hiểu là cá; "cá khô" là đồ khô; "sữa đặc/sữa bột" là đồ khô chứ
// không phải tươi.
final _drink = RegExp(
  r'\b(bia|coca|pepsi|7up|sting|red bull|monster|revive|ca phe|cafe|coffee|tra xanh|tra|'
  r'nuoc suoi|nuoc ngot|nuoc ep|nuoc khoang|nuoc dua|nuoc tang luc|soda|aquafina|'
  r'nuoc giai khat|ruou|sinh to)\b',
);
final _spice = RegExp(
  r'\b(xsugarx|nuoc mam|nuoc tuong|nuoc cham|tuong ot|tuong ca|tuong|dau an|dau hao|'
  r'dau olive|dau oliu|dau me|dau dua|dau dau nanh|muoi|bot ngot|bot canh|hat nem|'
  r'tieu|giam|gia vi|sa te|mat ong|mat mia|bot nghe|duong)\b',
);
final _dry = RegExp(
  r'\b(kho|do hop|mi|bun|pho|mien|banh|keo|snack|bim bim|gao|nep|hat|sua dac|sua bot|ngu coc|'
  r'bot|nuoc cot dua|sua hop|yen mach)\b',
);
final _fresh = RegExp(
  r'\b(rau|cu|ca chua|thit|ca|tom|muc|trung|sua|pho mai|bo|chuoi|cam|tao|trai cay|hanh|'
  r'toi|gung|ot|kem tuoi|kem que|sua chua)\b',
);

/// Xếp một sản phẩm vào nhóm lớn.
///
/// Thứ tự ưu tiên:
/// 1. Danh mục mỹ phẩm/đồ dùng rõ ràng trong dữ liệu thì tin danh mục.
/// 2. Tên là mỹ phẩm/đồ dùng thì thắng danh mục thực phẩm hoặc chung chung.
/// 3. Danh mục thực phẩm có sẵn.
/// 4. Đoán theo tên (đồ uống, gia vị, đồ khô, đồ tươi).
ProductGroup groupOf({String? category, required String name}) {
  final cat = normalizeVi(category ?? '');
  final direct = _byCategory[cat];
  if (direct == ProductGroup.beauty || direct == ProductGroup.home) {
    return direct!;
  }
  final text = _prepare(name.isEmpty ? (category ?? '') : name);
  if (_beauty.hasMatch(text)) return ProductGroup.beauty;
  if (_home.hasMatch(text)) return ProductGroup.home;
  if (direct != null) return direct;
  if (cat == _ambiguousCategory) return ProductGroup.home;
  if (_drink.hasMatch(text)) return ProductGroup.drink;
  // "sữa hạt" là sữa (tươi), không phải hạt (đồ khô).
  if (RegExp(r'\bsua (hat|dau nanh|dau|gao)\b').hasMatch(text)) {
    return ProductGroup.fresh;
  }
  if (_spice.hasMatch(text)) return ProductGroup.spice;
  // "phô mai" (đồ tươi) bỏ dấu thành "pho mai", dễ nhầm với "phở" (đồ khô): xét riêng trước.
  if (RegExp(r'\bpho mai\b').hasMatch(text)) return ProductGroup.fresh;
  if (_dry.hasMatch(text)) return ProductGroup.dry;
  if (_fresh.hasMatch(text)) return ProductGroup.fresh;
  return ProductGroup.other;
}
