// studio: 024 — every platform's files from one design
// (specs/024-icon-splash-studio, User Stories 3 and 4).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/icons/icons_command.dart';
import 'package:studio_ext/shared/icons/icons_generate_command.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_composer.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:studio_ext/src/shared/icons/icon_targets.dart';
import 'package:test/test.dart';

/// A red square on transparent.
RgbaImage _logo() {
  const side = 64;
  final out = Uint8List(side * side * 4);
  for (var y = 16; y < 48; y++) {
    for (var x = 16; x < 48; x++) {
      out.setRange((y * side + x) * 4, (y * side + x) * 4 + 4, [
        200,
        0,
        0,
        255,
      ]);
    }
  }
  return RgbaImage(side, side, out);
}

/// Every pixel a different opaque colour: no shape to take.
RgbaImage _photo() {
  const side = 32;
  final out = Uint8List(side * side * 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      out.setRange((y * side + x) * 4, (y * side + x) * 4 + 4, [
        x * 8,
        y * 8,
        (x + y) * 4,
        255,
      ]);
    }
  }
  return RgbaImage(side, side, out);
}

RgbaImage _png(Uint8List bytes) => PngDecoder.decode(bytes);

void main() {
  final composer = IconComposer(
    _logo(),
    const IconDesign(padding: IconPadding.all(15), colors: [(10, 132, 255)]),
  );

  IconTargetFiles build(
    IconTarget target, {
    String name = IconTargets.defaultName,
    IconShape shape = IconShape.squircle,
    bool themed = false,
    IconComposer? using,
  }) => IconTargets.build(
    target,
    using ?? composer,
    name: name,
    shape: shape,
    themed: themed,
  );

  group('AC-024-11 Android', () {
    const res = 'android/app/src/main/res';

    test('launcher, round and adaptive files at every density', () {
      final files = build(IconTarget.android).files;
      for (final (density, launcher, layer) in const [
        ('mdpi', 48, 108),
        ('hdpi', 72, 162),
        ('xhdpi', 96, 216),
        ('xxhdpi', 144, 324),
        ('xxxhdpi', 192, 432),
      ]) {
        final folder = '$res/mipmap-$density';
        expect(_png(files['$folder/ic_launcher.png']!).width, launcher);
        expect(_png(files['$folder/ic_launcher_round.png']!).height, launcher);
        expect(_png(files['$folder/ic_launcher_foreground.png']!).width, layer);
        expect(_png(files['$folder/ic_launcher_background.png']!).width, layer);
      }
      expect(
        _png(files['android/app/src/main/ic_launcher-playstore.png']!).width,
        512,
      );
    });

    test('the XML names the layers', () {
      final files = build(
        IconTarget.android,
        name: 'app_icon',
        themed: true,
      ).files;
      final xml = utf8.decode(files['$res/mipmap-anydpi-v26/app_icon.xml']!);
      expect(xml, contains('@mipmap/app_icon_background'));
      expect(xml, contains('@mipmap/app_icon_foreground'));
      expect(xml, contains('@mipmap/app_icon_monochrome'));
      expect(
        files.containsKey('$res/mipmap-mdpi/app_icon_monochrome.png'),
        isTrue,
      );
    });

    test('shapes cut the launcher icon differently', () {
      int alpha(IconShape shape) {
        final image = _png(
          build(
            IconTarget.android,
            shape: shape,
          ).files['$res/mipmap-xxxhdpi/ic_launcher.png']!,
        );
        // Near the top left corner.
        return image.rgba[(14 * image.width + 14) * 4 + 3];
      }

      expect(alpha(IconShape.square), greaterThan(alpha(IconShape.squircle)));
      expect(
        alpha(IconShape.squircle),
        greaterThanOrEqualTo(alpha(IconShape.circle)),
      );
      expect(alpha(IconShape.circle), 0);
    });

    test('the adaptive foreground keeps the logo in the safe zone', () {
      final image = _png(
        build(
          IconTarget.android,
        ).files['$res/mipmap-xxxhdpi/ic_launcher_foreground.png']!,
      );
      // 432 px canvas: 72 of 108 dp visible, so the outer sixth stays empty.
      final edge = image.rgba[(216 * image.width + 60) * 4 + 3];
      expect(edge, 0);
      expect(image.rgba[(216 * image.width + 216) * 4 + 3], 255);
    });
  });

  group('AC-024-12 themed, AC-024-13 notification', () {
    test('notification icons are white on transparent, at every density', () {
      final files = build(IconTarget.notification).files;
      for (final (density, size) in const [
        ('mdpi', 24),
        ('hdpi', 36),
        ('xhdpi', 48),
        ('xxhdpi', 72),
        ('xxxhdpi', 96),
      ]) {
        final image = _png(
          files['android/app/src/main/res/drawable-$density/ic_stat_notification.png']!,
        );
        expect(image.width, size);
        for (var i = 0; i < image.rgba.length; i += 4) {
          if (image.rgba[i + 3] > 0) expect(image.rgba[i], 255);
        }
        expect(image.rgba[3], 0, reason: 'its corner is transparent');
      }
    });

    test('a custom name is used as it is', () {
      expect(IconTargets.notificationName('orders'), 'ic_stat_orders');
    });

    test('no shape: an error, no white square', () {
      final built = build(
        IconTarget.notification,
        using: IconComposer(_photo(), const IconDesign()),
      );
      expect(built.files, isEmpty);
      expect(built.issues.single.code, 'icons.notification_no_shape');
      expect(built.issues.single.severity, 'error');
    });

    test('no shape for a themed icon: a warning, the rest still written', () {
      final built = build(
        IconTarget.android,
        themed: true,
        using: IconComposer(_photo(), const IconDesign()),
      );
      expect(built.issues.single.severity, 'warning');
      expect(built.files.keys.where((k) => k.contains('monochrome')), isEmpty);
      expect(built.files, isNotEmpty);
    });
  });

  group('AC-024-14 other targets', () {
    test('web: favicon, icons, maskable with a safe zone', () {
      final files = build(IconTarget.web).files;
      expect(_png(files['web/favicon.png']!).width, 32);
      expect(_png(files['web/icons/Icon-192.png']!).width, 192);
      expect(_png(files['web/icons/Icon-512.png']!).width, 512);
      expect(_png(files['web/icons/Icon-maskable-192.png']!).width, 192);
      final plain = _png(files['web/icons/Icon-512.png']!);
      final maskable = _png(files['web/icons/Icon-maskable-512.png']!);
      int width(RgbaImage image) {
        var count = 0;
        for (var x = 0; x < 512; x++) {
          if (image.rgba[(256 * 512 + x) * 4] > 150) count++;
        }
        return count;
      }

      expect(width(maskable), lessThan(width(plain)));
      final ico = files['web/favicon.ico']!;
      expect(ico.sublist(0, 6), [0, 0, 1, 0, 3, 0]);
    });

    test('the manifest gets the icons and keeps its other fields', () {
      final updated = IconTargets.updatedManifest(
        '{"name":"x","icons":[{"src":"old.png"}],"theme_color":"#000000"}',
      )!;
      final decoded = jsonDecode(updated) as Map<String, Object?>;
      expect(decoded['name'], 'x');
      expect(decoded['theme_color'], '#000000');
      expect((decoded['icons']! as List).length, 4);
      expect(updated, contains('Icon-maskable-512.png'));
      expect(IconTargets.updatedManifest('not json'), isNull);
    });

    test('macOS: its rounded shape and margin, with Contents.json', () {
      final files = build(IconTarget.macos).files;
      const folder = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final size in const [16, 32, 64, 128, 256, 512, 1024]) {
        expect(_png(files['$folder/app_icon_$size.png']!).width, size);
      }
      final master = _png(files['$folder/app_icon_1024.png']!);
      expect(master.rgba[(512 * 1024 + 50) * 4 + 3], 0, reason: 'the margin');
      expect(master.rgba[(512 * 1024 + 150) * 4 + 3], 255);
      final contents =
          jsonDecode(utf8.decode(files['$folder/Contents.json']!)) as Map;
      expect((contents['images'] as List).length, 10);
    });

    test('watchOS: every case size and no transparency', () {
      final files = build(IconTarget.watchos).files;
      final contents =
          jsonDecode(
                utf8.decode(files['watchos/AppIcon.appiconset/Contents.json']!),
              )
              as Map;
      final images = (contents['images'] as List).cast<Map<String, Object?>>();
      expect(images.length, 17);
      for (final image in images) {
        final file = files['watchos/AppIcon.appiconset/${image['filename']}']!;
        final decoded = _png(file);
        expect(decoded.width, decoded.height);
      }
    });

    test('banners have their exact sizes', () {
      final tv = _png(build(IconTarget.androidTv).files.values.single);
      expect((tv.width, tv.height), (320, 180));
      final feature = _png(build(IconTarget.playBanner).files.values.single);
      expect((feature.width, feature.height), (1024, 500));
    });

    test('tvOS app icon sizes', () {
      final small = IconComposer(
        _logo(),
        const IconDesign(colors: [(1, 2, 3)]),
      );
      final files = IconTargets.build(IconTarget.tvos, small).files;
      expect(_png(files['tvos/AppIcon-400x240.png']!).height, 240);
      expect(files.length, 7);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('the command', () {
    late Directory root;
    late String project;
    late List<String> out;
    late String source;

    setUp(() {
      root = Directory.systemTemp.createTempSync('icons_targets_');
      project = p.join(root.path, 'app');
      for (final folder in ['ios/Runner', 'android/app/src/main/res', 'web']) {
        Directory(p.join(project, folder)).createSync(recursive: true);
      }
      out = [];
      source = p.join(root.path, 'logo.png');
      File(source).writeAsBytesSync(PngEncoder.encode(_logo()));
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> run(List<String> args) =>
        (CommandRunner<void>('xcross', 't')..addCommand(
              IconsCommand(
                fileSystem: detectPlatformHost().fileSystem,
                currentDirectory: () => project,
                write: out.add,
                input: const Stream.empty(),
                now: () => DateTime(2026, 11, 4, 12),
              ),
            ))
            .run(['icons', 'generate', ...args]);

    test('AC-024-15 --output and --zip touch nothing in the project', () async {
      final output = p.join(root.path, 'out');
      await run([
        source,
        '--targets',
        'android,notification',
        '--output',
        output,
      ]);
      expect(
        File(
          p.join(
            output,
            'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(project, 'android/app/src/main/res')).listSync(),
        isEmpty,
      );

      final zip = p.join(root.path, 'all.zip');
      await run([source, '--targets', 'play-banner,android-tv', '--zip', zip]);
      final names = ZipDecoder()
          .decodeBytes(File(zip).readAsBytesSync())
          .map((f) => f.name);
      expect(names, contains('play-store/feature-graphic.png'));
      expect(names, contains('android-tv/drawable-xhdpi/banner.png'));
    });

    test('AC-024-5 the same design gives the same archive', () async {
      final a = p.join(root.path, 'a.zip');
      final b = p.join(root.path, 'b.zip');
      await run([source, '--targets', 'web', '--zip', a]);
      await run([source, '--targets', 'web', '--zip', b]);
      expect(File(a).readAsBytesSync(), File(b).readAsBytesSync());
    });

    test('AC-024-15 all: the folders the project has; a named missing one '
        'stops', () async {
      await run([source, '--targets', 'all', '--json']);
      final json = jsonDecode(out.last) as Map<String, Object?>;
      expect((json['targets']! as Map).keys, ['ios', 'android', 'web']);
      expect((json['notes']! as List).single, contains('macos'));
      await expectLater(
        run([source, '--targets', 'macos']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('icons.target_missing'),
          ),
        ),
      );
      await expectLater(
        run([source, '--targets', 'watchos']),
        throwsA(isA<CliError>()),
      );
    });

    test('AC-024-16 replaced files are backed up with their paths', () async {
      final icon = File(p.join(project, 'web', 'favicon.png'))
        ..writeAsBytesSync([1, 2, 3]);
      File(
        p.join(project, 'web', 'manifest.json'),
      ).writeAsStringSync('{"name":"x","icons":[]}');
      await run([source, '--targets', 'web', '--json']);
      final json = jsonDecode(out.last) as Map<String, Object?>;
      final backup = json['backup']! as String;
      expect(p.basename(backup), '20261104-120000');
      expect(File(p.join(backup, 'web', 'favicon.png')).readAsBytesSync(), [
        1,
        2,
        3,
      ]);
      expect(icon.readAsBytesSync().length, greaterThan(3));
      expect(
        File(p.join(project, 'web', 'manifest.json')).readAsStringSync(),
        contains('Icon-maskable-192.png'),
      );
    });

    test('AC-024-20 settings saved, then regenerated the same', () async {
      final first = p.join(root.path, 'first.zip');
      final second = p.join(root.path, 'second.zip');
      final copied = p.join(project, 'logo.png');
      File(source).copySync(copied);
      await run([
        copied,
        '--padding',
        '10,12,14,16',
        '--texture',
        'waves',
        '--targets',
        'web',
        '--background',
        '#123456',
        '--zip',
        first,
        '--save-config',
      ]);
      final saved =
          jsonDecode(
                File(p.join(project, 'xcross_assets.json')).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect((saved['icons']! as Map)['source'], 'logo.png');
      await run(['--config', '--zip', second]);
      expect(File(first).readAsBytesSync(), File(second).readAsBytesSync());
    });

    test('bad values are usage errors', () async {
      for (final args in [
        ['--padding', '60,0,60,0'],
        ['--foreground', 'red'],
        ['--name', 'Bad-Name'],
        ['--targets', 'windows'],
        ['--background-type', 'image'],
      ]) {
        await expectLater(
          run([source, ...args, '--output', p.join(root.path, 'x')]),
          throwsA(isA<UsageException>()),
          reason: args.join(' '),
        );
      }
    });
  });

  group('preview', () {
    test('draws each design it is sent, and says so on a bad one', () async {
      final root = Directory.systemTemp.createTempSync('icons_preview_');
      addTearDown(() => root.deleteSync(recursive: true));
      final source = p.join(root.path, 'logo.png');
      File(source).writeAsBytesSync(PngEncoder.encode(_logo()));
      final out = <String>[];
      final input = StreamController<List<int>>();
      final done =
          (CommandRunner<void>('xcross', 't')..addCommand(
                IconsPreviewCommand(
                  fileSystem: detectPlatformHost().fileSystem,
                  write: out.add,
                  input: input.stream,
                ),
              ))
              .run(['preview', '--serve', '--output', p.join(root.path, 'p')]);
      input
        ..add(
          utf8.encode(
            '${jsonEncode({'seq': 1, 'source': source, 'padding': '10', 'background': '#112233'})}\n',
          ),
        )
        ..add(
          utf8.encode(
            '${jsonEncode({'seq': 2, 'source': source, 'padding': '99'})}\n',
          ),
        )
        ..add(utf8.encode('${jsonEncode({'seq': 3, 'source': source})}\n'));
      await input.close();
      await done;
      final first = jsonDecode(out[0]) as Map<String, Object?>;
      expect(first['seq'], 1);
      final paths = first['paths']! as Map;
      expect(
        paths.keys,
        containsAll(['full', 'adaptive', 'maskable', 'silhouette', 'banner']),
      );
      final second = jsonDecode(out[1]) as Map<String, Object?>;
      expect(second['error'], contains('--padding'));
      final third = jsonDecode(out[2]) as Map<String, Object?>;
      final image = (third['paths']! as Map)['full'] as String;
      expect(
        _png(File(image).readAsBytesSync()).width,
        IconsPreviewCommand.previewSize,
      );
      // The earlier request's images are gone.
      expect(File(paths['full'] as String).existsSync(), isFalse);
    });
  });
}
