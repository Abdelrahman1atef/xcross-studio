// studio: 006 — `xcross plugin list` and `xcross plugin shim <plugin>`.
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
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
    return [
      for (final entity in dir.listSync(recursive: true, followLinks: false))
        if (fileSystem.file(entity.path).existsSync())
          paths
              .relative(entity.path, from: plugin.platformDirectory)
              .replaceAll(r'\', '/'),
    ]..sort();
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
        help: 'Overwrite an existing Package.swift draft.',
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
      final spec = Podspec.parse(
        fs.file(plugins.podspecPath(target)).readAsStringSync(),
      );
      final draft = draftPackageSwift(
        plugin: name,
        spec: spec,
        files: plugins.platformFiles(target),
        pluginVersion: target.version,
      );
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
      final version = target.version;
      final folder = version == null
          ? paths.join(base, name)
          : paths.join(base, name, version);
      final out = fs.file(paths.join(folder, 'Package.swift'));
      if (out.existsSync() && !args.flag('force')) {
        throw PluginFailure(
          'plugin.override_exists',
          '${out.path} already exists.',
          'Edit it, or pass --force to replace it with a new draft.',
        );
      }
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(draft.text);
      final message = StringBuffer()
        ..writeln('✔ Wrote ${out.path}')
        ..writeln(
          plugins.hasSwiftPackage(target)
              ? '  (overrides the Package.swift $name ships)'
              : '  ($name ships only a podspec)',
        );
      if (draft.notes.isNotEmpty) {
        message.writeln('Review before building:');
        for (final note in draft.notes) {
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
