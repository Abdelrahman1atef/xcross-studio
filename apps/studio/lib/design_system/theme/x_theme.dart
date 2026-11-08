import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// The design tokens on the widget tree: `XTheme.of(context).colors`.
class XTheme extends ThemeExtension<XTheme> {
  const XTheme(this.colors, [this.syntax = XSyntaxColors.dark]);

  final XColors colors;

  /// Editor syntax palette matching [colors]' brightness.
  final XSyntaxColors syntax;

  static XTheme of(BuildContext context) =>
      Theme.of(context).extension<XTheme>() ?? const XTheme(XColors.dark);

  @override
  XTheme copyWith({XColors? colors, XSyntaxColors? syntax}) =>
      XTheme(colors ?? this.colors, syntax ?? this.syntax);

  @override
  XTheme lerp(covariant XTheme? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// The dark theme (default), from the doc's exact tokens.
ThemeData xDarkTheme() =>
    _theme(XColors.dark, XSyntaxColors.dark, Brightness.dark);

/// The light theme (derived tokens; not part of the design document).
ThemeData xLightTheme() =>
    _theme(XColors.light, XSyntaxColors.light, Brightness.light);

ThemeData _theme(XColors c, XSyntaxColors syntax, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.primaryHover,
    onSecondary: c.onPrimary,
    error: c.error,
    onError: c.canvas,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    outline: c.border,
    outlineVariant: c.border,
    surfaceContainerLowest: c.console,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceElevated,
    surfaceContainerHighest: c.surfaceElevated,
    tertiary: c.success,
    onTertiary: c.canvas,
  );
  final text = TextTheme(
    headlineSmall: XType.title.copyWith(color: c.textPrimary),
    titleLarge: XType.section.copyWith(color: c.textPrimary),
    titleMedium: XType.card.copyWith(color: c.textPrimary),
    titleSmall: XType.card.copyWith(color: c.textPrimary, fontSize: 14),
    bodyLarge: XType.body.copyWith(color: c.textPrimary),
    bodyMedium: XType.body.copyWith(color: c.textPrimary),
    bodySmall: XType.support.copyWith(color: c.textSecondary),
    labelLarge: XType.body.copyWith(
      color: c.textPrimary,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: XType.support.copyWith(color: c.textSecondary),
    labelSmall: XType.support.copyWith(color: c.textMuted, fontSize: 11.5),
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(XRadius.md),
  );
  const minimum = Size(64, XSpace.control);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    fontFamily: XType.ui,
    textTheme: text,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    focusColor: c.focus,
    hoverColor: c.surfaceHover,
    extensions: [XTheme(c, syntax)],
    splashFactory: NoSplash.splashFactory,
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(XRadius.lg),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceElevated,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: XSpace.s3,
        vertical: XSpace.s3,
      ),
      labelStyle: XType.body.copyWith(color: c.textSecondary),
      hintStyle: XType.body.copyWith(color: c.textMuted),
      helperStyle: XType.support.copyWith(color: c.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(XRadius.md),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(XRadius.md),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(XRadius.md),
        borderSide: BorderSide(color: c.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minimum,
        shape: controlShape,
        textStyle: XType.body.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minimum,
        shape: controlShape,
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.border),
        textStyle: XType.body.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minimum,
        shape: controlShape,
        foregroundColor: c.primary,
        textStyle: XType.body.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, XSpace.control),
        side: BorderSide(color: c.border),
        selectedBackgroundColor: c.primary.withValues(alpha: 0.18),
        selectedForegroundColor: c.textPrimary,
        foregroundColor: c.textSecondary,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceElevated,
      side: BorderSide(color: c.border),
      labelStyle: XType.support.copyWith(color: c.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(XRadius.sm),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(XRadius.sm),
      ),
      textStyle: XType.support.copyWith(color: c.textPrimary),
      waitDuration: XMotion.panel,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(XRadius.xl),
        side: BorderSide(color: c.border),
      ),
      titleTextStyle: XType.section.copyWith(color: c.textPrimary),
      contentTextStyle: XType.body.copyWith(color: c.textSecondary),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.textPrimary,
      unselectedLabelColor: c.textSecondary,
      indicatorColor: c.primary,
      dividerColor: c.border,
      labelStyle: XType.body.copyWith(fontWeight: FontWeight.w500),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.surfaceElevated,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.border),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: c.textSecondary, width: 1.5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceElevated,
      contentTextStyle: XType.body.copyWith(color: c.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surfaceElevated,
      textStyle: XType.body.copyWith(color: c.textPrimary),
    ),
  );
}
