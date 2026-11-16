import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/pods/pod_resolver.dart';
import 'package:studio_ext/src/shared/pods/podfile_lock.dart';
import 'package:studio_ext/src/shared/pods/xcross_pods_lock.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File xcrossLockFile;
  late File podfileLock;
  const lock = XcrossPodsLock();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('xcross-pods-lock-test-');
    xcrossLockFile = File(p.join(tempDir.path, 'ios', 'xcross-pods.lock'));
    podfileLock = File(p.join(tempDir.path, 'ios', 'Podfile.lock'));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AC-046-21 serialize produces valid Podfile.lock format', () {
    final pods = {
      'GoogleUtilities': const PodCandidate(
        version: '7.13.0',
        iosMinimum: '10.0',
        dependencies: [
          PodConstraint('PromisesObjC', '~> 1.2', 'GoogleUtilities'),
        ],
      ),
      'PromisesObjC': const PodCandidate(version: '1.2.12', iosMinimum: '9.0'),
    };

    final content = lock.serialize(
      pods: pods,
      checksums: {'GoogleUtilities': 'abc123sha', 'PromisesObjC': 'def456sha'},
    );

    expect(content, contains('PODS:'));
    expect(content, contains('  - GoogleUtilities (7.13.0):'));
    expect(content, contains('    - PromisesObjC (~> 1.2)'));
    expect(content, contains('  - PromisesObjC (1.2.12)'));
    expect(content, contains('DEPENDENCIES:'));
    expect(content, contains('  - GoogleUtilities (= 7.13.0)'));
    expect(content, contains('  - PromisesObjC (= 1.2.12)'));
    expect(content, contains('SPEC REPOS:'));
    expect(content, contains('SPEC CHECKSUMS:'));
    expect(content, contains('  GoogleUtilities: abc123sha'));

    // PodfileLock parser can parse it without errors
    final parsed = PodfileLock.parse(content);
    expect(parsed.pods, contains('GoogleUtilities'));
    expect(parsed.pods['GoogleUtilities']!.version, '7.13.0');
    expect(
      parsed.pods['GoogleUtilities']!.dependencies,
      contains('PromisesObjC (~> 1.2)'),
    );
    expect(parsed.pods['PromisesObjC']!.version, '1.2.12');
  });

  test(
    'AC-046-21 writeLockFile writes xcross-pods.lock when Podfile.lock missing',
    () {
      final pods = {
        'WebRTC-SDK': const PodCandidate(
          version: '104.5112.02',
          iosMinimum: '12.0',
        ),
      };

      final written = lock.writeLockFile(
        xcrossLockFile: xcrossLockFile,
        podfileLock: podfileLock,
        pods: pods,
      );
      expect(written, isTrue);
      expect(xcrossLockFile.existsSync(), isTrue);

      final pins = lock.loadPins(
        podfileLock: podfileLock,
        xcrossLockFile: xcrossLockFile,
      );
      expect(pins, {'WebRTC-SDK': '104.5112.02'});
    },
  );

  test('AC-046-21 writeLockFile respects existing Podfile.lock', () {
    podfileLock.parent.createSync(recursive: true);
    podfileLock.writeAsStringSync('''
PODS:
  - WebRTC-SDK (99.0.0)
DEPENDENCIES:
  - WebRTC-SDK (= 99.0.0)
COCOAPODS: 1.12.0
''');

    final pods = {
      'WebRTC-SDK': const PodCandidate(
        version: '104.5112.02',
        iosMinimum: '12.0',
      ),
    };

    final written = lock.writeLockFile(
      xcrossLockFile: xcrossLockFile,
      podfileLock: podfileLock,
      pods: pods,
    );
    expect(written, isFalse);
    expect(xcrossLockFile.existsSync(), isFalse);

    final pins = lock.loadPins(
      podfileLock: podfileLock,
      xcrossLockFile: xcrossLockFile,
    );
    expect(pins, {'WebRTC-SDK': '99.0.0'});
  });

  test(
    'AC-046-21 second machine reproduces exact locked versions without network drift',
    () {
      // Machine 1 resolved and wrote xcross-pods.lock
      final machine1Pods = {
        'GoogleUtilities': const PodCandidate(
          version: '7.10.0',
          iosMinimum: '10.0',
        ),
      };
      lock.writeLockFile(
        xcrossLockFile: xcrossLockFile,
        podfileLock: podfileLock,
        pods: machine1Pods,
      );

      // Machine 2 receives repo without Podfile.lock, but with xcross-pods.lock
      final machine2Pins = lock.loadPins(
        podfileLock: podfileLock,
        xcrossLockFile: xcrossLockFile,
      );
      expect(machine2Pins, {'GoogleUtilities': '7.10.0'});

      // Resolver on Machine 2 has newer versions available, but uses lock pins
      const resolver = PodResolver();
      final resolution = resolver.resolve(
        roots: [const PodConstraint('GoogleUtilities', '>= 7.0', 'app')],
        available: {
          'GoogleUtilities': [
            const PodCandidate(version: '7.13.0', iosMinimum: '10.0'),
            const PodCandidate(version: '7.10.0', iosMinimum: '10.0'),
          ],
        },
        iosTarget: '12.0',
        lockPins: machine2Pins,
      );

      expect(resolution.pods['GoogleUtilities']!.version, '7.10.0');
      expect(resolution.sources['GoogleUtilities'], 'lock');
    },
  );
}
