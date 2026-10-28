import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/voice/domain/voice_command.dart';

void main() {
  group('VoiceCommand.fromJson', () {
    test('parses an allowed write command', () {
      final command = VoiceCommand.fromJson({
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
      }, rawTranscript: 'thêm hai hộp sữa chua');

      expect(command.intent, VoiceIntent.inventoryAdd);
      expect(command.operationType, OperationType.write);
      expect(command.riskLevel, RiskLevel.medium);
      expect(command.actions.single.entities['quantity'], 2);
      expect(command.requiresConfirmation, isTrue);
    });

    test('parses a read command without confirmation', () {
      final command = VoiceCommand.fromJson({
        'schemaVersion': '2.0',
        'commandId': 'cmd-2',
        'intent': 'inventory.expiring',
        'operationType': 'read',
        'riskLevel': 'low',
        'correctedTranscript': 'Tuần này có gì hết hạn?',
        'assistantReply': 'Mình sẽ mở danh sách sắp hết hạn.',
        'actions': <Object?>[],
        'query': {
          'resource': 'inventory',
          'filters': {'expiryWithinDays': 7},
          'sort': 'expiry_asc',
        },
        'missingSlots': <Object?>[],
        'clarification': null,
        'requiresConfirmation': false,
        'suggestedUiTarget': 'inventory_expiring',
        'conversation': {'state': 'answering', 'expectedIntents': <Object?>[]},
      }, rawTranscript: 'tuần này có gì hết hạn');

      expect(command.intent, VoiceIntent.inventoryExpiring);
      expect(command.operationType, OperationType.read);
      expect(command.query?.resource, 'inventory');
      expect(command.requiresConfirmation, isFalse);
    });

    test('rejects intent outside allowlist', () {
      expect(
        () => VoiceCommand.fromJson({
          'schemaVersion': '2.0',
          'commandId': 'cmd-x',
          'intent': 'system.run_sql',
          'operationType': 'write',
          'riskLevel': 'low',
          'correctedTranscript': 'x',
          'assistantReply': 'x',
          'actions': <Object?>[],
          'missingSlots': <Object?>[],
          'clarification': null,
          'requiresConfirmation': false,
          'suggestedUiTarget': null,
          'conversation': {'state': 'idle', 'expectedIntents': <Object?>[]},
        }, rawTranscript: 'x'),
        throwsA(isA<VoiceCommandFormatException>()),
      );
    });

    test('policy rejects write command without confirmation', () {
      expect(
        () => VoiceCommand.fromJson({
          'schemaVersion': '2.0',
          'commandId': 'cmd-x',
          'intent': 'inventory.delete',
          'operationType': 'write',
          'riskLevel': 'high',
          'correctedTranscript': 'Xóa sữa.',
          'assistantReply': 'Xóa sữa.',
          'actions': <Object?>[],
          'missingSlots': <Object?>[],
          'clarification': null,
          'requiresConfirmation': false,
          'suggestedUiTarget': null,
          'conversation': {'state': 'idle', 'expectedIntents': <Object?>[]},
        }, rawTranscript: 'xóa sữa'),
        throwsA(isA<VoiceCommandFormatException>()),
      );
    });

    test('parses clarification with missing slots', () {
      final command = VoiceCommand.fromJson({
        'schemaVersion': '2.0',
        'commandId': 'cmd-3',
        'intent': 'inventory.add',
        'operationType': 'write',
        'riskLevel': 'medium',
        'correctedTranscript': 'Thêm sữa chua.',
        'assistantReply': 'Bạn muốn thêm bao nhiêu?',
        'actions': <Object?>[],
        'missingSlots': ['quantity'],
        'clarification': 'Bạn muốn thêm bao nhiêu?',
        'requiresConfirmation': false,
        'suggestedUiTarget': 'voice_clarification',
        'conversation': {
          'state': 'awaiting_clarification',
          'expectedIntents': [
            'conversation.answer_slot',
            'conversation.reject',
          ],
        },
      }, rawTranscript: 'thêm sữa chua');

      expect(command.needsClarification, isTrue);
      expect(command.missingSlots, ['quantity']);
    });
  });
}
