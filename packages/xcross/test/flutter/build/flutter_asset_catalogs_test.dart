// studio: 004 — a Flutter project's Assets.xcassets and LaunchScreen
// storyboard reach the bundle as Assets.car, loose icons, CFBundleIcons and
// UILaunchScreen.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:studio_ext/shared/inspect/inspect_command.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/build/flutter_asset_catalogs.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_resources.dart';

void main() {
  late Directory temp;
  late String runner;
  late String bundle;
  late List<(String, String, String)> warnings;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross-assets-');
    runner = p.join(temp.path, 'ios', 'Runner');
    bundle = p.join(temp.path, 'Runner.app');
    Directory(bundle).createSync(recursive: true);
    warnings = [];
  });
  tearDown(() => temp.deleteSync(recursive: true));

  FlutterAssetCatalogs catalogs() => FlutterAssetCatalogs(
    fileSystem: const AssetTestFileSystem(),
    paths: p.context,
    warn: (code, {required subject, required message}) =>
        warnings.add((code.code, subject, message)),
    trace: (_) {},
  );

  void json(String path, Object value) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(value));

  void png(String path, int size, (int, int, int, int) color) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(solidPng(size, size, color));

  String flutterCatalog() {
    final catalog = p.join(runner, 'Assets.xcassets');
    json(p.join(catalog, 'Contents.json'), {
      'info': {'version': 1, 'author': 'xcode'},
    });
    final images = <Map<String, String>>[];
    for (final (idiom, size, scale) in [
      ('iphone', 60, 2),
      ('iphone', 60, 3),
      ('ipad', 76, 2),
      ('ios-marketing', 1024, 1),
    ]) {
      final name = 'Icon-App-${size}x$size@${scale}x.png';
      images.add({
        'idiom': idiom,
        'size': '${size}x$size',
        'scale': '${scale}x',
        'filename': name,
      });
      png(p.join(catalog, 'AppIcon.appiconset', name), size * scale, (
        0,
        120,
        255,
        255,
      ));
    }
    json(p.join(catalog, 'AppIcon.appiconset', 'Contents.json'), {
      'images': images,
    });
    json(p.join(catalog, 'LaunchImage.imageset', 'Contents.json'), {
      'images': [
        {'idiom': 'universal', 'filename': 'LaunchImage.png', 'scale': '1x'},
        {'idiom': 'universal', 'filename': 'LaunchImage@2x.png', 'scale': '2x'},
      ],
    });
    png(p.join(catalog, 'LaunchImage.imageset', 'LaunchImage.png'), 3, (
      255,
      0,
      0,
      255,
    ));
    png(p.join(catalog, 'LaunchImage.imageset', 'LaunchImage@2x.png'), 6, (
      255,
      0,
      0,
      255,
    ));
    return catalog;
  }

  String storyboard(String color, {String extra = ''}) {
    final path = p.join(runner, 'Base.lproj', 'LaunchScreen.storyboard');
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" launchScreen="YES" initialViewController="vc">
  <scenes><scene sceneID="s"><objects>
    <viewController id="vc" sceneMemberID="viewController">
      <view key="view" contentMode="scaleToFill" id="v">
        <subviews>
          <imageView contentMode="center" image="LaunchImage" id="i"/>
          $extra
        </subviews>
        $color
      </view>
    </viewController>
  </objects></scene></scenes>
</document>''');
    return path;
  }

  const templatePlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.example.app</string>
	<key>CFBundleExecutable</key>
	<string>Runner</string>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
</dict>
</plist>
''';

  test('AC-004-1 AC-004-2 Flutter project: Assets.car, loose icons, '
      'CFBundleIcons and UILaunchScreen', () async {
    final catalog = flutterCatalog();
    final launch = storyboard(
      '<color key="backgroundColor" red="0.2" green="0.4" blue="0.6" '
      'alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
    );
    expect(
      FlutterAssetCatalogs.launchStoryboardName(templatePlist),
      'LaunchScreen',
    );
    final result = catalogs().compile(
      bundleDir: bundle,
      skipped: [
        SkippedResource(catalog, SkippedResourceReason.assetCatalog),
        SkippedResource(launch, SkippedResourceReason.uncompiledStoryboard),
        SkippedResource(
          p.join(runner, 'Base.lproj', 'Main.storyboard'),
          SkippedResourceReason.uncompiledStoryboard,
        ),
      ],
      deploymentTarget: '13.0',
      launchStoryboardName: 'LaunchScreen',
    );

    expect(warnings, isEmpty);
    expect(result.handled, {catalog, launch});
    expect(result.launchStoryboardName, 'LaunchScreen');
    expect(result.launchScreen, {
      'UIColorName': FlutterAssetCatalogs.launchColorName,
      'UIImageName': 'LaunchImage',
    });
    final car = File(p.join(bundle, 'Assets.car')).readAsBytesSync();
    expect(ascii.decode(car.sublist(0, 8)), 'BOMStore');
    for (final name in [
      'AppIcon60x60@2x.png',
      'AppIcon60x60@3x.png',
      'AppIcon76x76@2x~ipad.png',
    ]) {
      expect(File(p.join(bundle, name)).existsSync(), isTrue, reason: name);
    }

    final merged = FlutterAssetCatalogs.mergeInfoPlist(templatePlist, result);
    final plist =
        PropertyListSerialization.propertyListWithString(merged) as Map;
    expect(plist['CFBundleIdentifier'], 'com.example.app');
    expect(plist['CFBundleIconName'], 'AppIcon');
    expect(
      ((plist['CFBundleIcons'] as Map)['CFBundlePrimaryIcon']
          as Map)['CFBundleIconFiles'],
      ['AppIcon60x60'],
    );
    expect(plist['UILaunchScreen'], {
      'UIColorName': 'XCrossLaunchBackground',
      'UIImageName': 'LaunchImage',
    });

    // xcross inspect (feature 001) reads the result back.
    File(p.join(bundle, 'Info.plist')).writeAsStringSync(
      merged.replaceAll(
        '<key>UILaunchStoryboardName</key>\n\t<string>LaunchScreen</string>',
        '',
      ),
    );
    final output = StringBuffer();
    await (CommandRunner<void>('xcross', 'test')..addCommand(
          InspectCommand(
            fileSystem: const AssetTestFileSystem(),
            write: output.write,
          ),
        ))
        .run(['inspect', bundle, '--json']);
    final report = jsonDecode(output.toString()) as Map<String, Object?>;
    final resources = report['resources']! as Map<String, Object?>;
    expect((resources['assetsCar']! as Map)['present'], isTrue);
    final icons = resources['icons']! as Map<String, Object?>;
    expect(
      (icons['declared']! as List).cast<Map<String, Object?>>().every(
        (icon) => icon['resolved'] == true,
      ),
      isTrue,
    );
    final launchScreen = resources['launchScreen']! as Map<String, Object?>;
    expect(launchScreen['kind'], 'UILaunchScreen');
    expect((launchScreen['image']! as Map)['source'], 'asset-catalog');
  });

  test('a developer-written UILaunchScreen is kept', () {
    const result = FlutterAssetCatalogResult(
      launchScreen: {'UIColorName': 'XCrossLaunchBackground'},
      infoPlistAdditions: {'CFBundleIconName': 'AppIcon'},
    );
    final merged = FlutterAssetCatalogs.mergeInfoPlist(
      templatePlist.replaceFirst(
        '</dict>',
        '<key>UILaunchScreen</key><dict><key>UIColorName</key>'
            '<string>Mine</string></dict></dict>',
      ),
      result,
    );
    final plist =
        PropertyListSerialization.propertyListWithString(merged) as Map;
    expect(plist['UILaunchScreen'], {'UIColorName': 'Mine'});
    expect(plist['CFBundleIconName'], 'AppIcon');
    expect(
      FlutterAssetCatalogs.mergeInfoPlist(
        templatePlist,
        FlutterAssetCatalogResult.none,
      ),
      templatePlist,
    );
  });

  test('AC-004-3 AC-004-4 unsupported assets and approximations are '
      'coded warnings; the build goes on', () {
    final catalog = flutterCatalog();
    json(p.join(catalog, 'Vector.imageset', 'Contents.json'), {
      'images': [
        {'idiom': 'universal', 'filename': 'v.pdf'},
      ],
    });
    File(p.join(catalog, 'Vector.imageset', 'v.pdf')).writeAsStringSync('%PDF');
    final launch = storyboard(
      '<color key="backgroundColor" name="SplashColor"/>',
      extra: '<label text="Hello" id="l"/>',
    );
    final result = catalogs().compile(
      bundleDir: bundle,
      skipped: [
        SkippedResource(catalog, SkippedResourceReason.assetCatalog),
        SkippedResource(launch, SkippedResourceReason.uncompiledStoryboard),
      ],
      deploymentTarget: '16.0',
      launchStoryboardName: 'LaunchScreen',
    );
    final codes = {for (final (code, subject, _) in warnings) code: subject};
    expect(codes[XcrossCodes.buildAssetUnsupported.code], 'Vector/v.pdf');
    expect(
      codes[XcrossCodes.buildLaunchScreenApproximated.code],
      'LaunchScreen',
    );
    final approximation = warnings
        .singleWhere(
          (w) => w.$1 == XcrossCodes.buildLaunchScreenApproximated.code,
        )
        .$3;
    expect(approximation, contains('label "Hello"'));
    expect(approximation, contains('colour "SplashColor"'));
    // The named colour is not in the catalog: the white fallback is used.
    expect(result.launchScreen!['UIColorName'], 'XCrossLaunchBackground');
  });

  test('a transparent launch image is drawn over its named colour, and a '
      'leftover image set does not hide that colour', () {
    final catalog = flutterCatalog();
    png(p.join(catalog, 'LaunchImage.imageset', 'LaunchImage.png'), 3, (
      0,
      0,
      0,
      0,
    ));
    json(p.join(catalog, 'LaunchBackground.colorset', 'Contents.json'), {
      'colors': [
        {
          'idiom': 'universal',
          'color': {
            'color-space': 'srgb',
            'components': {
              'red': '0.000',
              'green': '0.000',
              'blue': '1.000',
              'alpha': '1.000',
            },
          },
        },
      ],
    });
    json(p.join(catalog, 'LaunchBackground.imageset', 'Contents.json'), {
      'images': [
        {'idiom': 'universal', 'filename': 'background.png', 'scale': '1x'},
      ],
    });
    png(p.join(catalog, 'LaunchBackground.imageset', 'background.png'), 1, (
      255,
      255,
      255,
      255,
    ));
    final launch = storyboard(
      '<color key="backgroundColor" name="LaunchBackground"/>',
    );

    final result = catalogs().compile(
      bundleDir: bundle,
      skipped: [
        SkippedResource(catalog, SkippedResourceReason.assetCatalog),
        SkippedResource(launch, SkippedResourceReason.uncompiledStoryboard),
      ],
      deploymentTarget: '16.0',
      launchStoryboardName: 'LaunchScreen',
    );

    expect(result.launchScreen, {
      'UIColorName': 'LaunchBackground',
      'UIImageName': 'LaunchImage',
    });
    expect(
      firstPixel(
        File(p.join(bundle, 'Assets.car')).readAsBytesSync(),
        'LaunchImage.png',
      ),
      [255, 0, 0, 255],
      reason: 'BGRA: the blue background, opaque',
    );
    expect(
      warnings.singleWhere((w) => w.$2 == 'LaunchBackground').$1,
      XcrossCodes.buildAssetInvalid.code,
    );
  });

  test('AC-004-4 an unreadable storyboard keeps the old behaviour', () {
    final launch = p.join(runner, 'Base.lproj', 'LaunchScreen.storyboard');
    File(launch)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<document><broken');
    final result = catalogs().compile(
      bundleDir: bundle,
      skipped: [
        SkippedResource(launch, SkippedResourceReason.uncompiledStoryboard),
      ],
      deploymentTarget: '16.0',
      launchStoryboardName: 'LaunchScreen',
    );
    expect(warnings.single.$1, XcrossCodes.buildLaunchScreenUnreadable.code);
    expect(result.launchScreen, isNull);
    expect(result.handled, isEmpty);
    expect(result.launchStoryboardName, isNull);
  });

  test('nothing to compile: no Assets.car, nothing handled', () {
    final result = catalogs().compile(
      bundleDir: bundle,
      skipped: const [],
      deploymentTarget: '16.0',
      launchStoryboardName: 'LaunchScreen',
    );
    expect(result.handled, isEmpty);
    expect(File(p.join(bundle, 'Assets.car')).existsSync(), isFalse);
    expect(
      FlutterAssetCatalogs.launchStoryboardName(
        r'<key>UILaunchStoryboardName</key><string>$(LAUNCH)</string>',
      ),
      isNull,
    );
  });
}

/// The first pixel (BGRA) of the rendition with source file [name] in [car].
@internal
List<int> firstPixel(Uint8List car, String name) {
  final data = ByteData.sublistView(car);
  final tag = ascii.encode('ISTC');
  final wanted = ascii.encode('$name\u0000');
  bool matches(int at, List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      if (car[at + i] != bytes[i]) return false;
    }
    return true;
  }

  for (var i = 0; i + 184 < car.length; i++) {
    if (!matches(i, tag) || !matches(i + 40, wanted)) continue;
    // CSI header, TVL, then MLEC: 16 bytes, chunk header 20, `bvx-` header 8.
    final pixels = i + 184 + data.getUint32(i + 168, Endian.little) + 44;
    return car.sublist(pixels, pixels + 4);
  }
  throw StateError('$name is not in the catalog');
}

/// A solid RGBA8 PNG.
@internal
Uint8List solidPng(int width, int height, (int, int, int, int) color) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      raw.add([color.$1, color.$2, color.$3, color.$4]);
    }
  }
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> body) {
    final bytes = [...ascii.encode(type), ...body];
    out
      ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
      ..add(bytes)
      ..add((ByteData(4)..setUint32(0, getCrc32(bytes))).buffer.asUint8List());
  }

  chunk(
    'IHDR',
    (ByteData(13)
          ..setUint32(0, width)
          ..setUint32(4, height)
          ..setUint8(8, 8)
          ..setUint8(9, 6))
        .buffer
        .asUint8List(),
  );
  chunk('IDAT', const ZLibEncoder().encodeBytes(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

/// dart:io-backed host file system for this test.
@internal
final class AssetTestFileSystem implements HostFileSystemInterface {
  const AssetTestFileSystem();

  @override
  File file(String path) => File(path);
  @override
  Directory directory(String path) => Directory(path);
  @override
  Link link(String path) => Link(path);
  @override
  void makeExecutable(String path) {}
  @override
  void setPermissions(String path, int mode) {}
  @override
  Future<void> createArchiveLink(String destination, String target) =>
      Link(destination).create(target);
}
