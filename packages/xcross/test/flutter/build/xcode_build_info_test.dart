// studio: 018 — toolchain identity and export compliance in Info.plist
// (specs/018-app-store-build, AC-018-6, AC-018-8).
import 'dart:async';
import 'dart:io';

import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/info_plist.dart';
import 'package:xcross/src/shared/sdk/xcode_build_info.dart';

const _head =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0"><dict>';
const _tail = '</dict></plist>';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('xcode-build-info-'));
  tearDown(() => root.deleteSync(recursive: true));

  String sdk({String version = '26.1', String build = '23B77'}) {
    final dir = Directory(
      p.join(root.path, 'iPhoneOS.sdk', 'System', 'Library', 'CoreServices'),
    )..createSync(recursive: true);
    File(p.join(dir.path, 'SystemVersion.plist')).writeAsBytesSync(
      PropertyListSerialization.dataWithPropertyList(<String, Object>{
        'ProductVersion': version,
        'ProductBuildVersion': build,
      }).buffer.asUint8List(),
    );
    return p.join(root.path, 'iPhoneOS.sdk');
  }

  XcodeBuildInfo read({bool recorded = true}) {
    final iosSdk = sdk();
    if (recorded) {
      File(p.join(root.path, XcodeBuildInfo.recordFileName)).writeAsStringSync(
        PropertyListSerialization.stringWithPropertyList(<String, Object>{
          'CFBundleShortVersionString': '26.1.1',
          'ProductBuildVersion': '17B100',
        }),
      );
    }
    return XcodeBuildInfo.read(
      fileSystem: detectPlatformHost().fileSystem,
      paths: p.context,
      iosSdk: iosSdk,
      bundleRoot: root.path,
    );
  }

  group('AC-018-6 DT keys', () {
    test('from the recorded Xcode and the SDK (binary plist)', () {
      expect(read().keys, {
        'DTXcode': '2611',
        'DTXcodeBuild': '17B100',
        'DTSDKBuild': '23B77',
        'DTPlatformBuild': '23B77',
        'DTCompiler': 'com.apple.compilers.llvm.clang.1_0',
      });
    });

    test('an SDK installed before the record: DTXcode from the SDK, no '
        'DTXcodeBuild', () {
      final keys = read(recorded: false).keys;
      expect(keys['DTXcode'], '2610');
      expect(keys.containsKey('DTXcodeBuild'), isFalse);
    });

    test('an XML SystemVersion.plist is read without printing a parser '
        'stack trace', () {
      final iosSdk = sdk();
      File(
        p.join(
          iosSdk,
          'System',
          'Library',
          'CoreServices',
          'SystemVersion.plist',
        ),
      ).writeAsStringSync(
        PropertyListSerialization.stringWithPropertyList(<String, Object>{
          'ProductVersion': '27.1',
          'ProductBuildVersion': '25B5',
        }),
      );
      final printed = <String>[];
      final info = runZoned(
        () => XcodeBuildInfo.read(
          fileSystem: detectPlatformHost().fileSystem,
          paths: p.context,
          iosSdk: iosSdk,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );
      expect(info.sdkBuild, '25B5');
      expect(info.dtXcode, '2710');
      expect(printed, isEmpty);
    });

    test('DTXcode format', () {
      expect(XcodeBuildInfo.dtXcodeOf('26.0'), '2600');
      expect(XcodeBuildInfo.dtXcodeOf('27.1'), '2710');
      expect(XcodeBuildInfo.dtXcodeOf('9.4'), '0940');
      expect(XcodeBuildInfo.dtXcodeOf('x'), isNull);
    });

    test('written into the plist, replacing stale values', () {
      const xml = '$_head<key>DTXcode</key><string>1500</string>$_tail';
      final out =
          PropertyListSerialization.propertyListWithString(read().applyTo(xml))
              as Map;
      expect(out['DTXcode'], '2611');
      expect(out['DTSDKBuild'], '23B77');
    });
  });

  test('AC-018-8 export compliance is added only when missing', () {
    const plain = '$_head$_tail';
    final added =
        PropertyListSerialization.propertyListWithString(
              InfoPlist.withBoolIfMissing(
                plain,
                'ITSAppUsesNonExemptEncryption',
                value: false,
              ),
            )
            as Map;
    expect(added['ITSAppUsesNonExemptEncryption'], isFalse);

    const declared =
        '$_head<key>ITSAppUsesNonExemptEncryption</key><true/>$_tail';
    expect(
      InfoPlist.withBoolIfMissing(
        declared,
        'ITSAppUsesNonExemptEncryption',
        value: false,
      ),
      declared,
    );
  });
}
