import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/auth/domain/account_auth_service.dart';
import 'package:homemind_mobile/features/auth/presentation/register_page.dart';

class _Unused implements AccountAuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Finder field(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextFormField),
  );

  testWidgets(
    'email is mandatory; phone-only cannot satisfy registration readiness',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(auth: _Unused(), onSuccess: (_) {}),
        ),
      );
      expect(find.textContaining('Email là bắt buộc'), findsWidgets);
      String hint() => tester
          .widget<Text>(find.byKey(const ValueKey('register_missing_hint')))
          .data!;

      expect(hint(), contains('tên hiển thị'));
      await tester.enterText(field('register_name'), 'Lan Anh');
      await tester.pump();
      expect(hint(), contains('email'));
      await tester.enterText(field('register_phone'), '0901234567');
      await tester.pump();
      expect(hint(), contains('email'));
      await tester.enterText(field('register_email'), 'lan@example.invalid');
      await tester.pump();
      expect(hint(), contains('8 ký tự'));
      await tester.enterText(field('register_password'), 'matkhau-dai');
      await tester.pump();
      expect(hint(), contains('nhập lại mật khẩu'));
      await tester.enterText(field('register_confirm'), 'matkhau-dai');
      await tester.pump();
      expect(hint(), contains('Điều khoản'));
    },
  );
}
