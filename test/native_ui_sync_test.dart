import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';

import '../integration_test/native_ui_sync.dart';

import 'package:homemind_mobile/features/auth/presentation/auth_form_widgets.dart';

class _Pops extends NavigatorObserver {
  final names = <String?>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name);
  }
}

void main() {
  testWidgets('current Vietnamese auth back control returns its actual route', (
    tester,
  ) async {
    final observer = _Pops();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: 'auth-otp'),
                  builder: (_) => AuthFormScaffold(
                    title: 'OTP fixture',
                    formKey: GlobalKey<FormState>(),
                    children: const [],
                  ),
                ),
              ),
              child: const Text('Open auth'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quay lại'), findsOneWidget);
    await backWhenReady(tester);
    expect(find.text('Open auth'), findsOneWidget);
    expect(find.byType(AuthFormScaffold), findsNothing);
    expect(observer.names, ['auth-otp']);
  });
  testWidgets('semantics waits for actual handle release on a frame', (
    tester,
  ) async {
    final baseline = tester.binding.debugOutstandingSemanticsHandles;
    final handle = tester.binding.ensureSemantics();
    tester.binding.addPostFrameCallback((_) => handle.dispose());
    await waitForSemanticsBaseline(tester, baseline);
    expect(tester.binding.debugOutstandingSemanticsHandles, baseline);
  });

  testWidgets('unreleased semantics still fails the bounded prerequisite', (
    tester,
  ) async {
    final baseline = tester.binding.debugOutstandingSemanticsHandles;
    final handle = tester.binding.ensureSemantics();
    try {
      await expectLater(
        waitForSemanticsBaseline(tester, baseline, timeout: Duration.zero),
        throwsStateError,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('actual typed sheet returns its value after overlay removal', (
    tester,
  ) async {
    VoiceSheet.enableInfiniteAnimation = false;
    addTearDown(() => VoiceSheet.enableInfiniteAnimation = true);
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await VoiceSheet.show(
                  context,
                  speechService: const UnavailableSpeechRecognitionService(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    final route = await currentRouteWhenReady(
      tester,
      find.byType(VoiceSheet),
      timeout: const Duration(seconds: 25),
    );
    await tester.enterText(find.byType(TextField), 'scoped read');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final removed = route.completed.then<void>((_) {});
    await tester.tap(find.text('Xong'));
    await awaitWithFrames(tester, removed);
    expect(result, 'scoped read');
    expect(find.byType(VoiceSheet), findsNothing);
    expect(route.isActive, isFalse);
  });

  testWidgets('missing current sheet remains a bounded failure', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await expectLater(
      currentRouteWhenReady(
        tester,
        find.byType(VoiceSheet),
        timeout: Duration.zero,
      ),
      throwsStateError,
    );
  });

  testWidgets(
    'host completion receives frames without replaying the operation',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final result = Completer<void>();
      var calls = 0;
      Future<void> host() {
        calls++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          verifyHostResponse(200, 'PASS');
          result.complete();
        });
        return result.future;
      }

      await awaitWithFrames(tester, host());
      expect(result.isCompleted, isTrue);
      expect(calls, 1);
    },
  );

  testWidgets('host failures stay failures', (tester) async {
    final failure = StateError('owned host rejected');
    Object? observed;
    try {
      await awaitWithFrames(tester, Future<void>.error(failure));
    } catch (error) {
      observed = error;
    }
    expect(observed, same(failure));
  });

  testWidgets('rejected host response stays rejected while frames progress', (
    tester,
  ) async {
    final operation = Future<void>.microtask(
      () => verifyHostResponse(503, 'PASS'),
    );
    Object? observed;
    try {
      await awaitWithFrames(tester, operation);
    } catch (error) {
      observed = error;
    }
    expect(observed, isA<StateError>());
  });

  test('HTTP success cannot accept a missing or failed application status', () {
    for (final status in [null, 'FAIL']) {
      expect(() => verifyHostResponse(200, status), throwsStateError);
    }
  });

  testWidgets(
    'host deadline cannot turn an incomplete operation into success',
    (tester) async {
      final operation = Completer<void>();
      await expectLater(
        awaitWithFrames(tester, operation.future, timeout: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      operation.complete();
      await tester.pump();
    },
  );

  testWidgets(
    'back waits for the current route after an editor starts exiting',
    (tester) async {
      final observer = _Pops();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              key: const Key('home'),
              body: ElevatedButton(
                key: const Key('open'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'account'),
                    builder: (context) => Scaffold(
                      key: const Key('account'),
                      appBar: AppBar(title: const Text('Account')),
                      body: ElevatedButton(
                        key: const Key('edit'),
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            settings: const RouteSettings(name: 'editor'),
                            builder: (_) => Scaffold(
                              key: const Key('editor'),
                              appBar: AppBar(title: const Text('Edit')),
                            ),
                          ),
                        ),
                        child: const Text('Edit'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byKey(const Key('editor')))).pop();
      await tester.pump();
      expect(find.byTooltip('Back'), findsNWidgets(2));

      await backWhenReady(tester);
      expect(find.byKey(const Key('home')), findsOneWidget);
      expect(find.byKey(const Key('account')), findsNothing);
      expect(find.byKey(const Key('editor')), findsNothing);
      expect(observer.names, ['editor', 'account']);
    },
  );

  testWidgets('missing back control remains a bounded failure', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await expectLater(
      backWhenReady(tester, timeout: Duration.zero),
      throwsA(isA<StateError>()),
    );
  });
}
