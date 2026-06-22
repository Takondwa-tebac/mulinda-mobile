import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The signed-in shell: a 4-tab bottom nav with a central "＋" capture FAB.
/// The AI coach is intentionally NOT a tab — it's reached from Home and
/// contextual links — keeping the bar uncluttered.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCaptureSheet(context),
        child: const Icon(Icons.add),
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
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
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
    );
  }

  void _showCaptureSheet(BuildContext context) {
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
                child: Text('capture.title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            _CaptureTile(icon: Icons.document_scanner_outlined, label: 'capture.scanReceipt'.tr()),
            _CaptureTile(icon: Icons.sms_outlined, label: 'capture.pasteSms'.tr()),
            _CaptureTile(icon: Icons.edit_outlined, label: 'capture.manual'.tr()),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

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
      onTap: () => Navigator.of(context).pop(),
    );
  }
}
