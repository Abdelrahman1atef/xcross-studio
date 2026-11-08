// studio: 004 — BOM container, rendition keys, CSI records and the CAR
// blocks, checked against the CoreUI 970 layout AssetKit documents.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:studio_ext/src/shared/assets/bom_writer.dart';
import 'package:studio_ext/src/shared/assets/car_writer.dart';
import 'package:studio_ext/src/shared/assets/csi_writer.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';
import 'package:test/test.dart';

import '../../support/car_reader.dart';

Uint8List _pixels(int width, int height) =>
    Uint8List.fromList([for (var i = 0; i < width * height * 4; i++) i & 0xff]);

BitmapBody _bitmap(
  int width,
  int height, {
  BitmapKind kind = BitmapKind.image,
  String name = 'icon@2x.png',
}) => BitmapBody(
  width: width,
  height: height,
  pixelsBgra: _pixels(width, height),
  colorSpaceId: 1,
  kind: kind,
  renditionName: name,
);

void main() {
  group('BOM', () {
    test('AC-004-1 header: BOMStore, version, block count, index, vars', () {
      final bom = BomWriter();
      bom.setVariable('DEMO', bom.addBlock(Uint8List.fromList([1, 2, 3])));
      final bytes = bom.finalize();
      final data = ByteData.sublistView(bytes);
      expect(ascii.decode(bytes.sublist(0, 8)), 'BOMStore');
      expect(data.getUint32(8), 1);
      expect(data.getUint32(12), 2);
      final car = CarFile(bytes);
      expect(car.blockCount, 2);
      expect(car.block(0), isEmpty);
      expect(car.variable('DEMO'), [1, 2, 3]);
      expect(car.variables.keys, ['DEMO']);
      // Payloads start after the 512-byte header area.
      expect(bytes.sublist(512, 515), [1, 2, 3]);
    });

    test('AC-004-1 trees: sorted keys, value block before key block, '
        'leaf padded to the page size', () {
      final bom = BomWriter();
      final id = BomTree.insert(bom, [
        BomTreeEntry(utf8.encode('charlie'), Uint8List.fromList([3])),
        BomTreeEntry(utf8.encode('alpha'), Uint8List.fromList([1])),
        BomTreeEntry(utf8.encode('bravo'), Uint8List.fromList([2])),
      ]);
      bom.setVariable('TREE', id);
      final tree = CarFile(bom.finalize()).tree('TREE');
      expect(
        [for (final (k, _) in tree.entries) utf8.decode(k)],
        ['alpha', 'bravo', 'charlie'],
      );
      expect([for (final (_, v) in tree.entries) v.single], [1, 2, 3]);
      for (final (value, key) in tree.idPairs) {
        expect(value, lessThan(key));
      }
      expect(tree.blockSize, 4096);
      expect(tree.leafLength, 4096);
      expect(tree.pathInternal, isFalse);
      expect(tree.leafCount, 3);
    });

    test('inline-key trees sort by key and use 1024-byte pages', () {
      final bom = BomWriter();
      bom.setVariable(
        'INLINE',
        BomTree.insertInlineKey(bom, [
          BomInlineKeyEntry(9, Uint8List.fromList([9])),
          BomInlineKeyEntry(2, Uint8List.fromList([2])),
        ]),
      );
      final tree = CarFile(bom.finalize()).tree('INLINE');
      expect(tree.pathInternal, isTrue);
      expect(tree.blockSize, 1024);
      expect([for (final (_, key) in tree.idPairs) key], [2, 9]);
    });

    test('a leaf that would overflow declares a larger page', () {
      expect(BomTree.pageSizeFor(10, 4096), 4096);
      expect(BomTree.pageSizeFor(510, 4096), 4096);
      expect(BomTree.pageSizeFor(511, 4096), 8192);
      expect(BomTree.pageSizeFor(200, 1024), 2048);
    });
  });

  group('rendition keys', () {
    test('9 little-endian u16 slots in KEYFORMAT order', () {
      const key = RenditionKey(
        appearance: 0x0201,
        localization: 0x0403,
        scale: 0x0605,
        idiom: 0x0807,
        subtype: 0x0a09,
        dimension2: 0x0c0b,
        identifier: 0x0e0d,
        element: 0x100f,
        part: 0x1211,
      );
      expect(key.encode(), List.generate(18, (i) => i + 1));
      expect(RenditionKey.decode(key.encode()), key);
      expect(AttributeIds.keyFormat, [7, 13, 12, 15, 16, 9, 17, 1, 2]);
    });

    test('byte order sorts appearance, then scale, then idiom', () {
      int cmp(RenditionKey a, RenditionKey b) =>
          BomTree.compareBytes(a.encode(), b.encode());
      expect(
        cmp(
          const RenditionKey(scale: 2, idiom: 1),
          const RenditionKey(scale: 3, idiom: 1),
        ),
        lessThan(0),
      );
      expect(
        cmp(
          const RenditionKey(scale: 2, idiom: 1),
          const RenditionKey(scale: 2, idiom: 2),
        ),
        lessThan(0),
      );
      expect(
        cmp(const RenditionKey(scale: 3), const RenditionKey(appearance: 1)),
        lessThan(0),
      );
    });

    test('app icons, images, JPEGs and colours land in their slots', () {
      final id = AssetNameHash.of('AppIcon');
      expect(id, getCrc32(utf8.encode('AppIcon')) & 0xffff);
      expect(AssetNameHash.of('AppIcon'), isNot(AssetNameHash.of('Accent')));
      final icon = RenditionKey.of(
        Rendition(
          name: 'AppIcon',
          idiom: AssetIdiom.iphone,
          scale: AssetScale.x2,
          body: _bitmap(120, 120, kind: BitmapKind.appIcon),
        ),
      );
      expect(icon.slots, [0, 0, 2, 1, 0, 1, id, 85, 220]);
      final image = RenditionKey.of(
        Rendition(
          name: 'LaunchImage',
          idiom: AssetIdiom.universal,
          scale: AssetScale.x3,
          dark: true,
          body: _bitmap(3, 3),
        ),
      );
      expect(image.slots.sublist(0, 6), [1, 0, 3, 0, 0, 0]);
      expect(image.slots.sublist(7), [85, 181]);
      final jpeg = RenditionKey.of(
        Rendition(
          name: 'Jpg',
          idiom: AssetIdiom.universal,
          scale: AssetScale.x2,
          body: JpegBody(
            width: 1,
            height: 1,
            source: Uint8List(2),
            renditionName: 'Jpg@2x.jpg',
          ),
        ),
      );
      expect(jpeg.slots.sublist(7), [85, 181]);
      final color = RenditionKey.of(
        const Rendition(
          name: 'Accent',
          idiom: AssetIdiom.universal,
          body: ColorBody(red: 1, green: 0, blue: 0, alpha: 1, colorSpaceId: 1),
        ),
      );
      expect(color.slots.sublist(7), [85, 217]);
      expect(color.scale, 1);
    });
  });

  group('CSI', () {
    test('AC-004-1 bitmap header, 104-byte TVL and MLEC body', () {
      final csi = Csi(
        CsiWriter.bitmap(
          _bitmap(60, 60, kind: BitmapKind.appIcon),
          scaleFactor: 200,
        ),
      );
      expect(csi.bytes.sublist(0, 4), ascii.encode('ISTC'));
      expect(csi.u32(4), 1);
      expect(csi.flags, 0);
      expect(csi.width, 60);
      expect(csi.scaleFactor, 200);
      expect(csi.pixelFormat, 'BGRA');
      expect(csi.colorSpace, 1);
      expect(csi.layout, 12);
      expect(csi.name, 'icon@2x.png');
      expect(csi.tvlLength, 104);
      expect(csi.bitmapCount, 1);
      final tvl = csi.tvl;
      expect(tvl.keys, [1001, 1003, 1004, 1006, 1007]);
      final descriptor = ByteData.sublistView(tvl[1001]!);
      expect(descriptor.getUint32(0, Endian.little), 1);
      expect(descriptor.getUint32(12, Endian.little), 60);
      expect(descriptor.getUint32(16, Endian.little), 60);
      expect(
        ByteData.sublistView(tvl[1004]!).getFloat32(4, Endian.little),
        1.0,
      );
      expect(ByteData.sublistView(tvl[1007]!).getUint32(0, Endian.little), 240);
      expect(csi.renditionLength, csi.body.length);
      // 60 rows split in three KCBC chunks.
      expect(ByteData.sublistView(csi.body).getUint32(12, Endian.little), 3);
      expect(
        ByteData.sublistView(csi.body).getUint32(4, Endian.little),
        MlecBody.compressionLzfse,
      );
      expect(csi.mlecPixels, _pixels(60, 60));
    });

    test('images set the generic-image flag; bytes per row is exact for '
        'every width', () {
      final csi = Csi(CsiWriter.bitmap(_bitmap(29, 29), scaleFactor: 100));
      expect(csi.flags, 0x10);
      expect(
        ByteData.sublistView(csi.tvl[1007]!).getUint32(0, Endian.little),
        116,
      );
      // 29 rows do not divide by three: one chunk.
      expect(ByteData.sublistView(csi.body).getUint32(12, Endian.little), 1);
      expect(csi.mlecPixels, _pixels(29, 29));
    });

    test(r'LZFSE stored frame: bvx-, length, bytes, bvx$', () {
      final frame = LzfseStoredFrame.encode([7, 8, 9]);
      expect(ascii.decode(frame.sublist(0, 4)), 'bvx-');
      expect(ByteData.sublistView(frame).getUint32(4, Endian.little), 3);
      expect(frame.sublist(8, 11), [7, 8, 9]);
      expect(ascii.decode(frame.sublist(11)), r'bvx$');
    });

    test('JPEG passthrough: DWAR flags 0, zero header size, 92-byte TVL', () {
      final source = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
      final csi = Csi(
        CsiWriter.jpeg(
          JpegBody(
            width: 120,
            height: 90,
            source: source,
            renditionName: 'Jpg@2x.jpg',
          ),
          scaleFactor: 200,
        ),
      );
      expect(csi.pixelFormat, 'GEPJ');
      expect(csi.flags, 0x10);
      expect(csi.width, 0);
      expect(csi.tvlLength, 92);
      expect(csi.tvl.keys, [1001, 1003, 1004, 1006]);
      expect(ascii.decode(csi.body.sublist(0, 4)), 'DWAR');
      expect(ByteData.sublistView(csi.body).getUint32(4, Endian.little), 0);
      expect(csi.body.sublist(12), source);
    });

    test('colour: layout 1009, COLR stored as RLOC, four doubles', () {
      final csi = Csi(
        CsiWriter.color(
          'Accent',
          const ColorBody(
            red: 1,
            green: 0,
            blue: 0.5,
            alpha: 1,
            colorSpaceId: 2,
          ),
        ),
      );
      expect(csi.layout, 1009);
      expect(csi.scaleFactor, 0);
      expect(csi.colorSpace, 0, reason: 'the space is in the body');
      expect(csi.bitmapCount, 1);
      expect(csi.name, 'Accent');
      final body = ByteData.sublistView(csi.body);
      expect(ascii.decode(csi.body.sublist(0, 4)), 'RLOC');
      expect(body.getUint32(4, Endian.little), 1, reason: 'body version');
      expect(body.getUint32(8, Endian.little), 2);
      expect(body.getUint32(12, Endian.little), 4);
      expect(body.getFloat64(16 + 16, Endian.little), 0.5);
    });
  });

  group('AC-004-6 app icon set as actool writes it', () {
    Rendition icon(AssetIdiom idiom, AssetScale scale, double points, int px) =>
        Rendition(
          name: 'AppIcon',
          idiom: idiom,
          scale: scale,
          iconPoints: points,
          body: _bitmap(px, px, kind: BitmapKind.appIcon),
        );

    final renditions = [
      icon(AssetIdiom.iphone, AssetScale.x2, 20, 40),
      icon(AssetIdiom.iphone, AssetScale.x2, 60, 120),
      icon(AssetIdiom.iphone, AssetScale.x3, 60, 180),
      icon(AssetIdiom.ipad, AssetScale.x2, 76, 152),
      icon(AssetIdiom.ipad, AssetScale.x2, 83.5, 167),
      icon(AssetIdiom.marketing, AssetScale.x1, 1024, 1024),
    ];

    late CarFile car;
    setUp(() {
      car = CarFile(
        CarWriter(deploymentTarget: '15.0', renditions: renditions).write(),
      );
    });

    test('sizes of one idiom and scale keep their own Icon Index', () {
      final images = [
        for (final (key, csi) in car.renditions)
          if (key[8] == 220) (key, Csi(csi)),
      ];
      expect(images, hasLength(6));
      // dimension2 is the index of the point size: 20 → 1, 60 → 6.
      final iphone2x = {
        for (final (key, csi) in images)
          if (key[3] == 1 && key[2] == 2) key[5]: csi.width,
      };
      expect(iphone2x, {1: 40, 6: 120});
      expect({for (final (key, _) in images) key[5]}, {1, 6, 8, 9, 11});
    });

    test('every idiom has an icon set record with its sizes', () {
      final sets = {
        for (final (key, csi) in car.renditions)
          if (key[8] == 218) key[3]: (key, Csi(csi)),
      };
      expect(sets.keys, [1, 2, 6]);
      for (final (key, csi) in sets.values) {
        expect(key[2], 1);
        expect(key[5], 0);
        expect(key[6], AssetNameHash.of('AppIcon'));
        expect(key[7], 85);
        expect(csi.layout, 1010);
        expect(csi.name, 'AppIcon');
        expect((csi.width, csi.height, csi.scaleFactor), (0, 0, 0));
        expect(csi.tvl.keys, [1004, 1006]);
      }
      List<int> entries(int idiom) {
        final body = sets[idiom]!.$2.body;
        final data = ByteData.sublistView(body);
        expect(ascii.decode(body.sublist(0, 4)), 'SISM');
        expect(data.getUint32(4, Endian.little), 1);
        final count = data.getUint32(8, Endian.little);
        expect(body, hasLength(12 + count * 12));
        return [
          for (var i = 0; i < count * 3; i++)
            data.getUint32(12 + i * 4, Endian.little),
        ];
      }

      // (width, height, index) per size, in index order; 83.5 is 83.
      expect(entries(1), [20, 20, 1, 60, 60, 6]);
      expect(entries(2), [76, 76, 8, 83, 83, 9]);
      expect(entries(6), [1024, 1024, 11]);
      expect(
        ByteData.sublistView(
          car.variable('CARHEADER'),
        ).getUint32(16, Endian.little),
        9,
      );
    });

    test('BITMAPKEYS lists the scales, idioms and indices that exist', () {
      final descriptor = ByteData.sublistView(
        car.tree('BITMAPKEYS').entries.single.$2,
      );
      expect(descriptor.getUint32(24, Endian.little), 0x0e); // 1×, 2×, 3×
      expect(descriptor.getUint32(28, Endian.little), 0x46); // idioms 1, 2, 6
      expect(descriptor.getUint16(34, Endian.little), 1); // several indices
      // Bit 0 and the indices 1, 6, 8, 9 and 11.
      expect(descriptor.getUint32(36, Endian.little), 0x0b43);
    });
  });

  group('CAR', () {
    final renditions = [
      Rendition(
        name: 'AppIcon',
        idiom: AssetIdiom.iphone,
        scale: AssetScale.x2,
        body: _bitmap(4, 4, kind: BitmapKind.appIcon),
      ),
      Rendition(
        name: 'LaunchImage',
        idiom: AssetIdiom.universal,
        scale: AssetScale.x1,
        body: _bitmap(2, 2),
      ),
      // Same key as the previous one: dropped.
      Rendition(
        name: 'LaunchImage',
        idiom: AssetIdiom.universal,
        scale: AssetScale.x1,
        body: _bitmap(3, 3),
      ),
      const Rendition(
        name: 'Background',
        idiom: AssetIdiom.universal,
        body: ColorBody(red: 1, green: 1, blue: 1, alpha: 1, colorSpaceId: 1),
      ),
    ];

    test('AC-004-1 variables in actool order; header, key format and '
        'metadata blocks', () {
      final car = CarFile(
        CarWriter(deploymentTarget: '13.0', renditions: renditions).write(),
      );
      expect(car.variables.keys, [
        'CARHEADER',
        'RENDITIONS',
        'FACETKEYS',
        'APPEARANCEKEYS',
        'KEYFORMAT',
        'EXTENDED_METADATA',
        'BITMAPKEYS',
      ]);
      final header = car.variable('CARHEADER');
      expect(header, hasLength(436));
      expect(ascii.decode(header.sublist(0, 4)), 'RATC');
      final headerData = ByteData.sublistView(header);
      expect(headerData.getUint32(4, Endian.little), 970);
      expect(headerData.getUint32(8, Endian.little), 17);
      expect(headerData.getUint32(16, Endian.little), 3);

      final format = ByteData.sublistView(car.variable('KEYFORMAT'));
      expect(ascii.decode(car.variable('KEYFORMAT').sublist(0, 4)), 'tmfk');
      expect(format.getUint32(8, Endian.little), 9);
      expect(format.getUint32(12, Endian.little), 7);

      final metadata = car.variable('EXTENDED_METADATA');
      expect(metadata, hasLength(1028));
      expect(ascii.decode(metadata.sublist(0, 4)), 'META');
      expect(ascii.decode(metadata.sublist(0x104, 0x108)), '13.0');
      expect(ascii.decode(metadata.sublist(0x204, 0x207)), 'ios');
    });

    test('FACETKEYS, APPEARANCEKEYS and BITMAPKEYS per asset', () {
      final car = CarFile(
        CarWriter(deploymentTarget: '16.0', renditions: renditions).write(),
      );
      expect(car.renditions, hasLength(3));
      expect(car.facetNames, ['AppIcon', 'Background', 'LaunchImage']);
      final facets = {
        for (final (key, value) in car.tree('FACETKEYS').entries)
          utf8.decode(key): ByteData.sublistView(value),
      };
      final icon = facets['AppIcon']!;
      expect(icon.getUint16(4, Endian.little), 3);
      expect(icon.getUint16(8, Endian.little), 85);
      expect(icon.getUint16(12, Endian.little), 220);
      expect(icon.getUint16(16, Endian.little), AssetNameHash.of('AppIcon'));
      final background = facets['Background']!;
      expect(background.getUint16(4, Endian.little), 3);
      expect(background.getUint16(8, Endian.little), 85);
      expect(background.getUint16(12, Endian.little), 217);

      final appearances = car.tree('APPEARANCEKEYS').entries;
      expect(
        [for (final (k, _) in appearances) utf8.decode(k)],
        ['UIAppearanceAny'],
      );

      final bitmapKeys = car.tree('BITMAPKEYS');
      expect(bitmapKeys.entries, hasLength(2));
      final markers = {
        for (final (key, value) in bitmapKeys.entries)
          ByteData.sublistView(key).getUint32(0): ByteData.sublistView(
            value,
          ).getUint32(24, Endian.little),
      };
      // The marker of an app icon is the mask of its scales: one 2× icon.
      expect(markers[AssetNameHash.of('AppIcon')], 0x04);
      expect(markers[AssetNameHash.of('LaunchImage')], 0x04);
      for (final (_, value) in bitmapKeys.entries) {
        expect(value, hasLength(52));
      }
    });

    test('a dark rendition adds UIAppearanceDark', () {
      final car = CarFile(
        CarWriter(
          deploymentTarget: '16.0',
          renditions: [
            ...renditions,
            const Rendition(
              name: 'Background',
              idiom: AssetIdiom.universal,
              dark: true,
              body: ColorBody(
                red: 0,
                green: 0,
                blue: 0,
                alpha: 1,
                colorSpaceId: 1,
              ),
            ),
          ],
        ).write(),
      );
      expect(
        [
          for (final (k, _) in car.tree('APPEARANCEKEYS').entries)
            utf8.decode(k),
        ],
        ['UIAppearanceAny', 'UIAppearanceDark'],
      );
    });

    test('an empty catalog is a valid BOM without BITMAPKEYS', () {
      final car = CarFile(
        CarWriter(deploymentTarget: '16.0', renditions: const []).write(),
      );
      expect(car.variables.keys, isNot(contains('BITMAPKEYS')));
      expect(car.renditions, isEmpty);
    });
  });
}
