import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/email_otp_models.dart';
import '../domain/auth_service.dart';
import 'auth_form_widgets.dart';

class EmailOtpPage extends StatefulWidget {
  const EmailOtpPage({required this.auth, required this.challenge, super.key});
  final EmailOtpAuthService auth;
  final EmailChallenge challenge;
  @override
  State<EmailOtpPage> createState() => _EmailOtpPageState();
}

class _EmailOtpPageState extends State<EmailOtpPage>
    with WidgetsBindingObserver {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _clock = Stopwatch()..start();
  Timer? _timer;
  late EmailChallenge _challenge;
  bool _busy = false, _polling = false;
  String? _error;
  int _pollTicks = 0;
  DateTime get _now => _challenge.serverTime.add(_clock.elapsed);
  int seconds(DateTime? target) => target == null
      ? 0
      : (target.difference(_now).inMilliseconds / 1000).ceil().clamp(0, 3600);
  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (_challenge.state == 'preparing' && _pollTicks++ < 30) {
        unawaited(_refresh());
      }
    });
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  void _publish(EmailChallenge value) {
    if (mounted) {
      setState(() {
        _challenge = value;
        _clock.reset();
      });
    }
  }

  Future<void> _refresh() async {
    if (_polling || _busy || !mounted) return;
    _polling = true;
    try {
      _publish(await widget.auth.challengeStatus(_challenge));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không kết nối được HomeMind. Vui lòng thử lại.',
        );
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _verify() async {
    if (_busy ||
        !RegExp(r'^[0-9]{6}$').hasMatch(_code.text) ||
        seconds(_challenge.expiresAt) == 0 ||
        _challenge.state != 'ready') {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.auth.verifyChallenge(_challenge, _code.text);
      _code.clear();
      if (mounted) Navigator.pop(context, result);
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

  Future<void> _resend() async {
    if (_busy || seconds(_challenge.resendAvailableAt) > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _publish(await widget.auth.resendChallenge(_challenge));
      _code.clear();
      _pollTicks = 0;
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _code.dispose();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = seconds(_challenge.expiresAt),
        cooldown = seconds(_challenge.resendAvailableAt);
    final title = switch (_challenge.purpose) {
      'RESET' => 'Xác minh đặt lại mật khẩu',
      'CHANGE_PASSWORD' => 'Xác nhận đổi mật khẩu',
      'CHANGE_EMAIL_OLD' => 'Xác minh email hiện tại',
      'CHANGE_EMAIL_NEW' => 'Xác minh email mới',
      'LEGACY_EMAIL' => 'Xác minh email bổ sung',
      _ => 'Xác minh email',
    };
    return AuthFormScaffold(
      title: title,
      formKey: _form,
      subtitle:
          'Nhập mã gửi tới ${_challenge.maskedEmail}. Không chia sẻ mã với người khác.',
      children: [
        Center(
          child: Image.asset(
            'assets/logos/logo_symbol.png',
            height: 64,
            semanticLabel: 'HomeMind',
          ),
        ),
        const SizedBox(height: 16),
        if (_challenge.state == 'preparing')
          const Text('Đang chuẩn bị gửi mã…')
        else if (_challenge.state == 'failed')
          const Text('Chưa gửi được mã. Hãy chờ và yêu cầu mã mới.')
        else
          Text(
            remaining > 0
                ? 'Mã hết hạn sau $remaining giây (theo máy chủ).'
                : 'Mã đã hết hạn. Yêu cầu mã mới để tiếp tục.',
          ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('otp_code'),
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          maxLength: 6,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Mã xác thực 6 số'),
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) => _verify(),
        ),
        authError(_error),
        authSubmit(
          'Xác nhận',
          _busy,
          _verify,
          key: const ValueKey('otp_verify'),
          enabled:
              !_busy &&
              _challenge.state == 'ready' &&
              remaining > 0 &&
              RegExp(r'^[0-9]{6}$').hasMatch(_code.text),
        ),
        TextButton(
          key: const ValueKey('otp_resend'),
          onPressed: _busy || cooldown > 0 ? null : _resend,
          child: Text(
            cooldown > 0 ? 'Gửi lại sau $cooldown giây' : 'Gửi lại mã',
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('Kiểm tra trạng thái gửi'),
        ),
      ],
    );
  }
}
