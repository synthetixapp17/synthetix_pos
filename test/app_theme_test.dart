import 'package:billing_app/core/theme/app_theme.dart';
import 'package:billing_app/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final originalColor = AppThemeController.primaryColor.value;

  tearDown(() {
    AppThemeController.primaryColor.value = originalColor;
  });

  testWidgets('dark theme keeps the default black accent legible', (
    tester,
  ) async {
    const defaultColor = Color(0xFF111111);
    AppThemeController.primaryColor.value = defaultColor;

    expect(AppTheme.lightTheme.colorScheme.primary, defaultColor);
    final scheme = AppTheme.darkTheme.colorScheme;

    expect(
      AppTheme.darkTheme.scaffoldBackgroundColor.computeLuminance(),
      lessThan(.02),
    );
    expect(scheme.surface.computeLuminance(), lessThan(.03));
    expect(scheme.primary.computeLuminance(), greaterThanOrEqualTo(0.35));
    expect(_contrastRatio(scheme.primary, scheme.onPrimary), greaterThan(4.5));
  });

  testWidgets('custom accent colors remain represented in both themes', (
    tester,
  ) async {
    for (final selectedColor in AppThemeController.availableColors) {
      AppThemeController.primaryColor.value = selectedColor;

      final lightScheme = AppTheme.lightTheme.colorScheme;
      final darkScheme = AppTheme.darkTheme.colorScheme;

      expect(lightScheme.primary, selectedColor);
      expect(
        _contrastRatio(lightScheme.primary, lightScheme.onPrimary),
        greaterThan(4.5),
        reason: 'Light primary contrast for $selectedColor',
      );
      expect(
        _contrastRatio(
          lightScheme.primaryContainer,
          lightScheme.onPrimaryContainer,
        ),
        greaterThan(4.5),
        reason: 'Light primary container contrast for $selectedColor',
      );
      if (selectedColor.computeLuminance() >= .35) {
        expect(darkScheme.primary, selectedColor);
      } else {
        expect(darkScheme.primary, isNot(selectedColor));
      }
      expect(
        _contrastRatio(darkScheme.primary, darkScheme.onPrimary),
        greaterThan(4.5),
        reason: 'Dark primary contrast for $selectedColor',
      );
      expect(
        _contrastRatio(
          darkScheme.primaryContainer,
          darkScheme.onPrimaryContainer,
        ),
        greaterThan(4.5),
        reason: 'Dark primary container contrast for $selectedColor',
      );
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
