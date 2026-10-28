// Historical direct-provider fixture used only by existing MockClient tests.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:homemind_mobile/features/voice/domain/inventory_extraction_service.dart';
import 'package:homemind_mobile/features/voice/domain/voice_extraction.dart';

class GeminiInventoryExtractionService implements InventoryExtractionService {
  GeminiInventoryExtractionService({
    required this.apiKey,
    this.model = 'gemini-3.5-flash-lite',
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final Duration timeout;
  final http.Client _client;

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';

  @override
  Future<VoiceExtraction> extract({
    required String transcript,
    required DateTime currentDate,
    ExtractionMode mode = ExtractionMode.b2cInventory,
  }) async {
    final cleanTranscript = transcript.trim();
    if (apiKey.trim().isEmpty) {
      throw const ExtractionServiceException(
        'Chưa cấu hình Gemini API key cho bản development.',
        code: 'MISSING_API_KEY',
      );
    }
    if (cleanTranscript.isEmpty) {
      throw const ExtractionServiceException(
        'Transcript đang trống.',
        code: 'EMPTY_TRANSCRIPT',
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('$_endpoint/$model:generateContent')
          .replace(queryParameters: {'key': apiKey});
      final response = await _client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(
              _requestBody(
                transcript: cleanTranscript,
                currentDate: currentDate,
                mode: mode,
              ),
            ),
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ExtractionServiceException(
          _httpMessage(response.statusCode),
          code: 'GEMINI_HTTP_${response.statusCode}',
        );
      }

      final modelText = _candidateText(response.body);
      if (modelText == null || modelText.trim().isEmpty) {
        throw const ExtractionServiceException(
          'Gemini không trả nội dung có thể xử lý.',
          code: 'EMPTY_MODEL_RESPONSE',
        );
      }
      final decoded = jsonDecode(modelText);
      if (decoded is! Map) {
        throw const ExtractionServiceException(
          'Gemini trả dữ liệu không đúng định dạng JSON object.',
          code: 'INVALID_MODEL_JSON',
        );
      }

      stopwatch.stop();
      return VoiceExtraction.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
        rawTranscript: cleanTranscript,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      throw const ExtractionServiceException(
        'AI phản hồi quá 4 giây. Hãy thử lại hoặc chỉnh sửa thủ công.',
        code: 'TIMEOUT',
      );
    } on ExtractionServiceException {
      rethrow;
    } on ExtractionFormatException catch (error) {
      throw ExtractionServiceException(
        'Kết quả AI không hợp lệ: ${error.message}',
        code: 'INVALID_MODEL_SCHEMA',
      );
    } on FormatException {
      throw const ExtractionServiceException(
        'Gemini trả JSON không hợp lệ.',
        code: 'INVALID_MODEL_JSON',
      );
    } catch (_) {
      throw const ExtractionServiceException(
        'Không thể kết nối dịch vụ AI. Hãy kiểm tra mạng và thử lại.',
        code: 'NETWORK_ERROR',
      );
    }
  }

  Map<String, Object?> _requestBody({
    required String transcript,
    required DateTime currentDate,
    required ExtractionMode mode,
  }) {
    final date = currentDate.toIso8601String().split('T').first;
    final modeValue = switch (mode) {
      ExtractionMode.b2cInventory => 'b2c_inventory',
      ExtractionMode.b2bInventory => 'b2b_inventory',
    };
    final input = jsonEncode({
      'mode': modeValue,
      'locale': 'vi-VN',
      'currentDate': date,
      'timezone': 'Asia/Ho_Chi_Minh',
      'rawTranscript': transcript,
      'knownCategories': const [
        'Thực phẩm',
        'Mỹ phẩm',
        'Gia vị',
        'Thuốc',
        'Đồ tươi',
        'Đồ gia dụng',
      ],
      'knownUnits': const [
        'hộp',
        'chai',
        'gói',
        'bịch',
        'lốc',
        'kg',
        'gram',
        'lon',
        'thùng',
      ],
    });

    return {
      'systemInstruction': {
        'parts': [
          {
            'text': '''Bạn là bộ bóc tách dữ liệu tồn kho HomeMind.
Chỉ trả JSON theo schema được yêu cầu, không viết giải thích.
Không phát minh sản phẩm, số lượng, giá hoặc hạn sử dụng.
Nếu thiếu hoặc không chắc, trả null và thêm warning.
Chuẩn hóa cách đọc số, tiền, đơn vị và ngày tháng tiếng Việt.
expiryDate phải là YYYY-MM-DD và được tính từ currentDate nếu người dùng nói thời gian tương đối.
requiresConfirmation luôn là true.''',
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': input},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
        'responseJsonSchema': _responseSchema,
      },
    };
  }

  String? _candidateText(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final candidate = candidates.first;
    if (candidate is! Map) return null;
    final content = candidate['content'];
    if (content is! Map) return null;
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return null;
    final firstPart = parts.first;
    return firstPart is Map ? firstPart['text'] as String? : null;
  }

  String _httpMessage(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return 'Gemini API key không hợp lệ hoặc không có quyền truy cập.';
    }
    if (statusCode == 429) {
      return 'Gemini đã vượt quota. Hãy đợi một lúc rồi thử lại.';
    }
    if (statusCode >= 500) {
      return 'Dịch vụ Gemini đang lỗi. Hãy thử lại.';
    }
    return 'Gemini từ chối request (HTTP $statusCode).';
  }

  static const Map<String, Object?> _responseSchema = {
    'type': 'object',
    'required': [
      'schemaVersion',
      'intent',
      'correctedTranscript',
      'items',
      'warnings',
      'requiresConfirmation',
    ],
    'properties': {
      'schemaVersion': {
        'type': 'string',
        'enum': ['1.0'],
      },
      'intent': {
        'type': 'string',
        'enum': [
          'inventory.add',
          'inventory.mark_out',
          'shopping.add',
          'unknown',
        ],
      },
      'correctedTranscript': {'type': 'string'},
      'items': {
        'type': 'array',
        'items': {
          'type': 'object',
          'required': [
            'productName',
            'quantity',
            'unit',
            'category',
            'expiryDate',
            'importPrice',
            'sellPrice',
            'confidence',
            'warnings',
          ],
          'properties': {
            'productName': {'type': 'string'},
            'quantity': {
              'anyOf': [
                {'type': 'number'},
                {'type': 'null'},
              ],
            },
            'unit': {
              'anyOf': [
                {'type': 'string'},
                {'type': 'null'},
              ],
            },
            'category': {
              'anyOf': [
                {
                  'type': 'string',
                  'enum': [
                    'Thực phẩm',
                    'Mỹ phẩm',
                    'Gia vị',
                    'Thuốc',
                    'Đồ tươi',
                    'Đồ gia dụng',
                  ],
                },
                {'type': 'null'},
              ],
            },
            'expiryDate': {
              'anyOf': [
                {'type': 'string'},
                {'type': 'null'},
              ],
            },
            'importPrice': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
            },
            'sellPrice': {
              'anyOf': [
                {'type': 'integer'},
                {'type': 'null'},
              ],
            },
            'confidence': {
              'type': 'object',
              'additionalProperties': {'type': 'number'},
            },
            'warnings': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
      'warnings': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'requiresConfirmation': {
        'type': 'boolean',
        'enum': [true],
      },
    },
  };
}
