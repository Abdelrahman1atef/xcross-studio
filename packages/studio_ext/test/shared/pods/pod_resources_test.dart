import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:studio_ext/src/shared/pods/pod_resources.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const resources = PodResources(
    directoryFactory: Directory.new,
    fileFactory: File.new,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resources-test-');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'AC-046-8 stages resource bundle with org.cocoapods.<Key> Info.plist',
    () {
      final asset = File(path.join(tempDir.path, 'image.png'))
        ..writeAsBytesSync([1, 2, 3]);
      final destination = Directory(path.join(tempDir.path, 'AppRoot'))
        ..createSync();

      final claimed = resources.stageResources(
        pod: 'MyPod',
        destination: destination,
        resourceBundles: {
          'MyPodAssets': [asset],
        },
      );

      final bundleDir = Directory(
        path.join(destination.path, 'MyPodAssets.bundle'),
      );
      expect(bundleDir.existsSync(), isTrue);

      final infoPlist = File(path.join(bundleDir.path, 'Info.plist'));
      expect(infoPlist.existsSync(), isTrue);
      expect(
        infoPlist.readAsStringSync(),
        contains('org.cocoapods.MyPodAssets'),
      );

      final copiedAsset = File(path.join(bundleDir.path, 'image.png'));
      expect(copiedAsset.existsSync(), isTrue);
      expect(claimed, contains('MyPodAssets.bundle'));
    },
  );

  test(
    'AC-046-8 routes plain Info.plist and PrivacyInfo.xcprivacy into <Pod>Resources.bundle',
    () {
      final privacy = File(path.join(tempDir.path, 'PrivacyInfo.xcprivacy'))
        ..writeAsStringSync('<plist></plist>');
      final text = File(path.join(tempDir.path, 'data.json'))
        ..writeAsStringSync('{}');
      final destination = Directory(path.join(tempDir.path, 'AppRoot2'))
        ..createSync();

      resources.stageResources(
        pod: 'GooglePod',
        destination: destination,
        plainResources: [privacy, text],
      );

      // data.json goes to root
      expect(
        File(path.join(destination.path, 'data.json')).existsSync(),
        isTrue,
      );

      // PrivacyInfo goes into GooglePodResources.bundle
      final bundle = Directory(
        path.join(destination.path, 'GooglePodResources.bundle'),
      );
      expect(bundle.existsSync(), isTrue);
      expect(
        File(path.join(bundle.path, 'PrivacyInfo.xcprivacy')).existsSync(),
        isTrue,
      );
      expect(
        File(path.join(destination.path, 'PrivacyInfo.xcprivacy')).existsSync(),
        isFalse,
      );
    },
  );

  test('AC-046-8 throws PodResourceClash on collision', () {
    final file1 = File(path.join(tempDir.path, 'icon.png'))
      ..writeAsBytesSync([1]);
    final destination = Directory(path.join(tempDir.path, 'AppRoot3'))
      ..createSync();

    expect(
      () => resources.stageResources(
        pod: 'ClashingPod',
        destination: destination,
        plainResources: [file1],
        existingPaths: {'icon.png'},
      ),
      throwsA(
        isA<PodResourceClash>().having(
          (e) => e.toString(),
          'message',
          contains('pod.resource_clash'),
        ),
      ),
    );
  });

  test('AC-046-14 detects uncompiled resources requiring Apple compilers', () {
    expect(
      PodResourceCompilerCheck.checkUncompiled('Views/CustomScreen.storyboard'),
      '.storyboard',
    );
    expect(
      PodResourceCompilerCheck.checkUncompiled('Nibs/CustomView.xib'),
      '.xib',
    );
    expect(
      PodResourceCompilerCheck.checkUncompiled(
        'Model.xcdatamodeld/Model.xcdatamodel',
      ),
      '.xcdatamodeld',
    );
    expect(
      PodResourceCompilerCheck.checkUncompiled('Shaders/Kernels.metal'),
      '.metal',
    );
    expect(PodResourceCompilerCheck.checkUncompiled('Images/icon.png'), isNull);
    expect(PodResourceCompilerCheck.checkUncompiled('Fonts/Font.ttf'), isNull);
  });

  test(
    'AC-046-14 stageResources throws PodUncompiledResource for storyboard and nibs',
    () {
      final xib = File(path.join(tempDir.path, 'TapNib.xib'))
        ..writeAsStringSync('<xib></xib>');
      final destination = Directory(path.join(tempDir.path, 'AppRoot4'))
        ..createSync();

      expect(
        () => resources.stageResources(
          pod: 'TapNibViewV2',
          destination: destination,
          plainResources: [xib],
        ),
        throwsA(
          isA<PodUncompiledResource>().having(
            (e) => e.toString(),
            'message',
            contains(
              'pod.uncompiled_resource: Resource "TapNib.xib" in pod "TapNibViewV2" requires an Apple compiler (.xib)',
            ),
          ),
        ),
      );
    },
  );
}
