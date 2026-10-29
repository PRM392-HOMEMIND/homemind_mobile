import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';

class LegalConsent extends StatelessWidget {
  const LegalConsent({
    required this.accepted,
    required this.enabled,
    required this.onChanged,
    required this.onOpenError,
    this.openUrl,
    super.key,
  });
  static final terms = Uri.parse('https://homemind.vn/terms-of-service');
  static final privacy = Uri.parse('https://homemind.vn/privacy-policy');
  final bool accepted, enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenError;
  final Future<bool> Function(Uri)? openUrl;

  Future<void> _open(Uri uri) async {
    try {
      if (!await (openUrl?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication))) {
        onOpenError();
      }
    } catch (_) {
      onOpenError();
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Checkbox(
        key: const ValueKey('register_legal_acceptance'),
        value: accepted,
        semanticLabel: tr('Đồng ý Điều khoản sử dụng và Chính sách bảo mật'),
        onChanged: enabled ? (value) => onChanged(value == true) : null,
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('Tôi đã đọc và đồng ý với')),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _link(tr('Điều khoản sử dụng'), terms, 'register_terms_link'),
                Text(tr('và')),
                _link(
                  tr('Chính sách bảo mật'),
                  privacy,
                  'register_privacy_link',
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _link(String label, Uri uri, String id) => Semantics(
    link: true,
    child: TextButton(
      key: ValueKey(id),
      onPressed: () => _open(uri),
      style: TextButton.styleFrom(
        foregroundColor: HomeMindTheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      child: Text(
        label,
        style: const TextStyle(decoration: TextDecoration.underline),
      ),
    ),
  );
}
