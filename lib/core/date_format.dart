/// Ngày hiển thị cho người Việt: `2027-01-01` -> `01/01/2027`.
/// Chuỗi không đúng dạng ISO (hoặc rỗng) được giữ nguyên.
String formatDay(String? iso) {
  final value = iso?.trim() ?? '';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return value;
  return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
}
