import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/offline/offline_status.dart';
import '../../core/widgets/app_update_banner.dart';
import '../../core/widgets/scroll_aware_fab.dart';
import '../auth/providers/auth_controller.dart';
import '../auth/widgets/terms_update_dialog.dart';
import '../activity/data/activity_repository.dart';
import '../capture/data/inbox_repository.dart';
import '../../shared/plural.dart';

/// The signed-in shell: a 4-tab bottom nav with a central "＋" capture FAB.
/// The AI coach is intentionally NOT a tab — it's reached from Home and
/// contextual links — keeping the bar uncluttered.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _termsPrompted = false;

  /// Hides the capture button while a tab's list scrolls.
  final _fab = ScrollAwareFabController();

  @override
  void dispose() {
    _fab.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptTerms());
  }

  /// Prompt once per app session if the user is behind on the Terms. Re-checks
  /// the freshest user, so it works whether they were already loaded or arrive
  /// asynchronously after the shell mounts.
  void _maybePromptTerms() {
    if (_termsPrompted || !mounted) return;
    final user = ref.read(currentUserProvider);
    if (user != null && user.needsTermsAcceptance) {
      _termsPrompted = true;
      maybePromptTermsUpdate(context, ref);
    }
  }

  void _goBranch(int index) {
    // A new tab starts with the capture button showing.
    _fab.show();
    widget.navigationShell.goBranch(index, initialLocation: index == widget.navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    // Catch the user loading (or changing) after the first frame.
    ref.listen(currentUserProvider, (_, _) => _maybePromptTerms());

    final badgeCount = ref.watch(activityBadgeCountProvider);

    // Scroll notifications from every tab bubble up to this scope.
    return ScrollAwareFabScope(
      controller: _fab,
      child: Scaffold(
        body: Column(
          children: [
            // Offline mode: "showing saved data" bar. It handles the status-bar
            // inset itself, so the content below drops its own top padding.
            const OfflineBanner(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: ref.watch(offlineBannerVisibleProvider),
                child: Stack(
                  children: [
                    navigationShell,
                    // Floats over the content so it never shifts the layout.
                    const SafeArea(
                      child: Align(alignment: Alignment.topCenter, child: AppUpdateBanner()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Hide the capture FAB on the Profile tab (index 3) — it only clutters
        // and overlaps content there.
        floatingActionButton: navigationShell.currentIndex == 3
            ? null
            : ScrollAwareFab(
                child: FloatingActionButton(
                  tooltip: 'capture.title'.tr(),
                  onPressed: () => _showCaptureSheet(context),
                  child: const Icon(Icons.add),
                ),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _goBranch,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: 'nav.home'.tr(),
            ),
            NavigationDestination(
              icon: _ActivityIcon(count: badgeCount),
              selectedIcon: _ActivityIcon(count: badgeCount, selected: true),
              label: 'nav.activity'.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights),
              label: 'nav.plan'.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: 'nav.profile'.tr(),
            ),
          ],
        ),
      ),
    );
  }

  /// Close the capture sheet, then push the chosen capture route. The router is
  /// captured before popping so the sheet context can be safely torn down.
  void _open(BuildContext context, String route) {
    final router = GoRouter.of(context);
    _fab.show();
    Navigator.of(context).pop();
    router.push(route);
  }

  void _showCaptureSheet(BuildContext context) {
    _fab.show();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('capture.title'.tr(), style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            _CaptureTile(
              icon: Icons.document_scanner_outlined,
              label: 'capture.scanReceipt'.tr(),
              onTap: () => _open(context, Routes.scanReceipt),
            ),
            _CaptureTile(
              icon: Icons.sms_outlined,
              label: 'capture.pasteSms'.tr(),
              onTap: () => _open(context, Routes.pasteSms),
            ),
            _CaptureTile(
              icon: Icons.upload_file,
              label: 'activity2.bulkSmsImport'.tr(),
              onTap: () => _open(context, Routes.bulkSmsImport),
            ),
            _CaptureTile(
              icon: Icons.edit_outlined,
              label: 'capture.manual'.tr(),
              onTap: () => _open(context, Routes.addTransaction),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  const _ActivityIcon({required this.count, this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? Icons.receipt_long : Icons.receipt_long_outlined);
    if (count <= 0) return icon;
    return Semantics(
      label: trCount('activity2.badgeSemantics', count),
      child: Badge(label: Text(count > 99 ? '99+' : '$count'), child: icon),
    );
  }
}

/// The number on the Activity tab: inbox proposals waiting for approval plus
/// auto-recorded rows waiting for review. Rows that only need a category are
/// left out on purpose: most real accounts have many of them, so the badge
/// would sit at 99+ and stop meaning anything. Home's attention card covers them.
final activityBadgeCountProvider = Provider.autoDispose<int>((ref) {
  final inbox = ref.watch(pendingCountProvider);
  final review = ref.watch(reviewCountProvider).valueOrNull ?? 0;
  return inbox + review;
});
