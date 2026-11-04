// studio: 025 — podspec-only plugins get a draft when a build starts.
import 'dart:io';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/diagnostics/build_warnings.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';
import 'package:xcross/src/shared/flutter/build/plugin_auto_draft.dart';
import 'package:xcross/src/shared/flutter/build/plugin_overrides.dart';

import '../../log_fixture.dart';
import 'plugin_overrides_test.dart' as overrides;

void main() {
  const fs = overrides.OverrideTestFileSystem();
  late Directory tmp;
  late String project;
  late String pubCache;
  late TestLogOutput log;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('xcross_auto_draft_');
    project = p.join(tmp.path, 'app');
    pubCache = p.join(tmp.path, 'pub-cache');
    Directory(project).createSync();
    log = TestLogOutput();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  IosPlugin plugin(
    String name, {
    String pods = '',
    bool podspec = true,
    bool swiftPackage = false,
  }) {
    final root = p.join(pubCache, name);
    write(p.join(root, 'pubspec.yaml'), 'name: $name\nversion: 1.2.3\n');
    if (podspec) {
      write(
        p.join(root, 'ios', '$name.podspec'),
        "Pod::Spec.new do |s|\n  s.source_files = 'Classes/**/*'\n"
        "  s.dependency 'Flutter'\n$pods"
        'end\n',
      );
    }
    write(p.join(root, 'ios', 'Classes', '${name}Plugin.m'), '// objc');
    if (swiftPackage) {
      write(p.join(root, 'ios', name, 'Package.swift'), '// shipped');
    }
    return IosPlugin(name: name, fileSystem: fs, packageRoot: root);
  }

  PluginOverrideLocator locator() => PluginOverrideLocator(
    fileSystem: fs,
    paths: p.context,
    projectRoot: project,
    environment: {'HOME': p.join(tmp.path, 'home')},
  );

  BuildWarnings warnings() => BuildWarnings(Log(output: log));

  Set<String> draft(List<IosPlugin> plugins, {Map<String, String>? env}) =>
      PluginAutoDraft(
        fileSystem: fs,
        paths: p.context,
        projectRoot: project,
        locator: locator(),
        warnings: warnings(),
        environment: env ?? const {},
      ).draftMissing(plugins);

  String draftPath(String name) =>
      p.join(project, 'xcross_overrides', name, '1.2.3', 'Package.swift');

  test('AC-025-1 a podspec-only plugin gets a draft the build then uses', () {
    final foo = plugin('foo');
    expect(draft([foo]), isEmpty);

    expect(File(draftPath('foo')).existsSync(), isTrue);
    expect(log.messages.join('\n'), contains('[build.plugin_drafted]'));
    final applied = PluginOverrides(
      locator: locator(),
      warnings: warnings(),
    ).apply([foo], stagingRoot: p.join(tmp.path, 'staged')).single;
    expect(applied.usesSwiftPackageManager, isTrue);
  });

  test('AC-025-2 a pod with no known Swift package is said, not drafted', () {
    final foo = plugin('foo', pods: "  s.dependency 'SomeVendorSDK'\n");
    expect(draft([foo]), {'foo'});

    expect(File(draftPath('foo')).existsSync(), isFalse);
    final text = log.messages.join('\n');
    expect(text, contains('[build.plugin_unknown_pods]'));
    expect(text, contains('SomeVendorSDK'));
    expect(text, isNot(contains('[build.plugin_drafted]')));
  });

  test('AC-025-3 a plugin with its own package is left alone', () {
    expect(draft([plugin('foo', swiftPackage: true)]), isEmpty);
    expect(
      Directory(p.join(project, 'xcross_overrides')).existsSync(),
      isFalse,
    );
    expect(log.messages, isEmpty);
  });

  test('AC-025-3 a plugin with neither is left alone', () {
    expect(draft([plugin('foo', podspec: false)]), isEmpty);
    expect(
      Directory(p.join(project, 'xcross_overrides')).existsSync(),
      isFalse,
    );
  });

  test("AC-025-3 the developer's own folder is never replaced", () {
    final own = p.join(project, 'xcross_overrides', 'foo', 'Package.swift');
    write(own, '// mine');
    expect(draft([plugin('foo')]), isEmpty);

    expect(File(own).readAsStringSync(), '// mine');
    expect(File(draftPath('foo')).existsSync(), isFalse);
    expect(log.messages.join('\n'), isNot(contains('plugin_drafted')));
  });

  test('AC-025-3 XCROSS_PLUGIN_DRAFTS=off leaves them out as before', () {
    expect(
      draft([plugin('foo')], env: {PluginAutoDraft.switchName: 'off'}),
      isEmpty,
    );
    expect(File(draftPath('foo')).existsSync(), isFalse);
  });
}
