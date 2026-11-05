// studio: 018 — SwiftSupport in an App Store IPA (AC-018-16).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/cli/shared/ipa_packager.dart';
import 'package:xcross/src/target/iphone/device/swift_support.dart';

/// A 64-bit arm64 Mach-O that loads [libraries].
Uint8List _loading(List<String> libraries) {
  const le = Endian.little;
  final commands = <Uint8List>[];
  for (final library in libraries) {
    final name = utf8.encode(library);
    final size = (24 + name.length + 1 + 7) ~/ 8 * 8;
    final command = Uint8List(size);
    ByteData.sublistView(command)
      ..setUint32(0, 0xc, le)
      ..setUint32(4, size, le)
      ..setUint32(8, 24, le);
    command.setRange(24, 24 + name.length, name);
    commands.add(command);
  }
  final total = commands.fold<int>(0, (sum, c) => sum + c.length);
  final bytes = Uint8List(32 + total);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, le)
    ..setInt32(4, 0x0100000c, le)
    ..setUint32(12, 2, le)
    ..setUint32(16, commands.length, le)
    ..setUint32(20, total, le);
  var offset = 32;
  for (final command in commands) {
    bytes.setRange(offset, offset + command.length, command);
    offset += command.length;
  }
  return bytes;
}

void main() {
  final host = detectPlatformHost();
  late Directory temp;
  late String app;
  late String sdk;

  void write(String root, String relative, List<int> bytes) =>
      File(p.joinAll([root, ...relative.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  /// A library of the SDK, in [folder] (`swift-5.0`), loading [loads].
  void sdkLibrary(
    String folder,
    String name, [
    List<String> loads = const [],
  ]) => write(
    sdk,
    'Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/$folder/iphoneos/$name',
    _loading(loads),
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('swift-support-');
    app = p.join(temp.path, 'Runner.app');
    sdk = p.join(temp.path, 'sdk');
    Directory(app).createSync(recursive: true);
    write(app, 'Info.plist', utf8.encode('<plist/>'));
    write(app, 'Runner', _loading(['/usr/lib/libSystem.B.dylib']));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<SwiftSupport> collect({String? bundle}) => SwiftSupport.collect(
    fileSystem: host.fileSystem,
    appPath: app,
    sdkBundle: bundle,
  );

  test('an app that loads no Swift library needs nothing', () async {
    final support = await collect(bundle: sdk);
    expect(support.isEmpty, isTrue);
    expect(support.missing, isEmpty);
  });

  test('the libraries the binaries load, and what those load, come from the '
      'SDK, the first folder winning', () async {
    write(
      app,
      'Frameworks/Fb.framework/Fb',
      _loading([
        '@rpath/libswiftCore.dylib',
        '@rpath/libswift_Concurrency.dylib',
        '/usr/lib/swift/libswiftFoundation.dylib',
      ]),
    );
    sdkLibrary('swift-5.0', 'libswiftCore.dylib');
    sdkLibrary('swift-5.5', 'libswift_Concurrency.dylib', [
      '@rpath/libswiftCore.dylib',
    ]);
    sdkLibrary('swift-5.0', 'libswiftFoundation.dylib', [
      '@rpath/libswiftDarwin.dylib',
    ]);
    sdkLibrary('swift-5.0', 'libswiftDarwin.dylib');
    // The same name in a later folder is not taken.
    sdkLibrary('swift-6.2', 'libswiftCore.dylib', ['/usr/lib/other.dylib']);

    final support = await collect(bundle: sdk);
    expect(support.missing, isEmpty);
    expect(support.files.keys, [
      'SwiftSupport/iphoneos/libswiftCore.dylib',
      'SwiftSupport/iphoneos/libswiftDarwin.dylib',
      'SwiftSupport/iphoneos/libswiftFoundation.dylib',
      'SwiftSupport/iphoneos/libswift_Concurrency.dylib',
    ]);
    expect(
      support.files['SwiftSupport/iphoneos/libswiftCore.dylib'],
      contains('swift-5.0'),
    );
  });

  test('a library loaded through the rpath that the SDK lacks is reported; '
      'one named by its /usr/lib/swift path is not demanded', () async {
    write(
      app,
      'Frameworks/Fb.framework/Fb',
      _loading([
        '@rpath/libswiftCore.dylib',
        '/usr/lib/swift/libswiftUIKit.dylib',
      ]),
    );
    final support = await collect(bundle: sdk);
    expect(support.missing, ['libswiftCore.dylib']);
    expect(support.files, isEmpty);
  });

  test('a library loaded only weakly may be absent', () async {
    final binary = _loading([
      '@rpath/libswiftCore.dylib',
      '@rpath/libswiftXPC.dylib',
    ]);
    // LC_LOAD_DYLIB -> LC_LOAD_WEAK_DYLIB for the second command.
    ByteData.sublistView(binary).setUint32(
      32 + (24 + '@rpath/libswiftCore.dylib'.length + 1 + 7) ~/ 8 * 8,
      0x80000018,
      Endian.little,
    );
    write(app, 'Frameworks/Fb.framework/Fb', binary);
    sdkLibrary('swift-5.0', 'libswiftCore.dylib');
    final support = await collect(bundle: sdk);
    expect(support.missing, isEmpty);
    expect(support.files.keys, ['SwiftSupport/iphoneos/libswiftCore.dylib']);
  });

  test('without an installed SDK every rpath library is missing', () async {
    write(
      app,
      'Frameworks/Fb.framework/Fb',
      _loading(['@rpath/libswiftCore.dylib']),
    );
    expect((await collect()).missing, ['libswiftCore.dylib']);
  });

  test('the IPA carries the folder beside Payload, executable', () async {
    sdkLibrary('swift-5.0', 'libswiftCore.dylib');
    final extra = {
      'SwiftSupport/iphoneos/libswiftCore.dylib': p.join(
        sdk,
        'Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.0/'
        'iphoneos/libswiftCore.dylib',
      ),
    };
    final ipa = await IpaPackager(host: host).package(app, extraEntries: extra);
    final archive = ZipDecoder().decodeBytes(File(ipa).readAsBytesSync());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, contains('Payload/Runner.app/Runner'));
    expect(names, contains('SwiftSupport/iphoneos/libswiftCore.dylib'));
    final entry = archive.files.firstWhere(
      (f) => f.name == 'SwiftSupport/iphoneos/libswiftCore.dylib',
    );
    expect(entry.mode & 0x49, 0x49, reason: 'executable bits');
  });

  test('without extra entries the IPA has only Payload', () async {
    final ipa = await IpaPackager(host: host).package(app);
    final archive = ZipDecoder().decodeBytes(File(ipa).readAsBytesSync());
    expect(archive.files.every((f) => f.name.startsWith('Payload/')), isTrue);
  });
}
