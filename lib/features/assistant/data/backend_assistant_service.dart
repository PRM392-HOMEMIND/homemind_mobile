import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/env_config.dart';
import '../../auth/domain/auth_service.dart';
import '../../auth/domain/account_auth_service.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';
import '../../billing/billing_service.dart';
import '../../home/domain/home_hub_gateway.dart';
import '../../family/family_gateway.dart';
import 'workspace_pages.dart';

class BackendAssistantService
    implements
        AssistantService,
        BootstrapSource,
        BillingSource,
        HomeHubSource,
        SpendingSource,
        FamilySource,
        WorkspacePagesSource,
        VoiceQuotaSource {
  BackendAssistantService({
    required this.authService,
    required UserProfile profile,
    http.Client? client,
    FlutterSecureStorage? intentStorage,
  }) : _profile = profile,
       _currentRole = profile.accountRole,
       _scopeUser = profile.userId,
       _scopeWorkspace = profile.workspaceId,
       _client = client ?? http.Client(),
       _intentStorage = intentStorage ?? const FlutterSecureStorage();

  final AuthService authService;
  final http.Client _client;
  final FlutterSecureStorage _intentStorage;
  final String _scopeUser, _scopeWorkspace;
  final Map<String, Future<AssistantTurn>> _turnsInFlight = {};
  Future<void> _intentTail = Future<void>.value();
  String get _turnKey =>
      'homemind.assistant.intent.${_profile.userId}.$_workspaceId';
  UserProfile _profile;
  AccountRole _currentRole;

  String get _workspaceId => _scopeWorkspace;
  @override
  late final WorkspacePages workspacePages = WorkspacePages(
    workspaceId: _scopeWorkspace,
    request: (method, path) => _request(method, path),
  );
  @override
  late final FamilyGateway family = FamilyGateway(
    workspaceId: _scopeWorkspace,
    userId: _scopeUser,
    newKey: _uuid,
    refreshContext: () async {
      await getMe();
    },
    request: (method, path, {body, idempotencyKey}) =>
        _request(method, path, body: body, idempotencyKey: idempotencyKey),
  );
  @override
  late final HomeHubGateway homeHub = HomeHubGateway(
    write: (path, body) => _request('POST', path, body: body),
    workspaceId: _workspaceId,
    scope: '${_profile.userId}.$_workspaceId',
    request: (method, path) =>
        _request(method, path, expectedUserId: _profile.userId),
  );
  late final RemoteBillingService _billing = RemoteBillingService(
    userId: _profile.userId,
    workspaceId: _workspaceId,
    isCurrentIdentity: () async =>
        (await authService.getCurrentSession())?.profile.userId == _scopeUser &&
        (await authService.getCurrentSession())?.profile.workspaceId ==
            _scopeWorkspace,
    request: (method, path, {body, idempotencyKey}) => _request(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
      expectedUserId: _profile.userId,
    ),
  );
  @override
  BillingGateway get billing => _billing;
  @override
  Future<void> refreshBillingEntitlements() async {
    await getMe();
  }

  @override
  Future<VoiceQuota> getVoiceQuota() async {
    final quota = (await getMe()).voiceQuota;
    if (quota == null) {
      throw const FormatException('Missing authoritative voice quota');
    }
    return quota;
  }

  @override
  Listenable get dataChanges => const _NeverChanges();

  @override
  Stream<String> get backgroundErrors => const Stream<String>.empty();

  @override
  Future<Bootstrap> getBootstrap() async {
    final payload = await _request(
      'GET',
      '/workspaces/$_workspaceId/bootstrap',
    );
    return Bootstrap.fromJson(payload);
  }

  @override
  AccountRole get currentRole => _currentRole;

  @override
  void switchRole(AccountRole role) {
    // The real role belongs to the authenticated workspace and cannot be
    // switched client-side. Keeping this method preserves the UI contract.
    _currentRole = _profile.accountRole;
  }

  @override
  Future<UserProfile> getMe() async {
    final payload = await _request(
      'GET',
      '/me',
      expectedUserId: _profile.userId,
    );
    _acceptProfile(UserProfile.fromJson(payload));
    _currentRole = _profile.accountRole;
    return _profile;
  }

  @override
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  }) async {
    final payload = await _request(
      'PATCH',
      '/me',
      body: {
        if (displayName != null) 'displayName': displayName,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (language != null) 'language': language,
      },
      expectedUserId: _profile.userId,
    );
    _acceptProfile(UserProfile.fromJson(payload));
    return _profile;
  }

  void _acceptProfile(UserProfile profile) {
    if (profile.userId != _profile.userId) {
      throw const HomeMindApiException('Tài khoản đã thay đổi.');
    }
    final auth = authService;
    if (auth is SessionProfileService &&
        !(auth as SessionProfileService).publishProfile(profile)) {
      throw const HomeMindApiException('Tài khoản đã thay đổi.');
    }
    _profile = profile;
    _currentRole = profile.accountRole;
  }

  @override
  Future<HomeSummary> getHomeSummary() async {
    final payload = await _request('GET', '/workspaces/$_workspaceId/home');
    return HomeSummary.fromJson(payload);
  }

  @override
  Future<({List<AppNotification> items, int unreadCount})>
  getNotifications() async {
    final payload = await _request(
      'GET',
      '/workspaces/$_workspaceId/notifications',
    );
    final items = _list(payload['items'])
        .whereType<Map>()
        .map((item) => AppNotification.fromJson(_asMap(item)))
        .toList(growable: false);
    return (
      items: items,
      unreadCount: (payload['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> markNotificationRead(String notificationId) => _request(
    'PATCH',
    '/workspaces/$_workspaceId/notifications/${Uri.encodeComponent(notificationId)}/read',
  );

  @override
  Future<void> markAllNotificationsRead() =>
      _request('POST', '/workspaces/$_workspaceId/notifications/read-all');

  @override
  Future<List<InventoryItem>> getInventory() async {
    final payload = await _request(
      'GET',
      '/workspaces/$_workspaceId/inventory?limit=100',
    );
    return _list(payload['items'])
        .whereType<Map>()
        .map((item) => InventoryItem.fromJson(_asMap(item)))
        .toList(growable: false);
  }

  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async {
    final responses = await Future.wait([
      _request(
        'GET',
        '/workspaces/$_workspaceId/shopping-items?status=needed&includeSuggestions=true',
      ),
      _request('GET', '/workspaces/$_workspaceId/shopping-items?status=bought'),
      _request(
        'GET',
        '/workspaces/$_workspaceId/shopping-items?status=skipped',
      ),
    ]);
    final items = <ShoppingItem>[];
    for (final response in responses) {
      items.addAll(
        _list(response['items'])
            .whereType<Map>()
            .map((item) => ShoppingItem.fromJson(_asMap(item))),
      );
    }
    final suggestions = _list(responses.first['suggestions'])
        .whereType<Map>()
        .map(_asMap)
        .toList(growable: false);
    return (items: items, suggestions: suggestions);
  }

  @override
  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  }) async {
    await _request(
      'POST',
      '/workspaces/$_workspaceId/inventory/$productId/mark-out',
      body: {'quantity': quantity, 'addToShoppingList': addToShoppingList},
      idempotencyKey: _uuid(),
    );
  }

  @override
  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  }) async {
    await _request(
      'POST',
      '/workspaces/$_workspaceId/shopping-items',
      body: {'name': name, 'quantity': quantity, 'unit': unit},
      idempotencyKey: _uuid(),
    );
  }

  @override
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  }) async {
    await _request(
      'POST',
      '/workspaces/$_workspaceId/shopping-items/$itemId/receive',
      body: {
        if (quantity != null) 'quantity': quantity,
        if (unit != null) 'unit': unit,
        if (expiryDate != null) 'expiryDate': expiryDate,
        if (priceVnd != null) 'priceVnd': priceVnd,
        if (storageLocation != null) 'storageLocation': storageLocation,
      },
      idempotencyKey: _uuid(),
    );
  }

  @override
  bool get spendingAvailable => true;

  @override
  Future<SpendingSummary> getSpending({String? month}) async {
    final query = month == null
        ? ''
        : '?month=${Uri.encodeQueryComponent(month)}';
    final payload = await _request(
      'GET',
      '/workspaces/$_workspaceId/spending$query',
    );
    return SpendingSummary.fromJson(payload);
  }

  @override
  Future<void> updateLot({
    required String lotId,
    int? priceVnd,
    String? storageLocation,
  }) async {
    await _request(
      'PATCH',
      '/workspaces/$_workspaceId/lots/${Uri.encodeComponent(lotId)}',
      body: {if (priceVnd != null) 'priceVnd': priceVnd, if (storageLocation != null) 'storageLocation': storageLocation},
    );
  }

  @override
  Future<void> updateShoppingItem({
    required String itemId,
    required String status,
  }) async {
    await _request(
      'PATCH',
      '/workspaces/$_workspaceId/shopping-items/$itemId',
      body: {'status': status},
      idempotencyKey: _uuid(),
    );
  }

  @override
  Future<void> requestUpgrade({
    required String plan,
    required String source,
  }) async {
    if (!EnvConfig.externalBillingAllowed) {
      throw StateError('BILLING_DISTRIBUTION_DISABLED');
    }
    await _request(
      'POST',
      '/workspaces/$_workspaceId/upgrade-requests',
      body: {'plan': plan, 'source': source},
    );
  }

  @override
  Future<AssistantTurn> turn({
    required String text,
    String inputType = 'voice_transcript',
  }) async {
    final signature = jsonEncode([text.trim(), inputType]);
    final existing = _turnsInFlight[signature];
    if (existing != null) {
      return existing;
    }
    if (_turnsInFlight.length >= 4) {
      throw const HomeMindApiException(
        'Đang xử lý tối đa 4 yêu cầu. Vui lòng chờ một yêu cầu hoàn tất.',
        code: 'AI_CAPACITY_BUSY',
      );
    }
    final future = _sendTurn(text.trim(), inputType);
    _turnsInFlight[signature] = future;
    try {
      return await future;
    } finally {
      _turnsInFlight.remove(signature);
    }
  }

  Future<AssistantTurn> _sendTurn(String text, String inputType) async {
    final now = DateTime.now();
    final clientDate =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    Map<String, Object?> intent = {
      'requestId': _uuid(),
      'workspaceId': _workspaceId,
      'locale': 'vi-VN',
      'clientDate': clientDate,
      'timezone': 'Asia/Ho_Chi_Minh',
      'dictionaryVersion': '1.1.0',
      'input': {'type': inputType, 'text': text},
    };
    // Serialize only secure-storage allocation, never the HTTP/provider lifecycle.
    // Four durable slots retain ambiguous outcomes without overwriting another turn.
    String? intentKey;
    final allocation = _intentTail.then((_) async {
      String? emptyKey;
      for (var slot = 0; slot < 4; slot++) {
        final key = slot == 0 ? _turnKey : '$_turnKey.$slot';
        final saved = await _intentStorage.read(key: key);
        if (saved == null) {
          emptyKey ??= key;
          continue;
        }
        final previous = Map<String, Object?>.from(jsonDecode(saved) as Map);
        if (previous['workspaceId'] == _workspaceId &&
            previous['input'] is Map &&
            (previous['input'] as Map)['text'] == text &&
            (previous['input'] as Map)['type'] == inputType) {
          intent = previous;
          intentKey = key;
          break;
        }
      }
      intentKey ??= emptyKey;
      if (intentKey == null) {
        throw const HomeMindApiException(
          'Cần thử lại yêu cầu chưa rõ kết quả trước khi gửi thêm.',
          code: 'ASSISTANT_PENDING_INTENTS',
        );
      }
      await _intentStorage.write(key: intentKey!, value: jsonEncode(intent));
    });
    _intentTail = allocation.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    await allocation;
    late Map<String, Object?> payload;
    try {
      payload = await _request(
        'POST',
        '/assistant/turn',
        body: intent,
        expectedUserId: _profile.userId,
      );
    } on HomeMindApiException catch (error) {
      final rejectedQuota = error.voiceQuota;
      if (rejectedQuota != null) {
        _acceptQuota(rejectedQuota);
      }
      // These authoritative rejections cannot have committed a logical turn.
      // An unknown outcome, provider failure or in-progress lease keeps its ID.
      if (error.statusCode == 400 ||
          error.statusCode == 422 ||
          error.code == 'VOICE_QUOTA_EXHAUSTED' ||
          error.code == 'ASSISTANT_REQUEST_EXPIRED') {
        await _intentStorage.delete(key: intentKey!);
      }
      rethrow;
    }
    final turn = AssistantTurn.fromJson(payload);
    if (turn.voiceQuota != null) {
      _acceptQuota(turn.voiceQuota!);
    }
    await _intentStorage.delete(key: intentKey!);
    return turn;
  }

  @override
  Future<AssistantTurn> confirm({
    required String turnId,
    required List<ToolCall> tools,
  }) async {
    final payload = await _request(
      'POST',
      '/assistant/turns/$turnId/confirm',
      body: {
        'workspaceId': _workspaceId,
        'idempotencyKey': _uuid(),
        'tools': tools
            .map((tool) => {'toolId': tool.toolId, 'arguments': tool.arguments})
            .toList(growable: false),
      },
    );
    return AssistantTurn.fromJson(payload);
  }

  @override
  Future<AssistantTurn> cancel({required String turnId}) async {
    final payload = await _request('POST', '/assistant/turns/$turnId/cancel');
    return AssistantTurn.fromJson(payload);
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
    String? expectedUserId,
  }) async {
    expectedUserId ??= _scopeUser;
    final contextRead = path == '/me' || path == '/me/workspace-context';
    Future<void> checkScope() async {
      final session = await authService.getCurrentSession();
      if (session?.profile.userId != _scopeUser ||
          (!contextRead && session?.profile.workspaceId != _scopeWorkspace)) {
        throw const HomeMindApiException(
          'Không gian làm việc đã thay đổi. Vui lòng mở lại trang.',
          code: 'WORKSPACE_CHANGED',
        );
      }
    }

    await checkScope();
    final elapsed = clock.stopwatch()..start();
    Future<T> withinBudget<T>(Future<T> Function() operation) {
      final remaining = const Duration(seconds: 25) - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('HomeMind request budget exhausted');
      }
      return operation().timeout(remaining);
    }

    if ((await withinBudget(authService.getCurrentSession))?.profile.userId !=
        expectedUserId) {
      throw const HomeMindApiException('Tài khoản đã thay đổi.');
    }
    final token = await withinBudget(authService.getAccessToken);
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      if (path.contains('/billing') || path.endsWith('/upgrade-requests'))
        'X-HomeMind-Distribution': EnvConfig.distribution,
    };
    final uri = Uri.parse('${EnvConfig.backendBaseUrl}$path');
    late http.Response response;
    try {
      Future<http.Response> send() => switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
        'PATCH' => _client.patch(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw ArgumentError('HTTP method không hỗ trợ: $method'),
      };
      bool readReplayUsed = false;
      Future<http.Response> boundedSend() async {
        await checkScope();
        try {
          return await withinBudget(send);
        } on http.ClientException catch (error) {
          // A peer can close an idle connection before response headers.
          // Only replay a read, once, within the original request budget.
          if (readReplayUsed ||
              method != 'GET' ||
              !error.message.contains('Connection closed before full header')) {
            rethrow;
          }
          if ((await withinBudget(authService.getCurrentSession))
                  ?.profile
                  .userId !=
              expectedUserId) {
            throw const HomeMindApiException('Tài khoản đã thay đổi.');
          }
          readReplayUsed = true;
          return withinBudget(send);
        }
      }

      response = await boundedSend();
      final auth = authService;
      if (response.statusCode == 401 && auth is SessionRefreshService) {
        if ((await withinBudget(authService.getCurrentSession))
                ?.profile
                .userId !=
            expectedUserId) {
          throw const HomeMindApiException('Tài khoản đã thay đổi.');
        }
        final refreshed = await withinBudget(
          () => (auth as SessionRefreshService).refreshAccessToken(token),
        );
        if ((await withinBudget(authService.getCurrentSession))
                ?.profile
                .userId !=
            expectedUserId) {
          throw const HomeMindApiException('Tài khoản đã thay đổi.');
        }
        headers['Authorization'] = 'Bearer $refreshed';
        response = await boundedSend();
        if (response.statusCode == 401) await authService.logout();
      }
    } on Exception catch (error) {
      throw HomeMindApiException(
        'Không thể kết nối HomeMind API (${EnvConfig.backendBaseUrl}): $error',
      );
    }

    if ((await withinBudget(authService.getCurrentSession))?.profile.userId !=
        expectedUserId) {
      throw const HomeMindApiException('Tài khoản đã thay đổi.');
    }

    await checkScope();
    final payload = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = payload['error'];
      if (response.statusCode == 403 &&
          path.startsWith('/workspaces/') &&
          error is Map &&
          error['code'] == 'FORBIDDEN') {
        // A failed context refresh must not leave an unauthorized Family session
        // displaying cached data. Re-authentication can recover the current scope.
        try {
          await getMe();
        } catch (_) {
          await authService.logout();
        }
      }
      final message = error is Map && error['message'] is String
          ? error['message'] as String
          : 'HomeMind API trả lỗi HTTP ${response.statusCode}.';
      throw HomeMindApiException(
        message,
        statusCode: response.statusCode,
        code: error is Map && error['code'] is String
            ? error['code'] as String
            : null,
        details: error is Map && error['details'] is Map
            ? _asMap(error['details'])
            : null,
      );
    }
    return payload;
  }

  void _acceptQuota(VoiceQuota quota) {
    final old = _profile.voiceQuota;
    if (old == null || !quota.serverNow.isBefore(old.serverNow)) {
      _acceptProfile(_profile.copyWith(voiceQuota: quota));
    }
  }

  Map<String, Object?> _decodeObject(String body) {
    if (body.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return _asMap(decoded);
    } catch (_) {}
    throw const HomeMindApiException('HomeMind API trả dữ liệu không hợp lệ.');
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

class _NeverChanges implements Listenable {
  const _NeverChanges();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class HomeMindApiException implements Exception {
  const HomeMindApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.details,
  });

  final String message;
  final int? statusCode;

  /// Mã lỗi của backend (error.code), ví dụ PLAN_LIMIT.
  final String? code;

  /// error.details (ví dụ {plan, limit, count} khi PLAN_LIMIT).
  final Map<String, Object?>? details;

  /// Only a validated quota from an authenticated exhaustion response is usable.
  VoiceQuota? get voiceQuota {
    if (statusCode != 429 ||
        code != 'VOICE_QUOTA_EXHAUSTED' ||
        details == null) {
      return null;
    }
    try {
      return VoiceQuota.fromJson(details!);
    } catch (_) {
      return null;
    }
  }

  /// Backend từ chối vì gói đã đủ số sản phẩm (HTTP 402).
  bool get isPlanLimit => code == 'PLAN_LIMIT';

  @override
  String toString() => message;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}
