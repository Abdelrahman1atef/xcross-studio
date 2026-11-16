import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/pods/pod_prefix_header.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const pchHandler = PodPrefixHeader(
    directoryFactory: Directory.new,
    fileFactory: File.new,
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pod-pch-test-');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AC-046-13 PodPrefixHeader (T208)', () {
    test(
      'prefix_header_file: false generates nothing and returns empty flags',
      () {
        final flags = pchHandler.resolveAndGenerate(
          packageDir: tempDir,
          pod: 'GoogleUtilities',
          moduleName: 'GoogleUtilities',
          prefixHeaderFile: false,
        );

        expect(flags, isEmpty);
        expect(
          File(
            p.join(
              tempDir.path,
              'Sources',
              'GoogleUtilities',
              'xcross',
              'GoogleUtilities-prefix.pch',
            ),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'prefix_header_file: "custom/path.pch" returns include flag for custom file',
      () {
        final flags = pchHandler.resolveAndGenerate(
          packageDir: tempDir,
          pod: 'CustomPod',
          moduleName: 'CustomPod',
          prefixHeaderFile: 'custom/CustomPrefix.pch',
        );

        expect(flags, [
          '-include',
          p.join(tempDir.path, 'custom/CustomPrefix.pch').replaceAll(r'\', '/'),
        ]);
      },
    );

    test(
      'default generation writes UIKit import and includes prefix_header_contents',
      () {
        final flags = pchHandler.resolveAndGenerate(
          packageDir: tempDir,
          pod: 'OldObjCPod',
          moduleName: 'OldObjCPod',
          prefixHeaderContents: '#define CUSTOM_MACRO 1',
        );

        expect(flags, [
          '-include',
          'Sources/OldObjCPod/xcross/OldObjCPod-prefix.pch',
        ]);

        final pchFile = File(
          p.join(
            tempDir.path,
            'Sources',
            'OldObjCPod',
            'xcross',
            'OldObjCPod-prefix.pch',
          ),
        );
        expect(pchFile.existsSync(), isTrue);

        final content = pchFile.readAsStringSync();
        expect(content, contains('#import <UIKit/UIKit.h>'));
        expect(content, contains('#define FOUNDATION_EXPORT'));
        expect(content, contains('#define CUSTOM_MACRO 1'));
      },
    );
  });
}
