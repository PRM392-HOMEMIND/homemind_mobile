import 'support/restored_plan_billing_ui.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_quota_panel.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'support/recording_profile_service.dart';
import 'package:homemind_mobile/features/assistant/data/cached_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart';

void main() {
  setUp(() => AppText.setLanguage('vi', persist: false));
  Map<String, Object?> value(int used, int total) => {
    'periodId': 'owned-period', 'plan': 'family', 'used': used, 'total': total,
    'remaining': total - used, 'startsAt': '2026-10-04T07:25:30Z',
    'expiresAt': '2026-11-03T07:25:30Z', 'serverNow': '2026-10-04T07:25:30Z',
  };
  test('all official quotas parse without conflating product limits', () {
    for (final total in [15, 60, 100, 200]) {
      final quota = VoiceQuota.fromJson(value(total - 1, total));
      expect(quota.used, total - 1); expect(quota.remaining, 1);
      expect(quota.expiresAt.difference(quota.startsAt).inSeconds, 2592000);
    }
  });
  test('malformed, negative or over-limit authoritative quota is rejected', () {
    for (final raw in [{...value(1, 15), 'used': -1}, {...value(1, 15), 'total': 0},
      {...value(1, 15), 'remaining': 100}, {...value(1, 15), 'used': 16}]) {
      expect(() => VoiceQuota.fromJson(raw), throwsFormatException);
    }
  });
  testWidgets('98/100 means used98, remaining2; bar consumes committed profile', (tester) async {
    final profile = UserProfile(userId: 'u', email: '', displayName: 'Owned', workspaceId: 'ws',
      workspaceName: 'Owned', workspaceType: 'household', role: 'owner', voiceQuota: VoiceQuota.fromJson(value(98, 100)));
    final service = RecordingProfileService(profile);
    await tester.pumpRestoredPlanBillingWidget(MaterialApp(home: Scaffold(body: VoiceQuotaPanel(service: service))));
    await tester.pumpAndSettle();
    expect(find.text('98/100'), findsOneWidget);
    expect(find.text('Còn 2 lượt trong kỳ'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .98);
  });
  testWidgets('missing quota shows retry rather than a fabricated zero', (tester) async {
    const profile = UserProfile(userId: 'u', email: '', displayName: 'Owned', workspaceId: 'ws',
      workspaceName: 'Owned', workspaceType: 'household', role: 'owner');
    await tester.pumpRestoredPlanBillingWidget(MaterialApp(home: Scaffold(body: VoiceQuotaPanel(service: RecordingProfileService(profile)))));
    await tester.pumpAndSettle();
    expect(find.text('Chưa tải được hạn mức trợ lý. Hãy thử lại.'), findsOneWidget);
    expect(find.byKey(const Key('voice_quota_used_total')), findsNothing);
  });
  for (final width in [320.0, 360.0]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('quota fits ${width.toInt()} logical pixels / $brightness / text scale 200%', (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final profile = UserProfile(userId:'u',email:'',displayName:'Owned',workspaceId:'ws',
            workspaceName:'Owned',workspaceType:'household',role:'owner',
            voiceQuota:VoiceQuota.fromJson(value(98,100)));
        await tester.pumpRestoredPlanBillingWidget(MaterialApp(theme:ThemeData(brightness:brightness),
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(2)),child:child!),
            home:Scaffold(body:SingleChildScrollView(child:VoiceQuotaPanel(service:RecordingProfileService(profile))))));
        await tester.pumpAndSettle();
        expect(find.text('98/100'),findsOneWidget);
        expect(tester.takeException(),isNull);
        await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
      });
    }
  }
  for (final plan in ['free','personal','family','micro_pos']) {
    testWidgets('$plan exhausted action never initializes speech and explains the allowed transition', (tester) async {
      final total = {'free':15,'personal':60,'family':100,'micro_pos':200}[plan]!;
      final quota = VoiceQuota.fromJson({...value(total,total),'plan':plan});
      final profile = UserProfile(userId:'u',email:'',displayName:'Owned',workspaceId:'ws',
          workspaceName:'Owned',workspaceType:plan=='micro_pos'?'store':'household',role:'owner',voiceQuota:quota);
      final service = _QuotaFixture(profile),speech = _CountingSpeech();
      await tester.pumpRestoredPlanBillingWidget(MaterialApp(home:AppShell(assistantService:service,speechService:speech,profile:profile)));
      for (var i=0;i<4;i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:80)));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('nav_voice')));
      await tester.pumpAndSettle();
      expect(speech.initializations,0);
      expect(find.text(plan=='free'||plan=='personal'
          ? 'Đã hết lượt. Có thể nâng lên gói phù hợp cao hơn.'
          : 'Đã hết lượt. Hãy chờ kỳ tiếp theo; gia hạn đang cập nhật.'),findsOneWidget);
      expect(service.quotaReads,greaterThanOrEqualTo(2));
      await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
    });
  }
  testWidgets('resume refreshes authoritative period; loading failure never grants Free quota', (tester) async {
    final profile=UserProfile(userId:'u',email:'',displayName:'Owned',workspaceId:'ws',workspaceName:'Owned',
        workspaceType:'household',role:'owner',voiceQuota:VoiceQuota.fromJson(value(98,100)));
    final service=_QuotaFixture(profile);
    await tester.pumpRestoredPlanBillingWidget(MaterialApp(home:Scaffold(body:VoiceQuotaPanel(service:service))));
    await tester.pumpAndSettle();
    service.profile=profile.copyWith(voiceQuota:VoiceQuota.fromJson({...value(0,15),'plan':'free'}));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('0/15'),findsOneWidget);
    service.failQuota=true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Chưa tải được hạn mức trợ lý. Hãy thử lại.'),findsOneWidget);
    expect(find.byKey(const Key('voice_quota_used_total')),findsNothing);
    await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
  });
  testWidgets('shared cached quota timeout reaches both panels without an uncaught error; retry recovers', (tester) async {
    final profile=UserProfile(userId:'u',email:'',displayName:'Owned',workspaceId:'ws',workspaceName:'Owned',
        workspaceType:'household',role:'owner',voiceQuota:VoiceQuota.fromJson(value(14,15)));
    final inner=_DeferredQuota(profile);
    final cache=CachedAssistantService(inner,initialProfile:profile);
    addTearDown(cache.dispose);
    await tester.pumpRestoredPlanBillingWidget(MaterialApp(home:Scaffold(body:Column(children:[
      VoiceQuotaPanel(service:cache),VoiceQuotaPanel(service:cache),
    ]))));
    await tester.pumpAndSettle();
    final previousReads=inner.reads;
    inner.pending=Completer<UserProfile>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(inner.reads,previousReads+1);
    inner.pending!.completeError(const HomeMindApiException('Owned timeout'));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    expect(find.text('Chưa tải được hạn mức trợ lý. Hãy thử lại.'),findsNWidgets(2));
    expect(find.byKey(const Key('voice_quota_used_total')),findsNothing);
    inner.pending=null;
    await tester.tap(find.text('Chưa tải được hạn mức trợ lý. Hãy thử lại.').first);
    await tester.pumpAndSettle();
    expect(find.text('14/15'),findsNWidgets(2));
    expect(tester.takeException(),isNull);
    await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
  });
  testWidgets('disposed quota panel safely receives its pending timeout', (tester) async {
    final profile=UserProfile(userId:'u',email:'',displayName:'Owned',workspaceId:'ws',workspaceName:'Owned',
        workspaceType:'household',role:'owner',voiceQuota:VoiceQuota.fromJson(value(14,15)));
    final inner=_DeferredQuota(profile)..pending=Completer<UserProfile>();
    final cache=CachedAssistantService(inner,initialProfile:profile);
    addTearDown(cache.dispose);
    await tester.pumpRestoredPlanBillingWidget(MaterialApp(home:Scaffold(body:VoiceQuotaPanel(service:cache))));
    await tester.pump();
    await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
    inner.pending!.completeError(const HomeMindApiException('Owned timeout after close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });
}

class _DeferredQuota extends RecordingProfileService implements VoiceQuotaSource {
  _DeferredQuota(super.profile);
  Completer<UserProfile>? pending;
  int reads=0;
  @override
  Future<UserProfile> getMe() { reads++;return pending?.future ?? Future.value(profile); }
  @override
  Future<VoiceQuota?> getVoiceQuota() async => (await getMe()).voiceQuota;
}

class _QuotaFixture extends RecordingProfileService implements VoiceQuotaSource {
  _QuotaFixture(super.profile);
  int quotaReads=0;
  bool failQuota=false;
  @override
  Future<VoiceQuota?> getVoiceQuota() async {
    quotaReads++;
    if (failQuota) throw const FormatException('Owned quota failure');
    return profile.voiceQuota;
  }
}
class _CountingSpeech extends UnavailableSpeechRecognitionService {
  int initializations=0;
  @override
  Future<SpeechInitialization> initialize() {
    initializations++;
    return super.initialize();
  }
}
