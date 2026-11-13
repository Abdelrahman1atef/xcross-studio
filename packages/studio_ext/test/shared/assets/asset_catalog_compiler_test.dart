// studio: 004 — `.xcassets` → `Assets.car`, icon keys and loose PNGs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:studio_ext/src/shared/assets/csi_writer.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';
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
    // Every icon size is in the catalog under its own Icon Index (slot 5),
    // as in actool's: 60 pt is index 6, so 60@2x is the one at index 6.
    final icons = csis.where((r) => r.$1[8] == 220).toList();
    final iphone2x = icons.singleWhere(
      (r) => r.$1[3] == 1 && r.$1[2] == 2 && r.$1[5] == 6,
    );
    expect(iphone2x.$2.width, 120);
    expect(
      icons.map((r) => (r.$1[3], r.$1[2], r.$1[5])).toSet(),
      hasLength(icons.length),
    );
    expect(icons.length, greaterThan(6));
    // Each idiom of the set has its icon set record (part 218).
    final sets = csis.where((r) => r.$1[8] == 218).map((r) => r.$1[3]).toSet();
    expect(sets, {1, 2, 6});
    // App Store Connect reads the large icon from here (error 91111).
    final store = icons.singleWhere((r) => r.$1[3] == 6).$2;
    expect(icons.singleWhere((r) => r.$1[3] == 6).$1[2], 1);
    expect(icons.singleWhere((r) => r.$1[3] == 6).$1[5], 11);
    expect((store.width, store.height), (1024, 1024));
    expect(store.name, 'Icon-App-1024x1024@1x.png');
    expect(store.flags & CsiWriter.flagOpaque, CsiWriter.flagOpaque);
    expect(iphone2x.$2.flags & CsiWriter.flagOpaque, 0);
    expect(
      store.mlecPixels,
      PngDecoder.decode(
        File(
          '$catalog/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
        ).readAsBytesSync(),
      ).toPremultipliedBgra(),
    );
  });

  group('App Store icon', () {
    String iconSet(Uint8List png, {String size = '1024x1024'}) {
      final catalog = '${temp.path}/Assets.xcassets';
      writeBytes('$catalog/AppIcon.appiconset/store.png', png);
      writeBytes(
        '$catalog/AppIcon.appiconset/phone.png',
        solidPng(120, 120, (9, 9, 9, 255)),
      );
      writeJson('$catalog/AppIcon.appiconset/Contents.json', {
        'images': [
          {
            'idiom': 'iphone',
            'size': '60x60',
            'scale': '2x',
            'filename': 'phone.png',
          },
          {
            'idiom': 'ios-marketing',
            'size': size,
            'scale': '1x',
            'filename': 'store.png',
          },
        ],
      });
      return catalog;
    }

    Iterable<(List<int>, Csi)> storeRenditions(CompiledAssetCatalog result) => [
      for (final (key, csi) in CarFile(result.car).renditions)
        if (key[8] == 220 && key[3] == 6) (key, Csi(csi)),
    ];

    test('with transparency it is not marked opaque', () {
      final result = compiler.compile([
        iconSet(solidPng(1024, 1024, (9, 9, 9, 200))),
      ], deploymentTarget: '16.0');
      expect(result.issues, isEmpty);
      expect(storeRenditions(result).single.$2.flags & CsiWriter.flagOpaque, 0);
    });

    test('of the wrong size is reported and left out', () {
      final result = compiler.compile([
        iconSet(solidPng(512, 512, (9, 9, 9, 255))),
      ], deploymentTarget: '16.0');
      expect(storeRenditions(result), isEmpty);
      final issue = result.issues.single;
      expect(issue.kind, AssetCatalogIssueKind.invalid);
      expect(issue.subject, 'AppIcon/store.png');
      expect(issue.message, allOf(contains('512×512'), contains('1024×1024')));
      expect(result.looseFiles.single.name, 'AppIcon60x60@2x.png');
    });

    test('with a broken file is reported once and left out', () {
      final result = compiler.compile([
        iconSet(Uint8List.fromList([1, 2, 3])),
      ], deploymentTarget: '16.0');
      expect(storeRenditions(result), isEmpty);
      expect(result.issues.single.subject, 'AppIcon/store.png');
    });

    test('a set without one still compiles', () {
      final catalog = iconSet(solidPng(1024, 1024, (9, 9, 9, 255)));
      writeJson('$catalog/AppIcon.appiconset/Contents.json', {
        'images': [
          {
            'idiom': 'iphone',
            'size': '60x60',
            'scale': '2x',
            'filename': 'phone.png',
          },
        ],
      });
      final result = compiler.compile([catalog], deploymentTarget: '16.0');
      expect(result.issues, isEmpty);
      expect(storeRenditions(result), isEmpty);
    });
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
    // The source itself is the App Store icon, and only in the catalog.
    expect(loose.keys.where((name) => name.contains('1024')), isEmpty);
    final store = [
      for (final (key, csi) in CarFile(result.car).renditions)
        if (key[8] == 220 && key[3] == 6) Csi(csi),
    ].single;
    expect((store.width, store.height), (1024, 1024));
    expect(store.name, 'icon.png');
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
    final darkBody = ByteData.sublistView(dark.body);
    expect(darkBody.getUint32(8, Endian.little), 2, reason: 'colour space');
  });

  group(
    "a named colour is written as iOS looks it up, as in actool's output",
    () {
      late CarFile car;

      setUp(() {
        final catalog = '${temp.path}/Assets.xcassets';
        writeJson('$catalog/Back.colorset/Contents.json', {
          'colors': [
            {
              'idiom': 'universal',
              'color': {
                'color-space': 'srgb',
                'components': {
                  'red': '1.000',
                  'green': '0.000',
                  'blue': '0.000',
                  'alpha': '0.500',
                },
              },
            },
          ],
        });
        car = CarFile(
          compiler.compile([catalog], deploymentTarget: '16.0').car,
        );
      });

      test('its facet names element 85, part 217 and its identifier', () {
        final (name, facet) = car.tree('FACETKEYS').entries.single;
        expect(utf8.decode(name), 'Back');
        final view = ByteData.sublistView(facet);
        final identifier = AssetNameHash.of('Back');
        expect(
          [
            for (var i = 0; i < facet.length; i += 2)
              view.getUint16(i, Endian.little),
          ],
          [0, 0, 3, 1, 85, 2, 217, 17, identifier],
        );
      });

      test('its key has scale 1, element 85 and part 217', () {
        final (key, _) = car.renditions.single;
        // Appearance, localization, scale, idiom, subtype, dimension 2,
        // identifier, element, part.
        expect(key, [0, 0, 1, 0, 0, 0, AssetNameHash.of('Back'), 85, 217]);
      });

      test(
        'its record has scale 0, blend and orientation, then the colour',
        () {
          final (_, bytes) = car.renditions.single;
          final csi = Csi(bytes);
          expect(csi.scaleFactor, 0);
          expect(csi.width, 0);
          expect(csi.height, 0);
          expect(csi.layout, 1009);
          expect(csi.name, 'Back');
          expect(csi.tvlLength, 28);
          expect(csi.renditionLength, 48);
          expect(csi.tvl[1004], List.filled(8, 0));
          expect(csi.tvl[1006], [1, 0, 0, 0]);
          expect(ascii.decode(csi.body.sublist(0, 4)), 'RLOC');
          final body = ByteData.sublistView(csi.body);
          expect(body.getUint32(12, Endian.little), 4, reason: 'components');
          expect(body.getFloat64(16, Endian.little), 1);
          expect(body.getFloat64(40, Endian.little), 0.5);
        },
      );

      test("its fixed bytes equal a colour record from Apple's actool", () {
        // Read from the Assets.car of two shipped apps built with Xcode, one
        // an sRGB colour with these same fixed fields.
        final (_, bytes) = car.renditions.single;
        final csi = Csi(bytes);
        expect(bytes.sublist(0, 40), [
          ...ascii.encode('ISTC'),
          1, 0, 0, 0, // version
          0, 0, 0, 0, // flags
          0, 0, 0, 0, // width
          0, 0, 0, 0, // height
          0, 0, 0, 0, // scale
          0, 0, 0, 0, // pixel format
          0, 0, 0, 0, // colour space
          0, 0, 0, 0, // modification time
          0xF1, 0x03, 0, 0, // layout 1009
        ]);
        expect(bytes.sublist(168, 184), [
          28, 0, 0, 0, // TVL length
          1, 0, 0, 0, // bitmap count
          0, 0, 0, 0,
          48, 0, 0, 0, // record length
        ]);
        expect(bytes.sublist(184, 212), [
          0xEC,
          0x03,
          0,
          0,
          8,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0xEE,
          0x03,
          0,
          0,
          4,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
        ]);
        expect(csi.body.sublist(0, 16), [
          ...ascii.encode('RLOC'),
          1, 0, 0, 0, // record version
          1, 0, 0, 0, // sRGB
          4, 0, 0, 0, // components
        ]);
      });
    },
  );

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

  group('the launch image', () {
    const blue = (0, 0, 255);
    const navy = (0, 0, 64);

    Map<String, Object?> colorEntry(
      (int, int, int) color, {
      bool dark = false,
    }) => {
      'idiom': 'universal',
      if (dark)
        'appearances': [
          {'appearance': 'luminosity', 'value': 'dark'},
        ],
      'color': {
        'color-space': 'srgb',
        'components': {
          'red': '0x${color.$1.toRadixString(16)}',
          'green': '0x${color.$2.toRadixString(16)}',
          'blue': '0x${color.$3.toRadixString(16)}',
          'alpha': '1.000',
        },
      },
    };

    /// `Splash.imageset` with one PNG, and with [darkPng] a dark one too.
    String catalog({
      Uint8List? png,
      Uint8List? darkPng,
      (int, int, int)? color,
      (int, int, int)? darkColor,
    }) {
      final path = '${temp.path}/Assets.xcassets';
      writeJson('$path/Splash.imageset/Contents.json', {
        'images': [
          {'idiom': 'universal', 'filename': 's.png', 'scale': '1x'},
          if (darkPng != null)
            {
              'idiom': 'universal',
              'filename': 'd.png',
              'scale': '1x',
              'appearances': [
                {'appearance': 'luminosity', 'value': 'dark'},
              ],
            },
        ],
      });
      writeBytes(
        '$path/Splash.imageset/s.png',
        png ?? solidPng(4, 4, (0, 0, 0, 0)),
      );
      if (darkPng != null) {
        writeBytes('$path/Splash.imageset/d.png', darkPng);
      }
      if (color != null) {
        writeJson('$path/Back.colorset/Contents.json', {
          'colors': [
            colorEntry(color),
            if (darkColor != null) colorEntry(darkColor, dark: true),
          ],
        });
      }
      return path;
    }

    const whiteFallback = CatalogColor(red: 1, green: 1, blue: 1);

    const backdrop = LaunchBackdrop(
      imageName: 'Splash',
      colorName: 'Back',
      color: whiteFallback,
    );

    /// Image renditions as `(dark, CSI)`, light first.
    List<(bool, Csi)> images(Uint8List car) => [
      for (final (key, bytes) in CarFile(car).renditions)
        if (key[8] == 181) (key[0] == 1, Csi(bytes)),
    ]..sort((a, b) => (a.$1 ? 1 : 0) - (b.$1 ? 1 : 0));

    List<int> corner(Csi csi) => csi.mlecPixels.sublist(0, 4);

    /// The pixel in the middle of the canvas.
    List<int> centre(Csi csi) {
      final at = ((csi.height ~/ 2) * csi.width + csi.width ~/ 2) * 4;
      return csi.mlecPixels.sublist(at, at + 4);
    }

    test('transparent pixels become its colour, in light and dark', () {
      final result = compiler.compile(
        [catalog(color: blue, darkColor: navy)],
        deploymentTarget: '16.0',
        launch: backdrop,
      );
      expect(result.issues, isEmpty);
      final all = images(result.car);
      expect([for (final (dark, _) in all) dark], [false, true]);
      expect(corner(all.first.$2), [255, 0, 0, 255], reason: 'BGRA');
      expect(corner(all.last.$2), [64, 0, 0, 255], reason: 'BGRA');
      for (final (_, csi) in all) {
        expect(csi.flags, CsiWriter.flagImage, reason: 'a generic image');
      }
    });

    test(
      'the picture sits in the middle of a canvas shaped like the screen',
      () {
        final path = '${temp.path}/Assets.xcassets';
        writeJson('$path/Splash.imageset/Contents.json', {
          'images': [
            {'idiom': 'universal', 'filename': 'a.png', 'scale': '2x'},
            {'idiom': 'universal', 'filename': 'b.png', 'scale': '3x'},
            {'idiom': 'ipad', 'filename': 'c.png', 'scale': '2x'},
          ],
        });
        writeBytes(
          '$path/Splash.imageset/a.png',
          solidPng(8, 8, (9, 8, 7, 255)),
        );
        writeBytes(
          '$path/Splash.imageset/b.png',
          solidPng(12, 12, (9, 8, 7, 255)),
        );
        writeBytes(
          '$path/Splash.imageset/c.png',
          solidPng(8, 8, (9, 8, 7, 255)),
        );
        writeJson('$path/Back.colorset/Contents.json', {
          'colors': [colorEntry(blue)],
        });
        final result = compiler.compile(
          [path],
          deploymentTarget: '16.0',
          launch: backdrop,
        );
        final sizes = {
          for (final (_, csi) in images(result.car))
            '${csi.scaleFactor ~/ 100}x ${csi.width}x${csi.height}': csi,
        };
        // iPhone X is 375 x 812 points, the iPad canvas 768 x 1024.
        expect(
          sizes.keys,
          unorderedEquals(['2x 750x1624', '3x 1125x2436', '2x 1536x2048']),
        );
        for (final csi in sizes.values) {
          expect(corner(csi), [
            255,
            0,
            0,
            255,
          ], reason: 'the background colour');
          expect(centre(csi), [7, 8, 9, 255], reason: 'the picture');
        }
      },
    );

    test('a canvas never cuts the picture, and keeps the screen shape', () {
      final result = compiler.compile(
        [catalog(png: solidPng(1000, 1000, (9, 8, 7, 255)), color: blue)],
        deploymentTarget: '16.0',
        launch: backdrop,
      );
      final csi = images(result.car).single.$2;
      expect(csi.width, greaterThanOrEqualTo(1000));
      expect(csi.height, greaterThanOrEqualTo(1000));
      expect(csi.height / csi.width, closeTo(812 / 375, 0.01));
      expect(centre(csi), [7, 8, 9, 255]);
    });

    test('a half transparent pixel blends with the colour', () {
      final result = compiler.compile(
        [
          catalog(
            png: solidPng(2, 2, (255, 0, 0, 128)),
            color: (255, 255, 255),
          ),
        ],
        deploymentTarget: '16.0',
        launch: backdrop,
      );
      expect(centre(images(result.car).single.$2), [127, 127, 255, 255]);
    });

    test('an opaque pixel keeps its colour', () {
      final result = compiler.compile(
        [catalog(png: solidPng(2, 2, (9, 8, 7, 255)), color: blue)],
        deploymentTarget: '16.0',
        launch: backdrop,
      );
      expect(centre(images(result.car).single.$2), [7, 8, 9, 255]);
    });

    test('the same colour in dark adds no second image', () {
      final result = compiler.compile(
        [catalog(color: blue, darkColor: blue)],
        deploymentTarget: '16.0',
        launch: backdrop,
      );
      expect(images(result.car), hasLength(1));
    });

    test('its own dark image is drawn over the dark colour', () {
      final result = compiler.compile(
        [
          catalog(
            darkPng: solidPng(4, 4, (0, 0, 0, 0)),
            color: blue,
            darkColor: navy,
          ),
        ],
        deploymentTarget: '16.0',
        launch: backdrop,
      );
      final all = images(result.car);
      expect(all, hasLength(2));
      expect(corner(all.last.$2), [64, 0, 0, 255]);
    });

    test('without the colour set, the given colour is used with its dark', () {
      final result = compiler.compile(
        [catalog()],
        deploymentTarget: '16.0',
        launch: const LaunchBackdrop(
          imageName: 'Splash',
          colorName: 'Nothing',
          color: CatalogColor(
            red: 0,
            green: 1,
            blue: 0,
            dark: CatalogColor(red: 1, green: 0, blue: 0),
          ),
        ),
      );
      final all = images(result.car);
      expect(corner(all.first.$2), [0, 255, 0, 255]);
      expect(corner(all.last.$2), [0, 0, 255, 255]);
    });

    test(
      'other images and a catalog with no launch image keep their alpha',
      () {
        final path = catalog(color: blue);
        expect(
          corner(
            images(
              compiler.compile([path], deploymentTarget: '16.0').car,
            ).single.$2,
          ),
          [0, 0, 0, 0],
        );
        expect(
          corner(
            images(
              compiler
                  .compile(
                    [path],
                    deploymentTarget: '16.0',
                    launch: const LaunchBackdrop(
                      imageName: 'SomethingElse',
                      colorName: 'Back',
                      color: whiteFallback,
                    ),
                  )
                  .car,
            ).single.$2,
          ),
          [0, 0, 0, 0],
        );
      },
    );
  });

  group('an image set and a colour set with one name', () {
    late CompiledAssetCatalog result;

    setUp(() {
      final path = '${temp.path}/Assets.xcassets';
      writeJson('$path/LaunchBackground.imageset/Contents.json', {
        'images': [
          {'idiom': 'universal', 'filename': 'background.png', 'scale': '1x'},
        ],
      });
      writeBytes(
        '$path/LaunchBackground.imageset/background.png',
        solidPng(1, 1, (255, 255, 255, 255)),
      );
      writeJson('$path/LaunchBackground.colorset/Contents.json', {
        'colors': [
          {
            'idiom': 'universal',
            'color': {
              'color-space': 'srgb',
              'components': {
                'red': '1.000',
                'green': '1.000',
                'blue': '1.000',
                'alpha': '1.000',
              },
            },
          },
        ],
      });
      result = compiler.compile([path], deploymentTarget: '16.0');
    });

    test('the colour wins, so UIColor(named:) can find it', () {
      expect(result.colorNames, {'LaunchBackground'});
      expect(result.imageNames, isEmpty);
      final car = CarFile(result.car);
      final (name, facet) = car.tree('FACETKEYS').entries.single;
      expect(utf8.decode(name), 'LaunchBackground');
      // Element 85, then the part: 217 for a colour, 181 for an image.
      expect(ByteData.sublistView(facet).getUint16(12, Endian.little), 217);
      expect(
        [for (final (key, _) in car.renditions) key[8]],
        isNot(contains(181)),
        reason: 'no image rendition',
      );
    });

    test('the build is told which folder to delete', () {
      final issue = result.issues.single;
      expect(issue.kind, AssetCatalogIssueKind.invalid);
      expect(issue.subject, 'LaunchBackground');
      expect(issue.message, contains('LaunchBackground.imageset'));
    });
  });
}
