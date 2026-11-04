// studio: 024 — the native splash screen
// (specs/024-icon-splash-studio, User Story 2).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:studio_ext/shared/assets/launch_storyboard.dart';
import 'package:studio_ext/shared/icons/icons_generate_command.dart';
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

    test(
      'AC-026-28 padding makes the logo smaller, and the screen shows it',
      () {
        final image = SplashImages.logoCanvas(
          SplashDesign(logo: _logo(), padding: const IconPadding.all(10)),
          scale: 1,
        );
        expect(
          (image.width, image.height),
          (120, 60),
          reason: 'the same canvas',
        );
        expect(_visible(image), (12, 6, 107, 53), reason: '80% of the logo');
      },
    );

    test('AC-026-28 uneven padding also moves it', () {
      final design = SplashDesign(
        logo: _logo(),
        padding: IconPadding.parse('0,0,0,40')!,
      );
      final image = SplashImages.logoCanvas(design, scale: 1);
      final (left, _, right, _) = _visible(image);
      expect(left, 48, reason: '40% of the width from the left');
      expect(right, 119);
    });

    test('AC-026-28 the logo keeps its shape whatever the padding', () {
      final image = SplashImages.logoCanvas(
        SplashDesign(logo: _logo(), padding: IconPadding.parse('40,0,0,0')!),
        scale: 1,
      );
      final (left, top, right, bottom) = _visible(image);
      expect((right - left + 1) / (bottom - top + 1), closeTo(2, 0.05));
    });

    test('AC-026-29 one margin value cancels out, and that is noticed', () {
      final equal = SplashDesign(
        logo: _logo(),
        margin: const SplashMargin(50, 50, 50, 50),
      );
      expect(equal.marginHasNoEffect, isTrue);
      final image = SplashImages.logoCanvas(equal, scale: 1);
      // In the middle of a larger canvas: exactly where no margin puts it.
      final (left, top, right, bottom) = _visible(image);
      expect((left + right + 1) / 2, image.width / 2);
      expect((top + bottom + 1) / 2, image.height / 2);
      expect(
        SplashDesign(
          logo: _logo(),
          margin: const SplashMargin(50, 0, 0, 0),
        ).marginHasNoEffect,
        isFalse,
      );
      expect(SplashDesign(logo: _logo()).marginHasNoEffect, isFalse);
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

  group('AC-026-12 AC-026-17 the splash preview', () {
    late Directory root;
    late String logo;
    late String branding;

    setUp(() {
      root = Directory.systemTemp.createTempSync('splash_preview_');
      logo = p.join(root.path, 'logo.png');
      branding = p.join(root.path, 'band.png');
      File(logo).writeAsBytesSync(PngEncoder.encode(_logo()));
      File(
        branding,
      ).writeAsBytesSync(PngEncoder.encode(_logo(width: 40, height: 10)));
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<Map<String, Object?>> preview(Map<String, Object?> design) async {
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
      input.add(
        utf8.encode(
          '${jsonEncode({'seq': 1, 'kind': 'splash', 'source': logo, ...design})}\n',
        ),
      );
      await input.close();
      await done;
      final reply = jsonDecode(out.single) as Map<String, Object?>;
      return (reply['paths']! as Map).cast<String, Object?>();
    }

    test('Android gets its logo without the branding iOS has inside', () async {
      final paths = await preview({'branding': branding});
      expect(
        paths.keys,
        containsAll(['logo', 'androidLogo', 'android12', 'branding']),
      );
      RgbaImage image(String key) =>
          _png(File(paths[key]! as String).readAsBytesSync());
      expect(image('logo').height, SplashImages.brandedHeight * 2);
      expect(image('androidLogo').height, 120, reason: '120 pt wide, 60 tall');
    });

    test('with no branding, no second logo is drawn', () async {
      final paths = await preview(const {});
      expect(paths.keys, unorderedEquals(['logo', 'android12']));
    });

    test('a dark design has its dark images', () async {
      final paths = await preview({
        'branding': branding,
        'dark-branding': branding,
      });
      expect(
        paths.keys,
        containsAll(['darkLogo', 'darkAndroidLogo', 'darkBranding']),
      );
    });

    test('a request can name the images it needs', () async {
      final paths = await preview({
        'branding': branding,
        'variants': ['android12'],
      });
      expect(paths.keys, ['android12']);
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
      expect(SplashImages.android12Shrunk(design), isTrue);
      expect(SplashImages.android12Cut(design), isFalse);
      final image = SplashImages.android12Icon(design, scale: 1);
      final (left, top, right, bottom) = _visible(image);
      expect(right - left + 1, closeTo(136, 2));
      expect(bottom - top + 1, closeTo(136, 2));
      expect(left, closeTo(76, 2));
      expect(
        SplashImages.android12Shrunk(SplashDesign(logo: _logo())),
        isFalse,
      );
    });

    group('AC-026-30 the size chosen for Android 12', () {
      final square = _logo(width: 400, height: 400);
      int visibleWidth(SplashDesign design) {
        final (left, _, right, _) = _visible(
          SplashImages.android12Icon(design, scale: 1),
        );
        return right - left + 1;
      }

      for (final width in const [60.0, 135.0, 136.0, 192.0, 250.0]) {
        test('is used as it is at ${width.round()} dp', () {
          expect(
            visibleWidth(SplashDesign(logo: square, android12IconWidth: width)),
            width.round(),
          );
        });
      }

      test('a larger one is reported as cut, and is not shrunk', () {
        final design = SplashDesign(logo: square, android12IconWidth: 250);
        expect(SplashImages.android12Shrunk(design), isFalse);
        expect(SplashImages.android12Cut(design), isTrue);
      });

      test('a square logo that fits the circle is not reported', () {
        expect(
          SplashImages.android12Cut(
            SplashDesign(logo: square, android12IconWidth: 130),
          ),
          isFalse,
        );
      });

      test('a round logo can fill the circle without being cut', () {
        // Only what shows counts, not the transparent corners.
        const size = 192;
        final pixels = Uint8List(size * size * 4);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final dx = x - (size - 1) / 2;
            final dy = y - (size - 1) / 2;
            if (dx * dx + dy * dy <= 94 * 94) {
              pixels.setRange((y * size + x) * 4, (y * size + x) * 4 + 4, [
                0,
                0,
                0,
                255,
              ]);
            }
          }
        }
        expect(
          SplashImages.android12Cut(
            SplashDesign(
              logo: RgbaImage(size, size, pixels),
              android12IconWidth: 192,
            ),
          ),
          isFalse,
        );
      });

      test('with an icon background: a 240 dp canvas and a 160 dp circle', () {
        final design = SplashDesign(
          logo: square,
          android12IconWidth: 150,
          android12IconBackground: (1, 2, 3),
        );
        expect(SplashImages.android12Canvas(design), 240);
        expect(SplashImages.android12Circle(design), 160);
        expect(SplashImages.android12Icon(design, scale: 2).width, 480);
        expect(SplashImages.android12Cut(design), isTrue, reason: '150 > 113');
      });

      test('a dark icon background alone has its own canvas', () {
        final design = SplashDesign(
          logo: square,
          darkAndroid12IconBackground: (1, 2, 3),
        );
        expect(SplashImages.android12Canvas(design), 288);
        expect(SplashImages.android12Canvas(design, dark: true), 240);
      });
    });

    group('Android 12 follows padding and margin', () {
      final square = _logo(height: 100);

      test('AC-026-28 padding makes the icon smaller', () {
        final image = SplashImages.android12Icon(
          SplashDesign(
            logo: square,
            logoWidth: 100,
            padding: const IconPadding.all(25),
          ),
          scale: 1,
        );
        final (left, top, right, bottom) = _visible(image);
        expect((right - left + 1, bottom - top + 1), (50, 50));
        expect((left + right + 1) / 2, 144, reason: 'still in the middle');
      });

      test('AC-026-29 margin moves it by half the difference', () {
        final image = SplashImages.android12Icon(
          SplashDesign(
            logo: square,
            logoWidth: 100,
            margin: const SplashMargin(40, 0, 0, 20),
          ),
          scale: 1,
        );
        final (left, top, right, bottom) = _visible(image);
        expect((left + right + 1) / 2, 154, reason: '10 to the right');
        expect((top + bottom + 1) / 2, 164, reason: '20 down');
      });
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

    group("an old image with the background colour's name", () {
      late File leftover;

      setUp(() {
        leftover = File(
          p.join(
            project,
            'ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png',
          ),
        )..createSync(recursive: true);
        leftover.writeAsStringSync('old');
      });

      test('generate removes it, after a backup, and says so', () async {
        await run(['generate', logo, '--json']);
        final json = lastJson();
        expect(leftover.parent.existsSync(), isFalse);
        expect(json['removed'], [
          'ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png',
        ]);
        expect(
          File(
            p.join(
              json['backup']! as String,
              'ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png',
            ),
          ).readAsStringSync(),
          'old',
        );
        final check = json['check']! as Map<String, Object?>;
        expect(check['warnings'], 0, reason: '${check['issues']}');
      });

      test('generate for Android only leaves it', () async {
        await run(['generate', logo, '--platforms', 'android', '--json']);
        expect(leftover.existsSync(), isTrue);
        expect(lastJson()['removed'], isEmpty);
      });

      test('--output leaves it', () async {
        await run([
          'generate',
          logo,
          '--output',
          p.join(root.path, 'out'),
          '--json',
        ]);
        expect(leftover.existsSync(), isTrue);
      });

      test('check reports it', () async {
        await run(['generate', logo]);
        leftover
          ..createSync(recursive: true)
          ..writeAsStringSync('back again');
        await run(['check', '--json']);
        final issues = (lastJson()['issues']! as List)
            .cast<Map<String, Object?>>();
        expect(issues.map((i) => i['code']), contains('splash.name_clash'));
      });
    });

    group('AC-026-19 a size for each kind of device', () {
      RgbaImage written(String path) =>
          _png(File(p.join(project, path)).readAsBytesSync());

      test('an iPad width adds iPad images and leaves iPhones alone', () async {
        await run(['generate', logo, '--ipad-logo-width', '200']);
        const set = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
        expect(written('$set/LaunchImage-iPad@2x.png').width, 400);
        expect(written('$set/LaunchImage@2x.png').width, 240);
        final contents =
            jsonDecode(
                  File(
                    p.join(project, set, 'Contents.json'),
                  ).readAsStringSync(),
                )
                as Map;
        final images = (contents['images'] as List)
            .cast<Map<String, Object?>>();
        expect(
          images.singleWhere((image) => image['idiom'] == 'ipad')['filename'],
          'LaunchImage-iPad@2x.png',
        );
        expect(
          images.where((image) => image['idiom'] == 'universal'),
          hasLength(3),
        );
      });

      test('without one, no iPad image is written', () async {
        await run(['generate', logo]);
        expect(
          File(
            p.join(
              project,
              'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage-iPad@2x.png',
            ),
          ).existsSync(),
          isFalse,
        );
      });

      test('an iPad image is flattened over the colour too', () async {
        await run(['generate', logo, '--ipad-logo-width', '200']);
        final compiled =
            AssetCatalogCompiler(
              fileSystem: detectPlatformHost().fileSystem,
              paths: p.context,
            ).compile(
              [p.join(project, 'ios/Runner/Assets.xcassets')],
              deploymentTarget: '16.0',
              launch: const LaunchBackdrop(
                imageName: 'LaunchImage',
                colorName: 'LaunchBackground',
                color: CatalogColor(red: 1, green: 1, blue: 1),
              ),
            );
        expect(compiled.issues, isEmpty);
        expect(compiled.imageNames, {'LaunchImage'});
      });

      test('Android 11 and older have their own width', () async {
        await run(['generate', logo, '--android-logo-width', '60']);
        expect(
          written(
            'android/app/src/main/res/drawable-xhdpi/splash_logo.png',
          ).width,
          120,
        );
        const set = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
        expect(written('$set/LaunchImage@2x.png').width, 240, reason: 'iOS');
      });

      test(
        'Android 12 has its own width, and only it warns of its circle',
        () async {
          await run([
            'generate',
            logo,
            '--logo-width',
            '200',
            '--android12-icon-width',
            '100',
            '--json',
          ]);
          final issues = (lastJson()['issues']! as List)
              .cast<Map<String, Object?>>();
          expect(
            issues.map((i) => i['code']),
            isNot(contains('splash.android12_clipped')),
          );
          final icon = written(
            'android/app/src/main/res/drawable-xhdpi/android12_splash.png',
          );
          final (left, _, right, _) = _visible(icon);
          expect(right - left + 1, 200, reason: '100 dp at 2 px per dp');
        },
      );

      for (final option in const [
        '--ipad-logo-width',
        '--android-logo-width',
        '--android12-icon-width',
      ]) {
        test('$option outside 16 to 1024 says so', () {
          expect(
            run(['generate', logo, option, '2000']),
            throwsA(
              isA<UsageException>().having(
                (e) => e.message,
                'message',
                contains(option),
              ),
            ),
          );
        });
      }
    });

    test('AC-026-20 Android 12 icon background, light and dark', () async {
      await run([
        'generate',
        logo,
        '--android12-icon-background',
        '#112233',
        '--dark-android12-icon-background',
        '#445566',
      ]);
      String styles(String folder) => File(
        p.join(project, 'android/app/src/main/res/$folder/styles.xml'),
      ).readAsStringSync();
      expect(
        styles('values-v31'),
        contains(
          '<item name="android:windowSplashScreenIconBackgroundColor">#112233</item>',
        ),
      );
      expect(styles('values-night-v31'), contains('#445566'));
    });

    test('AC-026-20 without one, Android 12 has no icon background', () async {
      await run(['generate', logo]);
      expect(
        File(
          p.join(project, 'android/app/src/main/res/values-v31/styles.xml'),
        ).readAsStringSync(),
        isNot(contains('IconBackgroundColor')),
      );
    });

    group('AC-026-21 branding', () {
      late String band;

      setUp(() {
        band = p.join(root.path, 'band.png');
        File(
          band,
        ).writeAsBytesSync(PngEncoder.encode(_logo(width: 40, height: 10)));
      });

      test('its width and height above the bottom reach Android', () async {
        await run([
          'generate',
          logo,
          '--branding',
          band,
          '--branding-width',
          '100',
          '--branding-bottom',
          '50',
        ]);
        const res = 'android/app/src/main/res';
        expect(
          _png(
            File(
              p.join(project, '$res/drawable-xhdpi/splash_branding.png'),
            ).readAsBytesSync(),
          ).width,
          200,
        );
        expect(
          File(
            p.join(project, '$res/drawable/launch_background.xml'),
          ).readAsStringSync(),
          contains('android:bottom="50dp"'),
        );
      });

      test('its width reaches iOS', () {
        final image = SplashImages.logoCanvas(
          SplashDesign(
            logo: _logo(width: 10, height: 10),
            logoWidth: 10,
            branding: _logo(width: 40, height: 10),
            brandingWidth: 100,
          ),
          scale: 1,
          withBranding: true,
        );
        expect(image.width, 100);
      });
    });

    group('AC-026-22 branding that would be cut off', () {
      List<String> codes() => [
        for (final issue
            in ((lastJson()['check']! as Map)['issues'] as List)
                .cast<Map<String, Object?>>())
          issue['code']! as String,
      ];

      test('warns, naming the heights', () async {
        final band = p.join(root.path, 'band.png');
        File(
          band,
        ).writeAsBytesSync(PngEncoder.encode(_logo(width: 40, height: 10)));
        await run(['generate', logo, '--branding', band, '--json']);
        expect(codes(), contains('splash.branding_clipped'));
        final issue = ((lastJson()['check']! as Map)['issues'] as List)
            .cast<Map<String, Object?>>()
            .singleWhere((i) => i['code'] == 'splash.branding_clipped');
        expect(issue['message'], contains('760 points tall'));
        expect(issue['message'], contains('568 points'));
      });

      test('a splash that fits does not warn', () async {
        await run(['generate', logo, '--json']);
        expect(codes(), isNot(contains('splash.branding_clipped')));
      });
    });

    test('AC-026-23 the new options are saved and read back', () async {
      await run([
        'generate',
        logo,
        '--ipad-logo-width',
        '200',
        '--android-logo-width',
        '60',
        '--android12-icon-width',
        '100',
        '--android12-icon-background',
        '#112233',
        '--branding-width',
        '90',
        '--branding-bottom',
        '40',
        '--save-config',
      ]);
      final saved =
          (jsonDecode(
                    File(
                      p.join(project, 'xcross_assets.json'),
                    ).readAsStringSync(),
                  )
                  as Map)['splash']
              as Map;
      expect(saved['ipad-logo-width'], '200');
      expect(saved['android-logo-width'], '60');
      expect(saved['android12-icon-width'], '100');
      expect(saved['android12-icon-background'], '#112233');
      expect(saved['branding-width'], '90');
      expect(saved['branding-bottom'], '40');

      final output = p.join(root.path, 'again');
      await run(['generate', '--config', '--output', output]);
      expect(
        File(
          p.join(
            output,
            'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage-iPad@2x.png',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(output, 'android/app/src/main/res/values-v31/styles.xml'),
        ).readAsStringSync(),
        contains('#112233'),
      );
    });

    test('the text report says iOS keeps the saved splash', () async {
      await run(['generate', logo]);
      expect(out.last, contains('restart the iPhone, then install again'));
      await run(['generate', logo, '--output', p.join(root.path, 'out')]);
      expect(out.last, isNot(contains('restart the iPhone')));
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

    test(
      'AC-026-30 a chosen Android 12 size that gets cut is reported',
      () async {
        await run([
          'generate',
          logo,
          '--android12-icon-width',
          '250',
          '--json',
        ]);
        final issue = (lastJson()['issues']! as List).single as Map;
        expect(issue['code'], 'splash.android12_clipped');
        expect(issue['message'], contains('192 dp'));
      },
    );

    test('AC-026-29 equal margins say they do nothing', () async {
      await run(['generate', logo, '--margin', '50', '--json']);
      expect([
        for (final issue in lastJson()['issues']! as List)
          (issue as Map)['code'],
      ], contains('splash.margin_no_effect'));
      await run(['generate', logo, '--margin', '80,0,0,0', '--json']);
      expect([
        for (final issue in lastJson()['issues']! as List)
          (issue as Map)['code'],
      ], isNot(contains('splash.margin_no_effect')));
    });

    test('AC-026-30 the Android 12 files follow an icon background', () async {
      await run([
        'generate',
        logo,
        '--android12-icon-background',
        '#112233',
        '--dark-android12-icon-background',
        '#445566',
      ]);
      RgbaImage icon(String folder) => _png(
        File(
          p.join(
            project,
            'android/app/src/main/res/$folder/android12_splash.png',
          ),
        ).readAsBytesSync(),
      );
      expect(
        icon('drawable-xhdpi').width,
        480,
        reason: '240 dp at 2 px per dp',
      );
      expect(icon('drawable-night-xhdpi').width, 480);
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
