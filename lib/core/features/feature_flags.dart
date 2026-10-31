import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../network/dio_client.dart';

/// Server-side feature flags (admin tools > Feature flags), resolved for the
/// signed-in user. Fails closed: if the flags can't be read, every flag is off.
final featureFlagsProvider = FutureProvider<Map<String, bool>>((ref) async {
  // Flags are per user: re-read them when someone else signs in.
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return const {};
  try {
    final res = await ref.read(dioProvider).get('/v1/features');
    final data = (res.data['data'] as Map?) ?? const {};
    return data.map((k, v) => MapEntry(k.toString(), v == true));
  } on DioException {
    return const {};
  }
});

/// Keys of the flags the app reads.
abstract final class FeatureKeys {
  /// Read receipts on the phone (ML Kit + parser) before uploading. Off means
  /// the old path: upload the photo and let the server's AI read it.
  static const receiptOnDevice = 'receipt_on_device';
}

/// Whether [key] is on. False while loading, on error, and for flags an older
/// server doesn't know.
final featureEnabledProvider = Provider.family<bool, String>(
  (ref, key) => ref.watch(featureFlagsProvider).valueOrNull?[key] ?? false,
);
