import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/billing_concealment_scenarios.dart';
import 'native_ui_sync.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native S01-S10 billing concealment with production widgets', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    await concealmentScenarios(
      tester,
      capture: (name) => awaitWithFrames(
        tester,
        binding.takeScreenshot(name).then<void>((_) {}),
      ),
    );
  });
}
