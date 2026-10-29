import 'package:flutter/material.dart';

import '../domain/account_auth_service.dart';
import '../domain/auth_service.dart';
import 'auth_form_widgets.dart';
import '../domain/email_otp_models.dart';
import 'email_otp_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({required this.auth, super.key});
  final AccountAuthService auth;
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  String? _error;
  EmailChallenge? _challenge;
  EmailVerification? _proof;
  bool _busy = false, _accepted = false;
  @override
  void dispose() {
    for (final c in [_identifier, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_proof == null) {
        final challenge = await widget.auth.forgotPassword(_identifier.text);
        if (!mounted) return;
        setState(() => _accepted = true);
        final proof = await Navigator.push<EmailVerification>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                EmailOtpPage(auth: widget.auth, challenge: challenge),
          ),
        );
        if (mounted && proof?.ticket != null) {
          setState(() {
            _challenge = challenge;
            _proof = proof;
          });
        }
      } else {
        await widget.auth.resetWithProof(_challenge!, _proof!, _password.text);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã đặt lại mật khẩu. Vui lòng đăng nhập.'),
            ),
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không kết nối được HomeMind. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFormScaffold(
    title: _proof == null ? 'Quên mật khẩu' : 'Đặt lại mật khẩu',
    subtitle: _proof == null
        ? 'Nhập email đã đăng ký.'
        : 'Chọn mật khẩu mới cho tài khoản của bạn.',
    formKey: _form,
    children: [
      if (_proof == null) ...[
        AuthTextField(
          key: const ValueKey('forgot_identifier'),
          controller: _identifier,
          label: 'Email',
          hint: 'ten@email.com',
          keyboardType: TextInputType.emailAddress,
          validator: (value) =>
              RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                  .hasMatch(value?.trim() ?? '')
              ? null
              : 'Email chưa đúng định dạng.',
          icon: Icons.person_outline_rounded,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
        ),
        if (_accepted)
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              'Nếu tài khoản tồn tại, hướng dẫn đặt lại mật khẩu sẽ được gửi.',
            ),
          ),
      ] else ...[
        AuthTextField(
          key: const ValueKey('reset_password'),
          controller: _password,
          label: 'Mật khẩu mới',
          password: true,
          validator: newPasswordValidator,
          enabled: !_busy,
        ),
        AuthTextField(
          key: const ValueKey('reset_confirm'),
          controller: _confirm,
          label: 'Xác nhận mật khẩu mới',
          password: true,
          enabled: !_busy,
          validator: (v) =>
              v != _password.text ? 'Mật khẩu xác nhận chưa khớp.' : null,
        ),
      ],
      authError(_error),
      authSubmit(
        _proof == null ? 'Tiếp tục' : 'Lưu mật khẩu mới',
        _busy,
        _submit,
        key: const ValueKey('forgot_submit'),
      ),
    ],
  );
}
