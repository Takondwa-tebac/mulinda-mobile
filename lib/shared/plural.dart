import 'package:easy_localization/easy_localization.dart';

/// `key.plural(count)` that never throws: before localization has started
/// (e.g. in widget tests) it falls back to the plain translation of [key].
String trCount(String key, int count) {
  try {
    return key.plural(count);
  } catch (_) {
    return key.tr(args: ['$count']);
  }
}
