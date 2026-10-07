import 'package:flutter/material.dart';

import '../widgets/offline_sync_section.dart';

/// Everything about offline use in one place: the plan-gated Offline mode switch,
/// the data saved on the phone, and syncing what was captured or changed offline.
class OfflineSyncScreen extends StatelessWidget {
  const OfflineSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline capture & sync')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: const [
                Card(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: OfflineModeRow(),
                  ),
                ),
                SizedBox(height: 12),
                Card(child: SavedDataCard()),
                SizedBox(height: 12),
                Card(child: OfflineSyncSection()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
