import '../../assistant/domain/assistant_models.dart';
import 'auth_models.dart';
import 'email_otp_models.dart';

abstract interface class SessionRefreshService {
  Future<String> refreshAccessToken(String rejectedToken);
  Stream<AuthSession?> get sessionChanges;
}

/// Publish an authoritative profile into the existing authenticated session.
/// Implementations reject responses belonging to a previous identity.
abstract interface class SessionProfileService {
  bool publishProfile(UserProfile profile);
}

abstract interface class AccountAuthService implements EmailOtpAuthService {
  Future<EmailChallenge> register({
    required bool acceptedTerms,
    required bool acceptedPrivacy,
    required String displayName,
    String? email,
    String? phone,
    required String password,
    required String workspaceType,
  });
  Future<EmailChallenge> forgotPassword(String identifier);
  Future<void> resetPassword(String token, String newPassword);
  Future<PasswordChangeResult> changePassword(
    String currentPassword,
    String newPassword,
  );
  Future<UserProfile> changeIdentifiers({
    required String currentPassword,
    required String? email,
    required String? phone,
  });
  Future<void> logoutAll();
  Future<void> closeAccount(String currentPassword, {required bool delete});
}
