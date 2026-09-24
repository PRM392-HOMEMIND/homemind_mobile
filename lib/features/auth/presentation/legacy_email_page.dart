import 'package:flutter/material.dart';

import '../domain/email_otp_models.dart';
import '../domain/auth_service.dart';
import 'auth_form_widgets.dart';
import 'email_otp_page.dart';

class LegacyEmailPage extends StatefulWidget {
  const LegacyEmailPage({required this.auth, required this.proof, super.key});
  final EmailOtpAuthService auth;
  final LegacyEmailRequired proof;
  @override
  State<LegacyEmailPage> createState() => _LegacyEmailPageState();
}

class _LegacyEmailPageState extends State<LegacyEmailPage> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await widget.auth.addLegacyEmail(
        widget.proof,
        _email.text,
      );
      if (!mounted) return;
      final result = await Navigator.push<EmailVerification>(
        context,
        MaterialPageRoute(
          builder: (_) => EmailOtpPage(auth: widget.auth, challenge: challenge),
        ),
      );
      if (mounted && result?.session != null) Navigator.pop(context, result);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFormScaffold(
    title: 'Bổ sung email',
    subtitle:
        'Tài khoản cũ cần email đã xác minh. Dữ liệu của bạn được giữ nguyên.',
    formKey: _form,
    children: [
      AuthTextField(
        controller: _email,
        label: 'Email',
        keyboardType: TextInputType.emailAddress,
        enabled: !_busy,
        validator: (v) =>
            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
            ? null
            : 'Email chưa đúng định dạng.',
      ),
      authError(_error),
      authSubmit('Xác minh email', _busy, _submit),
    ],
  );
}
