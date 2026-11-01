// studio: 004 — opt-in byte parity with AssetKit's actool reference.
//
// Set ASSETKIT_FIXTURES to a local AssetKit checkout's
// `Tests/AssetKitTests/Fixtures` folder. The reference files are actool
// output and are not committed here.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/csi_writer.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';
import 'package:test/test.dart';

void main() {
  final fixtures = Platform.environment['ASSETKIT_FIXTURES'];

  test('AC-004-1 JPEG CSI record matches actool byte for byte', () {
    final source = File(
      p.join(fixtures!, 'Test.xcassets', 'Jpg.imageset', 'Jpg@2x.jpg'),
    ).readAsBytesSync();
    final (width, height) = JpegDimensions.read(source);
    final encoded = CsiWriter.jpeg(
      JpegBody(
        width: width,
        height: height,
        source: source,
        renditionName: 'Jpg@2x.jpg',
      ),
      scaleFactor: 200,
    );
    final reference = File(
      p.join(fixtures, 'Reference', 'Jpg.csi.bin'),
    ).readAsBytesSync();
    expect(encoded, reference);
  }, skip: fixtures == null ? 'set ASSETKIT_FIXTURES to run' : false);
}
