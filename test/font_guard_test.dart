import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Chặn lỗi font chữ quay lại: trong các nút, `textStyle:` tự đặt mà thiếu
/// `fontFamily` sẽ làm máy (đặc biệt Oppo) rơi về font hệ thống kiểu viết tay.
void main() {
  test('mọi textStyle đặt riêng cho nút đều có fontFamily', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!RegExp(r'\btextStyle:\s*(const\s+)?TextStyle\(')
            .hasMatch(lines[i])) {
          continue;
        }
        final window = lines
            .sublist(i, (i + 6).clamp(0, lines.length))
            .join('\n');
        if (!window.contains('fontFamily')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Thiếu fontFamily tại: $offenders');
  });

  test('font Be Vietnam Pro được đóng gói đủ độ đậm', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      expect(pubspec, contains('BeVietnamPro-$w.ttf'));
      expect(File('assets/fonts/BeVietnamPro-$w.ttf').existsSync(), isTrue);
    }
  });
}
