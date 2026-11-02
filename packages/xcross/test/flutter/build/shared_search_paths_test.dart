// studio: 006 — Xcode-style project-wide search paths for xcframeworks.
import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/host/macos/macos_host.dart';
import 'package:darwin_sdk_kit/target/iphone/iphone_target.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/swiftpm/artifact_filesystem.dart';
import 'package:xcross/src/shared/flutter/swiftpm/plan_reader.dart';
import 'package:xcross/src/shared/flutter/swiftpm/response_file_reader.dart';
import 'package:xcross/src/shared/flutter/swiftpm/shared_search_paths.dart';
import 'package:xcross/src/target/iphone/flutter/iphone_flutter_target.dart';

String _plist(String identifier, String libraryPath, {String? headers}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>AvailableLibraries</key><array><dict>
<key>LibraryIdentifier</key><string>$identifier</string>
<key>LibraryPath</key><string>$libraryPath</string>
${headers == null ? '' : '<key>HeadersPath</key><string>$headers</string>'}
<key>SupportedArchitectures</key><array><string>arm64</string></array>
<key>SupportedPlatform</key><string>ios</string>
${identifier.contains('simulator') ? '<key>SupportedPlatformVariant</key><string>simulator</string>' : ''}
</dict></array>
<key>XCFrameworkFormatVersion</key><string>1.0</string>
</dict></plist>
''';

/// Plain dart:io, so the test runs on every host.
@internal
final class IoArtifactFileSystem implements SwiftPmArtifactFileSystem {
  const IoArtifactFileSystem();
  @override
  File file(String path) => File(path);
  @override
  Directory directory(String path) => Directory(path);
  @override
  Link link(String path) => Link(path);
  @override
  FileSystemEntityType typeSync(String path, {bool followLinks = true}) =>
      FileSystemEntity.typeSync(path, followLinks: followLinks);
  @override
  String processPath(String path) => path;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('xcross_search_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  test('AC-006-11 every device xcframework slice is searched by every '
      'target, as in Xcode', () {
    final scratch = p.join(root.path, 'scratch');
    // Static library with headers (Google's GoogleMaps.xcframework).
    final maps = p.join(
      scratch,
      'checkouts',
      'ios-maps-sdk',
      '.xa',
      'abc',
      'GoogleMaps.xcframework',
    );
    write(
      p.join(maps, 'Info.plist'),
      _plist('ios-arm64', 'GoogleMaps.a', headers: 'Headers'),
    );
    write(
      p.join(maps, 'ios-arm64', 'Headers', 'GoogleMaps', 'module.modulemap'),
      'module GoogleMaps {}',
    );
    // A framework xcframework downloaded by SwiftPM itself.
    final grpc = p.join(scratch, 'artifacts', 'grpc', 'grpcpp.xcframework');
    write(p.join(grpc, 'Info.plist'), _plist('ios-arm64', 'grpcpp.framework'));
    Directory(
      p.join(grpc, 'ios-arm64', 'grpcpp.framework'),
    ).createSync(recursive: true);
    // Simulator-only: not for a device build.
    final sim = p.join(scratch, 'artifacts', 'sim', 'Sim.xcframework');
    write(
      p.join(sim, 'Info.plist'),
      _plist('ios-arm64-simulator', 'Sim.a', headers: 'Headers'),
    );
    Directory(
      p.join(sim, 'ios-arm64-simulator', 'Headers'),
    ).createSync(recursive: true);

    final host = MacOSHost();
    final arguments = SwiftPmSharedSearchPaths(
      fileSystem: const IoArtifactFileSystem(),
      targetPolicy: IPhoneFlutterTarget(IPhoneTarget(host)),
    ).arguments(scratch);

    final headers = p.join(maps, 'ios-arm64', 'Headers');
    final frameworks = p.join(grpc, 'ios-arm64');
    expect(arguments, containsAllInOrder(['-Xcc', '-I$headers']));
    expect(arguments, containsAllInOrder(['-Xswiftc', '-I', '-Xswiftc']));
    expect(arguments, containsAllInOrder(['-Xcc', '-F$frameworks']));
    expect(arguments.join(' '), isNot(contains('simulator')));
  });

  test('no resolved packages, no flags', () {
    final host = MacOSHost();
    expect(
      SwiftPmSharedSearchPaths(
        fileSystem: const IoArtifactFileSystem(),
        targetPolicy: IPhoneFlutterTarget(IPhoneTarget(host)),
      ).arguments(p.join(root.path, 'missing')),
      isEmpty,
    );
  });

  test('AC-006-13 static libraries the plan copies from xcframeworks are '
      'linked by path', () {
    final scratch = p.join(root.path, 'scratch');
    final debug = p.join(scratch, 'arm64-apple-ios', 'debug');
    final maps = p.join(debug, 'GoogleMaps.a');
    final slice = p.join(
      scratch,
      'checkouts',
      'ios-maps-sdk',
      '.xa',
      'abc',
      'GoogleMaps.xcframework',
      'ios-arm64',
      'GoogleMaps.a',
    );
    final other = p.join(debug, 'Resources.bundle', 'x.a');
    // Copied by SwiftPM but used by no product (GoogleMapsM4B.a).
    final unused = p.join(debug, 'Unused.a');
    final unusedSlice = p.join(
      scratch,
      'u.xcframework',
      'ios-arm64',
      'Unused.a',
    );
    String yaml(List<String> linkArgs) =>
        'commands:\n'
        '  ${jsonEncode(maps)}:\n'
        '    tool: copy-tool\n'
        '    inputs: [${jsonEncode(slice)}]\n'
        '    outputs: [${jsonEncode(maps)}]\n'
        '\n'
        '  ${jsonEncode(other)}:\n'
        '    tool: copy-tool\n'
        '    inputs: [${jsonEncode(p.join(root.path, 'src', 'x.a'))}]\n'
        '    outputs: [${jsonEncode(other)}]\n'
        '\n'
        '  ${jsonEncode(unused)}:\n'
        '    tool: copy-tool\n'
        '    inputs: [${jsonEncode(unusedSlice)}]\n'
        '    outputs: [${jsonEncode(unused)}]\n'
        '\n'
        '  "C.FlutterPluginsGenerated-arm64-apple-ios-debug.module":\n'
        '    tool: phony\n'
        '    inputs: [${jsonEncode(maps)},"other"]\n'
        '    outputs: ["<x>"]\n'
        '\n'
        '  "C.FlutterPluginsGenerated-debug.dylib":\n'
        '    tool: shell\n'
        '    args: [${linkArgs.map(jsonEncode).join(',')}]\n';
    write(p.join(scratch, 'debug.yaml'), yaml(['swiftc', '-L', debug]));
    final reader = SwiftPmPlanReader(
      fileSystem: const IoArtifactFileSystem(),
      responseFiles: SwiftPmResponseFileReader(
        fileSystem: const IoArtifactFileSystem(),
      ),
    );

    final archives = reader.plannedBinaryArchives(scratch, debug);

    expect(archives, [
      maps,
    ], reason: 'only xcframework archives the plugins product uses');
    expect(reader.manifestLinksArchives(scratch, archives), isFalse);
    write(
      p.join(scratch, 'debug.yaml'),
      yaml(['swiftc', '-L', debug, '-Xlinker', maps]),
    );
    expect(reader.manifestLinksArchives(scratch, archives), isTrue);
  });
}
