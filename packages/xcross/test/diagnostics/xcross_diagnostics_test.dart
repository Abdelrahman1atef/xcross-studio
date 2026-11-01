// studio: 002 — coded diagnostics and build warning collector.
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/diagnostics/build_warnings.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';

import '../log_fixture.dart';

void main() {
  test('codes are unique, dotted and have hints', () {
    final codes = [for (final c in XcrossCodes.all) c.code];
    expect(codes.toSet(), hasLength(codes.length));
    for (final code in XcrossCodes.all) {
      expect(
        code.code,
        matches(RegExp(r'^(device|toolchain|build|install|sign)\.[a-z_]+$')),
      );
      expect(code.hint, isNotEmpty);
    }
  });

  test('codedError and codedWarning format code, message and hint', () {
    final error = codedError(XcrossCodes.deviceNotFound, 'No device.');
    expect(error.message, startsWith('[device.not_found] No device.\nhint: '));
    expect(
      codedError(XcrossCodes.deviceNotFound, 'x', hint: 'custom').message,
      '[device.not_found] x\nhint: custom',
    );
    expect(
      codedWarning(XcrossCodes.buildResourceMissing, 'gone'),
      startsWith('[build.resource_missing] gone\n  hint: '),
    );
  });

  test('AC-002-15 dedupe and summary', () {
    final output = TestLogOutput();
    final warnings = BuildWarnings(Log(output: output));
    for (var i = 0; i < 2; i++) {
      warnings
        ..warn(
          XcrossCodes.buildStoryboardSkipped,
          subject: 'LaunchScreen',
          message: 'Storyboard "LaunchScreen" skipped.',
        )
        ..warn(
          XcrossCodes.buildAssetCatalogSkipped,
          subject: 'Assets.xcassets',
          message: 'Assets.xcassets skipped.',
        );
    }
    warnings.warn(
      XcrossCodes.buildStoryboardSkipped,
      subject: 'Main',
      message: 'Storyboard "Main" skipped.',
    );
    final lines = output.messages.join('\n');
    expect(
      RegExp(r'\[build\.storyboard_skipped\]').allMatches(lines),
      hasLength(2),
    );
    expect(
      RegExp(r'\[build\.asset_catalog_skipped\]').allMatches(lines),
      hasLength(1),
    );
    expect(
      warnings.takeSummary(),
      'Build finished with 3 warnings: build.asset_catalog_skipped ×1, '
      'build.storyboard_skipped ×2',
    );
    expect(warnings.takeSummary(), isNull, reason: 'summary resets');
  });
}
