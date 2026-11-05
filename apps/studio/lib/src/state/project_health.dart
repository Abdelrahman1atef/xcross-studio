import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';
import 'job.dart';
import 'settings.dart';

/// The tabs of the Project page.
enum ProjectTab { permissions, capabilities, plugins }

/// How much an [AttentionItem] matters.
enum AttentionSeverity { warning, info }

/// One thing the developer should do about the open project, with the click
/// that does it (features 027 and 028).
class AttentionItem {
  const AttentionItem({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    required this.tab,
    this.fixLabel,
    this.fixCommand,
    this.overwrites = false,
  });

  /// Stable across refreshes: `plugin:fluttertoast:manifest_missing`.
  final String id;
  final AttentionSeverity severity;
  final String title;
  final String detail;

  /// Where to look for the whole picture.
  final ProjectTab tab;

  /// The button, and the xcross command it runs in the project folder; both
  /// null when xcross cannot do it (the developer edits a file).
  final String? fixLabel;
  final List<String>? fixCommand;

  /// The fix replaces files (after a backup): ask first.
  final bool overwrites;
}

/// What the open project needs: plugin problems and permissions its plugins
/// need and Info.plist lacks. Read from `plugin status --json` and
/// `permissions list --json` (never from build output), refreshed when the
/// project changes and after any command that can change either.
class ProjectHealthController extends ChangeNotifier {
  ProjectHealthController(this.jobs, this.settings) {
    settings.addListener(_onSettings);
    jobs.addListener(_onJobs);
  }

  final JobCenter jobs;
  final Settings settings;

  /// Commands whose end can change the answers (`flutter doctor` cannot).
  static bool _changesProject(List<String> command) {
    final first = command.firstOrNull;
    if (first == 'flutter') {
      return const {'build', 'run', 'pub'}.contains(command.elementAtOrNull(1));
    }
    return const {
      'plugin',
      'permissions',
      'capabilities',
      'project',
      'publish',
    }.contains(first);
  }

  PermissionsReport? permissions;
  PluginStatusReport? plugins;
  bool refreshing = false;

  String? _loadedFor;
  int _generation = 0;
  final Set<Job> _seen = {};

  /// Everything to do, plugins first.
  List<AttentionItem> get items => [
    for (final plugin in plugins?.plugins ?? const <PluginItem>[])
      for (final problem in plugin.problems) _pluginItem(plugin, problem),
    for (final missing
        in permissions?.missing ?? const <MissingPermissionItem>[])
      _missingItem(missing),
    for (final item in permissions?.permissions ?? const <PermissionItem>[])
      if (item.isPlaceholder) _placeholderItem(item),
  ];

  int get count => items.length;

  bool get hasWarnings =>
      items.any((item) => item.severity == AttentionSeverity.warning);

  /// Reads the project the first time it is asked about, and again when the
  /// project changed.
  void ensureLoaded() {
    if (settings.projectPath != _loadedFor && !refreshing) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final project = settings.projectPath;
    final generation = ++_generation;
    _loadedFor = project;
    if (project == null) {
      permissions = null;
      plugins = null;
      refreshing = false;
      notifyListeners();
      return;
    }
    refreshing = true;
    notifyListeners();
    PermissionsReport? nextPermissions;
    PluginStatusReport? nextPlugins;
    final reads = [
      jobs.background(
        'Permissions',
        XcrossCommands.permissionsList(),
        workingDirectory: project,
        onEvent: (event) {
          if (event is PermissionsReport) nextPermissions = event;
        },
      ),
      jobs.background(
        'Plugin status',
        XcrossCommands.pluginStatus(),
        workingDirectory: project,
        onEvent: (event) {
          if (event is PluginStatusReport) nextPlugins = event;
        },
      ),
    ];
    await Future.wait([for (final read in reads) read.done]);
    // A newer refresh, or another project, took over meanwhile.
    if (generation != _generation) return;
    permissions = nextPermissions;
    plugins = nextPlugins;
    refreshing = false;
    notifyListeners();
  }

  void _onSettings() {
    if (settings.projectPath != _loadedFor) unawaited(refresh());
  }

  void _onJobs() {
    for (final job in jobs.jobs) {
      if (job.isRunning || !_seen.add(job)) continue;
      final project = settings.projectPath;
      if (project == null) continue;
      if (_changesProject(job.command)) unawaited(refresh());
    }
  }

  AttentionItem _pluginItem(PluginItem plugin, PluginProblemItem problem) {
    final regenerate = plugin.action == 'regenerate' && plugin.canRegenerate;
    final title = switch (problem.code) {
      'stale' => '${plugin.name}: its override is for another version',
      'manifest_missing' =>
        '${plugin.name}: the override has no privacy manifest',
      'unknown_pods' => '${plugin.name}: a build leaves out its iOS code',
      'review_pending' => '${plugin.name}: review the draft xcross wrote',
      _ => '${plugin.name}: ${problem.code}',
    };
    return AttentionItem(
      id: 'plugin:${plugin.name}:${problem.code}',
      severity: problem.code == 'review_pending'
          ? AttentionSeverity.info
          : AttentionSeverity.warning,
      title: title,
      detail: problem.message,
      tab: ProjectTab.plugins,
      fixLabel: regenerate
          ? 'Regenerate'
          : problem.code == 'review_pending'
          ? 'Mark as reviewed'
          : null,
      fixCommand: regenerate
          ? XcrossCommands.pluginRegenerate(plugin.name)
          : problem.code == 'review_pending'
          ? XcrossCommands.pluginAck(plugin.name)
          : null,
      overwrites: regenerate,
    );
  }

  AttentionItem _missingItem(MissingPermissionItem missing) {
    final key = missing.keys.first;
    final suggestion = permissions?.catalogOf(key)?.suggestion;
    return AttentionItem(
      id: 'permission:$key',
      severity: AttentionSeverity.warning,
      title: 'Add the ${missing.resource} permission',
      detail:
          '${missing.plugins.join(', ')} uses the ${missing.resource}, and '
          'Info.plist has no $key; iOS ends the app when it asks.',
      tab: ProjectTab.permissions,
      fixLabel: suggestion == null ? null : 'Add with a starting sentence',
      fixCommand: suggestion == null
          ? null
          : XcrossCommands.permissionSet(key, suggestion),
    );
  }

  AttentionItem _placeholderItem(PermissionItem item) => AttentionItem(
    id: 'permission:${item.key}:placeholder',
    severity: AttentionSeverity.warning,
    title: 'Say why the app needs the ${item.name.toLowerCase()}',
    detail:
        '${item.key} is "${item.value}"; App Review rejects an empty or '
        'placeholder purpose string.',
    tab: ProjectTab.permissions,
  );

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    jobs.removeListener(_onJobs);
    super.dispose();
  }
}
