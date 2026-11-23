import 'package:easy_localization/easy_localization.dart';

import '../data/admin_user.dart';

/// "14 Jul 2026", with month names from the translations.
String adminDate(DateTime? at) {
  if (at == null) return 'admin.user.notSet'.tr();
  return '${at.day} ${'common.monthShort.${at.month}'.tr()} ${at.year}';
}

/// "14 Jul 2026, 08:42".
String adminDateTime(DateTime? at) {
  if (at == null) return 'admin.user.never'.tr();
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  return '${adminDate(at)}, $hh:$mm';
}

/// "Just now", "5 min ago", "2 h ago", "3 days ago", "4 months ago".
String adminAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return 'admin.user.never'.tr();
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'admin.user.justNow'.tr();
  if (diff.inHours < 1) return 'admin.user.minutesAgo'.tr(args: ['${diff.inMinutes}']);
  if (diff.inDays < 1) return 'admin.user.hoursAgo'.tr(args: ['${diff.inHours}']);
  if (diff.inDays < 60) return _count('admin.user.daysAgo', diff.inDays);
  return _count('admin.user.monthsAgo', diff.inDays ~/ 30);
}

/// "Ends today" or "19 days left" until [end].
String adminLeft(DateTime? end, {DateTime? now}) {
  if (end == null) return '';
  final n = now ?? DateTime.now();
  final days = DateTime(end.year, end.month, end.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (days <= 0) return 'admin.user.endsToday'.tr();
  return _count('admin.user.daysLeft', days);
}

/// "1 day ago" or "3 days ago": the `.one` or `.other` string under [key].
String _count(String key, int n) => n == 1 ? '$key.one'.tr() : '$key.other'.tr(args: ['$n']);

/// "Super-admin", "Admin", "User", or the raw name for other roles.
String adminRoleLabel(String role) => switch (role) {
  'super-admin' => 'admin.user.role.superAdmin'.tr(),
  'admin' => 'admin.user.role.admin'.tr(),
  'user' => 'admin.user.role.user'.tr(),
  _ => role,
};

/// "Paid", "Gift from an admin", "Free trial", or the raw source.
String adminSourceLabel(String? source) => switch (source) {
  'payment' => 'admin.user.source.payment'.tr(),
  'credit' => 'admin.user.source.credit'.tr(),
  'trial' => 'admin.user.source.trial'.tr(),
  null => 'admin.user.notSet'.tr(),
  _ => source,
};

/// The income bracket label used in onboarding ("Middle income").
String adminIncomeLabel(String? bracket) {
  const keys = {
    'low': 'low',
    'lower_middle': 'lowerMiddle',
    'middle': 'middle',
    'upper_middle': 'upperMiddle',
    'upper': 'upper',
  };
  final key = keys[bracket];
  if (key != null) return 'income.$key.label'.tr();
  return bracket ?? 'admin.user.notSet'.tr();
}

/// The plan in a few words: "Monthly", "Trial · 3-Day Pass" or "Free plan".
String adminPlanLine(AdminUser user) {
  final sub = user.subscription;
  if (sub == null) return 'admin.user.freePlan'.tr();
  final label = sub.planLabel ?? 'admin.user.status.active'.tr();
  return sub.isTrial ? 'admin.user.trialPlan'.tr(args: [label]) : label;
}
