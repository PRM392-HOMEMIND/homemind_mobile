import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config/env_config.dart';
import 'billing_distribution.dart';

typedef BillingRequest = Future<Map<String, Object?>> Function(
  String method,
  String path, {
  Map<String, Object?>? body,
  String? idempotencyKey,
});

abstract interface class BillingSource {
  BillingGateway? get billing;
  Future<void> refreshBillingEntitlements();
}

abstract interface class BillingGateway {
  Future<Map<String, Object?>> plans();
  Future<Map<String, Object?>> overview({int offset = 0});
  Future<Map<String, Object?>> create(String priceId);
  Future<Map<String, Object?>?> pending();
  Future<Map<String, Object?>> reconcile(String id);
  Future<Map<String, Object?>> cancel(String id);
  Future<void> clearPending();
}

String billingUuid() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Uri billingCheckoutUri(String value) {
  if (!EnvConfig.externalBillingAllowed) {
    throw StateError('BILLING_DISTRIBUTION_DISABLED');
  }
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' ||
      uri.host != 'pay.payos.vn' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.hasPort) {
    throw StateError('Địa chỉ thanh toán không hợp lệ.');
  }
  return uri;
}

class RemoteBillingService implements BillingGateway {
  RemoteBillingService({
    required this.request,
    required String userId,
    required String workspaceId,
    FlutterSecureStorage? storage,
    this.isCurrentIdentity,
    this.externalBillingAllowed,
  }) : _path = '/workspaces/$workspaceId/billing',
       _key = 'homemind.billing.pending.$userId.$workspaceId',
       _storage = storage ?? const FlutterSecureStorage();
  final BillingRequest request;
  final Future<bool> Function()? isCurrentIdentity;
  final bool Function()? externalBillingAllowed;
  bool get _checkoutAllowed =>
      EnvConfig.externalBillingAllowed &&
      (externalBillingAllowed?.call() ?? true);
  final String _path, _key;
  final FlutterSecureStorage _storage;
  Future<Map<String, Object?>>? _creating;
  String? _creatingPriceId;
  @override
  Future<Map<String, Object?>> plans() async {
    final catalog = await request('GET', '/billing/plans');
    return {
      ...catalog,
      'checkoutEnabled': _checkoutAllowed && catalog['checkoutEnabled'] == true,
    };
  }

  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async =>
      billingOverviewForDistribution(
        await request('GET', '$_path/payments?offset=$offset'),
      );
  @override
  Future<Map<String, Object?>> create(String priceId) async {
    final inFlight = _creating;
    if (inFlight != null) {
      if (_creatingPriceId != priceId) {
        throw StateError('PAYMENT_ALREADY_PENDING');
      }
      return inFlight;
    }
    _creatingPriceId = priceId;
    final future = _create(priceId);
    _creating = future;
    try {
      return await future;
    } finally {
      _creating = null;
      _creatingPriceId = null;
    }
  }

  Future<Map<String, Object?>> _create(String priceId) async {
    if (!_checkoutAllowed) throw StateError('BILLING_DISTRIBUTION_DISABLED');
    await _checkIdentity();
    final previous = await _saved();
    if (previous != null && previous['priceId'] != priceId) {
      throw StateError(
        'Kiểm tra hoặc hủy đơn đang chờ trước khi chọn gói khác.',
      );
    }
    final saved = previous ?? {'priceId': priceId, 'key': billingUuid()};
    // Persist BEFORE POST. A network failure/restart retries the same intent.
    await _storage.write(key: _key, value: jsonEncode(saved));
    await _checkIdentity();
    final payment = await request(
      'POST',
      '$_path/payments',
      body: {'priceId': priceId, 'transition': 'immediate_upgrade'},
      idempotencyKey: saved['key'] as String,
    );
    await _checkIdentity();
    await _storage.write(
      key: _key,
      value: jsonEncode({...saved, 'id': payment['id']}),
    );
    await _checkIdentity();
    return payment;
  }

  Future<void> _checkIdentity() async {
    if (isCurrentIdentity != null && !await isCurrentIdentity!()) {
      await clearPending();
      throw StateError('Tài khoản đã thay đổi.');
    }
  }

  Future<Map<String, Object?>?> _saved() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      final saved = Map<String, Object?>.from(jsonDecode(value) as Map);
      final price = saved['priceId'], key = saved['key'], id = saved['id'];
      final uuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      if (price is! String ||
          price.length > 100 ||
          !RegExp(r'^(personal|family|micro_pos)-month-v\d+$')
              .hasMatch(price) ||
          key is! String ||
          !uuid.hasMatch(key) ||
          (saved.containsKey('id') && (id is! String || !uuid.hasMatch(id)))) {
        throw const FormatException('Invalid pending billing intent');
      }
      return saved;
    } catch (_) {
      await clearPending();
      return null;
    }
  }

  @override
  Future<Map<String, Object?>?> pending() async {
    await _checkIdentity();
    if (!_checkoutAllowed) {
      // Read-only billing must not revive a cached purchase intent.
      await clearPending();
      return null;
    }
    final saved = await _saved();
    if (saved == null) return null;
    final id = saved['id'];
    if (id is String) {
      final result = await request('GET', '$_path/payments/$id');
      await _checkIdentity();
      return billingPaymentForDistribution(result);
    }
    // Preserve the durable intent. Only an explicit recovery action may POST.
    return {'unresolvedIntent': true, 'priceId': saved['priceId']};
  }

  @override
  Future<Map<String, Object?>> reconcile(String id) {
    if (!_checkoutAllowed) throw StateError('BILLING_DISTRIBUTION_DISABLED');
    return request('POST', '$_path/payments/$id/reconcile');
  }

  @override
  Future<Map<String, Object?>> cancel(String id) {
    if (!_checkoutAllowed) throw StateError('BILLING_DISTRIBUTION_DISABLED');
    return request('POST', '$_path/payments/$id/cancel');
  }

  @override
  Future<void> clearPending() => _storage.delete(key: _key);
}
