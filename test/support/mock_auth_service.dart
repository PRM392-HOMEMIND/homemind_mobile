import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/auth/domain/auth_models.dart';
import 'package:homemind_mobile/features/auth/domain/auth_service.dart';

/// Test double chỉ được các widget test truyền vào `HomeMindApp`.
class MockAccount {
  const MockAccount({
    required this.email,
    required this.phone,
    required this.password,
    required this.role,
    required this.profile,
  });

  final String email;
  final String phone;
  final String password;
  final AccountRole role;
  final UserProfile profile;

  static const List<MockAccount> sampleAccounts = [
    MockAccount(
      email: 'person@homemind.vn',
      phone: '0912 345 678',
      password: 'mock-fixture-password',
      role: AccountRole.consumer,
      profile: UserProfile(
        userId: 'user-consumer-01',
        email: 'person@homemind.vn',
        displayName: 'Minh Anh',
        workspaceId: 'ws-home-01',
        workspaceName: 'Tủ đồ Gia đình',
        workspaceType: 'household',
        role: 'consumer',
        phone: '0912 345 678',
        address: 'Căn hộ 802, Sunrise City, Q.7, TP.HCM',
      ),
    ),
    MockAccount(
      email: 'store@homemind.vn',
      phone: '0988 765 432',
      password: 'mock-fixture-password',
      role: AccountRole.merchant,
      profile: UserProfile(
        userId: 'user-merchant-02',
        email: 'store@homemind.vn',
        displayName: 'Cô Lan',
        workspaceId: 'ws-store-02',
        workspaceName: 'Tiệm Tạp Hóa Lan Anh',
        workspaceType: 'grocery_store',
        role: 'merchant',
        phone: '0988 765 432',
        address: '142 Nguyễn Thị Thập, Tân Quy, Q.7, TP.HCM',
      ),
    ),
  ];
}

/// Test double xác thực; production luôn khởi tạo `RemoteAuthService`.
class MockAuthService implements AuthService {
  MockAuthService({
    bool initialOnboardingCompleted = false,
    AuthSession? initialSession,
    this.delay = const Duration(milliseconds: 400),
  }) : _onboardingCompleted = initialOnboardingCompleted,
       _currentSession = initialSession;

  final Duration delay;
  bool _onboardingCompleted;
  AuthSession? _currentSession;

  @override
  Future<bool> hasCompletedOnboarding() async {
    // Giả lập đọc từ SharedPreferences hoặc secure storage
    return _onboardingCompleted;
  }

  @override
  Future<void> setOnboardingCompleted() async {
    _onboardingCompleted = true;
  }

  @override
  Future<AuthSession?> getCurrentSession() async {
    return _currentSession;
  }

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    final cleanId = identifier.trim().toLowerCase();
    final cleanPass = password.trim();

    if (cleanId.isEmpty) {
      throw const AuthException('Vui lòng nhập Email hoặc Số điện thoại.');
    }
    if (cleanPass.isEmpty) {
      throw const AuthException('Vui lòng nhập mật khẩu.');
    }

    // =========================================================================
    // TODO: THAY THẾ BẰNG GỌI API BACKEND THỰC TẾ
    // Ví dụ:
    // final response = await http.post(
    //   Uri.parse('$apiBaseUrl/api/v1/auth/login'),
    //   headers: {'Content-Type': 'application/json'},
    //   body: jsonEncode({'identifier': cleanId, 'password': cleanPass}),
    // );
    // if (response.statusCode == 200) {
    //   final json = jsonDecode(response.body);
    //   return AuthSession(token: json['token'], profile: UserProfile.fromJson(json['user']), ...);
    // }
    // =========================================================================

    // Tìm tài khoản phù hợp trong danh sách Mockup
    final matched = MockAccount.sampleAccounts.firstWhere(
      (acc) =>
          acc.email.toLowerCase() == cleanId ||
          acc.phone.replaceAll(' ', '') == cleanId.replaceAll(' ', ''),
      orElse: () => throw const AuthException(
        'Tài khoản không tồn tại trên hệ thống. Vui lòng kiểm tra lại.',
      ),
    );

    if (matched.password != cleanPass) {
      throw const AuthException(
        'Mật khẩu không chính xác. Mật khẩu mặc định là: mock-fixture-password',
      );
    }

    final session = AuthSession(
      token:
          'jwt_mock_${matched.profile.userId}_${DateTime.now().millisecondsSinceEpoch}',
      profile: matched.profile,
      loginTime: DateTime.now(),
    );

    _currentSession = session;
    _onboardingCompleted =
        true; // Đăng nhập thành công xem như đã qua onboarding
    return session;
  }

  @override
  Future<void> logout() async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    _currentSession = null;
  }

  @override
  Future<String> getAccessToken() async => _currentSession?.token ?? '';
}
