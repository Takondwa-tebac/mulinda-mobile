// Phase 0 sanity: the brand theme is wired from the palette.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/theme/app_colors.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';

void main() {
  test('light theme uses the brand teal as primary and orange as secondary', () {
    final scheme = AppTheme.light.colorScheme;
    expect(scheme.primary, AppColors.teal);
    expect(scheme.secondary, AppColors.orange);
    expect(scheme.brightness, Brightness.light);
  });

  test('dark theme is provided and is dark', () {
    expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
  });
}
