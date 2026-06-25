import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/permissions/permission_service.dart';
import '../../../core/router/routes.dart';
import '../../capture/data/sms_auto_capture.dart';
import '../onboarding_prefs.dart';

/// Explains and requests the permissions Mulinda uses, with an emphasis on the
/// SMS feature's privacy guarantees. Shown after the onboarding carousel; also
/// reachable from Profile. Everything here is optional — the user can continue
/// without granting anything.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key, this.fromOnboarding = false});

  /// When launched from onboarding, "Continue" marks onboarding seen and goes
  /// to login. From Profile it simply pops.
  final bool fromOnboarding;

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _smsBusy = false;
  bool _smsOn = false;
  bool _camera = false;
  bool _photos = false;
  bool _notifications = false;

  @override
  void initState() {
    super.initState();
    SmsAutoCapture.isEnabled().then((v) {
      if (mounted) setState(() => _smsOn = v);
    });
  }

  PermissionService get _perms => ref.read(permissionServiceProvider);

  Future<void> _toggleSms(bool value) async {
    setState(() => _smsBusy = true);
    try {
      if (value) {
        final ok = await SmsAutoCapture.instance.enableAndStart();
        if (!mounted) return;
        setState(() => _smsOn = ok);
        if (!ok) _snack('permissions.smsDenied'.tr());
      } else {
        await SmsAutoCapture.instance.disable();
        if (mounted) setState(() => _smsOn = false);
      }
    } finally {
      if (mounted) setState(() => _smsBusy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _continue() async {
    if (widget.fromOnboarding) {
      await OnboardingPrefs.markSeen();
      if (mounted) context.go(Routes.login);
    } else {
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('permissions.title'.tr()),
        automaticallyImplyLeading: !widget.fromOnboarding,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('permissions.intro'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 20),

            // SMS — the most sensitive, with full privacy explanation + toggle.
            _PermissionCard(
              icon: Icons.sms_outlined,
              title: 'permissions.smsTitle'.tr(),
              body: 'permissions.smsBody'.tr(),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('permissions.smsToggle'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                value: _smsOn,
                onChanged: _smsBusy ? null : _toggleSms,
              ),
            ),

            _PermissionCard(
              icon: Icons.photo_camera_outlined,
              title: 'permissions.cameraTitle'.tr(),
              body: 'permissions.cameraBody'.tr(),
              child: _AllowButton(
                granted: _camera,
                onPressed: () async {
                  final ok = await _perms.requestCamera();
                  if (mounted) setState(() => _camera = ok);
                },
              ),
            ),

            _PermissionCard(
              icon: Icons.photo_library_outlined,
              title: 'permissions.photosTitle'.tr(),
              body: 'permissions.photosBody'.tr(),
              child: _AllowButton(
                granted: _photos,
                onPressed: () async {
                  final ok = await _perms.requestPhotos();
                  if (mounted) setState(() => _photos = ok);
                },
              ),
            ),

            _PermissionCard(
              icon: Icons.notifications_outlined,
              title: 'permissions.notifTitle'.tr(),
              body: 'permissions.notifBody'.tr(),
              child: _AllowButton(
                granted: _notifications,
                onPressed: () async {
                  final ok = await _perms.requestNotifications();
                  if (mounted) setState(() => _notifications = ok);
                },
              ),
            ),

            const SizedBox(height: 8),
            Text('permissions.footer'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _continue,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(widget.fromOnboarding
                  ? 'permissions.continue'.tr()
                  : 'permissions.done'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(icon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4, fontSize: 13)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _AllowButton extends StatelessWidget {
  const _AllowButton({required this.granted, required this.onPressed});
  final bool granted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (granted) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 18),
            const SizedBox(width: 6),
            Text('permissions.allowed'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(onPressed: onPressed, child: Text('permissions.allow'.tr())),
    );
  }
}
