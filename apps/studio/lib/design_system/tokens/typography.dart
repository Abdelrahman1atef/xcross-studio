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
}
