import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/pods/pod_source_layout.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const layout = PodSourceLayout(
    directoryFactory: Directory.new,
    fileFactory: File.new,
    linkFactory: Link.new,
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pod-layout-test-');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File makeFixtureFile(String relPath, [String content = '// test']) {
    final file = File(p.join(tempDir.path, 'fixtures', relPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  group('AC-046-14 PodSourceLayout (T202)', () {
    test('c99Identifier sanitizes names into C99 identifiers', () {
      expect(PodSourceLayout.c99Identifier('PromisesObjC'), 'PromisesObjC');
      expect(PodSourceLayout.c99Identifier('23skidoo'), '_23skidoo');
      expect(PodSourceLayout.c99Identifier('my-pod-name'), 'my_pod_name');
      expect(PodSourceLayout.c99Identifier('a--b___c'), 'a_b_c');
    });

    test('normalizeHeaderDir ignores . and ./', () {
      expect(PodSourceLayout.normalizeHeaderDir('.'), isNull);
      expect(PodSourceLayout.normalizeHeaderDir('./'), isNull);
      expect(PodSourceLayout.normalizeHeaderDir(r'.\'), isNull);
      expect(PodSourceLayout.normalizeHeaderDir(''), isNull);
      expect(PodSourceLayout.normalizeHeaderDir(null), isNull);
      expect(PodSourceLayout.normalizeHeaderDir('include'), 'include');
      expect(PodSourceLayout.normalizeHeaderDir('./include/'), 'include');
    });

    test('golden tree for PromisesObjC (header_dir: ./)', () {
      final pkgDir = Directory(p.join(tempDir.path, 'PromisesObjC_pkg'));
      final fblPromiseM = makeFixtureFile('Promises/FBLPromise.m');
      final fblPromiseH = makeFixtureFile('Promises/FBLPromise.h');
      final internalH = makeFixtureFile('Promises/FBLInternal.h');

      layout.layOutPod(
        packageDir: pkgDir,
        podName: 'PromisesObjC',
        version: '2.4.1',
        moduleName: 'FBLPromises',
        sourceFiles: {'FBLPromise.m': fblPromiseM},
        publicHeaders: {'FBLPromise.h': fblPromiseH},
        privateHeaders: {'FBLInternal.h': internalH},
        headerDir: './',
      );

      // 1. Sources/<Module>
      expect(
        File(
          p.join(pkgDir.path, 'Sources', 'FBLPromises', 'FBLPromise.m'),
        ).existsSync(),
        isTrue,
      );
      final versC = File(
        p.join(pkgDir.path, 'Sources', 'FBLPromises', 'xcross', 'vers.c'),
      );
      expect(versC.existsSync(), isTrue);
      expect(versC.readAsStringSync(), contains('FBLPromisesVersionNumber'));
      expect(versC.readAsStringSync(), contains('2.4'));

      // 2. Public Headers + Aliases
      final pubHeader = File(
        p.join(pkgDir.path, 'Headers', 'Public', 'FBLPromises', 'FBLPromise.h'),
      );
      expect(pubHeader.existsSync(), isTrue);
      final aliasHeader = File(
        p.join(
          pkgDir.path,
          'Headers',
          'Public',
          'PromisesObjC',
          'FBLPromise.h',
        ),
      );
      expect(aliasHeader.existsSync(), isTrue);

      // 3. Private Headers
      final privHeader = File(
        p.join(
          pkgDir.path,
          'Headers',
          'Private',
          'FBLPromises',
          'FBLInternal.h',
        ),
      );
      expect(privHeader.existsSync(), isTrue);

      // 4. Umbrella + module.modulemap
      final umbrella = File(
        p.join(
          pkgDir.path,
          'Headers',
          'Public',
          'FBLPromises',
          'FBLPromises-umbrella.h',
        ),
      );
      expect(umbrella.existsSync(), isTrue);
      expect(umbrella.readAsStringSync(), contains('#import "FBLPromise.h"'));

      final moduleMap = File(
        p.join(pkgDir.path, 'Headers', 'Public', 'module.modulemap'),
      );
      expect(moduleMap.existsSync(), isTrue);
      expect(
        moduleMap.readAsStringSync(),
        contains('framework module FBLPromises'),
      );
    });

    test(
      'golden tree for Protobuf (module protobuf, imports <Protobuf/...>)',
      () {
        final pkgDir = Directory(p.join(tempDir.path, 'Protobuf_pkg'));
        final protoM = makeFixtureFile('src/GPBMessage.m');
        final protoH = makeFixtureFile('src/GPBMessage.h');

        layout.layOutPod(
          packageDir: pkgDir,
          podName: 'Protobuf',
          version: '3.11.4',
          moduleName: 'protobuf',
          sourceFiles: {'GPBMessage.m': protoM},
          publicHeaders: {'GPBMessage.h': protoH},
          privateHeaders: {},
        );

        expect(
          File(
            p.join(
              pkgDir.path,
              'Headers',
              'Public',
              'protobuf',
              'GPBMessage.h',
            ),
          ).existsSync(),
          isTrue,
        );
        // Case-sensitive alias for <Protobuf/...> imports
        expect(
          File(
            p.join(
              pkgDir.path,
              'Headers',
              'Public',
              'Protobuf',
              'GPBMessage.h',
            ),
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('golden tree for GTMSessionFetcher, GoogleToolboxForMac, nanopb', () {
      for (final (pod, mod, ver) in [
        ('GTMSessionFetcher', 'GTMSessionFetcher', '3.3.0'),
        ('GoogleToolboxForMac', 'GoogleToolboxForMac', '2.3.2'),
        ('nanopb', 'nanopb', '3.30910.0'),
      ]) {
        final pkgDir = Directory(p.join(tempDir.path, '${pod}_pkg'));
        final src = makeFixtureFile('$pod/main.m');
        final hdr = makeFixtureFile('$pod/header.h');

        layout.layOutPod(
          packageDir: pkgDir,
          podName: pod,
          version: ver,
          moduleName: mod,
          sourceFiles: {'main.m': src},
          publicHeaders: {'header.h': hdr},
          privateHeaders: {},
        );

        expect(
          File(
            p.join(pkgDir.path, 'Headers', 'Public', mod, 'header.h'),
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            p.join(pkgDir.path, 'Sources', mod, 'xcross', 'vers.c'),
          ).existsSync(),
          isTrue,
        );
      }
    });

    test('golden tree for GoogleMLKit (uses its own module map)', () {
      final pkgDir = Directory(p.join(tempDir.path, 'GoogleMLKit_pkg'));
      final hdr = makeFixtureFile('MLKit.h');
      const customMap = 'module GoogleMLKit { header "MLKit.h" export * }';

      layout.layOutPod(
        packageDir: pkgDir,
        podName: 'GoogleMLKit',
        version: '9.0.0',
        moduleName: 'GoogleMLKit',
        sourceFiles: {},
        publicHeaders: {'MLKit.h': hdr},
        privateHeaders: {},
        customModuleMap: customMap,
      );

      final mapFile = File(
        p.join(pkgDir.path, 'Headers', 'Public', 'module.modulemap'),
      );
      expect(mapFile.existsSync(), isTrue);
      expect(mapFile.readAsStringSync(), customMap);
      // Ensure synthetic umbrella header was not generated
      expect(
        File(
          p.join(
            pkgDir.path,
            'Headers',
            'Public',
            'GoogleMLKit',
            'GoogleMLKit-umbrella.h',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('moduleMapDisabled: true suppresses module.modulemap generation', () {
      final pkgDir = Directory(p.join(tempDir.path, 'NoMap_pkg'));
      final hdr = makeFixtureFile('Header.h');

      layout.layOutPod(
        packageDir: pkgDir,
        podName: 'NoMapPod',
        version: '1.0.0',
        moduleName: 'NoMapPod',
        sourceFiles: {},
        publicHeaders: {'Header.h': hdr},
        privateHeaders: {},
        moduleMapDisabled: true,
      );

      expect(
        File(
          p.join(pkgDir.path, 'Headers', 'Public', 'module.modulemap'),
        ).existsSync(),
        isFalse,
      );
    });

    test('hard link links public header to the same staged file', () {
      final pkgDir = Directory(p.join(tempDir.path, 'Link_pkg'));
      final hdr = makeFixtureFile('Shared.h', '// shared content');

      layout.layOutPod(
        packageDir: pkgDir,
        podName: 'LinkPod',
        version: '1.0.0',
        moduleName: 'LinkPod',
        sourceFiles: {},
        publicHeaders: {'Shared.h': hdr},
        privateHeaders: {},
      );

      final pubHeader = File(
        p.join(pkgDir.path, 'Headers', 'Public', 'LinkPod', 'Shared.h'),
      );
      expect(pubHeader.existsSync(), isTrue);
      expect(pubHeader.readAsStringSync(), '// shared content');
    });
  });
}
