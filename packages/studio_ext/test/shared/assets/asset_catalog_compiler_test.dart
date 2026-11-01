// studio: 004 — `.xcassets` → `Assets.car`, icon keys and loose PNGs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:test/test.dart';

import '../../support/car_reader.dart';
import '../../support/catalog_fixture.dart';
import '../../support/png_builder.dart';
import '../../support/test_file_system.dart';

void main() {
  late Directory temp;
  final compiler = AssetCatalogCompiler(
    fileSystem: const IoFileSystem(),
    paths: p.context,
  );

  setUp(() => temp = Directory.systemTemp.createTempSync('studio-assets-'));
  tearDown(() => temp.deleteSync(recursive: true));

  Map<String, Object?> primaryIcon(Map<String, Object> additions, String key) =>
      (additions[key]! as Map)['CFBundlePrimaryIcon']! as Map<String, Object?>;

  test('AC-004-1 Flutter catalog: icon keys, loose PNGs and renditions', () {
    final catalog = writeFlutterCatalog(temp.path);
    final result = compiler.compile([catalog], deploymentTarget: '13.0');

    expect(result.issues, isEmpty);
    expect(result.appIconName, 'AppIcon');
    expect(result.imageNames, {'LaunchImage'});

    final additions = result.infoPlistAdditions;
    expect(additions['CFBundleIconName'], 'AppIcon');
    expect((additions['CFBundleIcons']! as Map)['CFBundleIconName'], 'AppIcon');
    final iphone = primaryIcon(additions, 'CFBundleIcons');
    expect(iphone['CFBundleIconName'], 'AppIcon');
    expect(iphone['CFBundleIconFiles'], [
      'AppIcon20x20',
      'AppIcon29x29',
      'AppIcon40x40',
      'AppIcon60x60',
    ]);
    expect(primaryIcon(additions, 'CFBundleIcons~ipad')['CFBundleIconFiles'], [
      'AppIcon20x20',
      'AppIcon29x29',
      'AppIcon40x40',
      'AppIcon76x76',
      'AppIcon83.5x83.5',
    ]);
    expect(
      additions['CFBundleIconFiles'],
      containsAll(['AppIcon60x60', 'AppIcon83.5x83.5']),
    );

    final loose = {for (final f in result.looseFiles) f.name: f.bytes};
    expect(
      loose.keys,
      containsAll([
        'AppIcon60x60@2x.png',
        'AppIcon60x60@3x.png',
        'AppIcon29x29.png',
        'AppIcon76x76@2x~ipad.png',
        'AppIcon83.5x83.5@2x~ipad.png',
      ]),
    );
    expect(loose.keys.where((name) => name.contains('1024')), isEmpty);
    // Loose files are the source PNGs, byte for byte.
    expect(
      loose['AppIcon60x60@2x.png'],
      File(
        '$catalog/AppIcon.appiconset/Icon-App-60x60@2x.png',
      ).readAsBytesSync(),
    );

    final car = CarFile(result.car);
    expect(car.facetNames, ['AppIcon', 'LaunchImage']);
    final csis = [for (final (key, csi) in car.renditions) (key, Csi(csi))];
    final launch = csis.where((r) => r.$2.name.startsWith('LaunchImage'));
    expect(launch, hasLength(3));
    final at3x = launch.singleWhere((r) => r.$1[2] == 3).$2;
    expect((at3x.width, at3x.height), (12, 9));
    expect(
      at3x.mlecPixels,
      PngDecoder.decode(
        File(
          '$catalog/LaunchImage.imageset/LaunchImage@3x.png',
        ).readAsBytesSync(),
      ).toPremultipliedBgra(),
    );
    // One app icon rendition per (idiom, scale): the largest size wins.
    final icons = csis.where((r) => r.$1[8] == 220).toList();
    final iphone2x = icons.singleWhere((r) => r.$1[3] == 1 && r.$1[2] == 2);
    expect(iphone2x.$2.width, 120);
    expect(icons.map((r) => (r.$1[3], r.$1[2])).toSet(), hasLength(5));
  });

  test('AC-004-5 single-size 1024 icon is scaled to every slot', () {
    final set = '${temp.path}/Assets.xcassets/AppIcon.appiconset';
    writeBytes('$set/icon.png', gradientPng(1024, 1024));
    writeJson('$set/Contents.json', {
      'images': [
        {
          'filename': 'icon.png',
          'idiom': 'universal',
          'platform': 'ios',
          'size': '1024x1024',
        },
      ],
      'info': {'version': 1, 'author': 'xcode'},
    });
    final result = compiler.compile([
      '${temp.path}/Assets.xcassets',
    ], deploymentTarget: '16.0');
    expect(result.issues, isEmpty);
    final loose = {for (final f in result.looseFiles) f.name: f.bytes};
    expect(PngDecoder.decode(loose['AppIcon60x60@2x.png']!).width, 120);
    expect(PngDecoder.decode(loose['AppIcon60x60@3x.png']!).width, 180);
    expect(
      PngDecoder.decode(loose['AppIcon83.5x83.5@2x~ipad.png']!).width,
      167,
    );
    expect(
      primaryIcon(
        result.infoPlistAdditions,
        'CFBundleIcons',
      )['CFBundleIconFiles'],
      contains('AppIcon60x60'),
    );
  });

  test('AC-004-3 unsupported and broken assets are reported, the rest '
      'compiles', () {
    final catalog = '${temp.path}/Assets.xcassets';
    writeJson('$catalog/Logo.imageset/Contents.json', {
      'images': [
        {'idiom': 'universal', 'filename': 'logo.svg'},
        {'idiom': 'universal', 'filename': 'logo@2x.png', 'scale': '2x'},
        {'idiom': 'universal', 'filename': 'missing@3x.png', 'scale': '3x'},
      ],
    });
    File('$catalog/Logo.imageset/logo.svg').writeAsStringSync('<svg/>');
    writeBytes(
      '$catalog/Logo.imageset/logo@2x.png',
      solidPng(2, 2, (1, 2, 3, 255)),
    );
    Directory('$catalog/Broken.imageset').createSync(recursive: true);
    File('$catalog/Broken.imageset/Contents.json').writeAsStringSync('{oops');
    writeJson('$catalog/Data.dataset/Contents.json', {'data': <Object>[]});
    writeJson('$catalog/Accent.colorset/Contents.json', {
      'colors': [
        {
          'idiom': 'universal',
          'color': {'platform': 'ios', 'reference': 'systemBlueColor'},
        },
      ],
    });

    final result = compiler.compile([catalog], deploymentTarget: '16.0');
    final kinds = {for (final i in result.issues) i.subject: i.kind};
    expect(kinds['Logo/logo.svg'], AssetCatalogIssueKind.unsupported);
    expect(kinds['Logo/missing@3x.png'], AssetCatalogIssueKind.invalid);
    expect(kinds['Broken.imageset'], AssetCatalogIssueKind.invalid);
    expect(kinds['Data.dataset'], AssetCatalogIssueKind.unsupported);
    expect(kinds['Accent'], AssetCatalogIssueKind.unsupported);
    expect(result.imageNames, {'Logo'});
    expect(CarFile(result.car).facetNames, ['Logo']);
    expect(result.infoPlistAdditions, isEmpty);
    expect(result.looseFiles, isEmpty);
  });

  test('colour sets, namespaced groups, dark variants and added colours', () {
    final catalog = '${temp.path}/Assets.xcassets';
    writeJson('$catalog/Brand/Contents.json', {
      'properties': {'provides-namespace': true},
    });
    writeJson('$catalog/Brand/Primary.colorset/Contents.json', {
      'colors': [
        {
          'idiom': 'universal',
          'color': {
            'color-space': 'srgb',
            'components': {
              'red': '0x80',
              'green': '255',
              'blue': '0.500',
              'alpha': '1.000',
            },
          },
        },
        {
          'idiom': 'universal',
          'appearances': [
            {'appearance': 'luminosity', 'value': 'dark'},
          ],
          'color': {
            'color-space': 'display-p3',
            'components': {'white': '0.2', 'alpha': '1'},
          },
        },
      ],
    });
    final result = compiler.compile(
      [catalog],
      deploymentTarget: '16.0',
      extraColors: const {
        'XCrossLaunchBackground': CatalogColor(
          red: 1,
          green: 1,
          blue: 1,
          dark: CatalogColor(red: 0, green: 0, blue: 0),
        ),
      },
    );
    expect(result.issues, isEmpty);
    expect(result.colorNames, {'Brand/Primary', 'XCrossLaunchBackground'});
    final car = CarFile(result.car);
    expect(car.facetNames, ['Brand/Primary', 'XCrossLaunchBackground']);
    expect(
      [
        for (final (key, _) in car.tree('APPEARANCEKEYS').entries)
          utf8.decode(key),
      ],
      ['UIAppearanceAny', 'UIAppearanceDark'],
    );
    final primary = [
      for (final (key, value) in car.renditions)
        if (Csi(value).name == 'Brand/Primary') (key, Csi(value)),
    ];
    expect(primary, hasLength(2));
    final light = ByteData.sublistView(
      primary.singleWhere((r) => r.$1[0] == 0).$2.body,
    );
    expect(light.getFloat64(16, Endian.little), closeTo(128 / 255, 1e-9));
    expect(light.getFloat64(24, Endian.little), 1.0);
    expect(light.getFloat64(32, Endian.little), 0.5);
    final dark = primary.singleWhere((r) => r.$1[0] == 1).$2;
    expect(dark.colorSpace, 2);
  });

  test('uniformImageColor reads a one-colour background image', () {
    final catalog = '${temp.path}/Assets.xcassets';
    writeJson('$catalog/LaunchBackground.imageset/Contents.json', {
      'images': [
        {'idiom': 'universal', 'filename': 'background.png'},
        {
          'idiom': 'universal',
          'filename': 'darkbackground.png',
          'appearances': [
            {'appearance': 'luminosity', 'value': 'dark'},
          ],
        },
      ],
    });
    writeBytes(
      '$catalog/LaunchBackground.imageset/background.png',
      solidPng(1, 1, (255, 0, 0, 255)),
    );
    writeBytes(
      '$catalog/LaunchBackground.imageset/darkbackground.png',
      solidPng(1, 1, (0, 0, 51, 255)),
    );
    writeJson('$catalog/Photo.imageset/Contents.json', {
      'images': [
        {'idiom': 'universal', 'filename': 'photo.png'},
      ],
    });
    writeBytes('$catalog/Photo.imageset/photo.png', gradientPng(4, 4));

    expect(
      compiler.uniformImageColor([catalog], 'LaunchBackground'),
      const CatalogColor(
        red: 1,
        green: 0,
        blue: 0,
        dark: CatalogColor(red: 0, green: 0, blue: 0.2),
      ),
    );
    expect(compiler.uniformImageColor([catalog], 'Photo'), isNull);
    expect(compiler.uniformImageColor([catalog], 'Nope'), isNull);
  });

  test('only the named app icon set is compiled', () {
    final catalog = '${temp.path}/Assets.xcassets';
    for (final name in ['AppIcon', 'AppIcon-Dev']) {
      writeJson('$catalog/$name.appiconset/Contents.json', {
        'images': [
          {
            'idiom': 'iphone',
            'size': '60x60',
            'scale': '2x',
            'filename': 'i.png',
          },
        ],
      });
      writeBytes(
        '$catalog/$name.appiconset/i.png',
        solidPng(120, 120, (0, 0, 0, 255)),
      );
    }
    final result = compiler.compile([catalog], deploymentTarget: '16.0');
    expect(result.appIconName, 'AppIcon');
    expect(result.issues.single.subject, 'AppIcon-Dev');
    expect(result.looseFiles.single.name, 'AppIcon60x60@2x.png');
  });
}
