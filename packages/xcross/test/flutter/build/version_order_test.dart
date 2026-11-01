// studio: 002 — bundle version precedence (flag > pubspec > xcconfig >
// project file > default).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/flutter_packer.dart';
import 'package:xcross/src/shared/flutter/build/info_plist.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_versions.dart';
import 'package:xcross/src/shared/flutter/flutter_build_steps.dart';
import 'package:xcross/src/shared/flutter/flutter_bundle_assembler.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_options.dart';
import 'package:xcross/src/shared/flutter/models/pubspec_info.dart';
import 'package:xcross/src/shared/flutter/project/ios_bundle_versions_resolver.dart';

import '../flutter_test_runtime.dart';

void main() {
  IosBundleVersions decide({
    String? flag,
    String? flagNumber,
    String? pubspec,
    String? xcconfig,
    String? xcconfigNumber,
    String? project,
    String? projectNumber,
  }) {
    final info = PubspecInfo(
      name: 'app',
      usesMaterialDesign: false,
      version: pubspec,
    );
    return IosBundleVersionsResolver.decide(
      buildName: flag,
      buildNumber: flagNumber,
      pubspecBuildName: info.buildName,
      pubspecBuildNumber: info.buildNumber,
      xcconfigBuildName: xcconfig,
      xcconfigBuildNumber: xcconfigNumber,
      projectBuildName: project,
      projectBuildNumber: projectNumber,
    );
  }

  test('AC-002-5 pubspec wins over a stale xcconfig', () {
    final versions = decide(
      pubspec: '1.0.7+7',
      xcconfig: '1.0.6',
      xcconfigNumber: '6',
      project: '9.9.9',
      projectNumber: '99',
    );
    expect(versions.toString(), '1.0.7 (7)');
    expect(versions.shortVersionSource, VersionSource.pubspec);
    expect(versions.bundleVersionSource, VersionSource.pubspec);
  });

  test('AC-002-6 flags win over everything', () {
    final versions = decide(
      flag: '2.0.0',
      flagNumber: '42',
      pubspec: '1.0.7+7',
      xcconfig: '1.0.6',
      xcconfigNumber: '6',
    );
    expect(versions.toString(), '2.0.0 (42)');
    expect(versions.shortVersionSource, VersionSource.flag);
  });

  test(
    'AC-002-7 without a pubspec version: xcconfig, project file, default',
    () {
      expect(
        decide(xcconfig: '1.0.6', xcconfigNumber: '6').toString(),
        '1.0.6 (6)',
      );
      expect(
        decide(project: '2.4.1', projectNumber: '37').toString(),
        '2.4.1 (37)',
      );
      final fallback = decide();
      expect(fallback.toString(), '1.0.0 (1)');
      expect(fallback.shortVersionSource, VersionSource.fallback);
    },
  );

  test('name and number are resolved independently', () {
    final versions = decide(pubspec: '1.2.3', xcconfigNumber: '6');
    expect(versions.toString(), '1.2.3 (6)');
    expect(versions.shortVersionSource, VersionSource.pubspec);
    expect(versions.bundleVersionSource, VersionSource.xcconfig);
  });

  test('an invalid pubspec version and unresolved values fall through', () {
    final versions = decide(
      pubspec: 'not-a-version',
      xcconfig: r'$(FLUTTER_BUILD_NAME)',
      project: '3.0.0',
      projectNumber: '30',
    );
    expect(versions.toString(), '3.0.0 (30)');
    expect(versions.shortVersionSource, VersionSource.projectFile);
  });

  test('AC-002-8 the version line names each source', () {
    expect(
      decide(pubspec: '1.0.7+7').describe(),
      '1.0.7 (7) · name: pubspec.yaml · number: pubspec.yaml',
    );
    expect(
      decide(flag: '2.0.0', xcconfigNumber: '6').describe(),
      '2.0.0 (6) · name: --build-name · number: xcconfig',
    );
  });

  test(
    testOn: '!windows',
    'AC-002-5 stale Generated.xcconfig: the plist gets the pubspec version for '
    'both template spellings',
    () async {
      final project = await Directory.systemTemp.createTemp('xcross-ver-');
      addTearDown(() => project.delete(recursive: true));
      File(
        p.join(project.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: example\nversion: 1.0.7+7\n');
      final flutter = Directory(p.join(project.path, 'ios', 'Flutter'))
        ..createSync(recursive: true);
      File(
        p.join(flutter.path, 'Generated.xcconfig'),
      ).writeAsStringSync('FLUTTER_BUILD_NAME=1.0.6\nFLUTTER_BUILD_NUMBER=6\n');
      File(
        p.join(flutter.path, 'Debug.xcconfig'),
      ).writeAsStringSync('#include "Generated.xcconfig"\n');
      final packer = FlutterPacker(
        runtime: testIPhoneRuntime(),
        projectRoot: project.path,
        bundleId: 'com.example.app',
        options: const FlutterBuildOptions(),
      );
      expect(packer.request.versions.toString(), '1.0.7 (7)');
      final xml = InfoPlist.expandXmlVars(
        '<plist><dict>'
        r'<key>A</key><string>$(FLUTTER_BUILD_NAME)</string>'
        r'<key>B</key><string>$(FLUTTER_BUILD_NUMBER)</string>'
        r'<key>C</key><string>$(MARKETING_VERSION)</string>'
        r'<key>D</key><string>$(CURRENT_PROJECT_VERSION)</string>'
        '</dict></plist>',
        await FlutterBundleAssembler(
          FlutterBuildContext(request: packer.request, flutterRoot: '/flutter'),
        ).buildSubstitutionMap(),
      );
      for (final value in ['1.0.7</string>', '7</string>']) {
        expect(RegExp(RegExp.escape(value)).allMatches(xml), hasLength(2));
      }
      expect(xml, isNot(contains('1.0.6')));
    },
  );
}
