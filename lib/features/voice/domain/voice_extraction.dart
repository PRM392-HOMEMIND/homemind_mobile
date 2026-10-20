enum ExtractionIntent {
  inventoryAdd('inventory.add'),
  inventoryMarkOut('inventory.mark_out'),
  shoppingAdd('shopping.add'),
  unknown('unknown');

  const ExtractionIntent(this.wireValue);
  final String wireValue;

  static ExtractionIntent parse(Object? value) => values.firstWhere(
    (intent) => intent.wireValue == value,
    orElse: () => unknown,
  );
}

class ExtractionFormatException implements Exception {
  const ExtractionFormatException(this.message);
  final String message;

  @override
  String toString() => 'ExtractionFormatException: $message';
}

class ExtractedInventoryItem {
  const ExtractedInventoryItem({
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.expiryDate,
    required this.importPrice,
    required this.sellPrice,
    required this.confidence,
    required this.warnings,
  });

  final String productName;
  final double? quantity;
  final String? unit;
  final String? category;
  final DateTime? expiryDate;
  final int? importPrice;
  final int? sellPrice;
  final Map<String, double> confidence;
  final List<String> warnings;

  factory ExtractedInventoryItem.fromJson(Map<String, Object?> json) {
    final name = (json['productName'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      throw const ExtractionFormatException(
        'Tên sản phẩm không được để trống.',
      );
    }
    return ExtractedInventoryItem(
      productName: name,
      quantity: (json['quantity'] as num?)?.toDouble(),
      unit: _nullableText(json['unit']),
      category: _nullableText(json['category']),
      expiryDate: _nullableDate(json['expiryDate']),
      importPrice: (json['importPrice'] as num?)?.round(),
      sellPrice: (json['sellPrice'] as num?)?.round(),
      confidence: _confidence(json['confidence']),
      warnings: _strings(json['warnings']),
    );
  }
}

class VoiceExtraction {
  const VoiceExtraction({
    required this.schemaVersion,
    required this.intent,
    required this.rawTranscript,
    required this.correctedTranscript,
    required this.items,
    required this.warnings,
    required this.requiresConfirmation,
    this.processingTimeMs = 0,
  });

  final String schemaVersion;
  final ExtractionIntent intent;
  final String rawTranscript;
  final String correctedTranscript;
  final List<ExtractedInventoryItem> items;
  final List<String> warnings;
  final bool requiresConfirmation;
  final int processingTimeMs;

  factory VoiceExtraction.fromJson(
    Map<String, Object?> json, {
    required String rawTranscript,
    int processingTimeMs = 0,
  }) {
    if (json['schemaVersion'] != '1.0') {
      throw const ExtractionFormatException(
        'Phiên bản schema không được hỗ trợ.',
      );
    }
    if (json['requiresConfirmation'] != true) {
      throw const ExtractionFormatException(
        'Voice draft bắt buộc phải xác nhận.',
      );
    }
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const ExtractionFormatException('items phải là một danh sách.');
    }
    return VoiceExtraction(
      schemaVersion: '1.0',
      intent: ExtractionIntent.parse(json['intent']),
      rawTranscript: rawTranscript,
      correctedTranscript:
          _nullableText(json['correctedTranscript']) ?? rawTranscript,
      items: rawItems
          .map((item) {
            if (item is! Map) {
              throw const ExtractionFormatException('Item không hợp lệ.');
            }
            return ExtractedInventoryItem.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            );
          })
          .toList(growable: false),
      warnings: _strings(json['warnings']),
      requiresConfirmation: true,
      processingTimeMs: processingTimeMs,
    );
  }
}

String? _nullableText(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

DateTime? _nullableDate(Object? value) {
  final text = _nullableText(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

Map<String, double> _confidence(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, score) {
    final parsed = score is num
        ? score.toDouble().clamp(0.0, 1.0).toDouble()
        : 0.0;
    return MapEntry(key.toString(), parsed);
  });
}
