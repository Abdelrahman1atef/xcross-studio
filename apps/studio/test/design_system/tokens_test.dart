import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/design_system/design_system.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('FR-001 / AC-029-1 workspace colour tokens', () {
    test('dark palette is every section 2.1 value', () {
      const c = XColors.dark;
      expect(c.canvas, const Color(0xFF111318));
      expect(c.toolbar, const Color(0xFF202329));
      expect(c.navigator, const Color(0xFF1B1D23));
      expect(c.editor, const Color(0xFF17191F));
      expect(c.inspector, const Color(0xFF202228));
      expect(c.console, const Color(0xFF111318));
      expect(c.surfaceElevated, const Color(0xFF262931));
      expect(c.surfaceHover, const Color(0xFF30343D));
      expect(c.border, const Color(0xFF343840));
      expect(c.selection, const Color(0xFF1B4E8E));
      expect(c.primary, const Color(0xFF0A84FF));
      expect(c.primaryHover, const Color(0xFF369AFF));
      expect(c.textPrimary, const Color(0xFFEBEDF2));
      expect(c.textSecondary, const Color(0xFFACB1BB));
      expect(c.textMuted, const Color(0xFF808794));
      expect(c.success, const Color(0xFF32D77B));
      expect(c.warning, const Color(0xFFFFB340));
      expect(c.error, const Color(0xFFFF5E5B));
      expect(c.info, const Color(0xFF65B3FF));
      expect(c.focus, const Color(0xFF80BEFF));
    });

    test('dark syntax palette is every section 2.2 value', () {
      const s = XSyntaxColors.dark;
      expect(s.keyword, const Color(0xFFD7A1F9));
      expect(s.type, const Color(0xFF7AC7F8));
      expect(s.string, const Color(0xFFF5AB87));
      expect(s.function, const Color(0xFF8BD9D0));
      expect(s.number, const Color(0xFFC9C0FF));
      expect(s.comment, const Color(0xFF81909A));
      expect(s.diagnostic, const Color(0xFFFF7775));
    });

    test('geometry tokens match section 2.4 and 3.1', () {
      expect(
        [XSpace.s1, XSpace.s2, XSpace.s3, XSpace.s4, XSpace.s6, XSpace.s8],
        [4, 8, 12, 16, 24, 32],
      );
      expect([XIcon.compact, XIcon.standard, XIcon.toolbar], [16, 18, 20]);
      expect(XDimensions.toolbarHeight, 52);
      expect(XDimensions.toolbarMinHeight, 48);
      expect(XDimensions.statusHeight, 25);
      expect(XDimensions.runButtonMinTarget, greaterThanOrEqualTo(36));
      expect(XDimensions.treeRowHeight, inInclusiveRange(25, 28));
      expect(XDimensions.inputHeight, inInclusiveRange(30, 32));
      expect(XDimensions.toolbarControlHeight, inInclusiveRange(28, 32));
      expect(XDimensions.navigatorWidth, 280);
      expect(XDimensions.navigatorMinWidth, 190);
      expect(XDimensions.inspectorWidth, 300);
      expect(XDimensions.inspectorMinWidth, 240);
      expect(XDimensions.previewWidth, 350);
      expect(XDimensions.previewMinWidth, 260);
      expect(XDimensions.consoleHeight, 210);
      expect(XDimensions.consoleMinHeight, 120);
      expect(XDimensions.editorMinWidth, 360);
      expect(XDimensions.windowMinWidth, 1100);
      expect(XDimensions.windowMinHeight, 700);
      expect(XDimensions.inspectorBreakpoint, 1180);
      expect(XDimensions.previewBreakpoint, 1360);
      expect(XDimensions.splitHitTarget, greaterThan(XDimensions.divider));
      expect(XRadius.panelMin, 6);
      expect(XRadius.panelMax, 10);
    });

    test('motion stays in 120-180 ms and reduced motion zeroes it', () {
      expect(XMotion.panel.inMilliseconds, inInclusiveRange(120, 180));
      expect(XMotion.hover.inMilliseconds, inInclusiveRange(120, 180));
      expect(XMotion.of(XMotion.panel, reduceMotion: true), Duration.zero);
      expect(XMotion.of(XMotion.panel, reduceMotion: false), XMotion.panel);
    });
  });

  group('FR-001 / FR-019 contrast', () {
    for (final entry in {
      'dark': XColors.dark,
      'light': XColors.light,
    }.entries) {
      final c = entry.value;
      // textMuted is placeholder / inactive metadata only (section 2.1); the
      // document value is ~4.3:1 on toolbar and surface, so it is held to 3:1
      // and must never carry required information.
      test('${entry.key}: text meets contrast on every region', () {
        final regions = {
          'canvas': c.canvas,
          'toolbar': c.toolbar,
          'navigator': c.navigator,
          'editor': c.editor,
          'inspector': c.inspector,
          'console': c.console,
          'surface': c.surfaceElevated,
        };
        for (final r in regions.entries) {
          for (final t in {
            'text': (c.textPrimary, 4.5),
            'secondary': (c.textSecondary, 4.5),
            'muted': (c.textMuted, 3.0),
          }.entries) {
            expect(
              _contrast(t.value.$1, r.value),
              greaterThanOrEqualTo(t.value.$2),
              reason: '${t.key} on ${r.key}',
            );
          }
        }
      });
      test('${entry.key}: status colours and focus meet 3:1 on editor', () {
        for (final status in {
          'success': c.success,
          'warning': c.warning,
          'error': c.error,
          'info': c.info,
          'focus': c.focus,
          'primary': c.primary,
        }.entries) {
          expect(
            _contrast(status.value, c.editor),
            greaterThanOrEqualTo(3),
            reason: status.key,
          );
        }
      });
      test('${entry.key}: text is readable on selection', () {
        expect(
          _contrast(c.onSelection, c.selection),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      });
    }

    for (final entry in {
      'dark': (XSyntaxColors.dark, XColors.dark),
      'light': (XSyntaxColors.light, XColors.light),
    }.entries) {
      test('${entry.key}: syntax colours meet 4.5:1 on the editor', () {
        final (s, c) = entry.value;
        for (final token in {
          'keyword': s.keyword,
          'type': s.type,
          'string': s.string,
          'function': s.function,
          'number': s.number,
          'comment': s.comment,
          'diagnostic': s.diagnostic,
        }.entries) {
          expect(
            _contrast(token.value, c.editor),
            greaterThanOrEqualTo(4.5),
            reason: token.key,
          );
        }
      });
    }
  });

  group('FR-001 / FR-019 theme wiring', () {
    test('dark and light themes expose XTheme with matching tokens', () {
      final dark = xDarkTheme().extension<XTheme>()!;
      final light = xLightTheme().extension<XTheme>()!;
      expect(dark.colors, XColors.dark);
      expect(dark.syntax, XSyntaxColors.dark);
      expect(light.colors, XColors.light);
      expect(light.syntax, XSyntaxColors.light);
    });

    test('focus colour drives the theme focus ring', () {
      expect(xDarkTheme().focusColor, XColors.dark.focus);
      expect(xLightTheme().focusColor, XColors.light.focus);
    });

    test('type scale uses 12-14 px workspace sizes with mono for code', () {
      expect(XType.toolbar.fontSize, inInclusiveRange(13, 14));
      expect(XType.panelHeading.fontSize, inInclusiveRange(12, 13));
      expect(XType.panelHeading.fontWeight, FontWeight.w600);
      expect(XType.treeRow.fontSize, inInclusiveRange(12, 13));
      expect(XType.inspectorLabel.fontSize, 12);
      expect(XType.statusMeta.fontSize, inInclusiveRange(11, 12));
      expect(XType.editor.fontSize, inInclusiveRange(13, 14));
      expect(XType.console.fontSize, inInclusiveRange(12, 13));
      expect(XType.editor.fontFamily, XType.code);
      expect(XType.console.fontFamily, XType.code);
      expect(XType.toolbar.fontFamilyFallback, contains('Segoe UI'));
    });
  });
}
