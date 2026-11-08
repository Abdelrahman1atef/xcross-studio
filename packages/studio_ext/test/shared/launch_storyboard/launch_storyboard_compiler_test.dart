import 'dart:convert';
import 'dart:typed_data';

import 'package:studio_ext/src/shared/launch_storyboard/binary_plist.dart';
import 'package:studio_ext/src/shared/launch_storyboard/launch_storyboard_compiler.dart';
import 'package:studio_ext/src/shared/launch_storyboard/nib_archive.dart';
import 'package:test/test.dart';

const _view = 'Ze5-6b-2t3.nib';

StoryboardSpec _spec({
  StoryboardColor color = const StoryboardColor(red: 1, green: 1, blue: 1),
  String? image = 'LaunchImage',
  String mode = 'center',
}) =>
    StoryboardSpec(background: color, imageName: image, imageContentMode: mode);

bool _contains(Uint8List bytes, String needle) =>
    latin1.decode(bytes).contains(needle);

void main() {
  test('AC-033-1 emits the three files ibtool emits', () {
    final out = LaunchStoryboardCompiler.compile(_spec())!;
    expect(out.files.keys, {
      '01J-lp-oVM-view-$_view',
      'UIViewController-01J-lp-oVM.nib',
      'Info.plist',
    });
    final nib = out.files['01J-lp-oVM-view-$_view']!;
    expect(ascii.decode(nib.sublist(0, 10)), 'NIBArchive');
    expect(_contains(nib, 'LaunchImage'), isTrue);
    expect(_contains(nib, 'UIImageView'), isTrue);
    expect(ascii.decode(out.files['Info.plist']!.sublist(0, 8)), 'bplist00');
  });

  test('Info.plist is byte identical to the one ibtool writes', () {
    final bytes = LaunchStoryboardCompiler.compile(
      _spec(),
    )!.files['Info.plist']!;
    expect(
      base64.encode(bytes),
      'YnBsaXN0MDDTAQIDBAcIXxAlVUlWaWV3Q29udHJvbGxlcklkZW50aWZpZXJzVG9OaWJOYW1lc18QKlVJU3Rvcnlib2FyZERlc2lnbmF0ZWRFbnRyeVBvaW50SWRlbnRpZmllcl8QE1VJU3Rvcnlib2FyZFZlcnNpb27RBQZfEBtVSVZpZXdDb250cm9sbGVyLTAxSi1scC1vVk1fEBtVSVZpZXdDb250cm9sbGVyLTAxSi1scC1vVk1fEBtVSVZpZXdDb250cm9sbGVyLTAxSi1scC1vVk0QAQgPN2R6fZu51wAAAAAAAAEBAAAAAAAAAAkAAAAAAAAAAAAAAAAAAADZ',
    );
  });

  test('color and image name are substituted', () {
    final out = LaunchStoryboardCompiler.compile(
      _spec(
        color: const StoryboardColor(red: 0.2, green: 0.4, blue: 0.6),
        image: 'Splash',
      ),
    )!;
    final nib = out.files['01J-lp-oVM-view-$_view']!;
    expect(_contains(nib, '0.2 0.4 0.6'), isTrue);
    expect(_contains(nib, 'UIRed-Double'), isTrue);
    expect(_contains(nib, 'Splash'), isTrue);
    expect(_contains(nib, 'LaunchImage'), isFalse);
  });

  test('no image variant drops the image view', () {
    final nib = LaunchStoryboardCompiler.compile(
      _spec(image: null),
    )!.files['01J-lp-oVM-view-$_view']!;
    expect(_contains(nib, 'UIImageView'), isFalse);
  });

  test('gray background uses the white components', () {
    final nib = LaunchStoryboardCompiler.compile(
      _spec(
        color: const StoryboardColor(
          red: 0.5,
          green: 0.5,
          blue: 0.5,
          grayGamma22: true,
        ),
      ),
    )!.files['01J-lp-oVM-view-$_view']!;
    expect(_contains(nib, 'UIWhite'), isTrue);
    expect(_contains(nib, 'NSRGB'), isFalse);
  });

  test('content mode is encoded', () {
    final center = LaunchStoryboardCompiler.compile(_spec())!;
    final fit = LaunchStoryboardCompiler.compile(
      _spec(mode: 'scaleAspectFit'),
    )!;
    expect(
      center.files['01J-lp-oVM-view-$_view'],
      isNot(fit.files['01J-lp-oVM-view-$_view']),
    );
  });

  test('an unknown content mode is not compiled', () {
    expect(
      LaunchStoryboardCompiler.compile(_spec(mode: 'scaleDiagonal')),
      isNull,
    );
  });

  test('NibArchiveWriter header and tables', () {
    final bytes = NibArchiveWriter.write([
      const NibObject('NSObject', [NibValue.int8('A', 1)]),
    ]);
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(10, Endian.little), 1); // version
    expect(data.getUint32(14, Endian.little), 10); // extension
    expect(data.getUint32(18, Endian.little), 1); // objects
    expect(data.getUint32(22, Endian.little), 50); // objects offset
  });

  test('BinaryPlist writes a bplist00 trailer', () {
    final bytes = BinaryPlist.write({'A': 1});
    expect(ascii.decode(bytes.sublist(0, 8)), 'bplist00');
    expect(bytes.length, greaterThan(40));
  });
}
