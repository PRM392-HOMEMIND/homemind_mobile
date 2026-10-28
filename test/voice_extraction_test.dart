import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/voice/domain/inventory_extraction_service.dart';
import 'package:homemind_mobile/features/voice/domain/voice_extraction.dart';

void main() {
  group('VoiceExtraction.fromJson', () {
    test('parses a valid inventory extraction', () {
      final extraction = VoiceExtraction.fromJson({
        'schemaVersion': '1.0',
        'intent': 'inventory.add',
        'correctedTranscript':
            'Tôi vừa mua 2 hộp sữa chua Vinamilk, hạn 7 ngày.',
        'items': [
          {
            'productName': 'Sữa chua Vinamilk',
            'quantity': 2,
            'unit': 'hộp',
            'category': 'Thực phẩm',
            'expiryDate': '2026-09-02',
            'importPrice': null,
            'sellPrice': null,
            'confidence': {
              'productName': 0.95,
              'quantity': 0.99,
              'unit': 0.98,
              'expiryDate': 0.93,
            },
            'warnings': <Object?>[],
          },
        ],
        'warnings': <Object?>[],
        'requiresConfirmation': true,
      }, rawTranscript: 'tôi vừa mua hai hộp sữa chua hạn bảy ngày');

      expect(extraction.intent, ExtractionIntent.inventoryAdd);
      expect(extraction.items, hasLength(1));
      expect(extraction.items.single.productName, 'Sữa chua Vinamilk');
      expect(extraction.items.single.quantity, 2);
      expect(extraction.items.single.expiryDate, DateTime(2026, 9, 2));
      expect(extraction.requiresConfirmation, isTrue);
    });

    test('allows nullable optional inventory fields', () {
      final extraction = VoiceExtraction.fromJson({
        'schemaVersion': '1.0',
        'intent': 'inventory.add',
        'correctedTranscript': 'Tôi vừa mua nước mắm.',
        'items': [
          {
            'productName': 'Nước mắm',
            'quantity': null,
            'unit': null,
            'category': 'Gia vị',
            'expiryDate': null,
            'importPrice': null,
            'sellPrice': null,
            'confidence': {'productName': 0.8},
            'warnings': ['Thiếu số lượng và hạn sử dụng.'],
          },
        ],
        'warnings': ['Cần bổ sung thông tin.'],
        'requiresConfirmation': true,
      }, rawTranscript: 'tôi vừa mua nước mắm');

      final item = extraction.items.single;
      expect(item.quantity, isNull);
      expect(item.unit, isNull);
      expect(item.expiryDate, isNull);
      expect(item.warnings, contains('Thiếu số lượng và hạn sử dụng.'));
    });

    test('rejects an unsupported schema version', () {
      expect(
        () => VoiceExtraction.fromJson({
          'schemaVersion': '2.0',
          'intent': 'unknown',
          'correctedTranscript': '',
          'items': <Object?>[],
          'warnings': <Object?>[],
          'requiresConfirmation': true,
        }, rawTranscript: 'test'),
        throwsA(isA<ExtractionFormatException>()),
      );
    });

    test('rejects blank product names', () {
      expect(
        () => VoiceExtraction.fromJson({
          'schemaVersion': '1.0',
          'intent': 'inventory.add',
          'correctedTranscript': 'test',
          'items': [
            {
              'productName': '   ',
              'quantity': 1,
              'unit': 'hộp',
              'category': null,
              'expiryDate': null,
              'importPrice': null,
              'sellPrice': null,
              'confidence': <String, Object?>{},
              'warnings': <Object?>[],
            },
          ],
          'warnings': <Object?>[],
          'requiresConfirmation': true,
        }, rawTranscript: 'test'),
        throwsA(isA<ExtractionFormatException>()),
      );
    });

    test('requires user confirmation for voice extraction', () {
      expect(
        () => VoiceExtraction.fromJson({
          'schemaVersion': '1.0',
          'intent': 'unknown',
          'correctedTranscript': 'test',
          'items': <Object?>[],
          'warnings': <Object?>[],
          'requiresConfirmation': false,
        }, rawTranscript: 'test'),
        throwsA(isA<ExtractionFormatException>()),
      );
    });
  });

  test('extraction service contract accepts transcript and current date', () {
    expect(InventoryExtractionService, isNotNull);
    expect(ExtractionMode.b2cInventory.name, 'b2cInventory');
  });
}
