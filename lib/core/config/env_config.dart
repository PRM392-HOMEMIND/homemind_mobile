import 'package:flutter/foundation.dart';

class EnvConfig {
  static const distribution = String.fromEnvironment(
    'APP_DISTRIBUTION',
    defaultValue: 'store',
  );
  static bool get externalBillingAllowed =>
      externalBillingAllowedFor(debug: kDebugMode, distribution: distribution);
  static bool externalBillingAllowedFor({
    required bool debug,
    String distribution = 'store',
  }) => false; // Temporary owner policy: no mobile channel may purchase.
  static const _definedBackendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
  );
  static String backendBaseUrl = '';
  static Future<void> load() async {
    if (!['store', 'direct'].contains(distribution)) {
      throw StateError('APP_DISTRIBUTION không hợp lệ.');
    }
    backendBaseUrl = _definedBackendBaseUrl.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    final uri = Uri.tryParse(backendBaseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        'Cần BACKEND_BASE_URL công khai hợp lệ qua --dart-define.',
      );
    }
    if (!kDebugMode && uri.scheme != 'https') {
      throw StateError('Bản phát hành yêu cầu BACKEND_BASE_URL HTTPS.');
    }
  }
}
