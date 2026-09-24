import '../../assistant/domain/assistant_models.dart';

/// Thông tin phiên đăng nhập của người dùng.
class AuthSession {
  const AuthSession({
    required this.token,
    required this.profile,
    required this.loginTime,
    this.refreshToken = '',
    this.expiresAt,
  });

  final String token;
  final String refreshToken;
  final DateTime? expiresAt;
  final UserProfile profile;
  final DateTime loginTime;

  AccountRole get role => profile.accountRole;

  bool get needsRefresh =>
      expiresAt != null &&
      expiresAt!.isBefore(DateTime.now().add(const Duration(seconds: 30)));
}
