import 'package:flutter/material.dart';

import '../money/money.dart';
import '../theme/semantic_colors.dart';

/// Which way money moved; decides the sign and the colour.
enum MoneyDirection { income, expense, neutral }

/// A money amount with a sign and the income/expense colour. The text is
/// always the server's preformatted string (see `lib/core/money`).
class AmountText extends StatelessWidget {
  const AmountText(
    this.money, {
    super.key,
    this.direction = MoneyDirection.neutral,
    this.style,
    this.signed = true,
    this.textAlign,
    this.whole = false,
  });

  final Money money;
  final MoneyDirection direction;
  final TextStyle? style;
  final bool signed;
  final TextAlign? textAlign;

  /// Whole major units (`MK 285,400`) for headlines, report rows and charts;
  /// transaction amounts keep the exact figure.
  final bool whole;

  /// The colour an amount of [direction] is drawn in.
  static Color colorFor(BuildContext context, MoneyDirection direction) {
    final semantic = context.semantic;
    return switch (direction) {
      MoneyDirection.income => semantic.income,
      MoneyDirection.expense => semantic.expense,
      // Muted, so moves between your own money read differently from spending.
      MoneyDirection.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  /// `+MK 1,000.00`, `-MK 1,000.00` or `MK 1,000.00`.
  static String label(Money money, MoneyDirection direction, {bool signed = true, bool whole = false}) {
    final text = whole ? money.whole : money.formatted;
    if (!signed || direction == MoneyDirection.neutral) return text;
    // The formatted string is unsigned for a positive amount; avoid "--".
    final raw = text.startsWith('-') ? text.substring(1) : text;
    return '${direction == MoneyDirection.income ? '+' : '-'}$raw';
  }

  /// [label] with every space made non-breaking, so the line can never break
  /// between the currency and the number (`MK` alone on the line).
  static String unbreakable(String text) => text.replaceAll(' ', nbsp);

  /// U+00A0, the no-break space.
  static final nbsp = String.fromCharCode(0x00A0);

  @override
  Widget build(BuildContext context) {
    return Text(
      unbreakable(label(money, direction, signed: signed, whole: whole)),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ).merge(style).copyWith(color: style?.color ?? colorFor(context, direction)),
    );
  }
}
