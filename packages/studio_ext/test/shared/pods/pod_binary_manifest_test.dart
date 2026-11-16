import 'package:studio_ext/src/shared/pods/pod_binary_manifest.dart';
import 'package:studio_ext/src/shared/pods/pod_xcconfig.dart';
import 'package:test/test.dart';

void main() {
  const writer = PodBinaryManifest();

  test('AC-046-8 WebRTC-SDK has binary and wrapper targets', () {
    final manifest = writer.write(
      pod: 'WebRTC-SDK',
      module: 'WebRTC',
      frameworks: const ['Frameworks/WebRTC.xcframework'],
    );
    expect(manifest, contains('name: "pod-WebRTC-SDK"'));
    expect(
      manifest,
      contains(
        '.binaryTarget(name: "WebRTC", path: "Frameworks/WebRTC.xcframework")',
      ),
    );
    expect(
      manifest,
      contains('.target(name: "WebRTC_xcross", path: "Sources/WebRTC_xcross")'),
    );
    expect(manifest, contains('targets: ["WebRTC", "WebRTC_xcross"]'));
    expect(
      writer.placeholder('WebRTC'),
      'void WebRTC_xcross_anchor(void) {}\n',
    );
  });

  test('AC-046-8 ObjectBox keeps product and binary name', () {
    final manifest = writer.write(
      pod: 'ObjectBox',
      module: 'ObjectBox',
      frameworks: const ['Frameworks/ObjectBox.xcframework'],
    );
    expect(
      manifest,
      contains('name: "ObjectBox", targets: ["ObjectBox", "ObjectBox_xcross"]'),
    );
  });

  test('AC-046-8 MLKitVision has no duplicate target names', () {
    final manifest = writer.write(
      pod: 'MLKitVision',
      module: 'MLKitVision',
      frameworks: const [
        'Frameworks/MLKitVision.xcframework',
        'Frameworks/MLKitVision.xcframework',
      ],
    );
    expect(RegExp(r'\.binaryTarget\(').allMatches(manifest), hasLength(1));
    expect(RegExp(r'\.target\(').allMatches(manifest), hasLength(1));
  });

  test('AC-046-8 rejects paths outside Frameworks', () {
    expect(
      () => writer.write(
        pod: 'Unsafe',
        module: 'Unsafe',
        frameworks: const ['../Unsafe.xcframework'],
      ),
      throwsArgumentError,
    );
  });

  test('AC-046-8 rejects unsafe package and target names', () {
    expect(
      () => writer.write(
        pod: '../Outside',
        module: 'Outside',
        frameworks: const ['Frameworks/Outside.xcframework'],
      ),
      throwsArgumentError,
    );
    expect(
      () => writer.write(
        pod: 'Safe',
        module: '../Outside',
        frameworks: const ['Frameworks/Safe.xcframework'],
      ),
      throwsArgumentError,
    );
  });

  test('AC-046-8 binary wrapper carries MobileVLCKit linker settings', () {
    final manifest = writer.write(
      pod: 'MobileVLCKit',
      module: 'MobileVLCKit',
      frameworks: const ['Frameworks/MobileVLCKit.xcframework'],
      linker: const PodBinaryLinkSettings(
        libraries: ['c++', 'xml2', 'z', 'bz2', 'iconv'],
        frameworks: ['AVFoundation'],
        weakFrameworks: ['CoreBluetooth'],
      ),
    );
    expect(manifest, contains('.linkedLibrary("c++")'));
    expect(manifest, contains('.linkedLibrary("iconv")'));
    expect(manifest, contains('.linkedFramework("AVFoundation")'));
    expect(
      manifest,
      contains('.unsafeFlags(["-weak_framework", "CoreBluetooth"])'),
    );
  });

  test('AC-046-8 reads binary linker flags from consumer attributes', () {
    final linker = PodBinaryLinkSettings.fromConsumer(
      const {
        'libraries': ['xml2'],
        'frameworks': ['AVFoundation'],
        'weak_frameworks': ['CoreBluetooth'],
        'pod_target_xcconfig': {
          'OTHER_LDFLAGS':
              '-lz -framework CoreAudio -weak_framework Metal -ObjC',
        },
        'user_target_xcconfig': {'OTHER_LDFLAGS': '-liconv'},
      },
      context: const PodBuildContext(simulator: false, distribution: false),
      pod: 'MobileVLCKit',
      module: 'MobileVLCKit',
    );
    expect(linker.libraries, ['xml2', 'z', 'iconv']);
    expect(linker.frameworks, ['AVFoundation', 'CoreAudio']);
    expect(linker.weakFrameworks, ['CoreBluetooth', 'Metal']);
    expect(linker.ignoredFlags, isEmpty);
  });
}
