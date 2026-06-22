import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text('app.name'.tr())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text('home.greeting'.tr(), style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          // "Ask Mulinda" coach entry — prominent, reachable from Home.
          Card(
            color: scheme.primaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.auto_awesome),
              ),
              title: Text('home.askCoach'.tr(),
                  style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
              trailing: Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
              onTap: () => context.push(Routes.coach),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('common.comingSoon'.tr(),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}
