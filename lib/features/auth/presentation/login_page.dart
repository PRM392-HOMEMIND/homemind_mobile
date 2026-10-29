import 'package:flutter/material.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';
import '../domain/auth_models.dart';
import '../domain/auth_service.dart';
import '../domain/account_auth_service.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import '../domain/email_otp_models.dart';
import 'email_otp_page.dart';
import 'legacy_email_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.authService,
    required this.onLoginSuccess,
    this.onBackToOnboarding,
    super.key,
  });

  final AuthService authService;
  final ValueChanged<AuthSession> onLoginSuccess;
  final VoidCallback? onBackToOnboarding;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _performLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = await widget.authService.login(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      widget.onLoginSuccess(session);
    } on EmailVerificationRequired catch (e) {
      if (!mounted) return;
      final auth = widget.authService;
      if (auth is EmailOtpAuthService) {
        final result = await Navigator.push<EmailVerification>(
          context,
          MaterialPageRoute(
            builder: (_) => EmailOtpPage(
              auth: auth as EmailOtpAuthService,
              challenge: e.challenge,
            ),
          ),
        );
        if (mounted && result?.session != null) {
          widget.onLoginSuccess(result!.session!);
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } on LegacyEmailRequired catch (e) {
      if (!mounted) return;
      final auth = widget.authService;
      if (auth is EmailOtpAuthService) {
        final result = await Navigator.push<EmailVerification>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LegacyEmailPage(auth: auth as EmailOtpAuthService, proof: e),
          ),
        );
        if (mounted && result?.session != null) {
          widget.onLoginSuccess(result!.session!);
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = tr('Không kết nối được HomeMind. Vui lòng thử lại.');
        _isLoading = false;
      });
    }
  }

  void _openAccountPage(bool register) {
    final auth = widget.authService;
    if (auth is! AccountAuthService) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => register
            ? RegisterPage(
                auth: auth as AccountAuthService,
                onSuccess: widget.onLoginSuccess,
              )
            : ForgotPasswordPage(auth: auth as AccountAuthService),
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: HomeMindTheme.textMuted, fontSize: 16),
      prefixIcon: Icon(icon, color: HomeMindTheme.textSub, size: 24),
      suffixIcon: suffix,
      filled: true,
      fillColor: HomeMindTheme.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border(HomeMindTheme.border),
      enabledBorder: border(HomeMindTheme.border),
      focusedBorder: border(HomeMindTheme.primary, 2),
      errorStyle: const TextStyle(fontSize: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: HomeMindTheme.textMain,
    );
    const fieldStyle = TextStyle(fontSize: 17, color: HomeMindTheme.textMain);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.onBackToOnboarding != null ||
                    Navigator.canPop(context))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: tr('Quay lại'),
                      iconSize: 28,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: HomeMindTheme.textMain,
                      ),
                      onPressed:
                          widget.onBackToOnboarding ??
                          () => Navigator.of(context).pop(),
                    ),
                  )
                else
                  const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/logos/logo_256.png',
                        width: 112,
                        height: 112,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr('Đăng nhập'),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Chào mừng bạn đến với HomeMind'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: HomeMindTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: HomeMindTheme.urgentBg,
                      borderRadius: BorderRadius.circular(
                        HomeMindTheme.radiusMd,
                      ),
                      border: Border.all(
                        color: HomeMindTheme.danger.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: HomeMindTheme.danger,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: HomeMindTheme.danger,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                const Text('Email hoặc số điện thoại', style: labelStyle),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('login_identifier'),
                  controller: _identifierController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enabled: !_isLoading,
                  style: fieldStyle,
                  decoration: _decoration(
                    hint: tr('Nhập email hoặc số điện thoại'),
                    icon: Icons.email_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return tr('Bạn chưa nhập email hoặc số điện thoại');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                Text(tr('Mật khẩu'), style: labelStyle),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('login_password'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  enabled: !_isLoading,
                  style: fieldStyle,
                  onFieldSubmitted: (_) => _performLogin(),
                  decoration: _decoration(
                    hint: tr('Nhập mật khẩu'),
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      tooltip: _obscurePassword
                          ? tr('Hiện mật khẩu')
                          : tr('Ẩn mật khẩu'),
                      iconSize: 26,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: HomeMindTheme.textSub,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return tr('Bạn chưa nhập mật khẩu');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    key: const ValueKey('login_submit'),
                    onPressed: _isLoading ? null : _performLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HomeMindTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: HomeMindTheme.primary.withValues(
                        alpha: 0.6,
                      ),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          HomeMindTheme.radiusMd,
                        ),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : Text(
                            tr('Đăng nhập'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    key: const ValueKey('login_register'),
                    onPressed: _isLoading ? null : () => _openAccountPage(true),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(
                      tr('Tạo tài khoản'),
                      style: TextStyle(
                        fontSize: 15,
                        color: HomeMindTheme.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    key: const ValueKey('login_forgot'),
                    onPressed: _isLoading
                        ? null
                        : () => _openAccountPage(false),
                    child: Text(tr('Quên mật khẩu?')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
