import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

// HTTP callbacks can finish while a guarded frame pump is still outstanding.
// Keep the same host invariant without entering a concurrent tester assertion.
void verifyHostResponse(int httpStatus, Object? applicationStatus) {
  if (httpStatus != 200 || applicationStatus != 'PASS') {
    throw StateError('Owned native host action rejected: HTTP $httpStatus');
  }
}

// UIAutomator's accessibility disconnect reaches Flutter asynchronously. Wait
// for actual release; persistent application/platform handles still fail.
Future<void> waitForSemanticsBaseline(
  WidgetTester tester,
  int baseline, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final watch = Stopwatch()..start();
  while (tester.binding.debugOutstandingSemanticsHandles > baseline &&
      watch.elapsed < timeout) {
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (tester.binding.debugOutstandingSemanticsHandles > baseline) {
    throw StateError('Native external semantics did not settle');
  }
}

Future<ModalRoute<dynamic>> currentRouteWhenReady(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    final elements = finder.evaluate().toList();
    if (elements.length == 1) {
      final route = ModalRoute.of(elements.single);
      if (route != null &&
          route.isCurrent &&
          route.animation?.status == AnimationStatus.completed) {
        return route;
      }
    }
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 200));
  }
  throw StateError('Native current route did not finish entering');
}

// Native callbacks can arrive after the sheet's first frame on a slower host.
// Keep frames progressing while ONE original host operation verifies the OS.
Future<void> awaitWithFrames(
  WidgetTester tester,
  Future<void> operation, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final watch = Stopwatch()..start();
  var completed = false;
  Object? failure;
  StackTrace? failureStack;
  unawaited(
    operation.then<void>(
      (_) {
        completed = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        completed = true;
      },
    ),
  );
  while (!completed && watch.elapsed < timeout) {
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (!completed) {
    throw TimeoutException('Native host frame deadline exceeded', timeout);
  }
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
}

// An exiting editor and its current parent can both retain a Back tooltip.
// Wait for the current route's actual pointer target, then verify its removal.
Future<void> backWhenReady(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final watch = Stopwatch()..start();
  Finder? ready;
  ModalRoute<dynamic>? route;
  while (watch.elapsed < timeout) {
    var control = find.byTooltip('Back').hitTestable();
    if (control.evaluate().isEmpty) {
      control = find.byType(CupertinoNavigationBarBackButton).hitTestable();
    }
    if (control.evaluate().isEmpty) {
      control = find.byTooltip('Quay lại').hitTestable();
    }
    final elements = control.evaluate().toList();
    if (elements.length == 1) {
      final candidate = ModalRoute.of(elements.single);
      if (candidate != null && candidate.isCurrent) {
        ready = control;
        route = candidate;
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (ready == null || route == null) {
    throw StateError('Native current back control did not become ready');
  }
  var returned = false;
  unawaited(route.completed.then<void>((_) => returned = true));
  await tester.tap(ready);
  while (!returned && watch.elapsed < timeout) {
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (!returned) {
    throw StateError('Native route did not finish returning');
  }
}
