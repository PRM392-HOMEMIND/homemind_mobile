import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final path = Platform.environment['HOMEMIND_VISUAL_EVIDENCE_DIR'];
  if (path == null || !File('$path/ownership.json').existsSync()) {
    throw StateError('Explicit task-owned evidence directory required');
  }
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
        throw StateError('Invalid screenshot name');
      }
      await File('$path/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
