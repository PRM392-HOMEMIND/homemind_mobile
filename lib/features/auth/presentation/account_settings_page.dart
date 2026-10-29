import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../../assistant/domain/assistant_models.dart';
import '../domain/account_auth_service.dart';
import '../domain/auth_service.dart';
import 'auth_form_widgets.dart';
import '../domain/email_otp_models.dart';
import 'email_otp_page.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    required this.auth,
    required this.profile,
    this.onProfileChanged,
    super.key,
  });
  final AccountAuthService auth;
  final UserProfile profile;
  final ValueChanged<UserProfile>? onProfileChanged;
  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late UserProfile _profile = widget.profile;
  bool _busy = false;
  String? _error;
  Future<void> _edit(bool identifiers) async {
    final result = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => _AccountEditPage(
          auth: widget.auth,
          profile: _profile,
          identifiers: identifiers,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _profile = result);
      widget.onProfileChanged?.call(result);
    }
  }

  Future<void> _logoutAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất tất cả thiết bị?'),
        content: const Text(
          'Bạn sẽ cần đăng nhập lại trên mọi thiết bị, kể cả thiết bị này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất tất cả'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.logoutAll();
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bảo mật tài khoản')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          _profile.email.isEmpty ? (_profile.loginPhone ?? '') : _profile.email,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (_profile.loginPhone != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_profile.loginPhone!),
          ),
        const SizedBox(height: 20),
        authError(_error),
        ListTile(
          key: const ValueKey('account_password'),
          leading: const Icon(Icons.lock_outline),
          title: const Text('Đổi mật khẩu'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => _edit(false),
        ),
        ListTile(
          key: const ValueKey('account_identifiers'),
          leading: const Icon(Icons.contact_mail_outlined),
          title: const Text('Đổi email / số điện thoại'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => _edit(true),
        ),
        ListTile(
          key: const ValueKey('account_logout_all'),
          leading: const Icon(Icons.devices_outlined),
          title: const Text('Đăng xuất tất cả thiết bị'),
          onTap: _busy ? null : _logoutAll,
        ),
        const Divider(height: 32),
        ListTile(
          key: const ValueKey('account_deactivate'),
          leading: const Icon(
            Icons.pause_circle_outline,
            color: HomeMindTheme.danger,
          ),
          title: const Text('Vô hiệu hóa tài khoản'),
          onTap: _busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _CloseAccountPage(auth: widget.auth, delete: false),
                  ),
                ),
        ),
        ListTile(
          key: const ValueKey('account_delete'),
          leading: const Icon(
            Icons.delete_outline,
            color: HomeMindTheme.danger,
          ),
          title: const Text('Xóa tài khoản'),
          onTap: _busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _CloseAccountPage(auth: widget.auth, delete: true),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _AccountEditPage extends StatefulWidget {
  const _AccountEditPage({
    required this.auth,
    required this.profile,
    required this.identifiers,
  });
  final AccountAuthService auth;
  final UserProfile profile;
  final bool identifiers;
  @override
  State<_AccountEditPage> createState() => _AccountEditPageState();
}

class _AccountEditPageState extends State<_AccountEditPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  late final _email = TextEditingController(text: widget.profile.email);
  late final _phone = TextEditingController(
    text: widget.profile.loginPhone ?? '',
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_current, _password, _confirm, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (widget.identifiers && _email.text.trim().isEmpty) {
      setState(() => _error = 'Email là bắt buộc.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      UserProfile? profile;
      if (widget.identifiers) {
        if (_email.text.trim().toLowerCase() !=
            widget.profile.email.trim().toLowerCase()) {
          final old = await widget.auth.startEmailChange(_current.text);
          if (!mounted) return;
          final oldProof = await Navigator.push<EmailVerification>(
            context,
            MaterialPageRoute(
              builder: (_) => EmailOtpPage(auth: widget.auth, challenge: old),
            ),
          );
          if (!mounted || oldProof?.ticket == null) return;
          final next = await widget.auth.startNewEmail(
            old,
            oldProof!,
            _email.text,
          );
          if (!mounted) return;
          final result = await Navigator.push<EmailVerification>(
            context,
            MaterialPageRoute(
              builder: (_) => EmailOtpPage(auth: widget.auth, challenge: next),
            ),
          );
          if (!mounted || result?.reauthenticationRequired != true) return;
        } else {
          profile = await widget.auth.changeIdentifiers(
            currentPassword: _current.text,
            email: _email.text.trim().isEmpty ? null : _email.text,
            phone: _phone.text.trim().isEmpty ? null : _phone.text,
          );
        }
      } else {
        final challenge = await widget.auth.changePassword(
          _current.text,
          _password.text,
        );
        if (!mounted) return;
        if (challenge is PasswordChanged) {
          Navigator.popUntil(context, (route) => route.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã đổi mật khẩu. Vui lòng đăng nhập lại.'),
            ),
          );
          return;
        }
        final result = await Navigator.push<EmailVerification>(
          context,
          MaterialPageRoute(
            builder: (_) => EmailOtpPage(
              auth: widget.auth,
              challenge: challenge as EmailChallenge,
            ),
          ),
        );
        if (!mounted || result?.reauthenticationRequired != true) return;
      }
      if (!mounted) return;
      Navigator.pop(context, profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.identifiers
                ? 'Đã cập nhật thông tin đăng nhập.'
                : 'Đã đổi mật khẩu. Các phiên cũ đã đăng xuất.',
          ),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFormScaffold(
    title: widget.identifiers ? 'Thông tin đăng nhập' : 'Đổi mật khẩu',
    formKey: _form,
    children: [
      if (widget.identifiers) ...[
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text(
            'Email là bắt buộc. Đổi email cần xác minh địa chỉ hiện tại và địa chỉ mới. Số điện thoại không bắt buộc.',
          ),
        ),
        AuthTextField(
          key: const ValueKey('account_email'),
          controller: _email,
          label: 'Email',
          icon: Icons.email_outlined,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
        ),
        AuthTextField(
          key: const ValueKey('account_phone'),
          controller: _phone,
          label: 'Số điện thoại',
          icon: Icons.phone_outlined,
          optional: true,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
        ),
      ],
      AuthTextField(
        key: const ValueKey('account_current_password'),
        controller: _current,
        label: 'Mật khẩu hiện tại',
        password: true,
        enabled: !_busy,
      ),
      if (!widget.identifiers) ...[
        AuthTextField(
          key: const ValueKey('account_new_password'),
          controller: _password,
          label: 'Mật khẩu mới',
          password: true,
          enabled: !_busy,
          validator: newPasswordValidator,
        ),
        AuthTextField(
          key: const ValueKey('account_confirm_password'),
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
        'Lưu thay đổi',
        _busy,
        _save,
        key: const ValueKey('account_save'),
      ),
    ],
  );
}

class _CloseAccountPage extends StatefulWidget {
  const _CloseAccountPage({required this.auth, required this.delete});
  final AccountAuthService auth;
  final bool delete;
  @override
  State<_CloseAccountPage> createState() => _CloseAccountPageState();
}

class _CloseAccountPageState extends State<_CloseAccountPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (!_form.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.delete ? 'Xác nhận xóa tài khoản' : 'Xác nhận vô hiệu hóa',
        ),
        content: const Text(
          'Bạn sẽ mất quyền đăng nhập và mọi phiên sẽ bị thu hồi. Dữ liệu workspace chung được bảo toàn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HomeMindTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.closeAccount(_password.text, delete: widget.delete);
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFormScaffold(
    title: widget.delete ? 'Xóa tài khoản' : 'Vô hiệu hóa tài khoản',
    formKey: _form,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Text(
          'Các phiên đăng nhập sẽ bị thu hồi. Nếu bạn là chủ sở hữu duy nhất của workspace có thành viên khác, hãy chuyển quyền sở hữu trước.',
        ),
      ),
      AuthTextField(
        key: const ValueKey('close_password'),
        controller: _password,
        label: 'Mật khẩu hiện tại',
        password: true,
        enabled: !_busy,
      ),
      authError(_error),
      authSubmit(
        widget.delete ? 'Xóa tài khoản' : 'Vô hiệu hóa tài khoản',
        _busy,
        _close,
        key: const ValueKey('close_submit'),
        destructive: true,
      ),
    ],
  );
}
