/// Tiền Việt (VND, số nguyên): `1250000` -> `1.250.000 ₫`.
String formatVnd(int amount) {
  final digits = amount.abs().toString();
  final out = StringBuffer(amount < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return '$out ₫';
}

const int maxPriceVnd = 100000000000;

/// Đọc số tiền người dùng gõ. Chấp nhận `45000`, `45.000`, `45,000`, `45k`,
/// `1.5tr`, `1,5 triệu`. Dấu `.` `,` là ngăn cách hàng nghìn, trừ khi có hậu tố
/// `k`/`tr`/`triệu` (khi đó là dấu thập phân). Trả null nếu rỗng hoặc không hợp lệ.
int? parseVnd(String input) {
  var text = input.trim().toLowerCase().replaceAll(RegExp(r'[\s₫đ]'), '');
  if (text.isEmpty) return null;
  var factor = 1;
  if (text.endsWith('triệu')) {
    factor = 1000000;
    text = text.substring(0, text.length - 'triệu'.length);
  } else if (text.endsWith('tr')) {
    factor = 1000000;
    text = text.substring(0, text.length - 2);
  } else if (text.endsWith('k')) {
    factor = 1000;
    text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty) return null;
  final num value;
  if (factor == 1) {
    if (!RegExp(r'^\d+([.,]\d{3})*$').hasMatch(text)) return null;
    value = int.parse(text.replaceAll(RegExp(r'[.,]'), ''));
  } else {
    if (!RegExp(r'^\d+([.,]\d{1,3})?$').hasMatch(text)) return null;
    value = double.parse(text.replaceAll(',', '.'));
  }
  final result = (value * factor).round();
  return result > maxPriceVnd ? null : result;
}
