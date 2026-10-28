import 'dart:async';

import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';

import 'fake_assistant_service.dart';

/// Test double ghi lại các lần gọi `updateProfile` (không đọc file mock) và
/// có thể giả lập lỗi để kiểm tra đường lỗi của màn Hồ sơ.
class RecordingProfileService extends FakeAssistantService {
  RecordingProfileService(this.profile) : super(delay: Duration.zero);

  UserProfile profile;
  bool shouldFail = false;
  Completer<void>? saveGate;
  final List<Map<String, String?>> calls = [];

  @override
  Future<UserProfile> getMe() async => profile;

  @override
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  }) async {
    calls.add({
      'displayName': displayName,
      'phone': phone,
      'address': address,
      'language': language,
    });
    await saveGate?.future;
    if (shouldFail) {
      throw Exception('SocketException: raw failure that must not be shown');
    }
    profile = profile.copyWith(
      displayName: displayName,
      phone: phone,
      address: address,
      language: language,
    );
    return profile;
  }
}
