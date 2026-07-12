import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import 'biometric_service.dart';

/// Wraps the app to enforce a biometric lock: locks on cold start (when a
/// session already exists) and whenever the app returns from the background,
/// and offers a one-time prompt to enable the feature after login.
class AppLock extends ConsumerStatefulWidget {
  const AppLock({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLock> createState() => _AppLockState();
}

class _AppLockState extends ConsumerState<AppLock> with WidgetsBindingObserver {
  bool _locked = false;
  bool _authing = false;
  bool _wasBackgrounded = false;
  bool _launching = true;
  bool _promptedThisSession = false;

  BiometricService get _bio => ref.read(biometricServiceProvider);
  bool get _authed =>
      ref.read(authControllerProvider).status == AuthStatus.authenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _lockIfEnabled();
    }
  }

  Future<void> _lockIfEnabled() async {
    if (_locked || !_authed) return;
    if (await _bio.isEnabled()) {
      setState(() => _locked = true);
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authing) return;
    _authing = true;
    final ok = await _bio.authenticate('security.unlockReason'.tr());
    _authing = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  /// Cold start with a restored session → lock; otherwise (or if disabled) maybe
  /// offer to enable.
  Future<void> _onColdStartAuthenticated() async {
    if (await _bio.isEnabled()) {
      setState(() => _locked = true);
      _authenticate();
    } else {
      _maybePromptEnable();
    }
  }

  Future<void> _maybePromptEnable() async {
    if (_promptedThisSession || !mounted) return;
    _promptedThisSession = true;
    if (await _bio.isEnabled() || await _bio.promptDismissed()) return;
    if (!await _bio.isAvailable() || !await _bio.hasEnrolledBiometrics()) return;
    if (!mounted) return;

    final enable = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('security.enableTitle'.tr()),
        content: Text('security.enableBody'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('security.notNow'.tr())),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('security.enable'.tr())),
        ],
      ),
    );

    if (enable == true) {
      if (await _bio.authenticate('security.unlockReason'.tr())) {
        await _bio.setEnabled(true);
      }
    } else {
      await _bio.dismissPrompt(); // don't ask again
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to auth resolution: cold-start lock vs post-login enable prompt.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.unknown) return;
      final wasLaunching = _launching;
      _launching = false;
      if (next.status == AuthStatus.authenticated) {
        if (wasLaunching) {
          _onColdStartAuthenticated();
        } else {
          _maybePromptEnable(); // fresh login — don't lock, just offer
        }
      } else {
        _promptedThisSession = false;
        if (_locked) setState(() => _locked = false);
      }
    });

    return Stack(
      children: [
        widget.child,
        if (_locked) _LockOverlay(onUnlock: _authenticate),
      ],
    );
  }
}

class _LockOverlay extends ConsumerWidget {
  const _LockOverlay({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Material(
        color: scheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.lock_outline, size: 40),
              ),
              const SizedBox(height: 20),
              Text('security.lockedTitle'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint),
                label: Text('security.unlock'.tr()),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                child: Text('profile.logOut'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
