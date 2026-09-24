import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../domain/account_auth_service.dart';
import '../domain/auth_models.dart';
import '../domain/auth_service.dart';
import 'auth_form_widgets.dart';
import 'legal_consent.dart';
import 'email_otp_page.dart';
import '../domain/email_otp_models.dart';
import '../../../core/l10n/app_text.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    required this.auth,
    required this.onSuccess,
    this.openLegalUrl,
    super.key,
  });
  final AccountAuthService auth;
  final ValueChanged<AuthSession> onSuccess;
  final Future<bool> Function(Uri)? openLegalUrl;
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _phone = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  String _workspaceType = 'household';
  String? _error;
  bool _busy = false;
  bool _legalAccepted = false;
  List<TextEditingController> get _inputs => [
    _name,
    _email,
    _phone,
    _password,
    _confirm,
  ];
  bool get _hasContact => _email.text.trim().isNotEmpty;
  bool get _ready =>
      _legalAccepted &&
      _name.text.trim().isNotEmpty &&
      _hasContact &&
      newPasswordValidator(_password.text) == null &&
      _password.text == _confirm.text;

  /// Cho người dùng biết vì sao nút "Tạo tài khoản" chưa bấm được.
  String? get _missing {
    if (_name.text.trim().isEmpty) return 'Hãy nhập tên hiển thị để tiếp tục.';
    if (!_hasContact) return 'Hãy nhập email để tiếp tục.';
    if (newPasswordValidator(_password.text) != null) {
      return 'Mật khẩu cần có ít nhất 8 ký tự.';
    }
    if (_password.text != _confirm.text) {
      return 'Hãy nhập lại mật khẩu cho khớp.';
    }
    if (!_legalAccepted) {
      return 'Hãy tích đồng ý Điều khoản và Chính sách bảo mật.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in _inputs) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    for (final c in _inputs) {
      c.dispose();
    }
    super.dispose();
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email là bắt buộc.';
    }
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
        ? null
        : 'Email chưa đúng định dạng.';
  }

  String? _phoneValidator(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length < 8 || digits.length > 15
        ? 'Số điện thoại chưa đúng.'
        : null;
  }

  Future<void> _register() async {
    if (_busy || !_legalAccepted) return;
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await widget.auth.register(
        acceptedTerms: _legalAccepted,
        acceptedPrivacy: _legalAccepted,
        displayName: _name.text,
        email: _email.text.trim().isEmpty ? null : _email.text,
        phone: _phone.text.trim().isEmpty ? null : _phone.text,
        password: _password.text,
        workspaceType: _workspaceType,
      );
      if (!mounted) return;
      final verified = await Navigator.push<EmailVerification>(
        context,
        MaterialPageRoute(
          builder: (_) => EmailOtpPage(auth: widget.auth, challenge: challenge),
        ),
      );
      if (!mounted || verified?.session == null) return;
      Navigator.pop(context);
      widget.onSuccess(verified!.session!);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr('Không kết nối được HomeMind. Vui lòng thử lại.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    return AuthFormScaffold(
      title: 'Tạo tài khoản',
      subtitle: 'Bắt đầu quản lý kho của bạn',
      formKey: _form,
      children: [
        authError(_error),
        AuthTextField(
          key: const ValueKey('register_name'),
          controller: _name,
          label: 'Tên hiển thị',
          hint: 'Ví dụ: Lan Anh',
          icon: Icons.person_outline_rounded,
          enabled: !_busy,
        ),
        // Cần ít nhất một trong hai: nói rõ ngay trên ô nhập, không ghi "tùy chọn".
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Email là bắt buộc và cần xác minh trước khi sử dụng tài khoản. Số điện thoại không bắt buộc.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: HomeMindTheme.textSub,
            ),
          ),
        ),
        AuthTextField(
          key: const ValueKey('register_email'),
          controller: _email,
          label: 'Email',
          hint: 'ten@email.com',
          icon: Icons.email_outlined,
          validator: _emailValidator,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
        ),
        AuthTextField(
          key: const ValueKey('register_phone'),
          controller: _phone,
          label: 'Số điện thoại',
          hint: '0901 234 567',
          icon: Icons.phone_outlined,
          optional: true,
          validator: _phoneValidator,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
        ),
        AuthTextField(
          key: const ValueKey('register_password'),
          controller: _password,
          label: 'Mật khẩu',
          hint: 'Ít nhất 8 ký tự',
          icon: Icons.lock_outline_rounded,
          password: true,
          validator: newPasswordValidator,
          enabled: !_busy,
        ),
        AuthTextField(
          key: const ValueKey('register_confirm'),
          controller: _confirm,
          label: 'Nhập lại mật khẩu',
          icon: Icons.lock_outline_rounded,
          password: true,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          validator: (v) =>
              v != _password.text ? 'Mật khẩu xác nhận chưa khớp.' : null,
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Bạn dùng HomeMind cho',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: HomeMindTheme.textMain,
            ),
          ),
        ),
        SegmentedButton<String>(
          key: const ValueKey('register_workspace'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: 'household',
              icon: Icon(Icons.home_outlined),
              label: Text('Gia đình'),
            ),
            ButtonSegment(
              value: 'store',
              icon: Icon(Icons.storefront_outlined),
              label: Text('Cửa hàng'),
            ),
          ],
          selected: {_workspaceType},
          onSelectionChanged: _busy
              ? null
              : (v) => setState(() => _workspaceType = v.first),
        ),
        const SizedBox(height: 20),
        LegalConsent(
          accepted: _legalAccepted,
          enabled: !_busy,
          openUrl: widget.openLegalUrl,
          onChanged: (value) => setState(() => _legalAccepted = value),
          onOpenError: () {
            if (mounted) {
              setState(
                () => _error = tr(
                  'Không thể mở trang pháp lý. Vui lòng thử lại.',
                ),
              );
            }
          },
        ),
        const SizedBox(height: 12),
        authSubmit(
          'Tạo tài khoản',
          _busy,
          _register,
          key: const ValueKey('register_submit'),
          enabled: _ready,
        ),
        if (missing != null && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              missing,
              key: const ValueKey('register_missing_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: HomeMindTheme.textSub,
              ),
            ),
          ),
      ],
    );
  }
}
