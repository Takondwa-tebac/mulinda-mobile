import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_mode.dart';

/// Whether the screens are currently showing saved (cached) data, and when that
/// data was last fetched from the server.
class OfflineDataState {
  const OfflineDataState({this.servingCache = false, this.fetchedAt});

  final bool servingCache;
  final DateTime? fetchedAt;
}

class OfflineDataController extends Notifier<OfflineDataState> {
  @override
  OfflineDataState build() => const OfflineDataState();

  /// A request was answered from the cache.
  void markCache(DateTime fetchedAt) {
    // Keep the oldest timestamp on screen: "saved data from X" must not look
    // fresher than the stalest thing the user may be looking at.
    final current = state.fetchedAt;
    state = OfflineDataState(
      servingCache: true,
      fetchedAt: current != null && state.servingCache && current.isBefore(fetchedAt) ? current : fetchedAt,
    );
  }

  /// A live response arrived, so we are online and current again.
  void markLive() {
    if (state.servingCache) state = const OfflineDataState();
  }
}

final offlineDataProvider =
    NotifierProvider<OfflineDataController, OfflineDataState>(OfflineDataController.new);

/// Live "has a network connection" signal (a connection can still be unusable;
/// the request path handles that case separately).
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) =>
      r.isNotEmpty && r.any((e) => e != ConnectivityResult.none);

  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});

/// The offline banner shows only for users with offline mode on, while the
/// device is offline or screens are showing saved data.
final offlineBannerVisibleProvider = Provider<bool>((ref) {
  final active = ref.watch(offlineModeProvider).active;
  if (!active) return false;
  final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
  final serving = ref.watch(offlineDataProvider).servingCache;
  return !online || serving;
});

/// Slim bar telling the user they are looking at saved data.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineBannerVisibleProvider)) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final fetchedAt = ref.watch(offlineDataProvider).fetchedAt;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    final text = online
        ? 'Showing saved data — reconnecting…'
        : fetchedAt != null
            ? 'You\'re offline · showing data saved ${_when(fetchedAt)}'
            : 'You\'re offline · showing saved data';

    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 16, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      return 'today at $hh:$mm';
    }
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
}
