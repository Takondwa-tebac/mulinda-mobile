import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/activity/data/activity_repository.dart';
import '../../features/capture/data/sms_background_sync.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/plan/data/plan_repository.dart';
import 'mutation_sync.dart';

/// Replays queued offline changes and refreshes the screens they affect.
///
/// Used from the app (reconnect, resume, timer, "Sync now", right after a change
/// is queued). The background job calls [MutationSync.flush] directly, since it
/// has no UI to refresh.
Future<MutationFlushResult> runMutationSync(
  ProviderContainer container, {
  void Function(int done, int total)? onProgress,
}) async {
  final result = await MutationSync.instance.flush(onProgress: onProgress);
  if (result.changedAnything) refreshAfterSync(container);
  return result;
}

/// Reload the lists whose records may have changed on the server during a sync.
void refreshAfterSync(ProviderContainer container) {
  container
    ..invalidate(transactionsProvider)
    ..invalidate(accountsProvider)
    ..invalidate(dashboardProvider)
    ..invalidate(goalsProvider)
    ..invalidate(loansProvider);
}

/// A change was just queued: try to send it now, and ask the OS to sync it as
/// soon as there is a connection even if the app has been closed by then.
void onChangeQueued(ProviderContainer container) {
  unawaited(runMutationSync(container));
  unawaited(SmsBackgroundSync.syncWhenOnline());
}
