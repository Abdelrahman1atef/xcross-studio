// studio: 006 — `xcross plugin list` and `xcross plugin shim <plugin>`.
// studio: 025 — `xcross plugin check`; builds write drafts too.
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/plugins/draft_ledger.dart'; // studio: 028
import 'package:studio_ext/shared/plugins/permission_macros.dart'; // studio: 027
import 'package:studio_ext/shared/plugins/plugin_status.dart'; // studio: 028
import 'package:studio_ext/src/shared/plugins/package_swift_draft.dart';
import 'package:studio_ext/src/shared/plugins/podspec.dart';

/// `xcross plugin`: the project's iOS plugins and Package.swift overrides.
final class PluginCommand extends Command<void> {
  PluginCommand({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required void Function(String) write,
    String? home,
  }) {
    final plugins = ProjectPlugins(fileSystem, paths);
    addSubcommand(PluginListCommand(plugins: plugins, write: write));
    addSubcommand(PluginCheckCommand(plugins: plugins, write: write));
    // studio: 028
    addSubcommand(PluginStatusCommand(plugins: plugins, write: write));
    addSubcommand(PluginAckCommand(plugins: plugins, write: write));
    addSubcommand(
      PluginShimCommand(plugins: plugins, write: write, home: home),
    );
  }

  @override
  String get name => 'plugin';

  @override
  String get description =>
      "List the project's iOS plugins and draft Package.swift overrides.";
}

/// A stable plugin-command error.
final class PluginFailure implements Exception {
  const PluginFailure(this.code, this.message, this.hint);

  final String code;
  final String message;
  final String hint;

  CliError toCliError() => CliError('[$code] $message\nhint: $hint');
}

/// One iOS plugin of a Flutter project.
final class ProjectPlugin {
  const ProjectPlugin({
    required this.name,
    required this.root,
    required this.platformDirectory,
    this.version,
  });

  final String name;

  /// The plugin's pub package root.
  final String root;

  /// `<root>/ios` or `<root>/darwin` (shared darwin source).
  final String platformDirectory;
  final String? version;
}

/// Reads a project's iOS plugins from `.flutter-plugins-dependencies`.
final class ProjectPlugins {
  ProjectPlugins(this.fileSystem, this.paths);

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  List<ProjectPlugin> read(String projectRoot) {
    final file = fileSystem.file(
      paths.join(projectRoot, '.flutter-plugins-dependencies'),
    );
    if (!file.existsSync()) {
      throw const PluginFailure(
        'plugin.no_project',
        'No .flutter-plugins-dependencies here.',
        'Run this in a Flutter project after "flutter pub get" (or pass '
            '--project <dir>).',
      );
    }
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException {
      throw const PluginFailure(
        'plugin.no_project',
        '.flutter-plugins-dependencies is not valid JSON.',
        'Run "flutter pub get" again.',
      );
    }
    if (json case {'plugins': {'ios': final List<Object?> entries}}) {
      return [
        for (final entry in entries)
          if (entry case {'name': final String name, 'path': final String path})
            _plugin(
              name,
              paths.isAbsolute(path) ? path : paths.join(projectRoot, path),
              shared: entry['shared_darwin_source'] == true,
            ),
      ]..sort((a, b) => a.name.compareTo(b.name));
    }
    return const [];
  }

  ProjectPlugin _plugin(String name, String root, {required bool shared}) {
    String? version;
    final pubspec = fileSystem.file(paths.join(root, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      version = RegExp(
        r'''^version:\s*["']?([^"'\s#]+)''',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync())?.group(1);
    }
    return ProjectPlugin(
      name: name,
      root: root,
      platformDirectory: paths.join(root, shared ? 'darwin' : 'ios'),
      version: version,
    );
  }

  bool hasSwiftPackage(ProjectPlugin plugin) => fileSystem
      .file(paths.join(plugin.platformDirectory, plugin.name, 'Package.swift'))
      .existsSync();

  String podspecPath(ProjectPlugin plugin) =>
      paths.join(plugin.platformDirectory, '${plugin.name}.podspec');

  bool hasPodspec(ProjectPlugin plugin) =>
      fileSystem.file(podspecPath(plugin)).existsSync();

  /// Files under the plugin's platform folder, relative, `/`-separated.
  List<String> platformFiles(ProjectPlugin plugin) {
    final dir = fileSystem.directory(plugin.platformDirectory);
    if (!dir.existsSync()) return const [];
    // Relative to the listing's own root: on Windows the host file system
    // hands back long-path names (\\?\C:\…) that `paths.relative` against
    // the plain C:\… folder cannot relate, which dropped every file (found
    // drafting pusher_channels_flutter, 2026-11-02).
    final root = dir.path.replaceAll(RegExp(r'[\\/]+$'), '');
    return [
      for (final entity in dir.listSync(recursive: true, followLinks: false))
        if (fileSystem.file(entity.path).existsSync())
          (entity.path.startsWith(root)
                  ? entity.path.substring(root.length)
                  : paths.relative(entity.path, from: plugin.platformDirectory))
              .replaceAll(r'\', '/')
              .replaceFirst(RegExp('^/+'), ''),
    ]..sort();
  }
}

/// What drafting a plugin wrote.
final class WrittenDraft {
  const WrittenDraft(this.path, this.patched, this.notes);

  /// The `Package.swift`.
  final String path;

  /// Patched copies of the plugin's files: relative path to why.
  final Map<String, String> patched;

  /// What to review.
  final List<String> notes;
}

/// Writes `<base>/<plugin>/<version>/Package.swift` from a plugin's podspec,
/// with patched copies of the sources that need them.
final class PluginDraftWriter {
  PluginDraftWriter(this.plugins);

  final ProjectPlugins plugins;

  Podspec _spec(ProjectPlugin target) => Podspec.parse(
    plugins.fileSystem.file(plugins.podspecPath(target)).readAsStringSync(),
  );

  /// The pods of [target] with no known Swift package, which a draft cannot
  /// link.
  List<String> unknownPods(ProjectPlugin target) => [
    for (final dependency in _spec(target).dependencies)
      if (dependency.name != 'Flutter' &&
          knownPackageFor(dependency.name) == null)
        dependency.name,
  ];

  /// The project folder an override [base] (`<project>/xcross_overrides`)
  /// belongs to; null for the shared `~/.xcross/overrides`.
  String? projectRootOf(String base) {
    final paths = plugins.paths;
    return paths.basename(base) == 'xcross_overrides'
        ? paths.dirname(base)
        : null;
  }

  /// The `PERMISSION_*` switches a draft of [target] needs, from the project's
  /// Info.plist and Podfile (studio: 027); none for other plugins.
  Map<String, String> macrosFor(ProjectPlugin target, String? project) {
    if (target.name != PermissionMacros.plugin || project == null) {
      return const {};
    }
    final fs = plugins.fileSystem;
    String? read(List<String> parts) {
      final file = fs.file(plugins.paths.joinAll([project, ...parts]));
      return file.existsSync() ? file.readAsStringSync() : null;
    }

    return PermissionMacros.environment(
      infoPlist: read(['ios', 'Runner', 'Info.plist']),
      podfile: read(['ios', 'Podfile']),
    );
  }

  /// Reads [target]'s files by their path relative to the podspec folder, for
  /// a draft to see what the sources use; null for a file that is not there.
  String? Function(String path) readerFor(ProjectPlugin target) {
    final fs = plugins.fileSystem;
    final paths = plugins.paths;
    return (relative) {
      final file = fs.file(
        paths.joinAll([target.platformDirectory, ...relative.split('/')]),
      );
      return file.existsSync() ? file.readAsStringSync() : null;
    };
  }

  /// Where the draft of [target] goes under [base].
  String packagePath(ProjectPlugin target, String base) {
    final paths = plugins.paths;
    final version = target.version;
    return version == null
        ? paths.join(base, target.name, 'Package.swift')
        : paths.join(base, target.name, version, 'Package.swift');
  }

  /// Writes the draft of [target] under [base], replacing one already there.
  WrittenDraft write(ProjectPlugin target, {required String base}) {
    final fs = plugins.fileSystem;
    final paths = plugins.paths;
    final name = target.name;
    final draft = draftPackageSwift(
      plugin: name,
      spec: _spec(target),
      files: plugins.platformFiles(target),
      pluginVersion: target.version,
      defines: macrosFor(target, projectRootOf(base)),
      read: readerFor(target),
    );
    // The logical path, for messages: the host file's path carries the
    // Windows long-path prefix ("✔ Wrote \\?\D:\…").
    final shown = packagePath(target, base);
    final folder = paths.dirname(shown);
    final out = fs.file(shown);
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(draft.text);
    // Write patched copies of Objective-C files into the override folder
    // (laid over the plugin's sources at build time): mixed plugins import
    // the split Swift target, and pods whose Objective-C module has another
    // name in its Swift package import that name.
    final patched = <String, String>{};
    for (final relative in draft.objcSources) {
      final source = fs.file(
        paths.joinAll([target.platformDirectory, ...relative.split('/')]),
      );
      if (!source.existsSync()) continue;
      final original = source.readAsStringSync();
      var text = original;
      final reasons = <String>[];
      // Not plain C or C++: UIKit is Objective-C, and CocoaPods' prefix
      // header only imports it for Objective-C.
      final extension = paths.extension(relative);
      if (const {'.m', '.mm', '.h'}.contains(extension)) {
        final implicit = patchImplicitObjcImports(
          text,
          header: extension == '.h',
        );
        if (implicit != null) {
          reasons.add(
            implicit.contains('<UIKit/UIKit.h>')
                ? 'import UIKit'
                : 'import Foundation',
          );
          text = implicit;
        }
      }
      if (draft.splitsSwift) {
        final swift = patchSwiftHeaderImports(text, name);
        if (swift != null) {
          text = swift;
          reasons.add('@import ${name}_swift;');
        }
      }
      if (extension == '.h') {
        final located = patchHeaderPaths(
          text,
          file: relative,
          headers: [
            for (final other in draft.objcSources)
              if (other.endsWith('.h')) other,
          ],
        );
        if (located != null) {
          reasons.add('header paths');
          text = located;
        }
      }
      final flat = patchFlatHeaderImports(text, draft.flatHeaderModules);
      if (flat != null) {
        reasons.add(
          [
            for (final module in draft.flatHeaderModules)
              if (flat.contains('@import $module;')) '@import $module;',
          ].join(', '),
        );
        text = flat;
      }
      final renamed = patchModuleImports(text, draft.moduleRenames);
      if (renamed != null) {
        text = renamed;
        reasons.add(
          [
            for (final MapEntry(key: from, value: to)
                in draft.moduleRenames.entries)
              if (original.contains(from)) '@import $to; for $from',
          ].join(', '),
        );
      }
      if (text == original) continue;
      final copy = fs.file(paths.joinAll([folder, ...relative.split('/')]));
      copy.parent.createSync(recursive: true);
      copy.writeAsStringSync(text);
      patched[relative] = reasons.join('; ');
    }
    // Swift files get the imports a pod's umbrella header gave them.
    for (final relative in draft.swiftSources) {
      final source = fs.file(
        paths.joinAll([target.platformDirectory, ...relative.split('/')]),
      );
      if (!source.existsSync()) continue;
      final original = source.readAsStringSync();
      final text = patchImplicitImports(original);
      if (text == null) continue;
      final copy = fs.file(paths.joinAll([folder, ...relative.split('/')]));
      copy.parent.createSync(recursive: true);
      copy.writeAsStringSync(text);
      patched[relative] = [
        for (final module in implicitImports(original)) 'import $module',
      ].join(', ');
    }
    for (final MapEntry(key: from, value: to) in draft.resourceCopies.entries) {
      final source = fs.file(
        paths.joinAll([target.platformDirectory, ...from.split('/')]),
      );
      final copy = fs.file(paths.joinAll([folder, ...to.split('/')]));
      copy.parent.createSync(recursive: true);
      copy.writeAsBytesSync(source.readAsBytesSync());
      patched[to] = 'copied from $from';
    }
    for (final MapEntry(key: relative, value: text)
        in draft.generatedFiles.entries) {
      final file = fs.file(paths.joinAll([folder, ...relative.split('/')]));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
      patched[relative] =
          'written by xcross: the headers the Swift target uses';
    }
    // studio: 028 — xcross wrote this one; the developer has yet to look.
    DraftLedger(fs, paths, base).record(name, target.version);
    return WrittenDraft(shown, patched, draft.notes);
  }
}

/// `xcross plugin check`: what a build will do with each plugin, in seconds.
final class PluginCheckCommand extends Command<void> {
  PluginCheckCommand({required this.plugins, required this.write}) {
    argParser.addOption(
      'project',
      defaultsTo: '.',
      help: 'Flutter project folder.',
    );
  }

  final ProjectPlugins plugins;
  final void Function(String) write;

  @override
  String get name => 'check';

  @override
  String get description =>
      'Say what a build will do with each iOS plugin, without compiling.';

  @override
  String get invocation => 'xcross plugin check [--project <dir>]';

  @override
  Future<void> run() async {
    final project = argResults!.option('project')!;
    final writer = PluginDraftWriter(plugins);
    try {
      final out = StringBuffer();
      final problems = <String>[];
      final all = plugins.read(project);
      final staleNames = {
        for (final status in readPluginStatus(plugins, project))
          if (status.problems.any((p) => p.code == 'stale')) status.name,
      };
      final staleProblems = <String>[];
      for (final plugin in all) {
        final label = '${plugin.name} ${plugin.version ?? ''}'.trimRight();
        final overridden = plugins.fileSystem
            .directory(
              plugins.paths.join(project, 'xcross_overrides', plugin.name),
            )
            .existsSync();
        // studio: 028 — a folder for another version is skipped by the build.
        final stale = overridden && staleNames.contains(plugin.name);
        if (stale) {
          problems.add(plugin.name);
          staleProblems.add(plugin.name);
          out.writeln(
            '✖ $label  (override does not apply: xcross_overrides/'
            '${plugin.name} is for another version)',
          );
        } else if (overridden) {
          out.writeln('✔ $label  (override)');
        } else if (plugins.hasSwiftPackage(plugin)) {
          out.writeln('✔ $label  (swiftpm)');
        } else if (!plugins.hasPodspec(plugin)) {
          out.writeln('✔ $label  (no iOS code)');
        } else {
          final unknown = writer.unknownPods(plugin);
          if (unknown.isEmpty) {
            out.writeln('✔ $label  (podspec only: the next build drafts it)');
          } else {
            problems.add(plugin.name);
            out.writeln(
              '✖ $label  (podspec only, no Swift package for: '
              '${unknown.join(', ')})',
            );
          }
        }
      }
      if (all.isEmpty) out.writeln('No iOS plugins.');
      write(out.toString());
      if (staleProblems.isNotEmpty) {
        throw PluginFailure(
          'plugin.override_stale',
          'A build skips the override of ${staleProblems.join(', ')}: it is '
              'for another version of the plugin.',
          'Run xcross plugin status; a draft is rewritten with '
              'xcross plugin shim <plugin> --force.',
        );
      }
      if (problems.isNotEmpty) {
        throw PluginFailure(
          'plugin.unknown_pods',
          'A build will leave out the native code of ${problems.join(', ')}.',
          'Run xcross plugin shim <plugin> and add a Swift package for each '
              'pod to the draft, or use a plugin version that ships '
              'Package.swift.',
        );
      }
    } on PluginFailure catch (failure) {
      throw failure.toCliError();
    }
  }
}

/// `xcross plugin list`: each iOS plugin and how xcross builds it.
final class PluginListCommand extends Command<void> {
  PluginListCommand({required this.plugins, required this.write}) {
    argParser.addOption(
      'project',
      defaultsTo: '.',
      help: 'Flutter project folder.',
    );
  }

  final ProjectPlugins plugins;
  final void Function(String) write;

  @override
  String get name => 'list';

  @override
  String get description =>
      'List the iOS plugins: Swift package, podspec only, or overridden.';

  @override
  Future<void> run() async {
    final project = argResults!.option('project')!;
    try {
      final all = plugins.read(project);
      final out = StringBuffer();
      for (final plugin in all) {
        final override = plugins.fileSystem
            .directory(
              plugins.paths.join(project, 'xcross_overrides', plugin.name),
            )
            .existsSync();
        final kind = override
            ? 'override'
            : plugins.hasSwiftPackage(plugin)
            ? 'swiftpm'
            : plugins.hasPodspec(plugin)
            ? 'podspec only'
            : 'no iOS code';
        final mark = kind == 'podspec only' ? '✖' : '✔';
        final label = '${plugin.name} ${plugin.version ?? ''}'.trimRight();
        out.writeln('$mark $label  ($kind)');
      }
      if (all.isEmpty) out.writeln('No iOS plugins.');
      if (all.any(
        (p) => !plugins.hasSwiftPackage(p) && plugins.hasPodspec(p),
      )) {
        out.writeln(
          'Draft an override for a podspec-only plugin: '
          'xcross plugin shim <plugin>',
        );
      }
      write(out.toString());
    } on PluginFailure catch (failure) {
      throw failure.toCliError();
    }
  }
}

/// `xcross plugin shim <plugin>`: drafts
/// `xcross_overrides/<plugin>/<version>/Package.swift` from the podspec.
final class PluginShimCommand extends Command<void> {
  PluginShimCommand({required this.plugins, required this.write, this.home}) {
    argParser
      ..addOption('project', defaultsTo: '.', help: 'Flutter project folder.')
      ..addFlag(
        'global',
        negatable: false,
        help: 'Write to ~/.xcross/overrides (all projects) instead.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite an existing Package.swift draft (after a backup).',
      )
      ..addFlag(
        'replace-hand-written',
        negatable: false,
        help:
            'With --force: also replace a Package.swift xcross did not '
            'write (after a backup).',
      );
  }

  final ProjectPlugins plugins;
  final void Function(String) write;
  final String? home;

  @override
  String get name => 'shim';

  @override
  String get description =>
      'Draft a Package.swift override for a plugin from its podspec.';

  @override
  String get invocation =>
      'xcross plugin shim <plugin> [--project <dir>] [--global] [--force]';

  @override
  Future<void> run() async {
    final args = argResults!;
    if (args.rest.length != 1) usageException('Pass exactly one plugin name.');
    final name = args.rest.single;
    final project = args.option('project')!;
    final fs = plugins.fileSystem;
    final paths = plugins.paths;
    try {
      final plugin = plugins.read(project).where((p) => p.name == name);
      if (plugin.isEmpty) {
        throw PluginFailure(
          'plugin.not_found',
          '$name is not an iOS plugin of this project.',
          'List them with: xcross plugin list',
        );
      }
      final target = plugin.single;
      if (!plugins.hasPodspec(target)) {
        throw PluginFailure(
          'plugin.no_podspec',
          '$name has no ${paths.basename(plugins.podspecPath(target))}.',
          'Write xcross_overrides/$name/Package.swift by hand (see the README '
              'section "Plugin overrides").',
        );
      }
      final String base;
      if (args.flag('global')) {
        if (home == null) {
          throw const PluginFailure(
            'plugin.no_home',
            'The home folder is unknown.',
            'Set HOME (USERPROFILE on Windows) or drop --global.',
          );
        }
        base = paths.join(home!, '.xcross', 'overrides');
      } else {
        base = paths.join(project, 'xcross_overrides');
      }
      final writer = PluginDraftWriter(plugins);
      final existing = writer.packagePath(target, base);
      if (fs.file(existing).existsSync() && !args.flag('force')) {
        throw PluginFailure(
          'plugin.override_exists',
          '$existing already exists.',
          'Edit it, or pass --force to replace it with a new draft.',
        );
      }
      // studio: 028 — never overwrite a file the developer wrote, and keep a
      // copy of a draft before it is replaced.
      String? backedUp;
      if (fs.file(existing).existsSync()) {
        if (!isDraftManifest(fs, existing) &&
            !args.flag('replace-hand-written')) {
          throw PluginFailure(
            'plugin.hand_written',
            '$existing was not written by xcross (it has no DRAFT header), so '
                'it is not replaced.',
            'Edit it by hand, or pass --replace-hand-written to replace it '
                'after a backup.',
          );
        }
        backedUp = _backUp(
          fs,
          paths,
          from: paths.dirname(existing),
          root: args.flag('global')
              ? paths.join(home!, '.xcross', 'plugin-backups')
              : paths.join(project, '.xcross', 'plugin-backups'),
          label: paths.relative(paths.dirname(existing), from: base),
        );
      }
      final written = writer.write(target, base: base);
      final message = StringBuffer()
        ..writeln('✔ Wrote ${written.path}')
        ..writeln(backedUp == null ? '' : '✔ Kept the old files in $backedUp')
        ..writeln(
          plugins.hasSwiftPackage(target)
              ? '  (overrides the Package.swift $name ships)'
              : '  ($name ships only a podspec)',
        );
      for (final MapEntry(key: relative, value: reason)
          in written.patched.entries) {
        message.writeln('✔ Patched $relative ($reason)');
      }
      if (written.notes.isNotEmpty) {
        message.writeln('Review before building:');
        for (final note in written.notes) {
          message.writeln('  • $note');
        }
      }
      message.writeln(
        'Then build: xcross flutter run --release (look for '
        '[build.plugin_override_applied]).',
      );
      write(message.toString());
    } on PluginFailure catch (failure) {
      throw failure.toCliError();
    }
  }
}

/// Copies every file under [from] to `<root>/<stamp>/<label>/`; returns that
/// folder.
String _backUp(
  HostFileSystemInterface fs,
  p.Context paths, {
  required String from,
  required String root,
  required String label,
}) {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final target = paths.join(root, stamp, label);
  final source = fs.directory(from);
  final prefix = source.path.replaceAll(RegExp(r'[\\/]+$'), '');
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final file = fs.file(entity.path);
    if (!file.existsSync()) continue;
    final relative = entity.path.startsWith(prefix)
        ? entity.path
              .substring(prefix.length)
              .replaceFirst(RegExp(r'^[\\/]+'), '')
        : paths.relative(entity.path, from: from);
    final copy = fs.file(paths.join(target, relative));
    copy.parent.createSync(recursive: true);
    copy.writeAsBytesSync(file.readAsBytesSync());
  }
  return target;
}
