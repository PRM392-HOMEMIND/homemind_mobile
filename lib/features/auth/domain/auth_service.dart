import 'auth_models.dart';

/// Giao diện dịch vụ xác thực.
/// Production dùng `RemoteAuthService`; các implementation khác chỉ được inject trong test.
abstract class AuthService {
  /// Kiểm tra xem người dùng đã hoàn thành màn hình Onboarding (mới tải app) chưa.
  Future<bool> hasCompletedOnboarding();

  /// Đánh dấu đã xem xong Onboarding.
  Future<void> setOnboardingCompleted();

  /// Lấy phiên đăng nhập hiện tại nếu có (null nếu chưa đăng nhập).
  Future<AuthSession?> getCurrentSession();

  /// Đăng nhập bằng Email hoặc Số điện thoại cùng Mật khẩu.
  /// Ném ngoại lệ `AuthException` nếu thông tin đăng nhập không hợp lệ.
  Future<AuthSession> login({
    required String identifier,
    required String password,
  });

  Future<String> getAccessToken();

  /// Đăng xuất khỏi hệ thống, hủy phiên làm việc hiện tại.
  Future<void> logout();
}

/// Ngoại lệ xác thực với thông báo thân thiện cho người dùng.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
