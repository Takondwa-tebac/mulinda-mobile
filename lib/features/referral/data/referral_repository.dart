import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

/// The person's invite code, link and score (`GET /referral`).
class ReferralInfo {
  const ReferralInfo({
    required this.code,
    required this.link,
    required this.signedUp,
    required this.rewarded,
    required this.daysEarned,
    this.rewardDays,
    this.shareText = const {},
  });

  final String code;
  final String link;

  /// Friends who created an account with the code.
  final int signedUp;

  /// Of those, the ones whose first money message arrived (both rewarded).
  final int rewarded;
  final int daysEarned;

  /// Premium days each side gets per friend; null when the API did not say.
  final int? rewardDays;

  /// The invite message by language code (`en`, `ny`).
  final Map<String, String> shareText;

  /// Friends who signed up but whose first money message has not arrived yet.
  int get waiting {
    final w = signedUp - rewarded;
    return w < 0 ? 0 : w;
  }

  /// The invite message in [languageCode], else English, else just the link.
  String shareMessage(String languageCode) => shareMessageOrNull(languageCode) ?? link;

  /// The API's invite message in [languageCode], else English, else null.
  String? shareMessageOrNull(String languageCode) => shareText[languageCode] ?? shareText['en'];

  factory ReferralInfo.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final share = json['share_text'];
    return ReferralInfo(
      code: json['code']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      signedUp: asInt(json['signed_up']),
      rewarded: asInt(json['rewarded']),
      daysEarned: asInt(json['days_earned']),
      rewardDays: int.tryParse(json['reward_days']?.toString() ?? ''),
      shareText: share is Map
          ? {
              for (final e in share.entries)
                if (e.value != null && e.value.toString().isNotEmpty) e.key.toString(): e.value.toString(),
            }
          : const {},
    );
  }
}

class ReferralRepository {
  const ReferralRepository(this._dio);

  final Dio _dio;

  Future<ReferralInfo> info() async {
    try {
      final res = await _dio.get('/v1/referral');
      return ReferralInfo.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Attach a code that arrived after sign-up (Play Install Referrer, a link
  /// opened later). The server ignores unknown or own codes and accounts
  /// that are too old or already referred.
  Future<void> claim(String code) async {
    try {
      await _dio.post('/v1/referral/claim', data: {'code': code});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final referralRepositoryProvider = Provider<ReferralRepository>(
  (ref) => ReferralRepository(ref.read(dioProvider)),
);

final referralInfoProvider = FutureProvider.autoDispose<ReferralInfo>(
  (ref) => ref.read(referralRepositoryProvider).info(),
);
