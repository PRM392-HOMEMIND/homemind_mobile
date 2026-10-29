import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'support/gemini_inventory_extraction_service.dart';
import 'package:homemind_mobile/features/voice/domain/inventory_extraction_service.dart';
import 'package:homemind_mobile/features/voice/domain/voice_extraction.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fails before network when API key is missing', () async {
    var called = false;
    final service = GeminiInventoryExtractionService(
      apiKey: '',
      client: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      service.extract(
        transcript: 'Tôi mua hai hộp sữa',
        currentDate: DateTime(2026, 8, 26),
      ),
      throwsA(
        isA<ExtractionServiceException>().having(
          (error) => error.code,
          'code',
          'MISSING_API_KEY',
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('sends JSON schema request and parses Gemini response', () async {
    http.Request? captured;
    final service = GeminiInventoryExtractionService(
      apiKey: 'test-key',
      model: 'gemini-test-model',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'schemaVersion': '1.0',
                        'intent': 'inventory.add',
                        'correctedTranscript':
                            'Tôi mua 2 hộp sữa chua, hạn 7 ngày.',
                        'items': [
                          {
                            'productName': 'Sữa chua',
                            'quantity': 2,
                            'unit': 'hộp',
                            'category': 'Thực phẩm',
                            'expiryDate': '2026-09-02',
                            'importPrice': null,
                            'sellPrice': null,
                            'confidence': {'productName': 0.95},
                            'warnings': <Object?>[],
                          },
                        ],
                        'warnings': <Object?>[],
                        'requiresConfirmation': true,
                      }),
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.extract(
      transcript: 'tôi mua hai hộp sữa chua hạn bảy ngày',
      currentDate: DateTime(2026, 8, 26),
    );

    expect(captured, isNotNull);
    expect(
      captured!.url.toString(),
      contains('/models/gemini-test-model:generateContent?key=test-key'),
    );
    expect(captured!.url.queryParameters['key'], 'test-key');
    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final generation = body['generationConfig'] as Map<String, Object?>;
    expect(generation['responseMimeType'], 'application/json');
    expect(generation['responseJsonSchema'], isA<Map>());
    expect(result.intent, ExtractionIntent.inventoryAdd);
    expect(result.items.single.quantity, 2);
    expect(result.processingTimeMs, greaterThanOrEqualTo(0));
  });

  test('maps API failures without exposing the API key', () async {
    final service = GeminiInventoryExtractionService(
      apiKey: 'super-secret-test-key',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {'message': 'API key not valid'},
          }),
          400,
        ),
      ),
    );

    try {
      await service.extract(
        transcript: 'test',
        currentDate: DateTime(2026, 8, 26),
      );
      fail('Expected ExtractionServiceException');
    } on ExtractionServiceException catch (error) {
      expect(error.code, 'GEMINI_HTTP_400');
      expect(error.message, isNot(contains('super-secret-test-key')));
    }
  });

  test('rejects a Gemini response with no candidate text', () async {
    final service = GeminiInventoryExtractionService(
      apiKey: 'test-key',
      client: MockClient(
        (request) async =>
            http.Response(jsonEncode({'candidates': <Object?>[]}), 200),
      ),
    );

    await expectLater(
      service.extract(transcript: 'test', currentDate: DateTime(2026, 8, 26)),
      throwsA(
        isA<ExtractionServiceException>().having(
          (error) => error.code,
          'code',
          'EMPTY_MODEL_RESPONSE',
        ),
      ),
    );
  });
}
