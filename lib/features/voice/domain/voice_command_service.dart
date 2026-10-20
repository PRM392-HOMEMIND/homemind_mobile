import 'voice_command.dart';

class VoiceContext {
  const VoiceContext({
    this.currentScreen = 'voice_assistant',
    this.userRole = 'B2C_MEMBER',
    this.workspaceType = 'household',
    this.conversationState = ConversationState.idle,
    this.pendingCommand,
  });

  final String currentScreen;
  final String userRole;
  final String workspaceType;
  final ConversationState conversationState;
  final VoiceCommand? pendingCommand;
}

abstract interface class VoiceCommandService {
  Future<VoiceCommand> understand({
    required String transcript,
    required VoiceContext context,
  });
}

class VoiceCommandServiceException implements Exception {
  const VoiceCommandServiceException(this.message, {this.code = 'UNKNOWN'});
  final String code;
  final String message;

  @override
  String toString() => message;
}
