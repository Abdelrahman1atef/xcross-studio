// studio: 018 — a loose dylib becomes a framework (App Store Connect 90429).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/release/swift_runtime.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/target/iphone/device/loose_dylibs.dart';

const _le = Endian.little;

Uint8List _dylibCommand(int command, String path) {
  final name = utf8.encode(path);
  final size = (24 + name.length + 1 + 7) ~/ 8 * 8;
  final bytes = Uint8List(size);
  ByteData.sublistView(bytes)
    ..setUint32(0, command, _le)
    ..setUint32(4, size, _le)
    ..setUint32(8, 24, _le);
  bytes.setRange(24, 24 + name.length, name);
  return bytes;
}

/// A thin arm64 Mach-O with room after its load commands, [id] as install
/// name (when given) and [loads] as dependencies.
Uint8List _machO({String? id, List<String> loads = const []}) {
  final commands = [
    if (id != null) _dylibCommand(0xd, id),
    for (final load in loads) _dylibCommand(0xc, load),
  ];
  final segment = Uint8List(72 + 80);
  ByteData.sublistView(segment)
    ..setUint32(0, 0x19, _le)
    ..setUint32(4, segment.length, _le)
    ..setUint32(64, 1, _le)
    ..setUint64(72 + 40, 8, _le)
    ..setUint32(72 + 48, 0x1000, _le);
  final all = [...commands, segment];
  final total = all.fold<int>(0, (sum, c) => sum + c.length);
  final bytes = Uint8List(0x1010);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, _le)
    ..setInt32(4, 0x0100000c, _le)
    ..setUint32(12, 6, _le)
    ..setUint32(16, all.length, _le)
    ..setUint32(20, total, _le);
  var offset = 32;
  for (final command in all) {
    bytes.setRange(offset, offset + command.length, command);
    offset += command.length;
  }
  bytes.fillRange(0x1000, 0x1008, 0xab);
  return bytes;
}

void main() {
  final host = detectPlatformHost();
  late Directory temp;
  late String app;

  void write(String relative, List<int> bytes) =>
      File(p.joinAll([app, ...relative.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  /// What the binary at [relative] loads, from its load commands.
  List<String> loadsOf(String relative) {
    final bytes = File(
      p.joinAll([app, ...relative.split('/')]),
    ).readAsBytesSync();
    final view = ByteData.sublistView(bytes);
    final count = view.getUint32(16, _le);
    final result = <String>[];
    var offset = 32;
    for (var i = 0; i < count; i++) {
      final command = view.getUint32(offset, _le);
      final size = view.getUint32(offset + 4, _le);
      if (command == 0xc || command == 0xd) {
        final nameOffset = view.getUint32(offset + 8, _le);
        final raw = bytes.sublist(offset + nameOffset, offset + size);
        final end = raw.indexOf(0);
        result.add(
          '${command == 0xd ? 'id:' : ''}'
          '${utf8.decode(end < 0 ? raw : raw.sublist(0, end))}',
        );
      }
      offset += size;
    }
    return result;
  }

  Future<List<String>> run() => LooseDylibs.frameworkize(
    fileSystem: host.fileSystem,
    appPath: app,
    version: '1.0.11',
    build: '14',
    minimumOs: '15.0',
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('loose-dylibs-');
    app = p.join(temp.path, 'Runner.app');
    write('Info.plist', utf8.encode('<plist/>'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('the library moves into a framework and its loaders follow', () async {
    write(
      'Runner',
      _machO(
        loads: ['@rpath/libFlutterPluginsGenerated.dylib', '/usr/lib/x.dylib'],
      ),
    );
    write(
      'Frameworks/libFlutterPluginsGenerated.dylib',
      _machO(id: '@rpath/libFlutterPluginsGenerated.dylib'),
    );
    write(
      'Frameworks/Fb.framework/Fb',
      _machO(
        id: '@rpath/Fb.framework/Fb',
        loads: ['@rpath/libFlutterPluginsGenerated.dylib'],
      ),
    );
    write('Frameworks/libswiftCore.dylib', _machO());

    expect(await run(), ['libFlutterPluginsGenerated.dylib']);

    const name = 'FlutterPluginsGenerated';
    const framework = 'Frameworks/$name.framework';
    expect(
      File(
        p.join(app, 'Frameworks', 'libFlutterPluginsGenerated.dylib'),
      ).existsSync(),
      isFalse,
    );
    expect(loadsOf('$framework/$name'), ['id:@rpath/$name.framework/$name']);
    expect(loadsOf('Runner'), [
      '@rpath/$name.framework/$name',
      '/usr/lib/x.dylib',
    ]);
    expect(loadsOf('Frameworks/Fb.framework/Fb'), [
      'id:@rpath/Fb.framework/Fb',
      '@rpath/$name.framework/$name',
    ]);
    // The Swift runtime stays where it is.
    expect(
      File(p.join(app, 'Frameworks/libswiftCore.dylib')).existsSync(),
      isTrue,
    );
    // Section data did not move.
    final moved = File(p.join(app, framework, name)).readAsBytesSync();
    expect(moved.sublist(0x1000, 0x1008), List.filled(8, 0xab));

    final plist = File(p.join(app, framework, 'Info.plist')).readAsStringSync();
    expect(plist, contains('<string>FlutterPluginsGenerated</string>'));
    expect(plist, contains('<string>FMWK</string>'));
    expect(
      plist,
      contains('<key>CFBundleVersion</key>\n\t<string>14</string>'),
    );
    expect(plist, contains('<string>1.0.11</string>'));
    expect(
      plist,
      contains('<key>MinimumOSVersion</key>\n\t<string>15.0</string>'),
    );
    expect(plist, contains('io.xcross.FlutterPluginsGenerated'));
  });

  test('nothing to do without loose dylibs, and a name already taken is '
      'not reused', () async {
    expect(await run(), isEmpty);
    write('Runner', _machO(loads: ['@rpath/libFoo.dylib']));
    write('Frameworks/libFoo.dylib', _machO(id: '@rpath/libFoo.dylib'));
    write(
      'Frameworks/Foo.framework/Foo',
      _machO(id: '@rpath/Foo.framework/Foo'),
    );
    expect(await run(), ['libFoo.dylib']);
    expect(loadsOf('Runner'), ['@rpath/FooLib1.framework/FooLib1']);
    expect(
      File(p.join(app, 'Frameworks/Foo.framework/Foo')).existsSync(),
      isTrue,
    );
  });

  test('a file that cannot be rewritten stops the export with a reason', () {
    // The padding after the load commands is taken, so the longer name
    // cannot be written.
    final bytes = _machO(loads: ['@rpath/libFoo.dylib']);
    bytes.fillRange(232, 0x1000, 1); // right after the commands
    write('Runner', bytes);
    write('Frameworks/libFoo.dylib', _machO(id: '@rpath/libFoo.dylib'));
    expect(
      run,
      throwsA(
        isA<XcrossError>().having(
          (e) => e.message,
          'message',
          allOf(contains('Runner'), contains('90429')),
        ),
      ),
    );
  });

  test('the Swift runtime scan still finds libraries in the converted app', () {
    // Frameworks the export keeps are read as before.
    expect(
      swiftRuntimeLibraries([
        _machO(loads: ['@rpath/libswiftCore.dylib']),
      ]),
      contains('libswiftCore.dylib'),
    );
  });
}
