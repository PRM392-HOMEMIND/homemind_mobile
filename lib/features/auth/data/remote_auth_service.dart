import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../../assistant/domain/assistant_models.dart';
import '../domain/account_auth_service.dart';
import '../domain/auth_models.dart';
import '../domain/auth_service.dart';
import '../domain/email_otp_models.dart';

class RemoteAuthService
    implements
        AuthService,
        AccountAuthService,
        SessionRefreshService,
        SessionProfileService {
  RemoteAuthService({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();
  static const _sessionKey = 'homemind.session.v2';
  static const _onboardingKey = 'homemind.onboarding_completed';
  final http.Client _client;
  final FlutterSecureStorage _storage;
  final _changes = StreamController<AuthSession?>.broadcast();
  AuthSession? _session;
  Future<AuthSession>? _refreshing;
  Future<AuthSession?>? _restoring;
  Future<void> _storageWrites = Future<void>.value();
  int _generation = 0;
  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;
  @override
  bool publishProfile(UserProfile profile) {
    final current = _session;
    if (current == null || current.profile.userId != profile.userId) {
      return false;
    }
    _session = _withProfile(current, profile);
    _changes.add(_session);
    return true;
  }

  @override
  Future<bool> hasCompletedOnboarding() async =>
      await _storage.read(key: _onboardingKey) == 'true';
  @override
  Future<void> setOnboardingCompleted() =>
      _storage.write(key: _onboardingKey, value: 'true');

  @override
  Future<AuthSession?> getCurrentSession() async {
    final current = _session;
    if (current != null) {
      return current.needsRefresh ? _refresh(current) : current;
    }
    final restoring = _restoring;
    if (restoring != null) return restoring;
    final future = _restore();
    _restoring = future;
    try {
      return await future;
    } finally {
      _restoring = null;
    }
  }

  Future<AuthSession?> _restore() async {
    final generation = _generation;
    await _storageWrites;
    final saved = await _storage.read(key: _sessionKey);
    if (generation != _generation) return null;
    if (saved == null) return null;
    try {
      final payload = _decode(saved);
      _session = AuthSession(
        token: payload['accessToken'] as String? ?? '',
        refreshToken: payload['refreshToken'] as String? ?? '',
        expiresAt: DateTime.tryParse(payload['expiresAt'] as String? ?? ''),
        profile: _emptyProfile,
        loginTime: DateTime.now(),
      );
      if (_session!.token.isEmpty || _session!.refreshToken.isEmpty) {
        throw const AuthException('Phiên đăng nhập không hợp lệ.');
      }
      if (_session!.needsRefresh) await _refresh(_session!);
      final profile = await _fetchProfile();
      if (generation != _generation) return null;
      _session = _withProfile(_session!, profile);
      return _session;
    } catch (_) {
      if (generation == _generation) await _clear();
      return null;
    }
  }

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final result = await _request(
      'POST',
      '/auth/login',
      body: {'identifier': identifier.trim(), 'password': password},
    );
    return _accept(result);
  }

  @override
  Future<EmailChallenge> register({
    required bool acceptedTerms,
    required bool acceptedPrivacy,
    required String displayName,
    String? email,
    String? phone,
    required String password,
    required String workspaceType,
  }) async {
    final result = await _request(
      'POST',
      '/auth/register',
      body: {
        'acceptedTerms': acceptedTerms,
        'acceptedPrivacy': acceptedPrivacy,
        'displayName': displayName.trim(),
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'password': password,
        'workspaceType': workspaceType,
      },
    );
    return EmailChallenge.fromJson(result);
  }

  Future<AuthSession> _accept(Map<String, Object?> payload) async {
    final generation = ++_generation;
    final next = _fromPayload(payload, _emptyProfile);
    _session = next;
    try {
      // Only storage mutations share a queue. Independent network operations
      // remain concurrent; old writes/deletes cannot erase a newer identity.
      await _persist(next);
      if (generation != _generation) {
        throw const AuthException('Phiên đăng nhập đã thay đổi.');
      }
      final profile = await _fetchProfile();
      if (generation != _generation) {
        throw const AuthException('Phiên đăng nhập đã thay đổi.');
      }
      _session = _withProfile(next, profile);
      await setOnboardingCompleted();
      if (generation != _generation) {
        throw const AuthException('Phiên đăng nhập đã thay đổi.');
      }
      _changes.add(_session);
      return _session!;
    } catch (_) {
      if (generation == _generation) await _clear();
      rethrow;
    }
  }

  @override
  Future<String> getAccessToken() async {
    final session = await getCurrentSession();
    if (session == null) {
      throw const AuthException(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );
    }
    return session.token;
  }

  @override
  Future<String> refreshAccessToken(String rejectedToken) async {
    final current = _session;
    if (current == null) throw const AuthException('Vui lòng đăng nhập lại.');
    // A concurrent request may already have rotated this exact rejected token.
    if (current.token != rejectedToken) return current.token;
    return (await _refresh(current)).token;
  }

  Future<AuthSession> _refresh(AuthSession session) async {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final generation = _generation;
    final future = _rotate(session, generation);
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<AuthSession> _rotate(AuthSession session, int generation) async {
    try {
      final payload = await _request(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': session.refreshToken},
      );
      if (generation != _generation) {
        throw const AuthException('Phiên đăng nhập đã thay đổi.');
      }
      final next = _fromPayload(payload, session.profile);
      _session = next;
      await _persist(next);
      return next;
    } catch (_) {
      if (generation == _generation) await _clear();
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    final generation = _generation;
    final refreshing = _refreshing;
    if (refreshing != null) {
      try {
        await refreshing;
      } catch (_) {}
    }
    if (generation != _generation) return;
    final token = _session?.refreshToken;
    await _clear();
    try {
      if (token != null) {
        await _request('POST', '/auth/logout', body: {'refreshToken': token});
      }
    } catch (_) {
      /* Local logout remains available while the server is unreachable. */
    }
  }

  @override
  Future<void> logoutAll() async {
    await _request('POST', '/auth/logout-all', authenticated: true);
    await _clear();
  }

  @override
  Future<EmailChallenge> forgotPassword(String identifier) async {
    final result = await _request(
      'POST',
      '/auth/password/forgot',
      body: {'identifier': identifier.trim()},
    );
    return EmailChallenge.fromJson(result);
  }

  @override
  Future<void> resetPassword(String token, String newPassword) async {
    await _request(
      'POST',
      '/auth/password/reset',
      body: {'token': token, 'newPassword': newPassword},
    );
    await _clear();
  }

  @override
  Future<PasswordChangeResult> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final payload = await _request(
      'POST',
      '/auth/password/change',
      authenticated: true,
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    if (payload['ok'] == true && payload['reauthenticationRequired'] == true) {
      await _clear();
      return const PasswordChanged();
    }
    return EmailChallenge.fromJson(payload);
  }

  @override
  Future<EmailChallenge> challengeStatus(EmailChallenge challenge) async =>
      EmailChallenge.fromJson(
        await _request('POST', '/auth/email/status', body: challenge.proof),
        token: challenge.token,
      );
  @override
  Future<EmailChallenge> resendChallenge(EmailChallenge challenge) async {
    await _request('POST', '/auth/email/resend', body: challenge.proof);
    return challengeStatus(challenge);
  }

  @override
  Future<EmailVerification> verifyChallenge(
    EmailChallenge challenge,
    String code,
  ) async {
    final authenticated = [
      'CHANGE_PASSWORD',
      'CHANGE_EMAIL_OLD',
      'CHANGE_EMAIL_NEW',
    ].contains(challenge.purpose);
    final payload = await _request(
      'POST',
      authenticated ? '/auth/email/verify-authenticated' : '/auth/email/verify',
      authenticated: authenticated,
      body: {...challenge.proof, 'purpose': challenge.purpose, 'code': code},
    );
    if (payload['accessToken'] is String) {
      return EmailVerification(session: await _accept(payload));
    }
    if (payload['reauthenticationRequired'] == true) await _clear();
    return EmailVerification(
      ticket: payload['ticket'] as String?,
      ticketExpiresAt: DateTime.tryParse(
        payload['ticketExpiresAt'] as String? ?? '',
      ),
      reauthenticationRequired: payload['reauthenticationRequired'] == true,
    );
  }

  @override
  Future<void> resetWithProof(
    EmailChallenge challenge,
    EmailVerification proof,
    String password,
  ) async {
    if (proof.ticket == null ||
        proof.ticketExpiresAt == null ||
        !proof.ticketExpiresAt!.isAfter(DateTime.now())) {
      throw const AuthException(
        'Quyền đặt lại mật khẩu đã hết hạn. Vui lòng xác minh lại.',
      );
    }
    await _request(
      'POST',
      '/auth/password/reset-ticket',
      body: {
        ...challenge.proof,
        'ticket': proof.ticket,
        'newPassword': password,
      },
    );
    await _clear();
  }

  @override
  Future<EmailChallenge> startEmailChange(String currentPassword) async =>
      EmailChallenge.fromJson(
        await _request(
          'POST',
          '/auth/email/change',
          authenticated: true,
          body: {'currentPassword': currentPassword},
        ),
      );
  @override
  Future<EmailChallenge> startNewEmail(
    EmailChallenge old,
    EmailVerification proof,
    String email,
  ) async => EmailChallenge.fromJson(
    await _request(
      'POST',
      '/auth/email/change-new',
      authenticated: true,
      body: {...old.proof, 'ticket': proof.ticket, 'email': email.trim()},
    ),
  );
  @override
  Future<EmailChallenge> addLegacyEmail(
    LegacyEmailRequired proof,
    String email,
  ) async => EmailChallenge.fromJson(
    await _request(
      'POST',
      '/auth/email/legacy',
      body: {
        'legacyId': proof.id,
        'legacyProof': proof.proof,
        'email': email.trim(),
      },
    ),
  );

  @override
  Future<UserProfile> changeIdentifiers({
    required String currentPassword,
    required String? email,
    required String? phone,
  }) async {
    await _request(
      'PATCH',
      '/auth/account/identifiers',
      authenticated: true,
      body: {
        'currentPassword': currentPassword,
        'newEmail': email,
        'newPhone': phone,
      },
    );
    final profile = await _fetchProfile();
    _session = _withProfile(_session!, profile);
    _changes.add(_session);
    return profile;
  }

  @override
  Future<void> closeAccount(
    String currentPassword, {
    required bool delete,
  }) async {
    await _request(
      delete ? 'DELETE' : 'POST',
      delete ? '/auth/account' : '/auth/account/deactivate',
      authenticated: true,
      body: {'currentPassword': currentPassword},
    );
    await _clear();
  }

  Future<UserProfile> _fetchProfile() async =>
      UserProfile.fromJson(await _request('GET', '/me', authenticated: true));
  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = false,
  }) async {
    final generation = _generation;
    String? token;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final requestId =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    if (authenticated) {
      final current = _session;
      if (current == null) throw const AuthException('Vui lòng đăng nhập lại.');
      token = current.needsRefresh
          ? (await _refresh(current)).token
          : current.token;
    }
    Future<http.Response> send(String? access) {
      if (generation != _generation) {
        throw const AuthException('Phiên đăng nhập đã thay đổi.');
      }
      final headers = {
        'Accept': 'application/json',
        'Idempotency-Key': requestId,
        if (path == '/auth/password/change') 'X-HomeMind-Auth-Contract': '2',
        if (body != null) 'Content-Type': 'application/json',
        if (access != null) 'Authorization': 'Bearer $access',
      };
      final uri = Uri.parse('${EnvConfig.backendBaseUrl}$path');
      return switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
        'PATCH' => _client.patch(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => _client.delete(
          uri,
          headers: headers,
          body: jsonEncode(body),
        ),
        _ => throw ArgumentError('HTTP method'),
      };
    }

    try {
      var response = await send(token).timeout(const Duration(seconds: 25));
      if (generation != _generation) {
        throw const AuthException('Phiên đăng nhập đã thay đổi.');
      }
      final firstError = _decode(response.body)['error'];
      if (authenticated &&
          response.statusCode == 401 &&
          !(firstError is Map &&
              firstError['code'] == 'CURRENT_PASSWORD_INVALID')) {
        token = await refreshAccessToken(token!);
        response = await send(token).timeout(const Duration(seconds: 25));
        if (generation != _generation) {
          throw const AuthException('Phiên đăng nhập đã thay đổi.');
        }
        if (response.statusCode == 401) await _clear();
      }
      final payload = _decode(response.body);
      if (generation != _generation) {
        throw const AuthException('Phiên đăng nhập đã thay đổi.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = payload['error'];
        if (error is Map && error['details'] is Map) {
          final details = Map<String, Object?>.from(error['details'] as Map);
          if (error['code'] == 'EMAIL_VERIFICATION_REQUIRED') {
            throw EmailVerificationRequired(EmailChallenge.fromJson(details));
          }
          if (error['code'] == 'EMAIL_REQUIRED') {
            throw LegacyEmailRequired(
              details['legacyId'] as String,
              details['legacyProof'] as String,
            );
          }
        }
        throw AuthException(
          error is Map && error['message'] is String
              ? error['message'] as String
              : 'Yêu cầu không thành công. Vui lòng thử lại.',
        );
      }
      return payload;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Không kết nối được HomeMind. Vui lòng thử lại.',
      );
    }
  }

  AuthSession _fromPayload(Map<String, Object?> payload, UserProfile profile) {
    final token = payload['accessToken'] as String? ?? '';
    final refresh = payload['refreshToken'] as String? ?? '';
    if (token.isEmpty || refresh.isEmpty) {
      throw const AuthException('Máy chủ trả về phiên không hợp lệ.');
    }
    return AuthSession(
      token: token,
      refreshToken: refresh,
      expiresAt: DateTime.now().add(
        Duration(seconds: (payload['expiresIn'] as num?)?.toInt() ?? 900),
      ),
      profile: profile,
      loginTime: DateTime.now(),
    );
  }

  AuthSession _withProfile(AuthSession session, UserProfile profile) =>
      AuthSession(
        token: session.token,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
        profile: profile,
        loginTime: session.loginTime,
      );
  Future<void> _writeStorage(Future<void> Function() action) {
    final next = _storageWrites.then((_) => action());
    _storageWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _persist(AuthSession session) => _writeStorage(
    () => _storage.write(
      key: _sessionKey,
      value: jsonEncode({
        'accessToken': session.token,
        'refreshToken': session.refreshToken,
        'expiresAt': session.expiresAt?.toUtc().toIso8601String(),
      }),
    ),
  );
  Future<void> _clear() async {
    final profile = _session?.profile;
    final generation = ++_generation;
    _session = null;
    await _writeStorage(() => _storage.delete(key: _sessionKey));
    // An incomplete restore has no verified owner. It cannot authorize deleting
    // durable intents belonging to accounts that previously used this device.
    if (profile != null &&
        profile.userId.isNotEmpty &&
        profile.workspaceId.isNotEmpty) {
      await _storage.delete(
        key:
            'homemind.billing.pending.${profile.userId}.${profile.workspaceId}',
      );
    }
    // Remove credentials written by the previous identity provider during migration.
    for (final key in [
      'homemind.access_token',
      'homemind.refresh_token',
      'homemind.expires_at',
    ]) {
      await _storage.delete(key: key);
    }
    if (generation == _generation) _changes.add(null);
  }

  Map<String, Object?> _decode(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    throw const AuthException('Máy chủ trả về dữ liệu không hợp lệ.');
  }

  static const _emptyProfile = UserProfile(
    userId: '',
    email: '',
    displayName: '',
    workspaceId: '',
    workspaceName: '',
    workspaceType: 'household',
    role: 'member',
  );
}

// Handled by Tran Gia Phu
