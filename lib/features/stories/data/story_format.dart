import 'dart:math' as math;

import '../../../core/money/money.dart';
import '../../../core/money/money_json.dart';
import 'story_models.dart';

/// `MK 310,000`: a story amount, without the `.00` of a whole amount.
String storyAmount(Money money) => formatMinorShort(money.minorUnits, money.currency);

/// `35%` from a share (0..1, or more for "130% of what came in").
String storyPercent(double share) => '${(share * 100).round()}%';

/// `1,846`: a count with thousands separators.
String groupCount(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// What the "came in / went out" slide shows. With amounts hidden, each side
/// is a percentage of the larger of the two (so what came in is usually
/// 100%); with amounts shown, the amounts. The bars are the same either way.
class InOutFigures {
  const InOutFigures({required this.inLabel, required this.outLabel, required this.inBar, required this.outBar});

  final String inLabel;
  final String outLabel;

  /// Bar lengths (0..1), the larger side is 1.
  final double inBar;
  final double outBar;

  /// Null when there is nothing to compare (no income and no spending).
  static InOutFigures? of(MoneyStory story, {required bool amounts}) {
    final income = story.income;
    final spending = story.spending;
    if (income == null || spending == null) return null;
    final inMinor = income.minorUnits.abs();
    final outMinor = spending.minorUnits.abs();
    final larger = math.max(inMinor, outMinor);
    if (larger == 0) return null;
    final inBar = inMinor / larger;
    final outBar = outMinor / larger;
    return InOutFigures(
      inLabel: amounts ? storyAmount(income) : storyPercent(inBar),
      outLabel: amounts ? storyAmount(spending) : storyPercent(outBar),
      inBar: inBar,
      outBar: outBar,
    );
  }
}

/// A category's figure: its share of spending, or its amount.
String categoryValue(StoryCategory c, {required bool amounts}) => amounts ? storyAmount(c.amount) : storyPercent(c.share);

/// Bar lengths for the top categories, the biggest one being 1.
List<double> categoryBars(List<StoryCategory> cats) {
  if (cats.isEmpty) return const [];
  final top = cats.map((c) => c.share).reduce(math.max);
  return [for (final c in cats) top > 0 ? (c.share / top).clamp(0.0, 1.0) : 0.0];
}

/// The biggest day's figure: its amount, or its share of the period's spending.
String biggestDayValue(StoryDay d, {required bool amounts}) => amounts ? storyAmount(d.amount) : storyPercent(d.share);

/// The biggest month's share of the year's spending (0..1), from the months
/// list and the year's total; null when either is missing.
double? biggestMonthShare(MoneyStory story) {
  final key = story.biggestMonth;
  final total = story.spending?.minorUnits ?? 0;
  if (key == null || total <= 0) return null;
  for (final m in story.months) {
    if (m.key == key) return (m.spending.minorUnits / total).clamp(0.0, 1.0);
  }
  return null;
}

/// The biggest month's bar, or null.
StoryMonthBar? biggestMonthBar(MoneyStory story) {
  for (final m in story.months) {
    if (m.key == story.biggestMonth) return m;
  }
  return null;
}

/// The month number (1 to 12) of a `2026-03` key, or null.
int? monthOfKey(String? key) {
  if (key == null || key.length < 7) return null;
  final m = int.tryParse(key.substring(5, 7));
  return m != null && m >= 1 && m <= 12 ? m : null;
}
