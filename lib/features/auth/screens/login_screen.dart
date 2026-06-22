import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_controller.dart';

/// Phase 0 login placeholder. Fields are non-functional; the "Sign in" button
/// performs a placeholder sign-in so the auth guard and app shell can be
/// exercised. Real login/register/Google flows arrive in the auth phase.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('auth.signIn'.tr(),
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              TextField(
                decoration: InputDecoration(labelText: 'auth.emailOrUsername'.tr()),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(labelText: 'auth.password'.tr()),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.read(authControllerProvider.notifier).devSignIn(),
                child: Text('auth.signIn'.tr()),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref.read(authControllerProvider.notifier).devSignIn(),
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: Text('auth.continueWithGoogle'.tr()),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: Text('auth.noAccount'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
