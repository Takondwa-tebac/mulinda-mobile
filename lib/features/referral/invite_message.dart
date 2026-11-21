import 'package:easy_localization/easy_localization.dart';

import 'data/referral_repository.dart';

/// The invite message to share: the API's `share_text` when it sent one,
/// otherwise the app's own copy with the link (the same wording as the API).
String inviteMessage(ReferralInfo info, String languageCode) {
  final fromApi = info.shareMessageOrNull(languageCode);
  if (fromApi != null) return fromApi;
  final days = info.rewardDays;
  return days == null
      ? 'referral.shareFallbackNoDays'.tr(namedArgs: {'link': info.link})
      : 'referral.shareFallback'.tr(namedArgs: {'link': info.link, 'days': '$days'});
}
