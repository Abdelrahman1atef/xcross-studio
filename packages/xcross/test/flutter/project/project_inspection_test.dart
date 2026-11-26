// studio: 051 — `xcross project inspect`, `set-bundle-id` and
// `firebase-import` (specs/051-project-inspect).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/flutter/project/project_inspection.dart';
import 'package:xcross/src/target/iphone/cli/basic/project_command.dart';

String _plist(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<plist version="1.0">\n<dict>\n$body</dict>\n</plist>\n';

String _config(String id, String name, Map<String, String> settings) =>
    '\t\t$id /* $name */ = {\n'
    '\t\t\tisa = XCBuildConfiguration;\n'
    '\t\t\tbuildSettings = {\n'
    '${settings.entries.map((e) => '\t\t\t\t${e.key} = ${e.value};\n').join()}'
    '\t\t\t};\n'
    '\t\t\tname = $name;\n'
    '\t\t};\n';

/// A Flutter-like pbxproj: Runner (app) and RunnerTests, three configs each.
String _pbxproj({
  Map<String, String> app = const {},
  Map<String, String> release = const {},
  String tests = 'com.example.app.RunnerTests',
  String projectTarget = '12.0',
}) {
  Map<String, String> appSettings(Map<String, String> extra) => {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.app',
    'DEVELOPMENT_TEAM': 'TEAM123456',
    'CODE_SIGN_STYLE': 'Automatic',
    'IPHONEOS_DEPLOYMENT_TARGET': '16.0',
    'CODE_SIGN_ENTITLEMENTS': 'Runner/Runner.entitlements',
    ...app,
    ...extra,
  };
  return '// !\$*UTF8*\$!\n{\n'
      '\tarchiveVersion = 1;\n\tobjectVersion = 54;\n\tobjects = {\n'
      '\t\tP0 = {\n\t\t\tisa = PBXProject;\n'
      '\t\t\tbuildConfigurationList = PL;\n'
      '\t\t\ttargets = (\n\t\t\t\tT1,\n\t\t\t\tT2,\n\t\t\t);\n\t\t};\n'
      '\t\tPL = {\n\t\t\tisa = XCConfigurationList;\n'
      '\t\t\tbuildConfigurations = (\n\t\t\t\tPD,\n\t\t\t\tPR,\n\t\t\t);\n\t\t};\n'
      '${_config('PD', 'Debug', {'IPHONEOS_DEPLOYMENT_TARGET': projectTarget})}'
      '${_config('PR', 'Release', {'IPHONEOS_DEPLOYMENT_TARGET': projectTarget})}'
      '\t\tT1 = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tname = Runner;\n'
      '\t\t\tbuildConfigurationList = L1;\n'
      '\t\t\tproductType = "com.apple.product-type.application";\n\t\t};\n'
      '\t\tL1 = {\n\t\t\tisa = XCConfigurationList;\n'
      '\t\t\tbuildConfigurations = (\n\t\t\t\tA1,\n\t\t\t\tA2,\n\t\t\t\tA3,\n'
      '\t\t\t);\n\t\t};\n'
      '${_config('A1', 'Debug', appSettings(const {}))}'
      '${_config('A2', 'Release', appSettings(release))}'
      '${_config('A3', 'Profile', appSettings(const {}))}'
      '\t\tT2 = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tname = RunnerTests;\n'
      '\t\t\tbuildConfigurationList = L2;\n'
      '\t\t\tproductType = "com.apple.product-type.bundle.unit-test";\n\t\t};\n'
      '\t\tL2 = {\n\t\t\tisa = XCConfigurationList;\n'
      '\t\t\tbuildConfigurations = (\n\t\t\t\tB1,\n\t\t\t\tB2,\n\t\t\t);\n\t\t};\n'
      '${_config('B1', 'Debug', {'PRODUCT_BUNDLE_IDENTIFIER': tests})}'
      '${_config('B2', 'Release', {'PRODUCT_BUNDLE_IDENTIFIER': tests})}'
      '\t};\n\trootObject = P0;\n}\n';
}

const _info =
    '\t<key>CFBundleIdentifier</key>\n'
    '\t<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>\n'
    '\t<key>CFBundleShortVersionString</key>\n'
    '\t<string>\$(FLUTTER_BUILD_NAME)</string>\n'
    '\t<key>CFBundleVersion</key>\n'
    '\t<string>\$(FLUTTER_BUILD_NUMBER)</string>\n';

String _googlePlist({
  String bundle = 'com.example.app',
  String app = '1:111:ios:aaa',
  String project = 'demo-project',
}) => _plist(
  '\t<key>API_KEY</key>\n\t<string>AIzaPLISTKEY000</string>\n'
  '\t<key>GCM_SENDER_ID</key>\n\t<string>111</string>\n'
  '\t<key>BUNDLE_ID</key>\n\t<string>$bundle</string>\n'
  '\t<key>PROJECT_ID</key>\n\t<string>$project</string>\n'
  '\t<key>STORAGE_BUCKET</key>\n\t<string>$project.appspot.com</string>\n'
  '\t<key>GOOGLE_APP_ID</key>\n\t<string>$app</string>\n',
);

String _options({
  String bundle = 'com.example.app',
  String app = '1:111:ios:aaa',
}) =>
    "import 'package:firebase_core/firebase_core.dart';\n\n"
    'class DefaultFirebaseOptions {\n'
    '  static const FirebaseOptions android = FirebaseOptions(\n'
    "    apiKey: 'AIzaANDROID',\n"
    "    appId: '1:111:android:bbb',\n"
    "    messagingSenderId: '111',\n"
    "    projectId: 'demo-project',\n"
    '  );\n\n'
    '  static const FirebaseOptions ios = FirebaseOptions(\n'
    "    apiKey: 'AIzaPLISTKEY000',\n"
    "    appId: '$app',\n"
    "    messagingSenderId: '111',\n"
    "    projectId: 'demo-project',\n"
    "    storageBucket: 'demo-project.appspot.com',\n"
    "    iosBundleId: '$bundle',\n"
    '  );\n'
    '}\n';

String _firebaseJson(String app) =>
    '{"flutter":{"platforms":{"android":{"default":{"projectId":"demo-project",'
    '"appId":"1:111:android:bbb"}},"ios":{"default":{"projectId":"demo-project",'
    '"appId":"$app","fileOutput":"ios/Runner/GoogleService-Info.plist"}},'
    '"dart":{"lib/firebase_options.dart":{"projectId":"demo-project",'
    '"configurations":{"android":"1:111:android:bbb","ios":"$app"}}}}}}\n';

void main() {
  late Directory root;
  late StringBuffer out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('project-inspect-');
    out = StringBuffer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String text) {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  String read(String relative) =>
      File(p.joinAll([root.path, ...relative.split('/')])).readAsStringSync();

  /// A healthy project with push and Firebase.
  void project({String pbx = '', String? info}) {
    write('pubspec.yaml', 'name: app\nversion: 1.2.3+7\n');
    write(
      'ios/Runner.xcodeproj/project.pbxproj',
      pbx.isEmpty ? _pbxproj() : pbx,
    );
    write('ios/Runner/Info.plist', _plist(info ?? _info));
    write('ios/Podfile', "platform :ios, '16.0'\n");
    write(
      'ios/Runner/Runner.entitlements',
      _plist('\t<key>aps-environment</key>\n\t<string>development</string>\n'),
    );
    write('ios/Runner/GoogleService-Info.plist', _googlePlist());
    write('lib/firebase_options.dart', _options());
    write('firebase.json', _firebaseJson('1:111:ios:aaa'));
  }

  ProjectInspection inspect() => ProjectInspector(
    fileSystem: detectPlatformHost().fileSystem,
    paths: p.context,
    projectRoot: root.path,
  ).inspect();

  InspectItem item(String id) => inspect().items.singleWhere((i) => i.id == id);

  Future<Map<String, Object?>> run(List<String> args) async {
    out.clear();
    await (CommandRunner<void>('xcross', 'test')..addCommand(
          ProjectCommand(
            fileSystem: detectPlatformHost().fileSystem,
            paths: p.context,
            projectRoot: () => root.path,
            environment: const {},
            write: out.write,
          ),
        ))
        .run(['project', ...args, '--json']);
    return jsonDecode(out.toString().trim()) as Map<String, Object?>;
  }

  group('AC-051-1 inspect reads the whole iOS setup', () {
    test('a healthy project has no problems and names every value', () async {
      project();
      final json = await run(['inspect']);
      expect(json['type'], 'project_inspect');
      expect(json['bundleId'], 'com.example.app');
      expect(json['teamId'], 'TEAM123456');
      expect(json['version'], '1.2.3');
      expect(json['build'], 7);
      expect(json['errors'], 0);
      expect(json['warnings'], 0);
      expect(item('deployment_target').value, '16.0');
      expect(item('signing').value, 'Automatic');
      expect(item('aps_environment').value, 'development');
      expect(item('firebase_app_id').value, '1:111:ios:aaa');
      expect(item('firebase_project').value, 'demo-project');
      final key = item('firebase_api_key');
      expect(key.secret, isTrue);
      expect(key.value, 'AIzaPLISTKEY000');
      expect(item('bundle_id').path, 'ios/Runner.xcodeproj/project.pbxproj');
    });

    test('the project-level deployment target is used when the app has '
        'none, and a higher Podfile is an error', () {
      project(
        pbx: _pbxproj(
          app: const {'IPHONEOS_DEPLOYMENT_TARGET': r'"$(inherited)"'},
        ),
      );
      write('ios/Podfile', "platform :ios, '17.0'\n");
      expect(item('deployment_target').value, r'$(inherited)');
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        _pbxproj(release: const {'IPHONEOS_DEPLOYMENT_TARGET': '15.0'}),
      );
      final target = item('deployment_target');
      expect(target.value, '15.0');
      expect(target.status, InspectStatus.error);
      expect(target.code, 'deployment_target.podfile_higher');
    });
  });

  group('AC-051-2 inspect finds the problems that block an upload', () {
    test('configurations with different bundle IDs', () {
      project(
        pbx: _pbxproj(
          release: const {'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.store'},
        ),
      );
      final id = item('bundle_id');
      expect(id.value, 'com.example.store');
      expect(id.status, InspectStatus.error);
      expect(id.code, 'bundle_id.configs_differ');
      expect(id.message, contains('Debug com.example.app'));
    });

    test('Firebase for another bundle ID or another app', () {
      project();
      write(
        'ios/Runner/GoogleService-Info.plist',
        _googlePlist(bundle: 'com.example.old', app: '1:111:ios:old'),
      );
      expect(item('plist_bundle_id').code, 'firebase.bundle_mismatch');
      final app = item('firebase_app_id');
      expect(app.status, InspectStatus.error);
      expect(app.code, 'firebase.app_mismatch');
      expect(app.message, contains('1:111:ios:old'));
      expect(app.message, contains('1:111:ios:aaa'));
    });

    test('firebase.json naming another iOS app', () {
      project();
      write('firebase.json', _firebaseJson('1:111:ios:zzz'));
      expect(item('firebase_app_id').code, 'firebase.app_mismatch');
    });

    test('a hard-coded Info.plist version and a missing push entitlement', () {
      project(
        info:
            '\t<key>CFBundleShortVersionString</key>\n'
            '\t<string>1.0</string>\n',
      );
      File(
        p.join(root.path, 'ios', 'Runner', 'Runner.entitlements'),
      ).deleteSync();
      write(
        'pubspec.yaml',
        'name: app\nversion: 1.2.3+7\ndependencies:\n  firebase_messaging: any\n',
      );
      expect(item('version').code, 'version.info_plist_fixed');
      expect(item('aps_environment').code, 'push.no_entitlement');
    });

    test('an extension outside the app ID is an error; tests only warn', () {
      project(pbx: _pbxproj(tests: 'com.other.tests'));
      final tests = item('target_runnertests');
      expect(tests.status, InspectStatus.warning);
      expect(tests.code, 'bundle_id.target_outside');
    });

    test('no iOS app target', () {
      write('ios/Runner.xcodeproj/project.pbxproj', '{ objects = {}; }');
      final report = inspect();
      expect(report.count(InspectStatus.error), 1);
      expect(report.items.first.code, 'project.no_ios_app');
    });
  });

  group('AC-051-3 other keys are listed, secrets marked', () {
    test('Google Maps key in AppDelegate and Info.plist IDs', () {
      project(
        info:
            '$_info\t<key>FacebookAppID</key>\n\t<string>123</string>\n'
            '\t<key>FacebookClientToken</key>\n\t<string></string>\n',
      );
      write(
        'ios/Runner/AppDelegate.swift',
        'GMSServices.provideAPIKey("AIzaMAPS1234")\n',
      );
      final maps = item('google_maps_key');
      expect(maps.value, 'AIzaMAPS1234');
      expect(maps.secret, isTrue);
      expect(item('info_facebookappid').value, '123');
      final token = item('info_facebookclienttoken');
      expect(token.status, InspectStatus.warning);
      expect(token.code, 'keys.empty');
    });
  });

  group('AC-051-4 set-bundle-id changes the ID everywhere', () {
    test('every app configuration and the test target, nothing else', () async {
      project(
        pbx: _pbxproj(
          release: const {'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.store'},
        ),
      );
      final before = read('ios/Runner.xcodeproj/project.pbxproj');
      final dry = await run(['set-bundle-id', 'com.new.app', '--dry-run']);
      expect(dry['dryRun'], isTrue);
      expect(read('ios/Runner.xcodeproj/project.pbxproj'), before);

      final json = await run(['set-bundle-id', 'com.new.app']);
      expect(json['previous'], 'com.example.store');
      expect(json['files'], [
        {'path': 'ios/Runner.xcodeproj/project.pbxproj', 'changes': 5},
      ]);
      final after = read('ios/Runner.xcodeproj/project.pbxproj');
      expect(after, isNot(contains('com.example.')));
      expect(after, contains('com.new.app.RunnerTests'));
      // Only the values changed: same length difference per value.
      expect(
        after.replaceAll('com.new.app', 'X'),
        before
            .replaceAll('com.example.store', 'X')
            .replaceAll('com.example.app', 'X'),
      );
      final report = inspect();
      expect(report.bundleId, 'com.new.app');
      expect(
        report.items.singleWhere((i) => i.id == 'bundle_id').status,
        InspectStatus.ok,
      );
      // Firebase is left alone and now reports the mismatch.
      expect(
        report.items.singleWhere((i) => i.id == 'plist_bundle_id').code,
        'firebase.bundle_mismatch',
      );
    });

    test('a hard-coded Info.plist ID follows the build setting', () async {
      project(
        info:
            '\t<key>CFBundleIdentifier</key>\n'
            '\t<string>com.example.app</string>\n',
      );
      await run(['set-bundle-id', 'com.new.app']);
      expect(
        read('ios/Runner/Info.plist'),
        contains(r'<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>'),
      );
    });

    test('an invalid ID is refused', () async {
      project();
      await expectLater(
        run(['set-bundle-id', 'not an id']),
        throwsA(isA<XcrossError>()),
      );
    });
  });

  group('AC-051-5 firebase-import puts one iOS app everywhere', () {
    test('the plist, firebase_options.dart and firebase.json agree '
        'afterwards; Android is untouched', () async {
      project();
      final download = p.join(root.path, 'download.plist');
      File(download).writeAsStringSync(_googlePlist(app: '1:111:ios:new'));
      final json = await run(['firebase-import', download]);
      expect(json['appId'], '1:111:ios:new');
      expect(
        (json['files']! as List).map((f) => (f as Map)['path']),
        containsAll([
          'ios/Runner/GoogleService-Info.plist',
          'lib/firebase_options.dart',
          'firebase.json',
        ]),
      );
      expect(read('lib/firebase_options.dart'), contains("'1:111:ios:new'"));
      expect(
        read('lib/firebase_options.dart'),
        contains("appId: '1:111:android:bbb'"),
      );
      expect(read('firebase.json'), isNot(contains('1:111:ios:aaa')));
      expect(read('firebase.json'), contains('1:111:android:bbb'));
      final app = item('firebase_app_id');
      expect(app.status, InspectStatus.ok);
      expect(app.value, '1:111:ios:new');
    });

    test('a plist for another bundle ID or project is refused, nothing '
        'written', () async {
      project();
      final download = p.join(root.path, 'download.plist');
      File(download).writeAsStringSync(_googlePlist(bundle: 'com.other.app'));
      await expectLater(
        run(['firebase-import', download]),
        throwsA(
          isA<XcrossError>().having(
            (e) => e.message,
            'message',
            contains('com.other.app'),
          ),
        ),
      );
      File(download).writeAsStringSync(_googlePlist(project: 'other-project'));
      await expectLater(
        run(['firebase-import', download]),
        throwsA(isA<XcrossError>()),
      );
      expect(read('ios/Runner/GoogleService-Info.plist'), _googlePlist());
    });
  });
}
