// studio: 025 — `xcross plugin check`: what a build will do, without compiling.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/plugins/plugin_command.dart';
import 'package:test/test.dart';

import '../../support/test_file_system.dart';

void main() {
  late Directory temp;
  late List<String> out;
  final entries = <Map<String, String>>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross_plugin_check_');
    out = [];
    entries.clear();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void addPlugin(String name, {String? podspec, bool swiftPackage = false}) {
    final root = p.join(temp.path, 'pub', name);
    File(p.join(root, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: $name\nversion: 1.0.0\n');
    if (podspec != null) {
      File(p.join(root, 'ios', '$name.podspec'))
        ..createSync(recursive: true)
        ..writeAsStringSync(podspec);
    }
    if (swiftPackage) {
      File(p.join(root, 'ios', name, 'Package.swift'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// shipped');
    }
    entries.add({'name': name, 'path': root});
  }

  Future<void> check() {
    File(p.join(temp.path, '.flutter-plugins-dependencies')).writeAsStringSync(
      jsonEncode({
        'plugins': {'ios': entries},
      }),
    );
    return (CommandRunner<void>('xcross', 'test')..addCommand(
          PluginCommand(
            fileSystem: const IoFileSystem(),
            paths: p.context,
            write: out.add,
          ),
        ))
        .run(['plugin', 'check', '--project', temp.path]);
  }

  test('AC-025-4 says what the build will do with each plugin', () async {
    addPlugin('modern', swiftPackage: true);
    addPlugin(
      'draftable',
      podspec: "Pod::Spec.new do |s|\n  s.dependency 'Flutter'\nend\n",
    );
    addPlugin('dart_only');
    await check();

    final text = out.join();
    expect(text, contains('✔ modern 1.0.0  (swiftpm)'));
    expect(
      text,
      contains('✔ draftable 1.0.0  (podspec only: the next build drafts it)'),
    );
    expect(text, contains('✔ dart_only 1.0.0  (no iOS code)'));
  });

  test('AC-025-4 a pod with no known Swift package fails the check and is '
      'named', () async {
    addPlugin(
      'vendored',
      podspec:
          "Pod::Spec.new do |s|\n  s.dependency 'Flutter'\n"
          "  s.dependency 'SomeVendorSDK', '~> 1.0'\nend\n",
    );
    await expectLater(
      check(),
      throwsA(
        isA<CliError>().having(
          (error) => error.toString(),
          'message',
          allOf(contains('plugin.unknown_pods'), contains('vendored')),
        ),
      ),
    );
    expect(
      out.join(),
      contains(
        '✖ vendored 1.0.0  (podspec only, no Swift package for: SomeVendorSDK)',
      ),
    );
  });

  test('AC-025-4 the check writes nothing', () async {
    addPlugin(
      'draftable',
      podspec: "Pod::Spec.new do |s|\n  s.dependency 'Flutter'\nend\n",
    );
    await check();
    expect(
      Directory(p.join(temp.path, 'xcross_overrides')).existsSync(),
      isFalse,
    );
  });
}
