import 'package:flutter/painting.dart';

/// Colour tokens (design system §3.1). [dark] holds the doc's exact values;
/// [light] is derived for the optional light theme (not in the doc).
class XColors {
  const XColors({
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.primary,
    required this.primaryHover,
    required this.success,
    required this.warning,
    required this.error,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.console,
    required this.onPrimary,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color primary;
  final Color primaryHover;
  final Color success;
  final Color warning;
  final Color error;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color console;

  /// Text on a primary-filled control.
  final Color onPrimary;

  /// `color.*` from §3.1 (dark theme, the default).
  static const dark = XColors(
    canvas: Color(0xFF0B1020),
    surface: Color(0xFF141B2D),
    surfaceElevated: Color(0xFF1D2840),
    border: Color(0xFF2F3D56),
    primary: Color(0xFF4F8CFF),
    primaryHover: Color(0xFF76A6FF),
    success: Color(0xFF36C89B),
    warning: Color(0xFFF4B860),
    error: Color(0xFFF27676),
    textPrimary: Color(0xFFF2F6FF),
    textSecondary: Color(0xFFA6B5CA),
    textMuted: Color(0xFF8593AA),
    console: Color(0xFF090E19),
    onPrimary: Color(0xFF0B1020),
  );

  /// Derived light palette (not part of the design document).
  static const light = XColors(
    canvas: Color(0xFFF5F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFEEF2F8),
    border: Color(0xFFCBD4E2),
    primary: Color(0xFF2563D9),
    primaryHover: Color(0xFF1E4FB0),
    success: Color(0xFF167A5C),
    warning: Color(0xFF8A5A00),
    error: Color(0xFFB42318),
    textPrimary: Color(0xFF0B1020),
    textSecondary: Color(0xFF3F4E66),
    textMuted: Color(0xFF55637A),
    console: Color(0xFF0B1020),
    onPrimary: Color(0xFFFFFFFF),
  );
}
