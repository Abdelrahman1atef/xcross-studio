// studio: 006 — xcross_overrides/ Package.swift overrides for plugins.
import 'dart:io';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:darwin_sdk_kit/target/iphone/iphone_build_platform.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/diagnostics/build_warnings.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';
import 'package:xcross/src/shared/flutter/build/plugin_overrides.dart';
import 'package:xcross/src/shared/flutter/project/ios_deployment_target_resolver.dart';

import '../../log_fixture.dart';

void main() {
  late Directory tmp;
  late String project;
  late String home;
  late String pubCache;
  late TestLogOutput log;
  const fs = OverrideTestFileSystem();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('xcross_overrides_');
    project = p.join(tmp.path, 'app');
    home = p.join(tmp.path, 'home');
    pubCache = p.join(tmp.path, 'pub-cache');
    for (final dir in [project, home, pubCache]) {
      Directory(dir).createSync(recursive: true);
    }
    log = TestLogOutput();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  /// A pub package `name` at `version`; `spm` adds its own Package.swift.
  IosPlugin plugin(String name, {String? version = '1.2.3', bool spm = false}) {
    final root = p.join(pubCache, name);
    write(p.join(root, 'pubspec.yaml'), '''
name: $name
${version == null ? '' : 'version: $version'}
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: ${name}Plugin
''');
    write(p.join(root, 'ios', '$name.podspec'), 'Pod::Spec.new');
    write(p.join(root, 'ios', 'Classes', '${name}Plugin.m'), '// objc');
    write(p.join(root, 'ios', 'Classes', 'include', '$name.h'), '// h');
    if (spm) {
      write(p.join(root, 'ios', name, 'Package.swift'), '// shipped');
      write(p.join(root, 'ios', name, 'Sources', name, 'a.swift'), '// a');
    }
    return IosPlugin(name: name, fileSystem: fs, packageRoot: root);
  }

  String overrideDir(List<String> parts, {String manifest = '// override'}) {
    final dir = p.joinAll(parts);
    write(p.join(dir, 'Package.swift'), manifest);
    return dir;
  }

  PluginOverrideLocator locator() => PluginOverrideLocator(
    fileSystem: fs,
    paths: p.context,
    projectRoot: project,
    environment: {'HOME': home},
  );

  PluginOverrides overrides() => PluginOverrides(
    locator: locator(),
    warnings: BuildWarnings(Log(output: log)),
  );

  String projectRoot(String name) =>
      p.join(project, PluginOverrideLocator.projectFolder, name);
  String userRoot(String name) => p.join(home, '.xcross', 'overrides', name);

  group('AC-006-1 lookup order', () {
    test('project version folder, project folder, user version, user', () {
      final userAny = overrideDir([userRoot('foo')]);
      expect(locator().find('foo', '1.2.3').override?.directory, userAny);
      final userExact = overrideDir([userRoot('foo'), '1.2.3']);
      expect(locator().find('foo', '1.2.3').override?.directory, userExact);
      final projectAny = overrideDir([projectRoot('foo')]);
      final found = locator().find('foo', '1.2.3').override!;
      expect(found.directory, projectAny);
      expect(found.scope, PluginOverrideScope.project);
      expect(found.versionSpecific, isFalse);
      final projectExact = overrideDir([projectRoot('foo'), '1.2.3']);
      expect(locator().find('foo', '1.2.3').override?.directory, projectExact);
      expect(locator().find('foo', '1.2.3').override!.versionSpecific, isTrue);
      expect(locator().find('bar', '1.0.0').override, isNull);
    });

    test('without HOME only the project folder is searched', () {
      overrideDir([userRoot('foo')]);
      final noHome = PluginOverrideLocator(
        fileSystem: fs,
        paths: p.context,
        projectRoot: project,
      );
      expect(noHome.roots, hasLength(1));
      expect(noHome.find('foo', '1.2.3').override, isNull);
    });
  });

  group('AC-006-2 versions', () {
    test('override.yaml versions: constraint', () {
      final dir = overrideDir([projectRoot('foo')]);
      write(p.join(dir, 'override.yaml'), 'versions: ">=1.2.0 <2.0.0"\n');
      expect(locator().find('foo', '1.2.3').override?.directory, dir);
      final miss = locator().find('foo', '2.1.0');
      expect(miss.override, isNull);
      expect(miss.problems.single.versionMismatch, isTrue);
      expect(miss.problems.single.reason, contains('2.1.0'));
      expect(locator().find('foo', null).override, isNull);
    });

    test('a mismatching project override falls through to the user one', () {
      overrideDir([projectRoot('foo'), '1.0.0']);
      final user = overrideDir([userRoot('foo')]);
      final lookup = locator().find('foo', '1.2.3');
      expect(lookup.override?.directory, user);
      expect(lookup.problems.single.reason, contains('1.0.0'));
    });

    test('constraint syntax', () {
      bool allows(String constraint, String version) =>
          OverrideVersionConstraint.tryParse(
            constraint,
          )!.allows(OverrideVersion.tryParse(version)!);
      expect(allows('any', '0.0.1'), isTrue);
      expect(allows('1.2.3', '1.2.3'), isTrue);
      expect(allows('1.2.3', '1.2.4'), isFalse);
      expect(allows('^1.2.3', '1.9.0'), isTrue);
      expect(allows('^1.2.3', '2.0.0'), isFalse);
      expect(allows('^0.2.3', '0.2.9'), isTrue);
      expect(allows('^0.2.3', '0.3.0'), isFalse);
      expect(allows('>1.0.0 <=1.5.0', '1.5.0'), isTrue);
      expect(allows('>=1.0.0', '1.0.0-dev.1'), isFalse);
      expect(allows('<1.0.0', '1.0.0-dev.1'), isTrue);
      expect(allows('>=1.0.0', '1.0.0+5'), isTrue);
      expect(OverrideVersionConstraint.tryParse('banana'), isNull);
      expect(OverrideVersionConstraint.tryParse('>=1.x'), isNull);
    });
  });

  group('AC-006-3 podspec-only plugin + override', () {
    test(
      'staging keeps every file with Windows long-path names',
      testOn: 'windows',
      () {
        const longFs = OverrideTestFileSystem(longPaths: true);
        plugin('foo');
        final source = IosPlugin(
          name: 'foo',
          fileSystem: longFs,
          packageRoot: p.join(pubCache, 'foo'),
        );
        overrideDir([projectRoot('foo')], manifest: '// mine');
        final staging = p.join(tmp.path, 'staging');

        final staged = PluginOverrides(
          locator: PluginOverrideLocator(
            fileSystem: longFs,
            paths: p.context,
            projectRoot: project,
            environment: {'HOME': home},
          ),
          warnings: BuildWarnings(Log(output: log)),
        ).apply([source], stagingRoot: staging).single;

        final package = p.join(staging, 'foo', 'ios', 'foo');
        expect(staged.usesSwiftPackageManager, isTrue);
        expect(File(p.join(package, 'Package.swift')).existsSync(), isTrue);
        expect(
          File(p.join(package, 'Classes', 'fooPlugin.m')).existsSync(),
          isTrue,
          reason: 'nested files were copied onto themselves before',
        );
        expect(
          File(p.join(staging, 'foo', 'pubspec.yaml')).existsSync(),
          isTrue,
          reason: 'top-level files were deleted as strays before',
        );
      },
    );

    test('a staged copy without its Package.swift warns and keeps the '
        'original plugin (never dropped silently)', () {
      final source = plugin('foo');
      overrideDir([projectRoot('foo')]);
      final staging = p.join(tmp.path, 'staging');
      final lossy = OverrideTestFileSystem(lostRoot: staging);

      final result = PluginOverrides(
        locator: PluginOverrideLocator(
          fileSystem: lossy,
          paths: p.context,
          projectRoot: project,
          environment: {'HOME': home},
        ),
        warnings: BuildWarnings(Log(output: log)),
      ).apply([source], stagingRoot: staging).single;

      expect(result.packageRoot, source.packageRoot);
      final messages = log.messages.join('\n');
      expect(messages, contains('[build.plugin_override_invalid]'));
      expect(messages, contains('did not produce'));
      expect(messages, isNot(contains('[build.plugin_override_applied]')));
    });

    test('is staged as a Swift package; the pub cache is untouched', () {
      final source = plugin('foo');
      expect(source.usesSwiftPackageManager, isFalse);
      final dir = overrideDir([projectRoot('foo')], manifest: '// mine');
      write(p.join(dir, 'Sources', 'shim', 'module.modulemap'), 'module X {}');
      write(p.join(dir, 'override.yaml'), 'versions: any\n');
      final staging = p.join(tmp.path, 'staging');

      final staged = overrides().apply([source], stagingRoot: staging).single;

      expect(staged.packageRoot, p.join(staging, 'foo'));
      expect(staged.usesSwiftPackageManager, isTrue);
      expect(staged.pluginClassIos, 'fooPlugin');
      final package = staged.swiftPackageDir;
      expect(
        File(p.join(package, 'Package.swift')).readAsStringSync(),
        '// mine',
      );
      expect(
        File(p.join(package, 'Classes', 'fooPlugin.m')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(package, 'Classes', 'include', 'foo.h')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(package, 'Sources', 'shim', 'module.modulemap'),
        ).existsSync(),
        isTrue,
      );
      expect(File(p.join(package, 'foo.podspec')).existsSync(), isFalse);
      expect(File(p.join(package, 'override.yaml')).existsSync(), isFalse);
      expect(
        Directory(source.swiftPackageDir).existsSync(),
        isFalse,
        reason: 'nothing written into the plugin package',
      );
      expect(
        log.messages.join('\n'),
        contains('[build.plugin_override_applied]'),
      );
    });

    test('AC-006-9 a plugin with ios/<name>/Sources but no Package.swift is '
        'staged from ios/, matching shim paths', () {
      // google_maps_flutter_ios 2.18: sources under ios/<name>/Sources/<name>
      // and only a podspec.
      final source = plugin('foo');
      write(
        p.join(source.packageRoot, 'ios', 'foo', 'Sources', 'foo', 'a.m'),
        '// a',
      );
      expect(source.usesSwiftPackageManager, isFalse);
      overrideDir([projectRoot('foo')]);
      final staging = p.join(tmp.path, 'staging');

      final staged = overrides().apply([source], stagingRoot: staging).single;

      expect(
        File(
          p.join(staged.swiftPackageDir, 'foo', 'Sources', 'foo', 'a.m'),
        ).existsSync(),
        isTrue,
        reason: 'a draft path "foo/Sources/foo" resolves in the staged copy',
      );
      expect(
        File(
          p.join(staged.swiftPackageDir, 'Classes', 'fooPlugin.m'),
        ).existsSync(),
        isTrue,
      );
    });

    test('re-staging keeps unchanged files and drops removed ones', () {
      final source = plugin('foo');
      final dir = overrideDir([projectRoot('foo')]);
      final extra = p.join(dir, 'Sources', 'shim', 'shim.c');
      write(extra, '// shim');
      final staging = p.join(tmp.path, 'staging');
      final staged = overrides().apply([source], stagingRoot: staging).single;
      final objc = File(
        p.join(staged.swiftPackageDir, 'Classes', 'fooPlugin.m'),
      );
      final stamp = DateTime(2020);
      objc.setLastModifiedSync(stamp);
      File(extra).deleteSync();

      overrides().apply([source], stagingRoot: staging);

      expect(objc.lastModifiedSync(), stamp, reason: 'unchanged file kept');
      expect(
        Directory(p.join(staged.swiftPackageDir, 'Sources')).existsSync(),
        isFalse,
        reason: 'removed file and its empty folders are gone',
      );
    });
  });

  test('AC-006-4 the override wins over a shipped Package.swift', () {
    final source = plugin('foo', spm: true);
    overrideDir([projectRoot('foo'), '1.2.3'], manifest: '// fixed');
    final staged = overrides().apply([
      source,
    ], stagingRoot: p.join(tmp.path, 'staging')).single;
    final package = staged.swiftPackageDir;
    expect(
      File(p.join(package, 'Package.swift')).readAsStringSync(),
      '// fixed',
    );
    expect(
      File(p.join(package, 'Sources', 'foo', 'a.swift')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(package, 'Classes', 'fooPlugin.m')).existsSync(),
      isFalse,
      reason: 'a shipped package keeps its own layout',
    );
    expect(File(source.swiftPackageManifest).readAsStringSync(), '// shipped');
    expect(log.messages.join('\n'), contains('instead of its own'));
  });

  test(
    'AC-006-5 an invalid override warns and leaves the plugin as it was',
    () {
      final source = plugin('foo');
      Directory(
        p.join(projectRoot('foo'), 'Sources'),
      ).createSync(recursive: true);
      final bad = overrideDir([userRoot('foo')]);
      write(p.join(bad, 'override.yaml'), 'versions: banana\n');

      final result = overrides().apply([
        source,
      ], stagingRoot: p.join(tmp.path, 'staging')).single;

      expect(result, same(source));
      expect(result.usesSwiftPackageManager, isFalse);
      final text = log.messages.join('\n');
      expect('[build.plugin_override_invalid]'.allMatches(text), hasLength(2));
      expect(text, contains('has no Package.swift'));
      expect(text, contains('is not a version constraint'));
      expect(text, isNot(contains('[build.plugin_override_applied]')));
    },
  );

  test('AC-006-6 the override Package.swift sets the deployment floor', () {
    write(
      p.join(project, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
      'IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n',
    );
    final source = plugin('foo');
    write(
      p.join(project, '.flutter-plugins-dependencies'),
      '{"plugins":{"ios":[{"name":"foo","path":"${p.toUri(source.packageRoot).toFilePath().replaceAll(r'\', r'\\')}"}]}}',
    );
    overrideDir(
      [projectRoot('foo')],
      manifest: 'let package = Package(name: "foo", platforms: [.iOS("15.0")])',
    );
    final resolver = IosDeploymentTargetResolver(
      fs,
      p.context,
      environment: {'HOME': home},
    );
    expect(
      resolver.resolve(project, platform: const IPhoneBuildPlatform()).version,
      '15.0',
    );
  });
}

/// dart:io-backed host file system for this test.
@internal
final class OverrideTestFileSystem implements HostFileSystemInterface {
  const OverrideTestFileSystem({this.longPaths = false, this.lostRoot});

  /// Hand out `\\?\C:\…` paths like the host file system on Windows.
  final bool longPaths;

  /// Writes under this folder land elsewhere (a staging that loses files).
  final String? lostRoot;

  String _path(String path) {
    final lost = lostRoot;
    if (lost != null && p.isWithin(lost, path)) {
      return p.join('${lost}_void', p.relative(path, from: lost));
    }
    if (longPaths && p.isAbsolute(path) && !path.startsWith(r'\\?\')) {
      return '\\\\?\\$path';
    }
    return path;
  }

  @override
  File file(String path) => File(_path(path));
  @override
  Directory directory(String path) => Directory(_path(path));
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
