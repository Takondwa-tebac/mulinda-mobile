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
  });

  final Money money;
  final MoneyDirection direction;
  final TextStyle? style;
  final bool signed;
  final TextAlign? textAlign;

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
  static String label(Money money, MoneyDirection direction, {bool signed = true}) {
    if (!signed || direction == MoneyDirection.neutral) return money.formatted;
    // The formatted string is unsigned for a positive amount; avoid "--".
    final raw = money.formatted.startsWith('-') ? money.formatted.substring(1) : money.formatted;
    return '${direction == MoneyDirection.income ? '+' : '-'}$raw';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      label(money, direction, signed: signed),
      maxLines: 1,
      textAlign: textAlign,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ).merge(style).copyWith(color: style?.color ?? colorFor(context, direction)),
    );
  }
}
