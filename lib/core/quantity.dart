/// Mirrors PostgreSQL numeric(12,3) input limits; null remains an explicit unknown.
double? parseQuantity(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(text)) return null;
  final value = double.tryParse(text);
  return value != null &&
          value.isFinite &&
          value >= 0.001 &&
          value <= 999999999.999
      ? value
      : null;
}
