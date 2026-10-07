import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/localization/ny_localizations.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'core/offline/offline_prefetch.dart';
import 'core/offline/offline_status.dart';
import 'core/offline/offline_mode.dart';
import 'core/offline/prefs.dart';
import 'core/offline/trusted_clock.dart';
import 'core/offline/offline_sync_runner.dart';
import 'core/security/app_lock.dart';
import 'core/security/screenshot_protection.dart';
import 'features/capture/data/sms_auto_capture.dart';
import 'features/capture/data/sms_background_sync.dart';
import 'features/capture/data/sms_manual_scanner.dart';
import 'features/capture/data/sms_outbox.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'features/auth/providers/auth_controller.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Firebase not configured for this platform (e.g. desktop dev) — skip.
  }
  await NotificationService.init();
  final prefs = await SharedPreferences.getInstance();
  TrustedClock.observeDevice(prefs);
  await SmsBackgroundSync.init();

  // Resume automatic SMS capture if the user previously opted in. No-op when
  // disabled, unsupported, or signed out.
  unawaited(SmsAutoCapture.instance.maybeStart());

  // Catch missed SMS on app open. Only runs for users who opted in to
  // auto-capture, never prompts, and only reads inbox messages after the
  // server-side baseline, so existing users never get history re-imported.
  // Anything captured while offline is synced first.
  unawaited(SmsManualScanner.instance.scanFinancialSms());

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ny'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'), // English is the default language.
      child: ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MulindaApp(),
      ),
    ),
  );
}

class MulindaApp extends ConsumerStatefulWidget {
  const MulindaApp({super.key});

  @override
  ConsumerState<MulindaApp> createState() => _MulindaAppState();
}

class _MulindaAppState extends ConsumerState<MulindaApp> with WidgetsBindingObserver {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  ProviderSubscription<AuthState>? _authSub;
  Uri? _pendingLink;
  Timer? _outboxTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The moment a connection comes back, sync what was queued offline.
    ref.listenManual(isOnlineProvider, (prev, next) {
      if (next.valueOrNull == true && prev?.valueOrNull != true) {
        _flushOutbox();
        _refreshOfflineData();
      }
    });
    // While the app is open, retry queued (offline-captured) SMS every 2 min.
    _outboxTimer = Timer.periodic(const Duration(minutes: 2), (_) => _flushOutbox());
    // Re-try a pending deep link, and register the FCM token, once auth resolves.
    _authSub = ref.listenManual(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.unknown) _flushPendingLink();
      if (next.status == AuthStatus.authenticated) {
        PushService.instance.registerToken(ref);
        _refreshOfflineData();
      }
    });
    _initDeepLinks();
    PushService.instance.init(ref);
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _onLink(initial);
    } catch (_) {
      // No initial link / unsupported platform.
    }
    _linkSub = _appLinks.uriLinkStream.listen(_onLink, onError: (_) {});
  }

  void _onLink(Uri uri) {
    final isReset = uri.host == 'reset-password' || uri.pathSegments.contains('reset-password');
    if (isReset) {
      _pendingLink = uri;
      _flushPendingLink();
    }
  }

  void _flushPendingLink() {
    final uri = _pendingLink;
    if (uri == null) return;
    if (ref.read(authControllerProvider).status == AuthStatus.unknown) return; // wait for splash
    _pendingLink = null;

    final target = Uri(
      path: Routes.resetPassword,
      queryParameters: {
        'token': uri.queryParameters['token'] ?? '',
        'email': uri.queryParameters['email'] ?? '',
      },
    ).toString();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(routerProvider).go(target));
  }

  /// Keep the data saved for offline use fresh (offline mode on, signed in, and
  /// the saved copy is more than a couple of hours old).
  void _refreshOfflineData() {
    if (ref.read(currentUserProvider) == null) return;
    unawaited(ref.read(offlinePrefetchProvider.notifier).start());
  }

  /// Send everything captured or changed offline: queued edits first (they can
  /// depend on one another), then SMS.
  Future<void> _flushOutbox() async {
    try {
      if (!mounted) return;
      await runMutationSync(ProviderScope.containerOf(context));
      if (await SmsOutbox.instance.pendingCount() > 0) {
        await SmsOutbox.instance.flush();
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Note the phone's time (it only ever moves the trusted value forward) and
      // re-check whether offline mode is still allowed.
      TrustedClock.observeDevice(ref.read(sharedPreferencesProvider));
      ref.invalidate(offlineModeProvider);
      _flushOutbox();
      _refreshOfflineData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _outboxTimer?.cancel();
    _linkSub?.cancel();
    _authSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Mulinda',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: [
        ...context.localizationDelegates,
        const NyMaterialLocalizations(),
        const NyCupertinoLocalizations(),
      ],
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      routerConfig: router,
      builder: (context, child) => AppLock(
        child: ScreenshotGuard(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
