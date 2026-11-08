import 'package:flutter/painting.dart';

/// Type scale (design system §3.3): Inter for UI, JetBrains Mono for code
/// and logs; the bundled fonts fall back to system fonts when missing.
abstract final class XType {
  static const ui = 'Inter';
  static const code = 'JetBrainsMono';
  static const _fallback = ['Segoe UI', 'Ubuntu', 'Cantarell', 'Arial'];
  static const _codeFallback = [
    'Cascadia Mono',
    'Consolas',
    'DejaVu Sans Mono',
    'monospace',
  ];

  /// App / screen title: Inter Semibold 24/32.
  static const title = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
  );

  /// Section title: Inter Semibold 18/26.
  static const section = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );

  /// Card title: Inter Medium 15/22.
  static const card = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
  );

  /// Body: Inter Regular 14/21.
  static const body = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    height: 21 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Supporting text: Inter Regular 12.5/18.
  static const support = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 12.5,
    height: 18 / 12.5,
    fontWeight: FontWeight.w400,
  );

  /// Code / logs: JetBrains Mono 12.5/19.
  static const mono = TextStyle(
    fontFamily: code,
    fontFamilyFallback: _codeFallback,
    fontSize: 12.5,
    height: 19 / 12.5,
    fontWeight: FontWeight.w400,
  );

  // Workspace styles (Xcode-inspired design system §2.3). Inter ships only
  // as a licensed bundled font or falls back to the system UI font; Apple's
  // San Francisco is never referenced.

  /// Main toolbar: 13 px, weight 500.
  static const toolbar = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
  );

  /// Panel headings: 12 px, weight 600.
  static const panelHeading = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
  );

  /// Tree rows and compact body: 12.5 px, weight 400.
  static const treeRow = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 12.5,
    height: 18 / 12.5,
    fontWeight: FontWeight.w400,
  );

  /// Inspector labels: 12 px, weight 400.
  static const inspectorLabel = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// Status strip metadata: 11.5 px, weight 500.
  static const statusMeta = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 11.5,
    height: 16 / 11.5,
    fontWeight: FontWeight.w500,
  );

  /// Editor text: mono 13 px (the user's size preference scales it).
  static const editor = TextStyle(
    fontFamily: code,
    fontFamilyFallback: _codeFallback,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );

  /// Console text: mono 12.5 px.
  static const console = TextStyle(
    fontFamily: code,
    fontFamilyFallback: _codeFallback,
    fontSize: 12.5,
    height: 19 / 12.5,
    fontWeight: FontWeight.w400,
  );
}
