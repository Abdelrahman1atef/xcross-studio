// studio: 016 — push without an entitlements file (specs/016-push-firebase-maps).
import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/composition/native_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/push_entitlement.dart';

@internal
String plist(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0"><dict>$body</dict></plist>\n';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('push-signals-'));
  tearDown(() => root.deleteSync(recursive: true));

  PushSignals read({String? infoPlist}) => PushSignals.read(
    fileSystem: detectPlatformHost().fileSystem,
    projectRoot: root.path,
    infoPlistXml: infoPlist,
  );

  void writePluginList(List<String> names) =>
      File(
        p.join(root.path, '.flutter-plugins-dependencies'),
      ).writeAsStringSync(
        jsonEncode({
          'plugins': {
            'ios': [
              for (final name in names)
                {'name': name, 'path': p.join(root.path, 'pkgs', name)},
            ],
          },
        }),
      );

  group('AC-016-4 push signals', () {
    test('firebase_messaging in the resolved plugin list', () {
      writePluginList(['firebase_core', 'firebase_messaging']);
      final signals = read(infoPlist: plist(''));
      expect(signals.usesFirebaseMessaging, isTrue);
      expect(signals.reason, 'the app uses firebase_messaging');
    });

    test('firebase_messaging in pubspec.yaml before pub get', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
        'name: app\ndependencies:\n  firebase_messaging: ^16.0.0\n',
      );
      expect(read(infoPlist: plist('')).usesFirebaseMessaging, isTrue);
    });

    test('remote-notification background mode', () {
      final signals = read(
        infoPlist: plist(
          '<key>UIBackgroundModes</key>'
          '<array><string>fetch</string>'
          '<string>remote-notification</string></array>',
        ),
      );
      expect(signals.remoteNotificationMode, isTrue);
      expect(signals.reason, contains('remote-notification'));
    });

    test('no signal, nothing inferred', () {
      writePluginList(['url_launcher_ios']);
      final signals = read(infoPlist: plist(''));
      expect(signals.any, isFalse);
      expect(signals.inferInto(const {}), isNull);
    });

    test('adds development when not declared, keeps other keys', () {
      writePluginList(['firebase_messaging']);
      expect(
        read(infoPlist: plist('')).inferInto({
          'com.apple.developer.associated-domains': ['applinks:example.com'],
        }),
        {
          'com.apple.developer.associated-domains': ['applinks:example.com'],
          'aps-environment': 'development',
        },
      );
    });

    test('never changes a declared value', () {
      writePluginList(['firebase_messaging']);
      expect(
        read(
          infoPlist: plist(''),
        ).inferInto(const {'aps-environment': 'production'}),
        isNull,
      );
    });

    test('reads the project Info.plist when none is passed', () {
      Directory(p.join(root.path, 'ios', 'Runner')).createSync(recursive: true);
      File(p.join(root.path, 'ios', 'Runner', 'Info.plist')).writeAsStringSync(
        plist(
          '<key>UIBackgroundModes</key>'
          '<array><string>remote-notification</string></array>',
        ),
      );
      expect(read().remoteNotificationMode, isTrue);
    });
  });
}
