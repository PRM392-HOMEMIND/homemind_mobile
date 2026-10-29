import 'voice_command.dart';
import 'voice_command_service.dart';

enum ConversationOutcomeType { command, confirmed, rejected, noPendingCommand }

class ConversationOutcome {
  const ConversationOutcome({required this.type, this.command, this.message});

  final ConversationOutcomeType type;
  final VoiceCommand? command;
  final String? message;
}

class VoiceConversationController {
  VoiceConversationController({required this.service});

  final VoiceCommandService service;
  VoiceCommand? pendingCommand;

  Future<ConversationOutcome> handle(String transcript) async {
    final normalized = _normalize(transcript);
    final pending = pendingCommand;

    if (pending != null && _isConfirmation(normalized)) {
      pendingCommand = null;
      return ConversationOutcome(
        type: ConversationOutcomeType.confirmed,
        command: pending,
        message: 'Đã xác nhận lệnh bằng giọng nói.',
      );
    }
    if (pending != null && _isRejection(normalized)) {
      pendingCommand = null;
      return const ConversationOutcome(
        type: ConversationOutcomeType.rejected,
        message: 'Đã hủy lệnh đang chờ.',
      );
    }
    if (pending == null &&
        (_isConfirmation(normalized) || _isRejection(normalized))) {
      return const ConversationOutcome(
        type: ConversationOutcomeType.noPendingCommand,
        message: 'Không có lệnh nào đang chờ xác nhận.',
      );
    }

    final command = await service.understand(
      transcript: transcript,
      context: VoiceContext(
        conversationState:
            pending?.conversation.state ?? ConversationState.idle,
        pendingCommand: pending,
      ),
    );
    if (command.requiresConfirmation || command.needsClarification) {
      pendingCommand = command;
    }
    return ConversationOutcome(
      type: ConversationOutcomeType.command,
      command: command,
    );
  }

  void clear() => pendingCommand = null;

  bool _isConfirmation(String value) => const {
    'dong y',
    'xac nhan',
    'luu di',
    'dung roi',
    'thuc hien di',
  }.contains(value);

  bool _isRejection(String value) => const {
    'khong',
    'huy',
    'huy di',
    'khong dung',
    'dung lai',
    'bo thao tac nay',
  }.contains(value);

  String _normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
      .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
      .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
      .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
      .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
      .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
      .replaceAll('đ', 'd')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
