// studio: 024 — the native splash screen
// (specs/024-icon-splash-studio, User Story 2).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/assets/launch_storyboard.dart';
import 'package:studio_ext/shared/splash/splash_command.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:studio_ext/src/shared/splash/splash_design.dart';
import 'package:test/test.dart';

/// A dark [width]×[height] logo, opaque.
RgbaImage _logo({int width = 100, int height = 50, int shade = 20}) {
  final out = Uint8List(width * height * 4);
  for (var i = 0; i < out.length; i += 4) {
    out.setRange(i, i + 4, [shade, shade, shade, 255]);
  }
  return RgbaImage(width, height, out);
}

/// Left, top, right, bottom of the visible pixels.
(int, int, int, int) _visible(RgbaImage image) {
  var left = image.width;
  var top = image.height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.rgba[(y * image.width + x) * 4 + 3] < 128) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return (left, top, right, bottom);
}

RgbaImage _png(Uint8List bytes) => PngDecoder.decode(bytes);

void main() {
  group('AC-024-7 padding and margin move the logo', () {
    test('the canvas holds the logo at its width, scaled', () {
      final design = SplashDesign(logo: _logo());
      final image = SplashImages.logoCanvas(design, scale: 2);
      expect((image.width, image.height), (240, 120));
      expect(_visible(image), (0, 0, 239, 119));
    });

    test('padding adds transparent space, in percent of the logo width', () {
      final image = SplashImages.logoCanvas(
        SplashDesign(logo: _logo(), padding: const IconPadding.all(10)),
        scale: 1,
      );
      expect((image.width, image.height), (144, 84));
      expect(_visible(image), (12, 12, 131, 71));
    });

    test('a top margin moves a centred logo down', () {
      final image = SplashImages.logoCanvas(
        SplashDesign(logo: _logo(), margin: const SplashMargin(40, 0, 0, 0)),
        scale: 1,
      );
      expect(image.height, 100);
      expect(_visible(image).$2, 40);
    });

    test('margins parse as one value or four', () {
      expect(SplashMargin.parse('8')!.left, 8);
      expect(SplashMargin.parse('1,2,3,4')!.bottom, 3);
      expect(SplashMargin.parse('-1'), isNull);
      expect(SplashMargin.parse('1,2'), isNull);
    });

    test('a branding image goes near the bottom of a taller image', () {
      final image = SplashImages.logoCanvas(
        SplashDesign(logo: _logo(), branding: _logo(width: 40, height: 10)),
        scale: 1,
        withBranding: true,
      );
      expect(image.height, SplashImages.brandedHeight);
      final (_, top, _, bottom) = _visible(image);
      expect(bottom, image.height - 1, reason: 'the branding');
      expect(top, (image.height - 60) ~/ 2, reason: 'the logo stays centred');
    });
  });

  group('AC-024-7 iOS files', () {
    final design = SplashDesign(
      logo: _logo(),
      darkLogo: _logo(shade: 230),
      background: (250, 250, 250),
      darkBackground: (16, 16, 20),
    );

    test('xcross reads the storyboard back as the image and colour set', () {
      final spec = LaunchStoryboard.parse(SplashFiles.storyboard(design));
      expect(spec.imageName, 'LaunchImage');
      expect(spec.backgroundColorName, 'LaunchBackground');
      expect(spec.approximations, isEmpty);
    });

    test('three scales, each with a dark variant', () {
      final files = SplashFiles.ios(design);
      const set = SplashFiles.iosImageSet;
      expect(_png(files['$set/LaunchImage.png']!).width, 120);
      expect(_png(files['$set/LaunchImage@2x.png']!).width, 240);
      expect(_png(files['$set/LaunchImage@3x.png']!).width, 360);
      expect(files.containsKey('$set/LaunchImageDark@3x.png'), isTrue);
      final contents =
          jsonDecode(utf8.decode(files['$set/Contents.json']!)) as Map;
      final images = (contents['images'] as List).cast<Map<String, Object?>>();
      expect(images.length, 6);
      expect(images.where((i) => i['appearances'] != null).length, 3);
    });

    test('the colour set has light and dark', () {
      final files = SplashFiles.ios(design);
      final contents =
          jsonDecode(
                utf8.decode(files['${SplashFiles.iosColorSet}/Contents.json']!),
              )
              as Map;
      final colors = (contents['colors'] as List).cast<Map<String, Object?>>();
      expect(colors.length, 2);
      expect(colors.last['appearances'], isNotNull);
    });

    test('light only: no dark entries', () {
      final files = SplashFiles.ios(SplashDesign(logo: _logo()));
      expect(files.keys.where((k) => k.contains('Dark')), isEmpty);
    });
  });

  group('AC-024-8 Android files', () {
    const res = 'android/app/src/main/res';

    test('the logo at five densities, the older and Android 12 styles', () {
      final files = SplashFiles.android(
        SplashDesign(logo: _logo(), background: (1, 2, 3)),
      );
      for (final (density, scale) in const [
        ('mdpi', 1.0),
        ('hdpi', 1.5),
        ('xhdpi', 2.0),
        ('xxhdpi', 3.0),
        ('xxxhdpi', 4.0),
      ]) {
        expect(
          _png(files['$res/drawable-$density/splash_logo.png']!).width,
          (120 * scale).round(),
        );
        expect(
          _png(files['$res/drawable-$density/android12_splash.png']!).width,
          (288 * scale).round(),
        );
      }
      final xml = utf8.decode(files['$res/drawable/launch_background.xml']!);
      expect(xml, contains('android:color="#010203"'));
      expect(xml, contains('@drawable/splash_logo'));
      expect(files['$res/drawable-v21/launch_background.xml'], isNotNull);
      final v31 = utf8.decode(files['$res/values-v31/styles.xml']!);
      expect(v31, contains('windowSplashScreenBackground">#010203'));
      expect(v31, contains('@drawable/android12_splash'));
      expect(v31, contains('name="NormalTheme"'));
      expect(files.containsKey('$res/values/styles.xml'), isFalse);
    });

    test('dark gets night folders', () {
      final files = SplashFiles.android(
        SplashDesign(
          logo: _logo(),
          darkLogo: _logo(shade: 230),
          darkBackground: (9, 9, 9),
        ),
      );
      expect(
        utf8.decode(files['$res/drawable-night/launch_background.xml']!),
        contains('#090909'),
      );
      expect(files['$res/drawable-night-xxhdpi/splash_logo.png'], isNotNull);
      expect(
        utf8.decode(files['$res/values-night-v31/styles.xml']!),
        contains('Theme.Black'),
      );
    });

    test('the Android 12 icon keeps a large logo inside the 192 dp circle', () {
      final design = SplashDesign(
        logo: _logo(width: 400, height: 400),
        logoWidth: 300,
      );
      expect(SplashImages.android12Clipped(design), isTrue);
      final image = SplashImages.android12Icon(design, 288);
      final (left, top, right, bottom) = _visible(image);
      expect(right - left + 1, closeTo(136, 2));
      expect(bottom - top + 1, closeTo(136, 2));
      expect(left, closeTo(76, 2));
      expect(
        SplashImages.android12Clipped(SplashDesign(logo: _logo())),
        isFalse,
      );
    });
  });

  group('the command', () {
    late Directory root;
    late String project;
    late List<String> out;
    late String logo;

    setUp(() {
      root = Directory.systemTemp.createTempSync('splash_');
      project = p.join(root.path, 'app');
      for (final folder in [
        'ios/Runner/Base.lproj',
        'ios/Runner/Assets.xcassets',
        'android/app/src/main/res/values',
      ]) {
        Directory(p.join(project, folder)).createSync(recursive: true);
      }
      File(p.join(project, 'ios/Runner/Info.plist')).writeAsStringSync(
        '<key>UILaunchStoryboardName</key><string>LaunchScreen</string>',
      );
      File(
        p.join(project, 'android/app/src/main/res/values/styles.xml'),
      ).writeAsStringSync('<item>@drawable/launch_background</item>');
      out = [];
      logo = p.join(root.path, 'logo.png');
      File(logo).writeAsBytesSync(PngEncoder.encode(_logo()));
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> run(List<String> args) =>
        (CommandRunner<void>('xcross', 't')..addCommand(
              SplashCommand(
                fileSystem: detectPlatformHost().fileSystem,
                currentDirectory: () => project,
                write: out.add,
                now: () => DateTime(2026, 11, 4, 12),
              ),
            ))
            .run(['splash', ...args]);

    Map<String, Object?> lastJson() =>
        jsonDecode(out.last) as Map<String, Object?>;

    test('AC-024-6, AC-024-9 written, then checked clean', () async {
      await run(['generate', logo, '--dark-background', '#101014', '--json']);
      final json = lastJson();
      expect(json['platforms'], ['ios', 'android']);
      expect(json['backup'], isNull);
      final check = json['check']! as Map<String, Object?>;
      expect(check['errors'], 0);
      expect(check['warnings'], 0, reason: '${check['issues']}');
      final ios = check['ios']! as Map<String, Object?>;
      expect(ios['background'], '#FFFFFF');
      expect(ios['darkBackground'], '#101014');
      expect(ios['logo'], 'LaunchImage');
      expect(ios['logoSize'], [120, 60]);
      final android = check['android']! as Map<String, Object?>;
      expect(android['logoSize'], [120, 60]);
      expect(android['android12'], isTrue);
    });

    test('AC-024-10 only the splash files change, after a backup', () async {
      final storyboard = File(
        p.join(project, 'ios/Runner/Base.lproj/LaunchScreen.storyboard'),
      )..writeAsStringSync('mine');
      final styles = File(
        p.join(project, 'android/app/src/main/res/values/styles.xml'),
      );
      final stylesBefore = styles.readAsStringSync();
      await run(['generate', logo, '--json']);
      final backup = lastJson()['backup']! as String;
      expect(
        File(
          p.join(backup, 'ios/Runner/Base.lproj/LaunchScreen.storyboard'),
        ).readAsStringSync(),
        'mine',
      );
      expect(storyboard.readAsStringSync(), contains('LaunchImage'));
      expect(styles.readAsStringSync(), stylesBefore);
    });

    test('--output and --zip touch nothing in the project', () async {
      await run(['generate', logo, '--output', p.join(root.path, 'out')]);
      expect(
        File(
          p.join(root.path, 'out', SplashFiles.iosImageSet, 'LaunchImage.png'),
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(project, 'ios/Runner/Assets.xcassets')).listSync(),
        isEmpty,
      );
    });

    test('AC-024-9 no splash, an empty logo, low contrast, not used', () async {
      await run(['check', '--json']);
      var codes = [
        for (final issue in lastJson()['issues']! as List)
          (issue as Map)['code'],
      ];
      expect(codes, ['splash.missing', 'splash.missing']);

      File(logo).writeAsBytesSync(PngEncoder.encode(_logo(shade: 250)));
      await run([
        'generate',
        logo,
        '--background',
        '#FFFFFF',
        '--platforms',
        'ios',
        '--json',
      ]);
      codes = [
        for (final issue in (lastJson()['check']! as Map)['issues'] as List)
          (issue as Map)['code'],
      ];
      expect(codes, contains('splash.low_contrast'));

      File(
        p.join(project, 'ios/Runner/Info.plist'),
      ).writeAsStringSync('<plist></plist>');
      await run(['check', '--json']);
      codes = [
        for (final issue in lastJson()['issues']! as List)
          (issue as Map)['code'],
      ];
      expect(codes, contains('splash.not_referenced'));
    });

    test('AC-024-9 a logo the storyboard names that is not there', () async {
      await run(['generate', logo, '--platforms', 'ios']);
      Directory(
        p.join(project, SplashFiles.iosImageSet),
      ).deleteSync(recursive: true);
      await expectLater(
        run(['check']),
        throwsA(
          isA<CliError>().having(
            (e) => e.message,
            'message',
            contains('splash.check_failed'),
          ),
        ),
      );
      expect(out.last, contains('splash.logo_missing'));
    });

    test('flutter_native_splash in pubspec.yaml is mentioned', () async {
      File(
        p.join(project, 'pubspec.yaml'),
      ).writeAsStringSync('flutter_native_splash:\n  color: "#000000"\n');
      await run(['check', '--json']);
      expect([
        for (final issue in lastJson()['issues']! as List)
          (issue as Map)['code'],
      ], contains('splash.other_tool'));
    });

    test('AC-024-8 a logo too big for Android 12 is reported', () async {
      await run(['generate', logo, '--logo-width', '300', '--json']);
      expect(
        [
          for (final issue in lastJson()['issues']! as List)
            (issue as Map)['code'],
        ],
        ['splash.android12_clipped'],
      );
    });

    test('AC-024-20 settings saved, then regenerated', () async {
      final copied = p.join(project, 'logo.png');
      File(logo).copySync(copied);
      await run([
        'generate',
        copied,
        '--logo-width',
        '90',
        '--margin',
        '10,0,0,0',
        '--save-config',
      ]);
      final saved =
          jsonDecode(
                File(p.join(project, 'xcross_assets.json')).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect((saved['splash']! as Map)['source'], 'logo.png');
      final output = p.join(root.path, 'again');
      await run(['generate', '--config', '--output', output]);
      expect(
        File(
          p.join(output, SplashFiles.iosImageSet, 'LaunchImage.png'),
        ).readAsBytesSync(),
        File(
          p.join(project, SplashFiles.iosImageSet, 'LaunchImage.png'),
        ).readAsBytesSync(),
      );
    });

    test('bad values are usage errors', () async {
      for (final args in [
        ['--background', 'red'],
        ['--logo-width', '4'],
        ['--margin', 'a'],
        ['--padding', '60'],
        ['--platforms', 'web'],
      ]) {
        await expectLater(
          run(['generate', logo, ...args, '--output', p.join(root.path, 'x')]),
          throwsA(isA<UsageException>()),
          reason: args.join(' '),
        );
      }
    });
  });
}
