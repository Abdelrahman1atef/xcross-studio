import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:studio_ext/src/shared/pods/pod_binary_slices.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pod-slices-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('AC-046-10 requires arm64 for the requested iOS variant', () {
    final framework = Directory(path.join(root.path, 'SDK.xcframework'));
    framework.createSync(recursive: true);
    File(path.join(framework.path, 'Info.plist')).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>AvailableLibraries</key><array>
<dict><key>LibraryIdentifier</key><string>ios-arm64</string>
<key>SupportedPlatform</key><string>ios</string>
<key>SupportedArchitectures</key><array><string>arm64</string></array></dict>
<dict><key>LibraryIdentifier</key><string>ios-x86_64-simulator</string>
<key>SupportedPlatform</key><string>ios</string>
<key>SupportedPlatformVariant</key><string>simulator</string>
<key>SupportedArchitectures</key><array><string>x86_64</string></array></dict>
</array></dict></plist>
''');
    const slices = PodBinarySlices(File.new);
    slices.requireArm64(
      pod: 'SDK',
      framework: framework,
      variant: null,
      needed: 'ios-arm64',
    );
    expect(
      () => slices.requireArm64(
        pod: 'SDK',
        framework: framework,
        variant: 'simulator',
        needed: 'ios-arm64-simulator',
      ),
      throwsA(
        isA<PodNoSlice>().having(
          (error) => error.toString(),
          'message',
          allOf(
            contains('ios-x86_64-simulator'),
            contains('ios-arm64-simulator'),
          ),
        ),
      ),
    );
  });
}
