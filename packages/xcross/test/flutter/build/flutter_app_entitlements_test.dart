// studio: 003 — the Flutter app's entitlements reach the signer.
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/flutter_app_entitlements.dart';

void main() {
  late Directory project;
  final entitlements = FlutterAppEntitlements(
    const IoTestFileSystem(),
    p.context,
  );

  setUp(() => project = Directory.systemTemp.createTempSync('xcross-ent-'));
  tearDown(() => project.deleteSync(recursive: true));

  File runnerEntitlements(String text) =>
      File(p.join(project.path, 'ios', 'Runner', 'Runner.entitlements'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);

  final declaredXml =
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>aps-environment</key><string>development</string>
  <key>com.apple.developer.associated-domains</key>
  <array><string>applinks:example.com</string></array>
</dict>
</plist>'''
          .trim();

  final infoXml =
      '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.app</string>
</dict></plist>'''
          .trim();

  test('AC-003-1 declared entitlements and capabilities reach Info.plist', () {
    runnerEntitlements(declaredXml);
    final path = entitlements.locate(project.path)!;
    final merged = FlutterAppEntitlements.withSigningKeys(
      infoXml,
      entitlements.read(path),
    );
    final root =
        PropertyListSerialization.propertyListWithString(merged) as Map;
    expect(root['CFBundleIdentifier'], 'com.example.app');
    expect(
      (root['XCrossEntitlements'] as Map)['aps-environment'],
      'development',
    );
    expect(
      root['XCrossCapabilities'],
      containsAll(['PUSH_NOTIFICATIONS', 'ASSOCIATED_DOMAINS']),
    );
  });

  test('CODE_SIGN_ENTITLEMENTS from the project wins over the default', () {
    runnerEntitlements(declaredXml);
    final custom = File(
      p.join(project.path, 'ios', 'Runner', 'Custom.entitlements'),
    )..writeAsStringSync(declaredXml);
    expect(
      entitlements.locate(project.path, fromProject: custom.path),
      custom.path,
    );
  });

  test('AC-003-2 no entitlements file: nothing changes', () {
    expect(entitlements.locate(project.path), isNull);
    expect(FlutterAppEntitlements.withSigningKeys(infoXml, {}), infoXml);
  });

  test(
    'AC-003-3 an unreadable file is a FormatException (warned upstream)',
    () {
      final path = runnerEntitlements('<plist><dict><key>broken').path;
      expect(() => entitlements.read(path), throwsFormatException);
    },
  );
}

/// dart:io-backed host file system for this test.
@internal
final class IoTestFileSystem implements HostFileSystemInterface {
  const IoTestFileSystem();

  @override
  File file(String path) => File(path);
  @override
  Directory directory(String path) => Directory(path);
  @override
  Link link(String path) => Link(path);
  @override
  void makeExecutable(String path) {}
  @override
  void setPermissions(String path, int mode) {}
  @override
  Future<void> createArchiveLink(String destination, String target) =>
      Link(destination).create(target);
}
