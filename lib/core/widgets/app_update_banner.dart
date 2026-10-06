import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/dio_client.dart';

/// Gentle "update available" toast, shown only when the API reports a build
/// newer than the installed one. Floats over the content (never pushes the
/// layout down), hides itself after a few seconds, and stays away for that
/// release once the user closes it. Fails silently if the check can't run.
class AppUpdateBanner extends ConsumerStatefulWidget {
  const AppUpdateBanner({super.key});

  @override
  ConsumerState<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends ConsumerState<AppUpdateBanner> {
  static const _dismissedKey = 'app_update_banner_dismissed';
  static const _dismissedVersionKey = 'app_update_banner_dismissed_version';
  static const _autoHideAfter = Duration(seconds: 8);

  bool _visible = false;
  String? _latestVersion;
  String? _storeUrl;
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    try {
      final res = await ref
          .read(dioProvider)
          .get<Map<String, dynamic>>('/v1/app-version');
      final data = (res.data?['data'] as Map?)?.cast<String, dynamic>();
      final latest = data?['latest_version']?.toString();
      if (latest == null || latest.isEmpty) return;

      final installed = (await PackageInfo.fromPlatform()).version;
      if (_compareVersions(installed, latest) >= 0) return;

      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool(_dismissedKey) ?? false;
      if (dismissed && prefs.getString(_dismissedVersionKey) == latest) return;

      if (!mounted) return;
      setState(() {
        _latestVersion = latest;
        _storeUrl = data?['store_url']?.toString();
        _visible = true;
      });
      _autoHide = Timer(_autoHideAfter, () {
        if (mounted) setState(() => _visible = false);
      });
    } catch (_) {
      // Offline or endpoint unavailable — just don't show anything.
    }
  }

  /// Compares dotted versions numerically ("1.10.0" > "1.9.0"); ignores any
  /// "+build" or "-suffix" part. Returns <0, 0 or >0.
  static int _compareVersions(String a, String b) {
    List<int> parse(String v) => v
        .split(RegExp(r'[+-]'))
        .first
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final pa = parse(a);
    final pb = parse(b);
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  Future<void> _dismiss() async {
    _autoHide?.cancel();
    setState(() => _visible = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
    if (_latestVersion != null) {
      await prefs.setString(_dismissedVersionKey, _latestVersion!);
    }
  }

  Future<void> _openStore() async {
    final url = _storeUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: !_visible
          ? const SizedBox.shrink()
          : Padding(
              key: const ValueKey('update-banner'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: scheme.secondaryContainer,
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.system_update,
                        color: scheme.onSecondaryContainer,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _latestVersion == null
                              ? 'A new version is available'
                              : 'Version $_latestVersion is available',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      if (_storeUrl != null && _storeUrl!.isNotEmpty)
                        TextButton(
                          onPressed: _openStore,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: scheme.onSecondaryContainer,
                          ),
                          child: const Text(
                            'Update',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Dismiss',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: scheme.onSecondaryContainer,
                        ),
                        onPressed: _dismiss,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
