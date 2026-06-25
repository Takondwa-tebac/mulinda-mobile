import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/ny_localizations.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'features/capture/data/sms_auto_capture.dart';
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

  // Resume automatic SMS capture if the user previously opted in. No-op when
  // disabled, unsupported, or signed out.
  unawaited(SmsAutoCapture.instance.maybeStart());

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ny'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('ny'), // Chichewa is the default language.
      child: const ProviderScope(child: MulindaApp()),
    ),
  );
}

class MulindaApp extends ConsumerStatefulWidget {
  const MulindaApp({super.key});

  @override
  ConsumerState<MulindaApp> createState() => _MulindaAppState();
}

class _MulindaAppState extends ConsumerState<MulindaApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  ProviderSubscription<AuthState>? _authSub;
  Uri? _pendingLink;

  @override
  void initState() {
    super.initState();
    // Re-try a pending deep link, and register the FCM token, once auth resolves.
    _authSub = ref.listenManual(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.unknown) _flushPendingLink();
      if (next.status == AuthStatus.authenticated) {
        PushService.instance.registerToken(ref);
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

  @override
  void dispose() {
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
    );
  }
}
