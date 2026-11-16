import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:studio_ext/src/shared/pods/pod_binary_slices.dart';
import 'package:studio_ext/src/shared/pods/pod_library_xcframework.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const builder = PodLibraryXcframework(
    directoryFactory: Directory.new,
    fileFactory: File.new,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lib-xcframework-test-');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('AC-046-8 wraps vendored .a and headers into xcframework', () {
    final libFile = File(path.join(tempDir.path, 'libStaticLib.a'))
      ..writeAsStringSync('!<arch>\nfake-archive');
    final headersDir = Directory(path.join(tempDir.path, 'include'))
      ..createSync(recursive: true);
    File(
      path.join(headersDir.path, 'StaticLib.h'),
    ).writeAsStringSync('// header');
    File(path.join(headersDir.path, 'Types.h')).writeAsStringSync('// types');

    final destination = Directory(path.join(tempDir.path, 'output'))
      ..createSync(recursive: true);
    final result = builder.build(
      name: 'StaticLib',
      libraryFile: libFile,
      headersDir: headersDir,
      destination: destination,
    );

    expect(result.existsSync(), isTrue);
    expect(path.basename(result.path), 'StaticLib.xcframework');

    // Check device slice
    final deviceLib = File(
      path.join(result.path, 'ios-arm64', 'libStaticLib.a'),
    );
    expect(deviceLib.existsSync(), isTrue);
    expect(deviceLib.readAsStringSync(), '!<arch>\nfake-archive');

    final deviceHeader = File(
      path.join(result.path, 'ios-arm64', 'Headers', 'StaticLib.h'),
    );
    expect(deviceHeader.existsSync(), isTrue);
    expect(deviceHeader.readAsStringSync(), '// header');

    // Check Info.plist
    final infoPlist = File(path.join(result.path, 'Info.plist'));
    expect(infoPlist.existsSync(), isTrue);
    final plistContent = infoPlist.readAsStringSync();
    expect(
      plistContent,
      contains('<key>BinaryPath</key>\n      <string>libStaticLib.a</string>'),
    );
    expect(
      plistContent,
      contains('<key>HeadersPath</key>\n      <string>Headers</string>'),
    );
    expect(
      plistContent,
      contains(
        '<key>LibraryIdentifier</key>\n      <string>ios-arm64</string>',
      ),
    );

    // Verify inspectable by PodBinarySlices
    const slices = PodBinarySlices(File.new);
    final arm64 = slices.requireArm64(
      pod: 'StaticLib',
      framework: result,
      variant: null,
      needed: 'ios-arm64',
    );
    expect(arm64, 'ios-arm64');
  });

  test(
    'AC-046-8 includes simulator slice when simulator library is provided',
    () {
      final devLib = File(path.join(tempDir.path, 'libMulti.a'))
        ..writeAsStringSync('!<arch>\ndevice');
      final simLib = File(path.join(tempDir.path, 'libMulti_sim.a'))
        ..writeAsStringSync('!<arch>\nsim');
      final destination = Directory(path.join(tempDir.path, 'output2'))
        ..createSync(recursive: true);

      final result = builder.build(
        name: 'Multi',
        libraryFile: devLib,
        simulatorLibraryFile: simLib,
        destination: destination,
      );

      final infoPlist = File(
        path.join(result.path, 'Info.plist'),
      ).readAsStringSync();
      expect(infoPlist, contains('<string>ios-arm64</string>'));
      expect(infoPlist, contains('<string>ios-arm64-simulator</string>'));
      expect(
        infoPlist,
        contains(
          '<key>SupportedPlatformVariant</key>\n      <string>simulator</string>',
        ),
      );

      const slices = PodBinarySlices(File.new);
      final simSlice = slices.requireArm64(
        pod: 'Multi',
        framework: result,
        variant: 'simulator',
        needed: 'ios-arm64-simulator',
      );
      expect(simSlice, 'ios-arm64-simulator');
    },
  );
}
