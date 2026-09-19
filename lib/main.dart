import 'package:flutter/material.dart';

import 'dart:async';

import 'app/app_shell.dart';
import 'app/homemind_theme.dart';
import 'core/config/env_config.dart';
import 'core/config/plan_billing_visibility.dart';
import 'core/l10n/app_text.dart';
import 'features/assistant/domain/assistant_service.dart';
import 'features/auth/data/remote_auth_service.dart';
import 'features/auth/domain/auth_models.dart';
import 'features/auth/domain/auth_service.dart';
import 'features/auth/domain/account_auth_service.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/onboarding_page.dart';
import 'features/voice/domain/speech_recognition_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.load();
  await AppText.loadSaved();
  runApp(const HomeMindApp());
}

class HomeMindApp extends StatefulWidget {
  const HomeMindApp({
    this.authService,
    this.assistantService,
    this.speechService,
    this.initialSession,
    this.initialOnboardingCompleted,
    super.key,
  });

  final AuthService? authService;
  final AssistantService? assistantService;
  final SpeechRecognitionService? speechService;
  final AuthSession? initialSession;
  final bool? initialOnboardingCompleted;

  @override
  State<HomeMindApp> createState() => _HomeMindAppState();
}

class _HomeMindAppState extends State<HomeMindApp> {
  late final AuthService _authService;
  bool _isLoading = true;
  bool _hasSeenOnboarding = false;
  AuthSession? _currentSession;
  StreamSubscription<AuthSession?>? _authChanges;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? RemoteAuthService();
    final source = _authService;
    if (source is SessionRefreshService) {
      _authChanges = (source as SessionRefreshService).sessionChanges.listen((
        session,
      ) {
        if (mounted) setState(() => _currentSession = session);
      });
    }
    if (widget.initialSession != null) {
      _currentSession = widget.initialSession;
      AppText.setLanguage(widget.initialSession!.profile.language);
      _hasSeenOnboarding = true;
      _isLoading = false;
    } else if (widget.initialOnboardingCompleted == true) {
      _hasSeenOnboarding = true;
      _isLoading = false;
    } else {
      _checkInitialState();
    }
  }

  Future<void> _checkInitialState() async {
    bool seen;
    AuthSession? session;
    try {
      seen = await _authService.hasCompletedOnboarding();
      session = await _authService.getCurrentSession();
    } catch (_) {
      seen = true;
      session = null;
    }
    if (session != null) {
      AppText.setLanguage(session.profile.language);
    }
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = seen;
        _currentSession = session;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleOnboardingFinish() async {
    await _authService.setOnboardingCompleted();
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = true;
      });
    }
  }

  void _handleLoginSuccess(AuthSession session) {
    // Ngôn ngữ đã lưu trong hồ sơ tài khoản được áp dụng ngay khi đăng nhập.
    AppText.setLanguage(session.profile.language);
    setState(() {
      _currentSession = session;
      _hasSeenOnboarding = true;
    });
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      setState(() {
        _currentSession = null;
      });
    }
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    super.dispose();
  }

  Widget _home() => _isLoading
      ? const Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: CircularProgressIndicator(color: HomeMindTheme.primary),
          ),
        )
      : !_hasSeenOnboarding
      ? OnboardingPage(onFinish: _handleOnboardingFinish)
      : _currentSession == null
      ? LoginPage(
          authService: _authService,
          onLoginSuccess: _handleLoginSuccess,
          onBackToOnboarding: () {
            setState(() {
              _hasSeenOnboarding = false;
            });
          },
        )
      : HomeMindAppShell(
          key: ValueKey(
            'shell_${_currentSession!.profile.userId}_${_currentSession!.profile.workspaceId}_${_currentSession!.role}',
          ),
          authService: _authService,
          profile: _currentSession!.profile,
          assistantService: widget.assistantService,
          speechService: widget.speechService,
          onLogout: _handleLogout,
        );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppText.language,
      builder: (context, language, _) {
        return MaterialApp(
          key: ValueKey(
            'session_${_currentSession?.profile.userId}_${_currentSession?.profile.workspaceId}',
          ),
          title: 'HomeMind',
          debugShowCheckedModeBanner: false,
          theme: HomeMindTheme.themeData,
          builder: (context, child) => PlanBillingVisibility(
            fallbackBuilder: (_) => _home(),
            child: child!,
          ),
          home: _home(),
          // No named billing routes, return/next URL or restoration stack are
          // registered. Unhandled URLs always land on the existing auth/shell.
          initialRoute: '/',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _home(),
          ),
        );
      },
    );
  }
}
