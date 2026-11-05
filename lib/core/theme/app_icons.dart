import 'package:flutter/material.dart';

/// Icons that carry a product meaning, defined once so the same idea always
/// looks the same and two ideas never share a glyph.
abstract final class AppIcons {
  /// Something the app suggests for the user to confirm (a category guess,
  /// rows that need a look). A light bulb: "here's an idea", not "AI magic".
  static const IconData suggestion = Icons.lightbulb_outline_rounded;

  /// Chat with Mulinda (the money coach): a conversation, distinct from
  /// suggestions so the app bar shortcut is never mistaken for one.
  static const IconData coach = Icons.question_answer_outlined;

  /// Filled variant of [coach] for avatars and solid surfaces.
  static const IconData coachFilled = Icons.question_answer_rounded;
}
