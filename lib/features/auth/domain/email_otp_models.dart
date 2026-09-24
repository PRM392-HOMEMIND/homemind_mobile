import 'auth_models.dart';
import 'auth_service.dart';

sealed class PasswordChangeResult {
  const PasswordChangeResult();
}

class PasswordChanged extends PasswordChangeResult {
  const PasswordChanged();
}

class EmailChallenge extends PasswordChangeResult {
  const EmailChallenge({
    required this.id,
    required this.token,
    required this.purpose,
    required this.maskedEmail,
    required this.state,
    required this.serverTime,
    required this.resendAvailableAt,
    this.expiresAt,
  });
  final String id, token, purpose, maskedEmail, state;
  final DateTime serverTime, resendAvailableAt;
  final DateTime? expiresAt;
  Map<String, Object?> get proof => {
    'challengeId': id,
    'challengeToken': token,
  };
  factory EmailChallenge.fromJson(Map<String, Object?> data, {String? token}) =>
      EmailChallenge(
        id: data['challengeId'] as String,
        token: token ?? data['challengeToken'] as String,
        purpose: data['purpose'] as String,
        maskedEmail: data['maskedEmail'] as String? ?? '',
        state: data['state'] as String,
        serverTime: DateTime.parse(data['serverTime'] as String),
        resendAvailableAt: DateTime.parse(data['resendAvailableAt'] as String),
        expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
      );
}

class EmailVerification {
  const EmailVerification({
    this.session,
    this.ticket,
    this.ticketExpiresAt,
    this.reauthenticationRequired = false,
  });
  final AuthSession? session;
  final String? ticket;
  final DateTime? ticketExpiresAt;
  final bool reauthenticationRequired;
}

class EmailVerificationRequired extends AuthException {
  const EmailVerificationRequired(this.challenge)
    : super('Vui lòng xác minh email để tiếp tục.');
  final EmailChallenge challenge;
}

class LegacyEmailRequired extends AuthException {
  const LegacyEmailRequired(this.id, this.proof)
    : super('Vui lòng bổ sung email để tiếp tục.');
  final String id, proof;
}

abstract interface class EmailOtpAuthService {
  Future<EmailChallenge> challengeStatus(EmailChallenge challenge);
  Future<EmailChallenge> resendChallenge(EmailChallenge challenge);
  Future<EmailVerification> verifyChallenge(
    EmailChallenge challenge,
    String code,
  );
  Future<void> resetWithProof(
    EmailChallenge challenge,
    EmailVerification proof,
    String password,
  );
  Future<EmailChallenge> startEmailChange(String currentPassword);
  Future<EmailChallenge> startNewEmail(
    EmailChallenge old,
    EmailVerification proof,
    String email,
  );
  Future<EmailChallenge> addLegacyEmail(
    LegacyEmailRequired proof,
    String email,
  );
}
