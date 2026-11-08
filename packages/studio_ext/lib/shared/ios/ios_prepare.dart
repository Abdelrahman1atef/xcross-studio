// studio: 032 — `xcross ios prepare`: makes a fresh Flutter iOS project ready
// to build here, the way `pod install` does on a Mac, and says what a build
// would leave out. xcross builds plugins with SwiftPM, so nothing here runs
// CocoaPods; the step is about the project being complete and the plugins
// being buildable, found out in seconds instead of after a long build.
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/plugins/permission_macros.dart';
import 'package:studio_ext/shared/plugins/plugin_command.dart';
import 'package:studio_ext/shared/plugins/plugin_status.dart';

/// How one step ended.
enum PrepareState {
  ok('ok'),
  warning('warning'),
  failed('failed');

  const PrepareState(this.wire);

  final String wire;
}

/// One step of the preparation.
@immutable
final class PrepareStep {
  const PrepareStep(this.id, this.title, this.state, this.detail, {this.hint});

  /// `project`, `dependencies`, `plugins` or `settings`.
  final String id;
  final String title;
  final PrepareState state;
  final String detail;

  /// What to do about a failure.
  final String? hint;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'state': state.wire,
    'detail': detail,
    'hint': hint,
  };
}

/// What a build will do with one plugin.
@immutable
final class PreparedPlugin {
  const PreparedPlugin({
    required this.name,
    required this.state,
    required this.detail,
    this.version,
    this.kind,
  });

  final String name;
  final String? version;

  /// `swiftpm`, `draft`, `hand_written`, `podspec_only` or `no_ios_code`.
  final String? kind;

  /// `ready`, `drafted`, `left_out` or `attention`.
  final String state;
  final String detail;

  bool get leftOut => state == 'left_out';

  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    'kind': kind,
    'state': state,
    'detail': detail,
  };
}

/// The result of preparing a project.
@immutable
final class PrepareReport {
  const PrepareReport({
    required this.steps,
    this.plugins = const [],
    this.bundleId,
    this.deploymentTarget,
    this.permissionMacros = const {},
    this.strict = false,
  });

  final List<PrepareStep> steps;
  final List<PreparedPlugin> plugins;
  final String? bundleId;
  final String? deploymentTarget;

  /// The `PERMISSION_*` switches a build gives permission_handler_apple.
  final Map<String, String> permissionMacros;
  final bool strict;

  List<PreparedPlugin> get leftOut => [
    for (final plugin in plugins)
      if (plugin.leftOut) plugin,
  ];

  /// No blocker, and with [strict] no plugin left out either.
  bool get ready =>
      steps.every((step) => step.state != PrepareState.failed) &&
      (!strict || leftOut.isEmpty);

  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'ios_prepare',
    'ready': ready,
    'steps': [for (final step in steps) step.toJson()],
    'plugins': [for (final plugin in plugins) plugin.toJson()],
    'leftOut': [for (final plugin in leftOut) plugin.name],
    'bundleId': bundleId,
    'deploymentTarget': deploymentTarget,
    'permissionMacros': permissionMacros,
  };

  String render() {
    final out = StringBuffer();
    String mark(PrepareState state) => switch (state) {
      PrepareState.ok => '✔',
      PrepareState.warning => '!',
      PrepareState.failed => '✖',
    };
    for (final step in steps) {
      out.writeln('${mark(step.state)} ${step.title}: ${step.detail}');
      if (step.hint != null) out.writeln('    ${step.hint}');
    }
    for (final plugin in plugins) {
      final mark = switch (plugin.state) {
        'left_out' => '✖',
        'attention' => '!',
        _ => '✔',
      };
      final label = '${plugin.name} ${plugin.version ?? ''}'.trimRight();
      out.writeln('  $mark $label  (${plugin.detail})');
    }
    out.writeln(
      ready
          ? leftOut.isEmpty
                ? 'Ready: a build needs nothing more.'
                : 'Ready, but a build leaves out the native code of '
                      '${leftOut.map((plugin) => plugin.name).join(', ')}.'
          : 'Not ready.',
    );
    return out.toString();
  }
}

/// Runs `flutter pub get` in a project; true when it succeeded.
typedef PubGet = Future<bool> Function(String project);

/// Prepares a project. Only reads, except for `flutter pub get` and the
/// plugin drafts a build would write anyway (`xcross_overrides/`).
final class IosPrepare {
  IosPrepare({
    required this.fileSystem,
    required this.paths,
    this.pubGet,
    this.environment = const {},
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// `null` skips `flutter pub get`.
  final PubGet? pubGet;
  final Map<String, String> environment;

  static const metadataFile = '.flutter-plugins-dependencies';

  Future<PrepareReport> run(String project, {bool strict = false}) async {
    final steps = <PrepareStep>[];
    final ios = paths.join(project, 'ios');
    final hasProject =
        fileSystem
            .file(paths.join(ios, 'Runner.xcodeproj', 'project.pbxproj'))
            .existsSync() ||
        fileSystem.file(paths.join(ios, 'Runner', 'Info.plist')).existsSync();
    if (!hasProject) {
      steps.add(
        PrepareStep(
          'project',
          'iOS project',
          PrepareState.failed,
          fileSystem.directory(ios).existsSync()
              ? 'ios/ has no Runner project.'
              : 'This Flutter project has no ios/ folder.',
          hint: 'Run: flutter create --platforms=ios .',
        ),
      );
      return PrepareReport(steps: steps, strict: strict);
    }
    steps.add(
      const PrepareStep(
        'project',
        'iOS project',
        PrepareState.ok,
        'ios/ has a Runner project. No Podfile, Pods or workspace is needed: '
            'plugins are built with SwiftPM.',
      ),
    );

    steps.add(await _dependencies(project));
    if (steps.last.state == PrepareState.failed) {
      return PrepareReport(steps: steps, strict: strict);
    }

    final plugins = _plugins(project);
    if (plugins == null) {
      steps.add(
        const PrepareStep(
          'plugins',
          'Plugins',
          PrepareState.failed,
          '$metadataFile cannot be read.',
          hint: 'Run: flutter pub get',
        ),
      );
      return PrepareReport(steps: steps, strict: strict);
    }
    final gone = [
      for (final plugin in plugins)
        if (plugin.leftOut) plugin.name,
    ];
    final attention = [
      for (final plugin in plugins)
        if (plugin.state == 'attention') plugin.name,
    ];
    steps.add(
      PrepareStep(
        'plugins',
        'Plugins',
        gone.isEmpty && attention.isEmpty
            ? PrepareState.ok
            : PrepareState.warning,
        plugins.isEmpty
            ? 'No plugins with iOS code.'
            : '${plugins.length} plugin${plugins.length == 1 ? '' : 's'}'
                  '${gone.isEmpty ? '' : ', the native code of ${gone.join(', ')} is left out'}'
                  '${attention.isEmpty ? '' : ', look at ${attention.join(', ')}'}.',
        hint: gone.isEmpty
            ? null
            : 'Run xcross plugin shim <plugin> and add a Swift package for '
                  'each pod, or use a plugin version that ships Package.swift.',
      ),
    );

    final settings = _settings(project);
    steps.add(settings.step);
    return PrepareReport(
      steps: steps,
      plugins: plugins,
      bundleId: settings.bundleId,
      deploymentTarget: settings.deploymentTarget,
      permissionMacros: settings.macros,
      strict: strict,
    );
  }

  Future<PrepareStep> _dependencies(String project) async {
    final metadata = fileSystem.file(paths.join(project, metadataFile));
    var pubOk = true;
    if (pubGet != null) pubOk = await pubGet!(project);
    if (metadata.existsSync()) {
      return PrepareStep(
        'dependencies',
        'Dependencies',
        pubOk ? PrepareState.ok : PrepareState.warning,
        pubOk
            ? pubGet == null
                  ? 'Plugin list found ($metadataFile); flutter pub get skipped.'
                  : 'flutter pub get done.'
            : 'flutter pub get failed; the plugin list from the last run is '
                  'used.',
      );
    }
    return PrepareStep(
      'dependencies',
      'Dependencies',
      PrepareState.failed,
      pubGet == null
          ? '$metadataFile is missing, so no plugin would be built.'
          : 'flutter pub get did not produce $metadataFile.',
      hint: 'Run: flutter pub get, and fix what it reports.',
    );
  }

  /// Classifies every plugin, drafting a Package.swift for podspec-only ones
  /// (what a build does first). Null when the plugin list cannot be read.
  List<PreparedPlugin>? _plugins(String project) {
    final projectPlugins = ProjectPlugins(fileSystem, paths);
    final writer = PluginDraftWriter(projectPlugins);
    final List<ProjectPlugin> all;
    try {
      all = projectPlugins.read(project);
    } on PluginFailure {
      return null;
    }
    final drafts = environment['XCROSS_PLUGIN_DRAFTS'] != 'off';
    final status = {
      for (final entry in readPluginStatus(projectPlugins, project))
        entry.name: entry,
    };
    final result = <PreparedPlugin>[];
    for (final plugin in all) {
      final known = status[plugin.name];
      final overridden = fileSystem
          .directory(paths.join(project, 'xcross_overrides', plugin.name))
          .existsSync();
      PreparedPlugin make(String state, String detail, {String? kind}) =>
          PreparedPlugin(
            name: plugin.name,
            version: plugin.version,
            kind: kind,
            state: state,
            detail: detail,
          );
      if (overridden && known != null) {
        if (known.problems.isEmpty) {
          result.add(
            make(
              'ready',
              known.kind == PluginKind.draft ? 'draft override' : 'override',
              kind: known.kind.wire,
            ),
          );
        } else {
          result.add(
            make(
              'attention',
              known.problems.map((problem) => problem.message).join(' '),
              kind: known.kind.wire,
            ),
          );
        }
      } else if (projectPlugins.hasSwiftPackage(plugin)) {
        result.add(make('ready', 'swiftpm', kind: 'swiftpm'));
      } else if (!projectPlugins.hasPodspec(plugin)) {
        result.add(make('ready', 'no iOS code', kind: 'no_ios_code'));
      } else {
        try {
          final unknown = writer.unknownPods(plugin);
          if (unknown.isNotEmpty) {
            result.add(
              make(
                'left_out',
                'podspec only, no Swift package for: ${unknown.join(', ')}',
                kind: 'podspec_only',
              ),
            );
          } else if (!drafts) {
            result.add(
              make(
                'left_out',
                'podspec only and drafts are switched off '
                    '(XCROSS_PLUGIN_DRAFTS=off)',
                kind: 'podspec_only',
              ),
            );
          } else {
            final written = writer.write(
              plugin,
              base: paths.join(project, 'xcross_overrides'),
            );
            result.add(
              make(
                'drafted',
                'podspec only: drafted ${paths.relative(written.path, from: project).replaceAll(r'\', '/')}',
                kind: 'draft',
              ),
            );
          }
          // A podspec the drafter cannot read is reported, not thrown.
          // ignore: avoid_catches_without_on_clauses
        } catch (error) {
          result.add(
            make(
              'left_out',
              'podspec could not be read: $error',
              kind: 'podspec_only',
            ),
          );
        }
      }
    }
    return result;
  }

  ({
    PrepareStep step,
    String? bundleId,
    String? deploymentTarget,
    Map<String, String> macros,
  })
  _settings(String project) {
    String? read(List<String> parts) {
      final file = fileSystem.file(paths.joinAll([project, ...parts]));
      return file.existsSync() ? file.readAsStringSync() : null;
    }

    final pbxproj = read(['ios', 'Runner.xcodeproj', 'project.pbxproj']);
    final bundleId = pbxproj == null
        ? null
        : RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;\s]+);')
              .allMatches(pbxproj)
              .map((match) => match.group(1)!.replaceAll('"', ''))
              .where((id) => !id.toLowerCase().contains('tests'))
              .firstOrNull;
    final target = pbxproj == null
        ? null
        : RegExp(
            'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
          ).firstMatch(pbxproj)?.group(1);
    final macros = PermissionMacros.environment(
      infoPlist: read(['ios', 'Runner', 'Info.plist']),
      podfile: read(['ios', 'Podfile']),
    );
    final detail = [
      'bundle ID ${bundleId ?? 'not found in the project file'}',
      'iOS ${target ?? 'default'} or later',
      if (macros.isNotEmpty)
        'permissions on: ${[for (final entry in macros.entries)
          if (entry.value == '1') entry.key.replaceFirst('PERMISSION_', '').toLowerCase()].join(', ')}',
    ].join('; ');
    return (
      step: PrepareStep(
        'settings',
        'Settings',
        bundleId == null ? PrepareState.warning : PrepareState.ok,
        detail,
        hint: bundleId == null
            ? 'Set the bundle ID in Xcode or in ios/Runner.xcodeproj.'
            : null,
      ),
      bundleId: bundleId,
      deploymentTarget: target,
      macros: macros,
    );
  }
}

/// `xcross ios`: preparing a Flutter iOS project.
final class IosCommand extends Command<void> {
  IosCommand({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String Function() currentDirectory,
    required void Function(String) write,
    required Map<String, String> environment,
    PubGet? pubGet,
  }) {
    addSubcommand(
      IosPrepareCommand(
        fileSystem: fileSystem,
        paths: paths,
        currentDirectory: currentDirectory,
        write: write,
        environment: environment,
        pubGet: pubGet,
      ),
    );
  }

  @override
  String get name => 'ios';

  @override
  String get description => 'Get a Flutter iOS project ready to build here.';
}

/// `xcross ios prepare [--project <dir>] [--no-pub] [--strict] [--json]`.
final class IosPrepareCommand extends Command<void> {
  IosPrepareCommand({
    required this.fileSystem,
    required this.paths,
    required this.currentDirectory,
    required this.write,
    required this.environment,
    this.pubGet,
  }) {
    argParser
      ..addOption('project', help: 'Flutter project folder (default: here).')
      ..addFlag(
        'pub',
        defaultsTo: true,
        help: 'Run flutter pub get first, which writes the plugin list.',
      )
      ..addFlag(
        'strict',
        negatable: false,
        help: 'Also fail when a build would leave out a plugin.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print one JSON object (type ios_prepare).',
      );
  }

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String Function() currentDirectory;
  final void Function(String) write;
  final Map<String, String> environment;
  final PubGet? pubGet;

  @override
  String get name => 'prepare';

  @override
  String get description =>
      'Make a fresh Flutter iOS project ready to build without a Mac: '
      'dependencies, plugin drafts, and what a build would leave out.';

  @override
  String get invocation =>
      'xcross ios prepare [--project <dir>] [--no-pub] [--strict] [--json]';

  @override
  Future<void> run() async {
    final results = argResults!;
    final project = paths.normalize(
      paths.absolute(results.option('project') ?? currentDirectory()),
    );
    final report = await IosPrepare(
      fileSystem: fileSystem,
      paths: paths,
      environment: environment,
      pubGet: results.flag('pub') ? pubGet : null,
    ).run(project, strict: results.flag('strict'));
    write(
      results.flag('json')
          ? '${jsonEncode(report.toJson())}\n'
          : report.render(),
    );
    if (!report.ready) {
      final failed = report.steps.where(
        (step) => step.state == PrepareState.failed,
      );
      throw CliError(
        failed.isEmpty
            ? 'A build would leave out the native code of '
                  '${report.leftOut.map((plugin) => plugin.name).join(', ')}.'
            : '${failed.first.title}: ${failed.first.detail}'
                  '${failed.first.hint == null ? '' : '\nhint: ${failed.first.hint}'}',
      );
    }
  }
}
