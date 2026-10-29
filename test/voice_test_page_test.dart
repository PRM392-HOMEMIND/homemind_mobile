import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/voice/domain/inventory_extraction_service.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/domain/voice_extraction.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_test_page.dart';

class FakeSpeechRecognitionService implements SpeechRecognitionService {
  FakeSpeechRecognitionService({this.available = true});

  final bool available;
  SpeechResultCallback? _onResult;
  SpeechStatusCallback? _onStatus;
  SpeechErrorCallback? _onError;

  @override
  bool get isListening => false;

  @override
  Future<SpeechInitialization> initialize() async => SpeechInitialization(
    available: available,
    localeId: 'vi-VN',
    message: available ? null : 'Không hỗ trợ nhận diện giọng nói.',
  );

  @override
  Future<void> startListening({
    required SpeechResultCallback onResult,
    required SpeechStatusCallback onStatus,
    required SpeechErrorCallback onError,
  }) async {
    _onResult = onResult;
    _onStatus = onStatus;
    _onError = onError;
    _onStatus?.call(SpeechListeningStatus.listening);
  }

  void emitPartial(String text) {
    _onResult?.call(SpeechRecognitionResult(text: text, isFinal: false));
  }

  void emitFinal(String text) {
    _onResult?.call(SpeechRecognitionResult(text: text, isFinal: true));
  }

  void emitError(String message) => _onError?.call(message);

  @override
  Future<void> stopListening() async {
    _onStatus?.call(SpeechListeningStatus.stopped);
  }

  @override
  Future<void> cancelListening() async {
    _onStatus?.call(SpeechListeningStatus.stopped);
  }

  @override
  Future<void> dispose() async {}
}

class FakeExtractionService implements InventoryExtractionService {
  FakeExtractionService({this.failure});

  final ExtractionServiceException? failure;
  String? receivedTranscript;

  @override
  Future<VoiceExtraction> extract({
    required String transcript,
    required DateTime currentDate,
    ExtractionMode mode = ExtractionMode.b2cInventory,
  }) async {
    receivedTranscript = transcript;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failure != null) throw failure!;
    return VoiceExtraction.fromJson(
      {
        'schemaVersion': '1.0',
        'intent': 'inventory.add',
        'correctedTranscript': 'Tôi mua 2 hộp sữa chua, hạn 7 ngày.',
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
      },
      rawTranscript: transcript,
      processingTimeMs: 820,
    );
  }
}

void main() {
  testWidgets('shows Vietnamese-ready state after initialization', (
    tester,
  ) async {
    final service = FakeSpeechRecognitionService();

    await tester.pumpWidget(
      MaterialApp(home: VoiceTestPage(speechService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('HomeMind Voice Test'), findsOneWidget);
    expect(find.textContaining('Tiếng Việt'), findsWidgets);
    expect(find.byKey(const Key('microphoneButton')), findsOneWidget);
  });

  testWidgets('updates transcript when partial speech results arrive', (
    tester,
  ) async {
    final service = FakeSpeechRecognitionService();

    await tester.pumpWidget(
      MaterialApp(home: VoiceTestPage(speechService: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();

    service.emitPartial('Tôi vừa mua hai hộp sữa');
    await tester.pump();

    expect(find.text('Tôi vừa mua hai hộp sữa'), findsOneWidget);
    expect(find.text('Đang nghe...'), findsOneWidget);
  });

  testWidgets('keeps final transcript and allows clearing it', (tester) async {
    final service = FakeSpeechRecognitionService();

    await tester.pumpWidget(
      MaterialApp(home: VoiceTestPage(speechService: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();

    service.emitFinal('Nhập năm mươi lon bia Heineken');
    await tester.pump();
    expect(find.text('Nhập năm mươi lon bia Heineken'), findsOneWidget);

    final clearButton = find.byKey(const Key('clearTranscriptButton'));
    await tester.ensureVisible(clearButton);
    await tester.tap(clearButton);
    await tester.pump();
    expect(find.text('Nhập năm mươi lon bia Heineken'), findsNothing);
    final transcriptWidget = tester.widget<Text>(
      find.byKey(const Key('transcriptText')),
    );
    expect(transcriptWidget.data, contains('Bấm mic rồi nói'));
  });

  testWidgets('shows a friendly unavailable state', (tester) async {
    final service = FakeSpeechRecognitionService(available: false);

    await tester.pumpWidget(
      MaterialApp(home: VoiceTestPage(speechService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Không hỗ trợ nhận diện giọng nói.'), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('microphoneButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('analyzes transcript and shows confirmation', (tester) async {
    final speech = FakeSpeechRecognitionService();
    final extraction = FakeExtractionService();
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceTestPage(
          speechService: speech,
          extractionService: extraction,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();
    speech.emitFinal('tôi mua hai hộp sữa chua hạn bảy ngày');
    await tester.pump();

    final analyze = find.byKey(const Key('analyzeButton'));
    await tester.ensureVisible(analyze);
    await tester.tap(analyze);
    await tester.pump();
    expect(find.text('HomeMind AI đang phân tích...'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(
      extraction.receivedTranscript,
      'tôi mua hai hộp sữa chua hạn bảy ngày',
    );
    expect(find.text('AI đã hiểu như sau'), findsOneWidget);
    expect(find.text('Sữa chua'), findsOneWidget);
    expect(find.textContaining('820 ms'), findsOneWidget);
  });

  testWidgets('keeps transcript when extraction fails', (tester) async {
    final speech = FakeSpeechRecognitionService();
    final extraction = FakeExtractionService(
      failure: const ExtractionServiceException(
        'AI phản hồi quá 4 giây.',
        code: 'TIMEOUT',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceTestPage(
          speechService: speech,
          extractionService: extraction,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();
    speech.emitFinal('tôi mua nước mắm');
    await tester.pump();

    final analyze = find.byKey(const Key('analyzeButton'));
    await tester.ensureVisible(analyze);
    await tester.tap(analyze);
    await tester.pumpAndSettle();

    expect(find.text('tôi mua nước mắm'), findsOneWidget);
    expect(find.text('AI phản hồi quá 4 giây.'), findsOneWidget);
    expect(find.text('Thử phân tích lại'), findsOneWidget);
  });

  testWidgets('confirms extraction in prototype success state', (tester) async {
    final speech = FakeSpeechRecognitionService();
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceTestPage(
          speechService: speech,
          extractionService: FakeExtractionService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();
    speech.emitFinal('tôi mua hai hộp sữa chua hạn bảy ngày');
    await tester.pump();
    final analyze = find.byKey(const Key('analyzeButton'));
    await tester.ensureVisible(analyze);
    await tester.tap(analyze);
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('confirmButton'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('Đã xác nhận bản nháp'), findsOneWidget);
    expect(find.textContaining('chưa lưu database'), findsOneWidget);
  });
}
