import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/screens/activity_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/coach/screens/coach_screen.dart';
import '../../features/dashboard/screens/home_screen.dart';
import '../../features/onboarding/screens/income_setup_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/splash_screen.dart';
import '../../features/plan/screens/plan_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/shell/app_shell.dart';
import 'routes.dart';

/// App router with an auth guard driven by [authControllerProvider].
final routerProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod auth changes to GoRouter's refresh mechanism.
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final loc = state.matchedLocation;

      // While we don't yet know, sit on the splash screen.
      if (status == AuthStatus.unknown) {
        return loc == Routes.splash ? null : Routes.splash;
      }

      const authFlow = {
        Routes.splash,
        Routes.onboarding,
        Routes.login,
        Routes.register,
        Routes.forgotPassword,
      };
      final onAuthFlow = authFlow.contains(loc);

      if (status == AuthStatus.unauthenticated) {
        return onAuthFlow ? null : Routes.onboarding;
      }

      // Authenticated. First-run: declare income bracket before the app proper.
      final user = ref.read(authControllerProvider).user;
      final needsIncomeSetup = user != null && user.declaredIncomeBracket == null;
      if (needsIncomeSetup) {
        return loc == Routes.incomeSetup ? null : Routes.incomeSetup;
      }

      // Keep them out of the auth flow and the (now-complete) setup screen.
      if (onAuthFlow || loc == Routes.incomeSetup) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: Routes.incomeSetup, builder: (_, _) => const IncomeSetupScreen()),
      GoRoute(
        path: Routes.coach,
        builder: (_, _) => const CoachScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.activity, builder: (_, _) => const ActivityScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.plan, builder: (_, _) => const PlanScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});
