import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:studio_ext/shared/events/ndjson_events.dart';
import 'package:studio_ext/src/shared/pods/pod_binary_manifest.dart';
import 'package:studio_ext/src/shared/pods/pod_binary_package.dart';
import 'package:studio_ext/src/shared/pods/pod_binary_slices.dart';
import 'package:studio_ext/src/shared/pods/pod_swift_binary_check.dart';
import 'package:studio_ext/src/shared/pods/pod_xcconfig.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('binary-pod-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'AC-046-8 copies xcframework bytes unchanged into Swift package',
    () async {
      final source = Directory(path.join(root.path, 'download'));
      final destination = Directory(path.join(root.path, 'package'));
      final vendor = File(
        path.join(
          source.path,
          'Frameworks',
          'ObjectBox.xcframework',
          'ios-arm64',
          'ObjectBox.framework',
          'ObjectBox',
        ),
      );
      await vendor.create(recursive: true);
      await vendor.writeAsBytes([0, 1, 2, 255]);
      const PodBinaryPackage(
        manifest: PodBinaryManifest(),
        directoryFactory: Directory.new,
        fileFactory: File.new,
        slices: PodBinarySlices(File.new),
        swiftBinaryCheck: PodSwiftBinaryCheck(
          directoryFactory: Directory.new,
          fileFactory: File.new,
        ),
      ).write(
        pod: 'ObjectBox',
        module: 'ObjectBox',
        source: source,
        destination: destination,
        frameworks: const ['Frameworks/ObjectBox.xcframework'],
        linker: const PodBinaryLinkSettings(
          frameworks: ['Foundation'],
          weakFrameworks: ['CoreBluetooth'],
          libraries: ['z'],
        ),
      );
      expect(
        await File(
          path.join(
            destination.path,
            'Frameworks',
            'ObjectBox.xcframework',
            'ios-arm64',
            'ObjectBox.framework',
            'ObjectBox',
          ),
        ).readAsBytes(),
        [0, 1, 2, 255],
      );
      expect(
        await File(path.join(destination.path, 'Package.swift')).readAsString(),
        contains('.binaryTarget(name: "ObjectBox"'),
      );
      expect(
        await File(
          path.join(
            destination.path,
            'Sources',
            'ObjectBox_xcross',
            'anchor.c',
          ),
        ).readAsString(),
        contains('ObjectBox_xcross_anchor'),
      );
      if (Platform.environment['XCROSS_TEST_SWIFTPM'] == '1') {
        final swift = await Process.run('swift', [
          'package',
          'dump-package',
          '--package-path',
          destination.path,
        ]);
        expect(swift.exitCode, 0, reason: '${swift.stderr}');
      }
    },
  );

  test('AC-046-8 maps a vendor subfolder to Frameworks', () async {
    final source = Directory(path.join(root.path, 'download'));
    final destination = Directory(path.join(root.path, 'package'));
    final vendor = File(
      path.join(source.path, 'Vendor', 'SDK.xcframework', 'Info.plist'),
    );
    await vendor.create(recursive: true);
    await vendor.writeAsBytes([1, 2, 3]);
    const writer = PodBinaryPackage(
      manifest: PodBinaryManifest(),
      directoryFactory: Directory.new,
      fileFactory: File.new,
      slices: PodBinarySlices(File.new),
      swiftBinaryCheck: PodSwiftBinaryCheck(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
    );
    writer.write(
      pod: 'SDK',
      module: 'SDK',
      source: source,
      destination: destination,
      frameworks: const ['Frameworks/SDK.xcframework'],
      sourceFrameworks: const {
        'Frameworks/SDK.xcframework': 'Vendor/SDK.xcframework',
      },
    );
    expect(
      File(
        path.join(
          destination.path,
          'Frameworks',
          'SDK.xcframework',
          'Info.plist',
        ),
      ).readAsBytesSync(),
      [1, 2, 3],
    );
    expect(
      () => writer.write(
        pod: 'SDK',
        module: 'SDK',
        source: source,
        destination: destination,
        frameworks: const ['Frameworks/SDK.xcframework'],
        sourceFrameworks: const {
          'Frameworks/SDK.xcframework': '../outside/SDK.xcframework',
        },
      ),
      throwsArgumentError,
    );
  });

  test('AC-046-6 conversion reports bytes through NDJSON events', () async {
    final source = Directory(path.join(root.path, 'source'));
    final vendor = File(
      path.join(source.path, 'Frameworks', 'SDK.xcframework', 'Info.plist'),
    );
    await vendor.create(recursive: true);
    await vendor.writeAsBytes([1, 2, 3, 4]);
    final output = <int>[];
    final events = NdjsonEvents.fromEnvironment(const {
      'XCROSS_EVENTS': 'ndjson',
    }, output.addAll)!;
    PodBinaryPackage(
      manifest: const PodBinaryManifest(),
      directoryFactory: Directory.new,
      fileFactory: File.new,
      slices: const PodBinarySlices(File.new),
      swiftBinaryCheck: const PodSwiftBinaryCheck(
        directoryFactory: Directory.new,
        fileFactory: File.new,
      ),
      events: events,
    ).write(
      pod: 'SDK',
      module: 'SDK',
      source: source,
      destination: Directory(path.join(root.path, 'package')),
      frameworks: const ['Frameworks/SDK.xcframework'],
    );
    final records = utf8
        .decode(output)
        .trim()
        .split('\n')
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(records.first['status'], 'start');
    expect(records.first['name'], 'pod_convert');
    expect(records.last['status'], 'done');
    expect(records.last['bytesDone'], 4);
    expect(records.last['bytesTotal'], 4);
  });

  test(
    'AC-046-8 writes binary package from selected podspec attributes',
    () async {
      final source = Directory(path.join(root.path, 'download'));
      final destination = Directory(path.join(root.path, 'package'));
      final vendor = File(
        path.join(source.path, 'Vendor', 'ObjectBox.xcframework', 'Info.plist'),
      );
      await vendor.create(recursive: true);
      const info = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>AvailableLibraries</key><array>
<dict><key>LibraryIdentifier</key><string>ios-arm64</string>
<key>SupportedPlatform</key><string>ios</string>
<key>SupportedArchitectures</key><array><string>arm64</string></array></dict>
</array></dict></plist>
''';
      await vendor.writeAsString(info);
      const PodBinaryPackage(
        manifest: PodBinaryManifest(),
        directoryFactory: Directory.new,
        fileFactory: File.new,
        slices: PodBinarySlices(File.new),
        swiftBinaryCheck: PodSwiftBinaryCheck(
          directoryFactory: Directory.new,
          fileFactory: File.new,
        ),
      ).writeFromSpec(
        pod: 'ObjectBox',
        spec: const {
          'name': 'ObjectBox',
          'module_name': 'ObjectBox',
          'vendored_frameworks': 'Vendor/ObjectBox.xcframework',
          'libraries': ['z'],
        },
        context: const PodBuildContext(simulator: false, distribution: false),
        source: source,
        destination: destination,
      );
      expect(
        File(
          path.join(
            destination.path,
            'Frameworks',
            'ObjectBox.xcframework',
            'Info.plist',
          ),
        ).readAsBytesSync(),
        utf8.encode(info),
      );
      final manifest = File(
        path.join(destination.path, 'Package.swift'),
      ).readAsStringSync();
      expect(manifest, contains('.linkedLibrary("z")'));
      expect(manifest, contains('pod-ObjectBox'));
      final simulatorOutput = Directory(
        path.join(root.path, 'simulator-package'),
      );
      expect(
        () =>
            const PodBinaryPackage(
              manifest: PodBinaryManifest(),
              directoryFactory: Directory.new,
              fileFactory: File.new,
              slices: PodBinarySlices(File.new),
              swiftBinaryCheck: PodSwiftBinaryCheck(
                directoryFactory: Directory.new,
                fileFactory: File.new,
              ),
            ).writeFromSpec(
              pod: 'ObjectBox',
              spec: const {
                'name': 'ObjectBox',
                'vendored_frameworks': 'Vendor/ObjectBox.xcframework',
              },
              context: const PodBuildContext(
                simulator: true,
                distribution: false,
              ),
              source: source,
              destination: simulatorOutput,
            ),
        throwsA(isA<PodNoSlice>()),
      );
      expect(simulatorOutput.existsSync(), isFalse);

      final swiftModule = Directory(
        path.join(
          source.path,
          'Vendor',
          'ObjectBox.xcframework',
          'ios-arm64',
          'ObjectBox.framework',
          'Modules',
          'ObjectBox.swiftmodule',
        ),
      );
      swiftModule.createSync(recursive: true);
      final swiftOutput = Directory(path.join(root.path, 'swift-package'));
      expect(
        () =>
            const PodBinaryPackage(
              manifest: PodBinaryManifest(),
              directoryFactory: Directory.new,
              fileFactory: File.new,
              slices: PodBinarySlices(File.new),
              swiftBinaryCheck: PodSwiftBinaryCheck(
                directoryFactory: Directory.new,
                fileFactory: File.new,
              ),
            ).writeFromSpec(
              pod: 'ObjectBox',
              spec: const {
                'name': 'ObjectBox',
                'vendored_frameworks': 'Vendor/ObjectBox.xcframework',
              },
              context: const PodBuildContext(
                simulator: false,
                distribution: false,
              ),
              source: source,
              destination: swiftOutput,
            ),
        throwsA(isA<PodSwiftBinaryIncompatible>()),
      );
      expect(swiftOutput.existsSync(), isFalse);
    },
  );
}
