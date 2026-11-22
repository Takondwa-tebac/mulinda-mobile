import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/plural.dart';
import '../data/story_format.dart';
import '../data/story_models.dart';
import 'story_motion.dart';
import 'story_player.dart';
import 'story_slide_parts.dart';

/// Slide backgrounds, as in the prototypes.
abstract class StoryBackgrounds {
  static const month = [
    AppColors.onTeal,
    AppColors.onTealPale,
    AppColors.onTeal,
    AppColors.onOrange,
    AppColors.onTealPale,
    AppColors.onTeal,
    AppColors.onTealPale,
    AppColors.tealDeep,
  ];
  static const year = [
    AppColors.onTeal,
    AppColors.onTealPale,
    AppColors.onTeal,
    AppColors.onOrange,
    AppColors.onTealPale,
    AppColors.onTeal,
    AppColors.onTealPale,
    AppColors.onTeal,
    AppColors.tealDeep,
  ];
}

String monthName(int month) => 'common.monthLong.$month'.tr();

const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

String weekdayName(String slug) => 'stories.weekday.$slug'.tr();

/// `School fees, Rent and a new phone`.
String joinNames(List<String> names) {
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} ${'stories.and'.tr()} ${names.last}';
}

/// "My October" / "My 2026": the story's short title.
String storyTitle(MoneyStory s) {
  final m = s.period.month;
  return m == null
      ? 'stories.myYear'.tr(namedArgs: {'year': '${s.period.year}'})
      : 'stories.myMonth'.tr(namedArgs: {'month': monthName(m)});
}

/// The month story's slides (the prototype's 8), leaving out any whose data
/// is missing. [share] builds the last slide.
List<StorySlide> monthStorySlides(MoneyStory s, {required bool amounts, required WidgetBuilder share}) {
  const bg = StoryBackgrounds.month;
  final month = s.period.month ?? 1;
  final slides = <StorySlide>[
    StorySlide(
      id: 'intro',
      background: bg[0],
      builder: (_) => storyColumn([
        StoryReveal(
          child: Text('${monthName(month).toUpperCase()} ${s.period.year}', style: StoryType.eyebrow),
        ),
        const StoryGap(AppSpacing.md),
        StoryReveal(
          delay: Reveal.a2,
          child: Text(
            'stories.month.introTitle'.tr(),
            style: const TextStyle(fontSize: 44, fontWeight: StoryType.heavy, height: 1.02, letterSpacing: -1.5),
          ),
        ),
        const StoryGap(AppSpacing.lg),
        StoryReveal(
          delay: Reveal.a3,
          child: Text('stories.month.introBody'.tr(), style: StoryType.body.copyWith(fontSize: 17)),
        ),
      ]),
    ),
  ];

  final messages = s.messagesRecorded ?? 0;
  if (messages > 0) {
    slides.add(
      StorySlide(
        id: 'messages',
        background: bg[1],
        builder: (_) => storyColumn([
          StoryReveal(child: Text('stories.month.messagesLead'.tr(), style: StoryType.leadLight)),
          const StoryGap(10),
          StoryReveal(kind: RevealKind.pop, delay: Reveal.pop, child: StoryHero(groupCount(messages), size: 120)),
          const StoryGap(10),
          StoryReveal(delay: Reveal.a3, child: Text(trCount('stories.messagesUnit', messages), style: StoryType.statement)),
          const StoryGap(AppSpacing.lg),
          StoryReveal(delay: Reveal.a4, child: Text('stories.month.messagesBody'.tr(), style: StoryType.body)),
        ]),
      ),
    );
  }

  final inOut = InOutFigures.of(s, amounts: amounts);
  if (inOut != null) {
    slides.add(
      StorySlide(
        id: 'in-out',
        background: bg[2],
        builder: (_) {
          final f = InOutFigures.of(s, amounts: amounts)!;
          final kept = keptLine(s.keptRatio);
          Widget side(String label, String value, double bar, Color color, double barDelay) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: StoryType.body.copyWith(fontSize: 14)),
              StoryHero(value, size: 36, color: AppColors.white),
              const SizedBox(height: 6),
              StoryGrowBar(fraction: bar, color: color, height: 18, delay: barDelay),
            ],
          );
          return storyColumn([
            StoryReveal(child: Text('stories.month.inOutTitle'.tr(), style: StoryType.lead.copyWith(fontSize: 26))),
            const StoryGap(AppSpacing.xxl),
            StoryReveal(delay: Reveal.a2, child: side('stories.in'.tr(), f.inLabel, f.inBar, AppColors.teal, Reveal.bar)),
            const StoryGap(AppSpacing.xl),
            StoryReveal(delay: Reveal.a3, child: side('stories.out'.tr(), f.outLabel, f.outBar, AppColors.orange, 1.2)),
            if (kept != null) ...[
              const StoryGap(28),
              StoryReveal(
                delay: Reveal.a4,
                child: Text(kept, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ]);
        },
      ),
    );
  }

  if (s.topCategories.isNotEmpty) {
    slides.add(
      StorySlide(
        id: 'categories',
        background: bg[3],
        builder: (_) {
          final cats = s.topCategories.take(3).toList();
          final bars = categoryBars(cats);
          return storyColumn([
            StoryReveal(child: Text('stories.month.topLead'.tr(), style: StoryType.lead)),
            const StoryGap(14),
            StoryReveal(
              kind: RevealKind.spin,
              delay: Reveal.spin,
              child: Text(
                cats.first.name,
                style: const TextStyle(fontSize: 48, fontWeight: StoryType.heavy, height: 1.02, color: AppColors.orange),
              ),
            ),
            const StoryGap(26),
            StoryReveal(
              delay: Reveal.a3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < cats.length; k++) ...[
                    if (k > 0) const SizedBox(height: 14),
                    StoryBarRow(
                      label: '${k + 1} · ${cats[k].name}',
                      value: categoryValue(cats[k], amounts: amounts),
                      fraction: bars[k],
                      color: k == 0 ? AppColors.orange : AppColors.teal,
                      bold: k == 0,
                    ),
                  ],
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }

  final day = s.biggestDay;
  if (day != null) {
    slides.add(
      StorySlide(
        id: 'biggest-day',
        background: bg[4],
        builder: (_) => storyColumn([
          StoryReveal(child: Text('stories.month.bigDayLead'.tr(), style: StoryType.lead)),
          const StoryGap(18),
          StoryReveal(kind: RevealKind.pop, delay: Reveal.pop, child: _CalendarTile(date: day.date)),
          const StoryGap(18),
          StoryReveal(
            delay: Reveal.a3,
            child: Text(
              amounts
                  ? 'stories.bigDayAmount'.tr(namedArgs: {'amount': biggestDayValue(day, amounts: true)})
                  : 'stories.bigDayShare'.tr(namedArgs: {'percent': biggestDayValue(day, amounts: false)}),
              style: const TextStyle(fontSize: 28, fontWeight: StoryType.heavy, height: 1.15),
            ),
          ),
        ]),
      ),
    );
  }

  final style = s.moneyStyle;
  if (style != null) {
    slides.add(
      StorySlide(
        id: 'style',
        background: bg[5],
        builder: (_) => _styleSlide(style, 'stories.month.styleLead'.tr()),
      ),
    );
  }

  final change = s.changeVsPrevious;
  if (change != null) {
    final prevMonth = monthOfKey(change.previousKey) ?? (month == 1 ? 12 : month - 1);
    slides.add(
      StorySlide(
        id: 'change',
        background: bg[6],
        builder: (_) {
          final budgets = s.budgets;
          return storyColumn([
            StoryReveal(
              child: Text('stories.month.changeLead'.tr(namedArgs: {'month': monthName(prevMonth)}), style: StoryType.lead),
            ),
            const StoryGap(20),
            if (change.isLess || change.isMore) ...[
              StoryReveal(
                kind: RevealKind.pop,
                delay: Reveal.pop,
                child: Row(
                  children: [
                    Icon(
                      change.isLess ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      size: 64,
                      color: change.isLess ? AppColors.teal : AppColors.orange,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(child: StoryHero('${change.percent}%', size: 96, color: AppColors.white)),
                  ],
                ),
              ),
              const StoryGap(20),
              StoryReveal(
                delay: Reveal.a3,
                child: Text(
                  (change.isLess ? 'stories.changeLess' : 'stories.changeMore').tr(),
                  style: StoryType.statement.copyWith(fontSize: 26),
                ),
              ),
            ] else
              StoryReveal(
                kind: RevealKind.pop,
                delay: Reveal.pop,
                child: Text(
                  'stories.changeSame'.tr(namedArgs: {'month': monthName(prevMonth)}),
                  style: StoryType.statement.copyWith(fontSize: 32),
                ),
              ),
            if (budgets != null) ...[
              const StoryGap(14),
              StoryReveal(
                delay: Reveal.a4,
                child: Text(
                  'stories.budgetsLine'.tr(namedArgs: {'kept': '${budgets.kept}', 'total': '${budgets.total}'}),
                  style: StoryType.body,
                ),
              ),
            ],
          ]);
        },
      ),
    );
  }

  slides.add(StorySlide(id: 'share', background: bg[7], builder: share));
  return slides;
}

/// The year story's slides (the prototype's 9), leaving out any whose data
/// is missing. [share] builds the last slide.
List<StorySlide> yearStorySlides(MoneyStory s, {required bool amounts, required WidgetBuilder share}) {
  const bg = StoryBackgrounds.year;
  final year = '${s.period.year}';
  final from = s.period.startsOn;
  final to = s.period.endsOn;
  final slides = <StorySlide>[
    StorySlide(
      id: 'intro',
      background: bg[0],
      builder: (_) => storyColumn([
        StoryReveal(kind: RevealKind.pop, delay: Reveal.pop, child: StoryHero(year, size: 110)),
        const StoryGap(AppSpacing.lg),
        StoryReveal(
          delay: Reveal.a3,
          child: Text(
            'stories.year.introTitle'.tr(),
            style: const TextStyle(fontSize: 38, fontWeight: StoryType.heavy, height: 1.05),
          ),
        ),
        if (from != null && to != null) ...[
          const StoryGap(AppSpacing.lg),
          StoryReveal(
            delay: Reveal.a4,
            child: Text(
              'stories.year.introBody'.tr(
                namedArgs: {'from': '${from.day} ${monthName(from.month)}', 'to': '${to.day} ${monthName(to.month)}'},
              ),
              style: StoryType.body,
            ),
          ),
        ],
      ]),
    ),
  ];

  final messages = s.messagesRecorded ?? 0;
  if (messages > 0) {
    final perDay = (s.messagesPerDay ?? 0).round();
    slides.add(
      StorySlide(
        id: 'messages',
        background: bg[1],
        builder: (_) => storyColumn([
          StoryReveal(child: Text('stories.year.messagesLead'.tr(), style: StoryType.leadLight)),
          const StoryGap(10),
          StoryReveal(kind: RevealKind.pop, delay: Reveal.pop, child: StoryHero(groupCount(messages), size: 104)),
          const StoryGap(10),
          StoryReveal(delay: Reveal.a3, child: Text(trCount('stories.messagesUnit', messages), style: StoryType.statement)),
          if (perDay >= 1) ...[
            const StoryGap(14),
            StoryReveal(
              delay: Reveal.a4,
              child: Text('stories.year.perDay'.tr(namedArgs: {'count': '$perDay'}), style: StoryType.body),
            ),
          ],
        ]),
      ),
    );
  }

  final biggest = biggestMonthBar(s);
  if (s.months.isNotEmpty && biggest != null) {
    slides.add(
      StorySlide(
        id: 'months',
        background: bg[2],
        builder: (_) {
          final share = biggestMonthShare(s);
          final name = monthName(biggest.month);
          final detail = amounts
              ? 'stories.year.biggestMonthAmount'.tr(namedArgs: {'amount': storyAmount(biggest.spending), 'month': name})
              : (share == null ? null : 'stories.year.biggestMonthShare'.tr(namedArgs: {'percent': storyPercent(share)}));
          return storyColumn([
            StoryReveal(child: Text('stories.year.monthsLead'.tr(), style: StoryType.lead)),
            const StoryGap(AppSpacing.xl),
            StoryReveal(
              delay: Reveal.a2,
              child: SizedBox(
                height: 220,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var k = 0; k < s.months.length; k++) ...[
                      if (k > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: StoryRiseColumn(
                                fraction: s.months[k].shareOfMax,
                                color: s.months[k].key == s.biggestMonth ? AppColors.orange : AppColors.teal,
                                delay: 0.5 + k * 0.08,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ExcludeSemantics(
                              child: Text(
                                monthName(s.months[k].month).characters.first,
                                style: const TextStyle(fontSize: 11, color: AppColors.tealPale),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const StoryGap(AppSpacing.sm),
            StoryReveal(
              delay: Reveal.a3,
              child: Text(
                'stories.year.biggestMonth'.tr(namedArgs: {'month': name}),
                style: StoryType.statement,
              ),
            ),
            if (detail != null) ...[
              const StoryGap(AppSpacing.sm),
              StoryReveal(delay: Reveal.a4, child: Text(detail, style: StoryType.body)),
            ],
          ]);
        },
      ),
    );
  }

  if (s.topCategories.isNotEmpty) {
    slides.add(
      StorySlide(
        id: 'categories',
        background: bg[3],
        builder: (_) {
          final top = s.topCategories.first;
          final rest = s.topCategories.skip(1).take(2).map((c) => c.name).toList();
          return storyColumn([
            StoryReveal(child: Text('stories.year.topLead'.tr(), style: StoryType.lead)),
            const StoryGap(AppSpacing.lg),
            StoryReveal(
              kind: RevealKind.pop,
              delay: Reveal.pop,
              child: Text(
                top.name,
                style: const TextStyle(fontSize: 50, fontWeight: StoryType.heavy, height: 1.02, color: AppColors.orange),
              ),
            ),
            const StoryGap(AppSpacing.lg),
            StoryReveal(
              delay: Reveal.a3,
              child: Text(
                amounts
                    ? 'stories.year.topAmount'.tr(namedArgs: {'amount': storyAmount(top.amount), 'category': top.name})
                    : 'stories.year.topShare'.tr(namedArgs: {'percent': storyPercent(top.share)}),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            if (rest.isNotEmpty) ...[
              const StoryGap(AppSpacing.md),
              StoryReveal(
                delay: Reveal.a4,
                child: Text(
                  rest.length == 1
                      ? 'stories.year.then1'.tr(namedArgs: {'a': rest[0]})
                      : 'stories.year.then2'.tr(namedArgs: {'a': rest[0], 'b': rest[1]}),
                  style: StoryType.body,
                ),
              ),
            ],
          ]);
        },
      ),
    );
  }

  final person = s.topCounterparty;
  if (person != null && person.count > 0) {
    slides.add(
      StorySlide(
        id: 'person',
        background: bg[4],
        builder: (_) => storyColumn([
          StoryReveal(child: Text('stories.year.personLead'.tr(), style: StoryType.lead)),
          const StoryGap(22),
          StoryReveal(
            kind: RevealKind.pop,
            delay: Reveal.pop,
            child: ExcludeSemantics(
              child: Container(
                width: 120,
                height: 120,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle),
                child: Text(
                  person.name.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 48, fontWeight: StoryType.heavy, color: AppColors.onTeal),
                ),
              ),
            ),
          ),
          const StoryGap(22),
          StoryReveal(
            delay: Reveal.a3,
            child: Text(person.name, style: const TextStyle(fontSize: 40, fontWeight: StoryType.heavy, height: 1.1)),
          ),
          const StoryGap(AppSpacing.sm),
          StoryReveal(
            delay: Reveal.a4,
            child: Text(trCount('stories.year.personTimes', person.count), style: StoryType.body.copyWith(fontSize: 18)),
          ),
        ]),
      ),
    );
  }

  final place = s.topMerchant;
  if (place != null && place.count > 0) {
    final weekday = _weekdays.contains(place.topWeekday) ? place.topWeekday : null;
    slides.add(
      StorySlide(
        id: 'place',
        background: bg[5],
        builder: (_) => storyColumn([
          StoryReveal(child: Text('stories.year.placeLead'.tr(), style: StoryType.lead)),
          const StoryGap(AppSpacing.lg),
          StoryReveal(
            kind: RevealKind.pop,
            delay: Reveal.pop,
            child: Text(
              place.name,
              style: const TextStyle(fontSize: 48, fontWeight: StoryType.heavy, height: 1.05, color: AppColors.orange),
            ),
          ),
          const StoryGap(AppSpacing.lg),
          StoryReveal(
            delay: Reveal.a3,
            child: Text(
              trCount('stories.year.visits', place.count),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          if (weekday != null) ...[
            const StoryGap(10),
            StoryReveal(
              delay: Reveal.a4,
              child: Text('stories.year.weekday'.tr(namedArgs: {'day': weekdayName(weekday)}), style: StoryType.body),
            ),
          ],
        ]),
      ),
    );
  }

  final goals = s.goalsReached;
  if (goals != null && goals.count > 0) {
    slides.add(
      StorySlide(
        id: 'goals',
        background: bg[6],
        builder: (_) {
          final saved = goals.saved;
          final savedLine = amounts && saved != null && saved.minorUnits > 0
              ? 'stories.year.goalsSaved'.tr(namedArgs: {'amount': storyAmount(saved)})
              : 'stories.year.goalsDone'.tr();
          return storyColumn([
            StoryReveal(child: Text('stories.year.goalsLead'.tr(), style: StoryType.lead)),
            const StoryGap(22),
            StoryReveal(
              kind: RevealKind.pop,
              delay: Reveal.pop,
              child: Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                child: Container(
                  width: 116,
                  height: 116,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg[6], shape: BoxShape.circle),
                  child: Text('${goals.count}', style: const TextStyle(fontSize: 46, fontWeight: StoryType.heavy)),
                ),
              ),
            ),
            const StoryGap(22),
            if (goals.names.isNotEmpty)
              StoryReveal(
                delay: Reveal.a3,
                child: Text('${joinNames(goals.names)}.', style: StoryType.statement.copyWith(fontSize: 26)),
              ),
            const StoryGap(10),
            StoryReveal(delay: Reveal.a4, child: Text(savedLine, style: StoryType.body)),
          ]);
        },
      ),
    );
  }

  final style = s.moneyStyle;
  if (style != null) {
    slides.add(
      StorySlide(
        id: 'style',
        background: bg[7],
        builder: (_) => _styleSlide(style, 'stories.year.styleLead'.tr(namedArgs: {'year': year})),
      ),
    );
  }

  slides.add(StorySlide(id: 'share', background: bg[8], builder: share));
  return slides;
}

/// "You kept 35% of what came in." (or spent more than came in); null
/// without income.
String? keptLine(double? keptRatio) {
  if (keptRatio == null) return null;
  final pct = storyPercent(keptRatio.abs());
  return keptRatio < 0
      ? 'stories.overspentLine'.tr(namedArgs: {'percent': pct})
      : 'stories.keptLine'.tr(namedArgs: {'percent': pct});
}

Widget _styleSlide(MoneyStyle style, String lead) => storyColumn([
  StoryReveal(child: Text(lead, style: StoryType.leadLight)),
  const StoryGap(22),
  StoryReveal(kind: RevealKind.spin, delay: Reveal.spin, child: StyleBadge(icon: style.icon)),
  const StoryGap(22),
  StoryReveal(delay: Reveal.a3, child: Text(style.titleKey.tr(), style: StoryType.title)),
  const StoryGap(AppSpacing.md),
  StoryReveal(delay: Reveal.a4, child: Text(style.descriptionKey.tr(), style: StoryType.body.copyWith(fontSize: 17))),
]);

/// A calendar page for the biggest day: month, day and weekday.
class _CalendarTile extends StatelessWidget {
  const _CalendarTile({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.orange,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              monthName(date.month).toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: StoryType.heavy, color: AppColors.onOrange),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '${date.day}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 72, fontWeight: StoryType.heavy, height: 1.1, color: AppColors.onTeal),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              weekdayName(_weekdays[date.weekday - 1]),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onTeal),
            ),
          ),
        ],
      ),
    );
  }
}
