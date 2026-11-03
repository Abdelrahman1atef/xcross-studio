// studio: 016 — the doctor's push section (specs/016-push-firebase-maps).
import 'dart:io';

import 'package:cli_kit/composition/native_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/cli/basic/doctor_models.dart';
import 'package:xcross/src/shared/flutter/project/push_readiness.dart';

@internal
String plist(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<plist version="1.0"><dict>$body</dict></plist>\n';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('push-readiness-');
    Directory(p.join(root.path, 'ios', 'Runner')).createSync(recursive: true);
    final project = Directory(p.join(root.path, 'ios', 'Runner.xcodeproj'))
      ..createSync(recursive: true);
    File(p.join(project.path, 'project.pbxproj')).writeAsStringSync(
      '{\n  PRODUCT_BUNDLE_IDENTIFIER = com.example.app;\n}\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String text) {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  void usesMessaging() => write(
    'pubspec.yaml',
    'name: app\ndependencies:\n  firebase_messaging: any\n',
  );

  PushReadiness readiness([Map<String, String> environment = const {}]) =>
      PushReadiness(
        fileSystem: detectPlatformHost().fileSystem,
        paths: p.context,
        projectRoot: root.path,
        environment: environment,
      );

  DoctorCheck check(String name, [Map<String, String> env = const {}]) =>
      readiness(env).checks().singleWhere((c) => c.name == name);

  group('AC-016-6 push readiness', () {
    test('absent for an app without push', () {
      write('pubspec.yaml', 'name: app\ndependencies:\n  http: any\n');
      expect(readiness().applies, isFalse);
    });

    test('inferred entitlement is a warning with the fix', () {
      usesMessaging();
      expect(readiness().applies, isTrue);
      final entitlement = check(PushReadiness.entitlementCheck);
      expect(entitlement.status, DoctorStatus.warning);
      expect(entitlement.message, contains('Runner.entitlements'));
    });

    test('declared entitlement is fine', () {
      write(
        'ios/Runner/Runner.entitlements',
        plist('<key>aps-environment</key><string>development</string>'),
      );
      expect(readiness().applies, isTrue);
      expect(
        check(PushReadiness.entitlementCheck).status,
        DoctorStatus.success,
      );
    });

    test('a saved prefixed App ID fails with the command to fix it', () {
      write(
        'pubspec.yaml',
        'name: app\ndependencies:\n  firebase_messaging: any\n'
            'xcross:\n  bundle_id: prefixed\n',
      );
      final appId = check(PushReadiness.appIdCheck);
      expect(appId.status, DoctorStatus.failure);
      expect(appId.message, contains('xcross project bundle-id original'));
      expect(appId.message, contains('com.example.app'));
    });

    test('XCROSS_BUNDLE_ID=original wins over a saved prefixed', () {
      write(
        'pubspec.yaml',
        'name: app\ndependencies:\n  firebase_messaging: any\n'
            'xcross:\n  bundle_id: prefixed\n',
      );
      final appId = check(PushReadiness.appIdCheck, {
        'XCROSS_BUNDLE_ID': 'original',
      });
      expect(appId.status, DoctorStatus.success);
    });

    test('GoogleService-Info.plist for another bundle ID fails', () {
      usesMessaging();
      write(
        'ios/Runner/GoogleService-Info.plist',
        plist(
          '<key>API_KEY</key><string>secret-key-value</string>'
          '<key>BUNDLE_ID</key><string>XCR-team.com.example.app</string>',
        ),
      );
      final firebase = check(PushReadiness.firebaseCheck);
      expect(firebase.status, DoctorStatus.failure);
      expect(firebase.message, contains('XCR-team.com.example.app'));
      expect(firebase.message, isNot(contains('secret-key-value')));
    });

    test('matching Firebase config passes; options file is checked too', () {
      usesMessaging();
      write(
        'ios/Runner/GoogleService-Info.plist',
        plist('<key>BUNDLE_ID</key><string>com.example.app</string>'),
      );
      write(
        'lib/firebase_options.dart',
        "const ios = FirebaseOptions(iosBundleId: 'com.example.app');\n",
      );
      final firebase = check(PushReadiness.firebaseCheck);
      expect(firebase.status, DoctorStatus.success);
      expect(firebase.message, contains('firebase_options.dart'));
    });

    test('missing Firebase config is a warning for a messaging app', () {
      usesMessaging();
      expect(check(PushReadiness.firebaseCheck).status, DoctorStatus.warning);
    });
  });
}
