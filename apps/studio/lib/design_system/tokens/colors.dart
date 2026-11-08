import 'package:flutter/painting.dart';

/// Semantic colour tokens (Xcode-inspired IDE design system §2.1). [dark]
/// holds the document's exact values; [light] is derived from the same
/// semantic roles (the document asks for it later, not as exact values).
///
/// The names `canvas`, `surface*`, `border`, `primary*` and `text*` predate
/// the workspace and stay as the shared roles; the region tokens
/// (`toolbar`, `navigator`, `editor`, `inspector`, `console`) and
/// `selection`, `info`, `focus` come from §2.1.
class XColors {
  const XColors({
    required this.canvas,
    required this.toolbar,
    required this.navigator,
    required this.editor,
    required this.inspector,
    required this.console,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHover,
    required this.border,
    required this.selection,
    required this.onSelection,
    required this.primary,
    required this.primaryHover,
    required this.onPrimary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.focus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  /// `color.canvas`: outer workspace background.
  final Color canvas;

  /// `color.toolbar`: main top toolbar.
  final Color toolbar;

  /// `color.navigator`: project navigator.
  final Color navigator;

  /// `color.editor`: source editor background.
  final Color editor;

  /// `color.inspector`: properties inspector.
  final Color inspector;

  /// `color.console`: debug/build console.
  final Color console;

  /// Page-level cards and panels (the navigator tone).
  final Color surface;

  /// `color.surface`: menus, popovers, segmented controls, inputs.
  final Color surfaceElevated;

  /// `color.surfaceHover`: hovered items.
  final Color surfaceHover;

  /// `color.divider`: panel separators and borders.
  final Color border;

  /// `color.selection`: selected file/tab/row.
  final Color selection;

  /// Text on a [selection] fill.
  final Color onSelection;

  /// `color.accent`: primary action, link, active state.
  final Color primary;

  /// `color.accentHover`: hovered primary action.
  final Color primaryHover;

  /// Text on a [primary]-filled control.
  final Color onPrimary;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  /// `color.focus`: keyboard focus ring.
  final Color focus;

  final Color textPrimary;
  final Color textSecondary;

  /// Placeholder and inactive metadata only; never required information.
  final Color textMuted;

  /// §2.1 values (dark theme, the default).
  static const dark = XColors(
    canvas: Color(0xFF111318),
    toolbar: Color(0xFF202329),
    navigator: Color(0xFF1B1D23),
    editor: Color(0xFF17191F),
    inspector: Color(0xFF202228),
    console: Color(0xFF111318),
    surface: Color(0xFF1B1D23),
    surfaceElevated: Color(0xFF262931),
    surfaceHover: Color(0xFF30343D),
    border: Color(0xFF343840),
    selection: Color(0xFF1B4E8E),
    onSelection: Color(0xFFEBEDF2),
    primary: Color(0xFF0A84FF),
    primaryHover: Color(0xFF369AFF),
    onPrimary: Color(0xFF111318),
    success: Color(0xFF32D77B),
    warning: Color(0xFFFFB340),
    error: Color(0xFFFF5E5B),
    info: Color(0xFF65B3FF),
    focus: Color(0xFF80BEFF),
    textPrimary: Color(0xFFEBEDF2),
    textSecondary: Color(0xFFACB1BB),
    textMuted: Color(0xFF808794),
  );

  /// Derived light palette (not part of the design document).
  static const light = XColors(
    canvas: Color(0xFFF3F4F7),
    toolbar: Color(0xFFE9EBEF),
    navigator: Color(0xFFF7F8FA),
    editor: Color(0xFFFFFFFF),
    inspector: Color(0xFFF7F8FA),
    console: Color(0xFFF3F4F7),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFE3E6EB),
    border: Color(0xFFCDD1D9),
    selection: Color(0xFFC9E0FF),
    onSelection: Color(0xFF111318),
    primary: Color(0xFF0A60D0),
    primaryHover: Color(0xFF0850B0),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF12713F),
    warning: Color(0xFF8A5200),
    error: Color(0xFFC0261F),
    info: Color(0xFF0B5CAD),
    focus: Color(0xFF0A60D0),
    textPrimary: Color(0xFF1B1E24),
    textSecondary: Color(0xFF4A515C),
    textMuted: Color(0xFF5B6370),
  );
}

/// Syntax token colours (§2.2). The document marks them a design proposal
/// subject to contrast review; [light] is derived for the light editor.
class XSyntaxColors {
  const XSyntaxColors({
    required this.keyword,
    required this.type,
    required this.string,
    required this.function,
    required this.number,
    required this.comment,
    required this.diagnostic,
  });

  final Color keyword;
  final Color type;
  final Color string;
  final Color function;
  final Color number;
  final Color comment;

  /// Errors / diagnostics.
  final Color diagnostic;

  static const dark = XSyntaxColors(
    keyword: Color(0xFFD7A1F9),
    type: Color(0xFF7AC7F8),
    string: Color(0xFFF5AB87),
    function: Color(0xFF8BD9D0),
    number: Color(0xFFC9C0FF),
    comment: Color(0xFF81909A),
    diagnostic: Color(0xFFFF7775),
  );

  static const light = XSyntaxColors(
    keyword: Color(0xFF8A2BB8),
    type: Color(0xFF0B5C91),
    string: Color(0xFF9A4A1E),
    function: Color(0xFF0B6B63),
    number: Color(0xFF4B3FB0),
    comment: Color(0xFF5E6B75),
    diagnostic: Color(0xFFC0261F),
  );
}
