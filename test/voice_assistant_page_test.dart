import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/domain/voice_command.dart';
import 'package:homemind_mobile/features/voice/domain/voice_command_service.dart';
import 'package:homemind_mobile/features/voice/domain/voice_conversation_controller.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_assistant_page.dart';

class FakeSpeech implements SpeechRecognitionService {
  SpeechResultCallback? result;
  SpeechStatusCallback? status;

  @override
  bool get isListening => false;
  @override
  Future<SpeechInitialization> initialize() async =>
      const SpeechInitialization(available: true, localeId: 'vi-VN');
  @override
  Future<void> startListening({
    required SpeechResultCallback onResult,
    required SpeechStatusCallback onStatus,
    required SpeechErrorCallback onError,
  }) async {
    result = onResult;
    status = onStatus;
    status!(SpeechListeningStatus.listening);
  }

  void finalText(String text) =>
      result!(SpeechRecognitionResult(text: text, isFinal: true));

  @override
  Future<void> stopListening() async =>
      status?.call(SpeechListeningStatus.stopped);
  @override
  Future<void> cancelListening() async =>
      status?.call(SpeechListeningStatus.stopped);
  @override
  Future<void> dispose() async {}
}

class FakeCommands implements VoiceCommandService {
  @override
  Future<VoiceCommand> understand({
    required String transcript,
    required VoiceContext context,
  }) async {
    return VoiceCommand.fromJson(
      {
        'schemaVersion': '2.0',
        'commandId': 'cmd-1',
        'intent': 'inventory.add',
        'operationType': 'write',
        'riskLevel': 'medium',
        'correctedTranscript': 'Thêm 2 hộp sữa chua.',
        'assistantReply': 'Thêm 2 hộp sữa chua. Đúng không?',
        'actions': [
          {
            'actionType': 'inventory.add',
            'targetId': null,
            'entities': {
              'productName': 'Sữa chua',
              'quantity': 2,
              'unit': 'hộp',
            },
            'confidence': {'productName': 0.95},
            'warnings': <Object?>[],
          },
        ],
        'missingSlots': <Object?>[],
        'clarification': null,
        'requiresConfirmation': true,
        'suggestedUiTarget': 'voice_confirmation',
        'conversation': {
          'state': 'awaiting_confirmation',
          'expectedIntents': ['conversation.confirm', 'conversation.reject'],
        },
      },
      rawTranscript: transcript,
      processingTimeMs: 800,
    );
  }
}

void main() {
  testWidgets('voice command reaches confirmation and confirms by voice', (
    tester,
  ) async {
    final speech = FakeSpeech();
    final controller = VoiceConversationController(service: FakeCommands());
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceAssistantPage(
          speechService: speech,
          conversationController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assistantMicButton')));
    await tester.pump();
    speech.finalText('thêm hai hộp sữa chua');
    await tester.pumpAndSettle();

    expect(find.text('Cần bạn xác nhận'), findsOneWidget);
    expect(find.text('Sữa chua'), findsOneWidget);

    final voiceConfirm = find.byKey(const Key('voiceConfirmButton'));
    await tester.ensureVisible(voiceConfirm);
    await tester.tap(voiceConfirm);
    await tester.pump();
    speech.finalText('đồng ý');
    await tester.pumpAndSettle();

    expect(find.text('Đã xác nhận bằng giọng nói'), findsOneWidget);
    expect(find.textContaining('chưa lưu database'), findsOneWidget);
  });
}
