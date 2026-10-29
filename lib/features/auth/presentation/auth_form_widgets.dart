import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';

/// Khung màn hình tài khoản: cùng ngôn ngữ thiết kế với màn đăng nhập
/// (nền trắng, nút quay lại, tiêu đề lớn, ô nhập có nhãn phía trên).
class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({
    required this.title,
    required this.formKey,
    required this.children,
    this.subtitle,
    super.key,
  });
  final String title;
  final String? subtitle;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Navigator.canPop(context))
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Quay lại',
                    iconSize: 28,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: HomeMindTheme.textMain,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: HomeMindTheme.textMain,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: HomeMindTheme.textSub,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

class AuthTextField extends StatefulWidget {
  const AuthTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.icon,
    this.password = false,
    this.optional = false,
    this.validator,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    super.key,
  });
  final TextEditingController controller;

  /// Nhãn hiển thị phía trên ô nhập.
  final String label;
  final String? hint, helper;
  final IconData? icon;
  final bool password, optional, enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _hidden = true;

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: HomeMindTheme.textMain,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: widget.keyboardType,
          autocorrect: false,
          obscureText: widget.password && _hidden,
          textInputAction: widget.textInputAction,
          style: const TextStyle(fontSize: 17, color: HomeMindTheme.textMain),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(
              color: HomeMindTheme.textMuted,
              fontSize: 16,
            ),
            helperText: widget.helper,
            helperMaxLines: 3,
            prefixIcon: widget.icon == null
                ? null
                : Icon(widget.icon, color: HomeMindTheme.textSub, size: 24),
            filled: true,
            fillColor: HomeMindTheme.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: _border(HomeMindTheme.border),
            enabledBorder: _border(HomeMindTheme.border),
            focusedBorder: _border(HomeMindTheme.primary, 2),
            errorStyle: const TextStyle(fontSize: 14),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    iconSize: 26,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: HomeMindTheme.textSub,
                    ),
                  )
                : null,
          ),
          validator:
              widget.validator ??
              (value) => !widget.optional && (value?.trim().isEmpty ?? true)
                  ? 'Vui lòng nhập ${widget.label.toLowerCase()}.'
                  : null,
        ),
      ],
    ),
  );
}

String? newPasswordValidator(String? value) =>
    value == null || value.length < 8 || value.length > 128
    ? 'Mật khẩu cần từ 8 đến 128 ký tự.'
    : null;

/// Thông báo lỗi nổi bật, cùng kiểu với màn đăng nhập.
Widget authError(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          key: const ValueKey('auth_error'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: HomeMindTheme.urgentBg,
            borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
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
                  error,
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
      );

Widget authSubmit(
  String label,
  bool busy,
  VoidCallback action, {
  Key? key,
  bool destructive = false,
  bool enabled = true,
}) {
  final color = destructive ? HomeMindTheme.danger : HomeMindTheme.primary;
  return SizedBox(
    height: 56,
    child: ElevatedButton(
      key: key,
      onPressed: busy || !enabled ? null : action,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        ),
        textStyle: const TextStyle(
          fontFamily: HomeMindTheme.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            )
          : Text(label),
    ),
  );
}
