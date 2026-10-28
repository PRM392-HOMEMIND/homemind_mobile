import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/voice/domain/voice_command.dart';
import 'package:homemind_mobile/features/voice/domain/voice_command_service.dart';
import 'package:homemind_mobile/features/voice/domain/voice_conversation_controller.dart';

class FakeCommandService implements VoiceCommandService {
  FakeCommandService(this.next);
  final VoiceCommand next;
  var calls = 0;

  @override
  Future<VoiceCommand> understand({
    required String transcript,
    required VoiceContext context,
  }) async {
    calls++;
    return next;
  }
}

VoiceCommand writeCommand() => VoiceCommand.fromJson({
  'schemaVersion': '2.0',
  'commandId': 'cmd-1',
  'intent': 'inventory.add',
  'operationType': 'write',
  'riskLevel': 'medium',
  'correctedTranscript': 'Thêm 2 hộp sữa.',
  'assistantReply': 'Thêm 2 hộp sữa. Đúng không?',
  'actions': [
    {
      'actionType': 'inventory.add',
      'targetId': null,
      'entities': {'productName': 'Sữa', 'quantity': 2, 'unit': 'hộp'},
      'confidence': {'productName': 0.9},
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
}, rawTranscript: 'thêm hai hộp sữa');

void main() {
  test('understands initial utterance through command service', () async {
    final service = FakeCommandService(writeCommand());
    final controller = VoiceConversationController(service: service);

    final outcome = await controller.handle('thêm hai hộp sữa');

    expect(outcome.type, ConversationOutcomeType.command);
    expect(controller.pendingCommand?.commandId, 'cmd-1');
    expect(service.calls, 1);
  });

  test('confirms pending command locally without another model call', () async {
    final service = FakeCommandService(writeCommand());
    final controller = VoiceConversationController(service: service);
    await controller.handle('thêm hai hộp sữa');

    final outcome = await controller.handle('đồng ý');

    expect(outcome.type, ConversationOutcomeType.confirmed);
    expect(outcome.command?.commandId, 'cmd-1');
    expect(service.calls, 1);
    expect(controller.pendingCommand, isNull);
  });

  test('rejects pending command locally', () async {
    final service = FakeCommandService(writeCommand());
    final controller = VoiceConversationController(service: service);
    await controller.handle('thêm hai hộp sữa');

    final outcome = await controller.handle('hủy đi');

    expect(outcome.type, ConversationOutcomeType.rejected);
    expect(service.calls, 1);
    expect(controller.pendingCommand, isNull);
  });

  test('confirmation word at idle does not execute anything', () async {
    final service = FakeCommandService(writeCommand());
    final controller = VoiceConversationController(service: service);

    final outcome = await controller.handle('đồng ý');

    expect(outcome.type, ConversationOutcomeType.noPendingCommand);
    expect(service.calls, 0);
  });
}
