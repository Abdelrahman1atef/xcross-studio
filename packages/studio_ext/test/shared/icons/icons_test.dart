// studio: 023 — icon studio: check and generate the app icon set
// (specs/023-icon-studio, AC-023-1…7).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/icons/icons_command.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_check.dart';
import 'package:studio_ext/src/shared/icons/icon_generator.dart';
import 'package:studio_ext/src/shared/icons/icon_slots.dart';
import 'package:test/test.dart';

/// A [size]² image of [background] with an optional filled rectangle.
@internal
RgbaImage canvas(
  int size,
  IconColor background, {
  int alpha = 255,
  (int, int, int, int)? rect,
  IconColor rectColor = (0, 0, 0),
}) {
  final rgba = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final inRect =
          rect != null &&
          x >= rect.$1 &&
          y >= rect.$2 &&
          x < rect.$1 + rect.$3 &&
          y < rect.$2 + rect.$4;
      final c = inRect ? rectColor : background;
      rgba
        ..[i] = c.$1
        ..[i + 1] = c.$2
        ..[i + 2] = c.$3
        ..[i + 3] = inRect ? 255 : alpha;
    }
  }
  return RgbaImage(size, size, rgba);
}

void main() {
  final fileSystem = detectPlatformHost().fileSystem;
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('icons-');
    Directory(
      p.join(root.path, 'ios', 'Runner', 'Assets.xcassets'),
    ).createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  String setPath() => p.join(
    root.path,
    'ios',
    'Runner',
    'Assets.xcassets',
    'AppIcon.appiconset',
  );

  /// Writes a complete set made from [master] with [IconGenerator].
  void writeSet(RgbaImage master) {
    IconGenerator.write(
      fileSystem: fileSystem,
      files: IconGenerator.files(IconGenerator.compose(master)),
      now: DateTime(2026, 11, 3, 10, 45),
      projectRoot: root.path,
    );
  }

  IconReport check() =>
      IconCheck(fileSystem: fileSystem, projectRoot: root.path).run();

  final logo = canvas(
    1024,
    (255, 255, 255),
    rect: (256, 256, 512, 512),
    rectColor: (10, 132, 255),
  );

  group('AC-023-1 slots', () {
    test('a generated set: every iPhone, iPad and App Store slot is ok', () {
      writeSet(logo);
      final report = check();
      expect(report.style, 'all-sizes');
      expect(report.name, 'AppIcon');
      expect(report.slots, hasLength(19));
      expect(report.slots.every((s) => s.status == 'ok'), isTrue);
      expect(report.errors, 0);
      expect(report.warnings, 0);
      final notification = report.slots.first;
      expect(notification.slot.role, IconRole.notification);
      expect(notification.slot.pixels, 40);
      expect(notification.file, 'Icon-App-20x20@2x.png');
    });

    test('an iPhone-only app does not need the iPad sizes', () {
      writeSet(logo);
      File(p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('TARGETED_DEVICE_FAMILY = 1;\n');
      expect(check().slots, hasLength(10));
    });

    test('a single-size set is checked as one image', () {
      Directory(setPath()).createSync();
      File(
        p.join(setPath(), 'icon.png'),
      ).writeAsBytesSync(PngEncoder.encodeOpaque(logo));
      File(p.join(setPath(), 'Contents.json')).writeAsStringSync(
        jsonEncode({
          'images': [
            {
              'filename': 'icon.png',
              'idiom': 'universal',
              'platform': 'ios',
              'size': '1024x1024',
            },
          ],
        }),
      );
      final report = check();
      expect(report.style, 'single-size');
      expect(report.slots.single.status, 'ok');
      expect(report.errors, 0);
    });
  });

  group('AC-023-2 errors', () {
    test('no icon set', () {
      final report = check();
      expect(report.issues.single.code, 'icons.no_set');
      expect(report.errors, 1);
    });

    test('Contents.json that is not an icon set', () {
      Directory(setPath()).createSync();
      File(p.join(setPath(), 'Contents.json')).writeAsStringSync('[]');
      expect(check().issues.single.code, 'icons.contents_invalid');
    });

    test('alpha channel in the App Store icon, a missing home screen icon, '
        'a wrong size and a file that is not a PNG', () {
      writeSet(logo);
      File(
        p.join(setPath(), 'Icon-App-1024x1024@1x.png'),
      ).writeAsBytesSync(PngEncoder.encode(logo));
      File(p.join(setPath(), 'Icon-App-60x60@2x.png')).deleteSync();
      File(
        p.join(setPath(), 'Icon-App-40x40@3x.png'),
      ).writeAsBytesSync(PngEncoder.encodeOpaque(canvas(100, (0, 0, 0))));
      File(
        p.join(setPath(), 'Icon-App-29x29@1x.png'),
      ).writeAsStringSync('not a png');
      final report = check();
      final codes = {
        for (final issue in report.issues) '${issue.code} ${issue.severity}',
      };
      expect(codes, contains('icons.alpha error'));
      expect(codes, contains('icons.missing error'));
      expect(codes, contains('icons.wrong_size error'));
      expect(codes, contains('icons.unreadable error'));
      final wrong = report.slots.firstWhere(
        (s) => s.file == 'Icon-App-40x40@3x.png',
      );
      expect(wrong.status, 'wrong_size');
      expect(wrong.actual, '100x100');
      expect(report.errors, greaterThanOrEqualTo(4));
    });

    test('a missing Settings size is a warning; transparency outside the App '
        'Store icon is a warning', () {
      writeSet(logo);
      File(p.join(setPath(), 'Icon-App-29x29@3x.png')).deleteSync();
      File(p.join(setPath(), 'Icon-App-20x20@3x.png')).writeAsBytesSync(
        PngEncoder.encode(canvas(60, (255, 255, 255), alpha: 0)),
      );
      final report = check();
      expect(report.errors, 0);
      expect(
        report.issues.map((i) => '${i.code} ${i.severity}'),
        containsAll(['icons.missing warning', 'icons.alpha warning']),
      );
    });
  });

  group('AC-023-3 placement', () {
    test('a centred logo of half the side: no warning', () {
      final placement = IconAnalyzer.analyze(logo);
      expect(placement.background, (255, 255, 255));
      expect(placement.box!.$3, closeTo(0.5, 0.01));
      expect(placement.offset.$1.abs(), lessThan(0.01));
      expect(placement.outsideMask, 0);
      expect(placement.prerounded, isFalse);
    });

    test('a logo 100 px right of centre', () {
      writeSet(canvas(1024, (255, 255, 255), rect: (412, 312, 400, 400)));
      final issue = check().issues.firstWhere(
        (i) => i.code == 'icons.off_center',
      );
      expect(issue.message, contains('100 px right'));
      expect(issue.message, isNot(contains('low')));
    });

    test('a logo reaching into the corners is cut', () {
      final placement = IconAnalyzer.analyze(
        canvas(1024, (255, 255, 255), rect: (12, 12, 1000, 1000)),
      );
      expect(placement.outsideMask, greaterThan(IconCheck.clipTolerance));
      writeSet(canvas(1024, (255, 255, 255), rect: (12, 12, 1000, 1000)));
      expect(check().issues.map((i) => i.code), contains('icons.clipped'));
    });

    test('a small logo', () {
      writeSet(canvas(1024, (255, 255, 255), rect: (362, 362, 300, 300)));
      expect(check().issues.map((i) => i.code), contains('icons.logo_small'));
    });

    test('an icon exported with transparent rounded corners', () {
      const side = 1024;
      const radius = 229;
      final image = canvas(side, (10, 132, 255));
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final cx = x < radius
              ? radius
              : x >= side - radius
              ? side - radius - 1
              : x;
          final cy = y < radius
              ? radius
              : y >= side - radius
              ? side - radius - 1
              : y;
          final dx = x - cx;
          final dy = y - cy;
          if (dx * dx + dy * dy > radius * radius) {
            image.rgba[(y * side + x) * 4 + 3] = 0;
          }
        }
      }
      final placement = IconAnalyzer.analyze(image);
      expect(placement.prerounded, isTrue);
      expect(placement.transparent, isTrue);
    });

    test('full-bleed artwork is not measured', () {
      final rgba = Uint8List(256 * 256 * 4);
      for (var i = 0; i < 256 * 256; i++) {
        rgba
          ..[i * 4] = i % 256
          ..[i * 4 + 1] = i ~/ 256
          ..[i * 4 + 2] = 128
          ..[i * 4 + 3] = 255;
      }
      final placement = IconAnalyzer.analyze(RgbaImage(256, 256, rgba));
      expect(placement.fullBleed, isTrue);
      expect(placement.box, isNull);
    });
  });

  group('AC-023-5…7 generate', () {
    late List<String> out;
    Future<void> run(List<String> args) =>
        (CommandRunner<void>('xcross', '')..addCommand(
              IconsCommand(
                fileSystem: fileSystem,
                currentDirectory: () => root.path,
                write: out.add,
                now: () => DateTime(2026, 11, 3, 10, 45, 7),
              ),
            ))
            .run(args);

    setUp(() => out = []);

    String writeSource(RgbaImage image) {
      final path = p.join(root.path, 'logo.png');
      File(path).writeAsBytesSync(PngEncoder.encode(image));
      return path;
    }

    test('a transparent 512 px logo: background, margin, every size without '
        'alpha, a passing check', () async {
      final source = writeSource(
        canvas(
          512,
          (0, 0, 0),
          alpha: 0,
          rect: (0, 0, 512, 512),
          rectColor: (255, 255, 255),
        ),
      );
      await run([
        'icons',
        'generate',
        source,
        '--background',
        '#0A84FF',
        '--padding',
        '12',
        '--json',
      ]);
      final json = jsonDecode(out.single) as Map<String, Object?>;
      expect(json['type'], 'icons_generate');
      expect(json['background'], '#0A84FF');
      expect(json['upscaled'], isTrue);
      expect(json['written'], hasLength(15));
      expect((json['check']! as Map)['errors'], 0);

      final contents =
          jsonDecode(
                File(p.join(setPath(), 'Contents.json')).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(contents['images'], hasLength(19));
      for (final MapEntry(key: name, value: pixels)
          in IconSlots.files.entries) {
        final bytes = File(p.join(setPath(), name)).readAsBytesSync();
        final info = IconPngInfo.read(bytes)!;
        expect((info.width, info.height), (pixels, pixels), reason: name);
        expect(info.alphaChannel, isFalse, reason: name);
      }
      final master = PngDecoder.decode(
        File(p.join(setPath(), 'Icon-App-1024x1024@1x.png')).readAsBytesSync(),
      );
      // The corner is background; the centre is the logo.
      expect(master.rgba.sublist(0, 3), [10, 132, 255]);
      const centre = (512 * 1024 + 512) * 4;
      expect(master.rgba.sublist(centre, centre + 3), [255, 255, 255]);
      // 12% margin: the logo starts at 123 px.
      const edge = (512 * 1024 + 110) * 4;
      expect(master.rgba.sublist(edge, edge + 3), [10, 132, 255]);
    });

    test('auto background: the source border colour', () {
      final master = IconGenerator.compose(
        canvas(
          1024,
          (20, 30, 40),
          rect: (300, 300, 424, 424),
          rectColor: (250, 250, 250),
        ),
        padding: 10,
      );
      expect(master.background, (20, 30, 40));
      expect(master.upscaled, isFalse);
    });

    test('AC-023-6 the old set is backed up first', () async {
      writeSet(logo);
      File(p.join(setPath(), 'Old.png')).writeAsStringSync('old');
      await run(['icons', 'generate', writeSource(logo)]);
      final backup = p.join(
        root.path,
        '.xcross',
        'icon-backups',
        '20261103-104507',
        'AppIcon.appiconset',
      );
      expect(File(p.join(backup, 'Old.png')).readAsStringSync(), 'old');
      expect(File(p.join(backup, 'Contents.json')).existsSync(), isTrue);
      expect(File(p.join(setPath(), 'Old.png')).existsSync(), isFalse);
      expect(out.single, contains('The old set is in $backup'));
      expect(out.single, contains('The icon set is ready.'));
    });

    test(
      'AC-023-6 --output writes elsewhere and leaves the project alone',
      () async {
        final output = p.join(root.path, 'preview');
        await run([
          'icons',
          'generate',
          writeSource(logo),
          '--output',
          output,
          '--json',
        ]);
        expect(File(p.join(output, 'Contents.json')).existsSync(), isTrue);
        expect(Directory(setPath()).existsSync(), isFalse);
        expect(Directory(p.join(root.path, '.xcross')).existsSync(), isFalse);
        final json = jsonDecode(out.single) as Map<String, Object?>;
        expect(json['backup'], isNull);
        expect(json['check'], isNull);
      },
    );

    test('AC-023-6 a source that is not a PNG, and bad options', () async {
      final text = p.join(root.path, 'logo.png');
      File(text).writeAsStringSync('nope');
      await expectLater(
        run(['icons', 'generate', text]),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('icons.source_unreadable'),
          ),
        ),
      );
      final source = writeSource(logo);
      await expectLater(
        run(['icons', 'generate', source, '--padding', '46']),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        run(['icons', 'generate', source, '--background', 'blue']),
        throwsA(isA<UsageException>()),
      );
    });

    test('AC-023-4 check --json, and exit 1 on errors', () async {
      await expectLater(
        run(['icons', 'check', '--json']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('icons.check_failed'),
          ),
        ),
      );
      final json = jsonDecode(out.single) as Map<String, Object?>;
      expect(json, containsPair('v', 1));
      expect(json, containsPair('type', 'icons_check'));
      expect(json['set'], isNull);
      expect(json['errors'], 1);

      out.clear();
      writeSet(logo);
      await run(['icons', 'check', '--json']);
      final ready = jsonDecode(out.single) as Map<String, Object?>;
      expect(ready['set'], 'AppIcon');
      expect(ready['style'], 'all-sizes');
      expect(ready['source'], 'Icon-App-1024x1024@1x.png');
      expect((ready['placement']! as Map)['background'], '#FFFFFF');
      expect(ready['slots'], hasLength(19));
    });
  });
}
