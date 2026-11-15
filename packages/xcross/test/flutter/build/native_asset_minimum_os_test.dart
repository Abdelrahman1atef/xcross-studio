// studio: 018 — App Store Connect 90208: objective_c.framework said
// MinimumOSVersion 13.0 (Flutter's hook target) while the clang shim built it
// for the app's 15.0 (mastkdm, 2026-11-15).
import 'dart:io';
import 'dart:typed_data';

import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/internal/native_asset_frameworks.dart';

import '../../host_operations_fixtures.dart';
import 'support/native_asset_framework_fixtures.dart';

/// A thin arm64 Mach-O with `LC_BUILD_VERSION` (iOS, [minos]).
Uint8List _binary(String minos) {
  final parts = [...minos.split('.').map(int.parse), 0];
  const le = Endian.little;
  final bytes = Uint8List(56);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, le)
    ..setInt32(4, 0x0100000c, le)
    ..setUint32(12, 6, le)
    ..setUint32(16, 1, le)
    ..setUint32(20, 24, le)
    ..setUint32(32, 0x32, le)
    ..setUint32(36, 24, le)
    ..setUint32(40, 2, le)
    ..setUint32(44, parts[0] << 16 | parts[1] << 8, le)
    ..setUint32(48, 26 << 16 | 5 << 8, le);
  return bytes;
}

String _plist(String? minimum) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<plist version="1.0">\n<dict>\n'
    '\t<key>CFBundleExecutable</key>\n\t<string>objective_c</string>\n'
    '${minimum == null ? '' : '\t<key>MinimumOSVersion</key>\n\t<string>$minimum</string>\n'}'
    '</dict>\n</plist>\n';

void main() {
  late Directory temporary;
  late FixtureMappedFileSystem mapped;
  late NativeAssetFrameworks<LinuxHost> frameworks;
  late String framework;
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('native_asset_minos-');
    mapped = FixtureMappedFileSystem(temporary);
    final host = LinuxHost(fileSystem: mapped);
    frameworks = nativeFrameworkService(fixtureRunner(host, log: fixtureLog()));
    framework = '/xcross-framework-fixture/staged/objective_c.framework';
    mapped.directory(framework).createSync(recursive: true);
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  void write({required String minos, String? minimum}) {
    mapped
        .file(p.join(framework, 'objective_c'))
        .writeAsBytesSync(_binary(minos));
    mapped
        .file(p.join(framework, 'Info.plist'))
        .writeAsStringSync(_plist(minimum));
  }

  String plist() =>
      mapped.file(p.join(framework, 'Info.plist')).readAsStringSync();

  test('a lower MinimumOSVersion is raised to what the code needs', () async {
    write(minos: '15.0', minimum: '13.0');
    expect(await frameworks.matchMinimumOs([framework]), [
      'objective_c.framework: 13.0 → 15.0',
    ]);
    expect(plist(), _plist('15.0'));
  });

  test('a missing MinimumOSVersion is added', () async {
    write(minos: '15.0');
    expect(await frameworks.matchMinimumOs([framework]), [
      'objective_c.framework: none → 15.0',
    ]);
    expect(plist(), contains('<key>MinimumOSVersion</key>\n\t<string>15.0'));
  });

  test('an equal or higher MinimumOSVersion is left alone', () async {
    for (final minimum in ['15.0', '15', '16.0']) {
      write(minos: '15.0', minimum: minimum);
      expect(await frameworks.matchMinimumOs([framework]), isEmpty);
      expect(plist(), _plist(minimum));
    }
  });
}
