import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../../src/state/log_session.dart';
import '../common/app_info_view.dart';
import '../common/job_views.dart';

/// Logs & Debug (§6.5): the iPhone's live log with presets and filters,
/// app info, push checklist, crash reports, and every tool command's output.
class LogsDebugPage extends StatelessWidget {
  const LogsDebugPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            XSpace.s6,
            XSpace.s6,
            XSpace.s6,
            0,
          ),
          child: Semantics(
            header: true,
            child: Text(
              'Logs & Debug',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: XSpace.s6),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Device log'),
              Tab(text: 'Tool output'),
            ],
          ),
        ),
        const Expanded(
          child: TabBarView(children: [DeviceLogView(), ToolOutputView()]),
        ),
      ],
    ),
  );
}

/// The live iPhone log (`xcross logs --json`) with filters and side panel.
class DeviceLogView extends StatefulWidget {
  const DeviceLogView({super.key});

  @override
  State<DeviceLogView> createState() => _DeviceLogViewState();
}

class _DeviceLogViewState extends State<DeviceLogView> {
  final _app = TextEditingController();
  final _text = TextEditingController();
  final _process = TextEditingController();
  final _scroll = ScrollController();
  LogPreset? _preset;
  List<InstalledApp> _apps = const [];
  AppInfo? _info;
  Job? _infoJob;
  List<CrashReport>? _crashes;
  Job? _crashJob;
  bool _follow = true;
  String? _seenLogApp;

  @override
  void dispose() {
    for (final c in [_app, _text, _process]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  String? get _appId => _app.text.trim().isEmpty ? null : _app.text.trim();

  Future<void> _loadApps() async {
    final services = Services.of(context);
    final (_, events) = await services.jobs.collect(
      'List apps',
      XcrossCommands.appList(udid: services.settings.udid),
    );
    if (!mounted) return;
    setState(() => _apps = events.whereType<InstalledApp>().toList());
  }

  Future<void> _loadInfo() async {
    final id = _appId;
    if (id == null) return;
    final services = Services.of(context);
    final future = services.jobs.collect(
      'App info',
      XcrossCommands.appInfo(id, udid: services.settings.udid),
    );
    setState(() => _info = null);
    final (job, events) = await future;
    if (!mounted) return;
    setState(() {
      _infoJob = job;
      _info = events.whereType<AppInfo>().firstOrNull;
    });
  }

  Future<void> _loadCrashes() async {
    final services = Services.of(context);
    final future = services.jobs.collect(
      'Crash reports',
      XcrossCommands.crashesList(app: _appId, udid: services.settings.udid),
    );
    setState(() => _crashes = null);
    final (job, events) = await future;
    if (!mounted) return;
    setState(() {
      _crashJob = job;
      _crashes = events.whereType<CrashReport>().toList();
    });
  }

  Future<void> _pullCrash(CrashReport crash) async {
    final services = Services.of(context);
    final folder = await getDirectoryPath();
    if (folder == null || !mounted) return;
    final job = services.jobs.run(
      'Pull ${crash.name}',
      XcrossCommands.crashesPull(
        crash.name,
        outDirectory: folder,
        udid: services.settings.udid,
      ),
    );
    if (await job.done == JobStatus.succeeded) {
      await services.launcher.openFolder(folder);
    }
  }

  void _start(LogSession logs) {
    final services = Services.of(context);
    services.settings.update((s) => s.logApp = _appId);
    _seenLogApp = _appId;
    logs.start(app: _appId, preset: _preset, udid: services.settings.udid);
  }

  Future<void> _save(LogSession logs) async {
    final location = await getSaveLocation(
      suggestedName: 'device-log.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Text', extensions: ['txt', 'log']),
      ],
    );
    if (location == null) return;
    await File(location.path).writeAsString('${logs.visibleText()}\n');
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final logs = services.logs;
    return ListenableBuilder(
      listenable: Listenable.merge([logs, services.settings]),
      builder: (context, _) {
        final logApp = services.settings.logApp;
        if (logApp != _seenLogApp) {
          _seenLogApp = logApp;
          _app.text = logApp ?? '';
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _logColumn(logs)),
            VerticalDivider(width: 1, color: XTheme.of(context).colors.border),
            SizedBox(width: 360, child: _sidePanel(logs)),
          ],
        );
      },
    );
  }

  XConsoleState _state(LogSession logs) {
    final job = logs.job;
    if (job == null) return XConsoleState.stopped;
    if (logs.paused) return XConsoleState.paused;
    return consoleState(job);
  }

  Widget _logColumn(LogSession logs) {
    final c = XTheme.of(context).colors;
    final visible = logs.visible;
    if (_follow && !logs.paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    final pushOrCrash = _preset == LogPreset.push || _preset == LogPreset.crash;
    return Padding(
      padding: const EdgeInsets.all(XSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: XSpace.s3,
            runSpacing: XSpace.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  controller: _app,
                  decoration: InputDecoration(
                    labelText: 'App bundle ID (empty = whole device)',
                    suffixIcon: _apps.isEmpty
                        ? IconButton(
                            tooltip: 'Load installed apps',
                            icon: const Icon(Icons.apps),
                            onPressed: _loadApps,
                          )
                        : PopupMenuButton<String>(
                            tooltip: 'Installed apps',
                            icon: const Icon(Icons.arrow_drop_down_circle),
                            onSelected: (id) => setState(() => _app.text = id),
                            itemBuilder: (context) => [
                              for (final app in _apps)
                                PopupMenuItem(
                                  value: app.bundleId,
                                  child: Text(app.label),
                                ),
                            ],
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SegmentedButton<LogPreset?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(
                    value: LogPreset.flutter,
                    label: Text('Flutter'),
                  ),
                  ButtonSegment(value: LogPreset.push, label: Text('Push')),
                  ButtonSegment(value: LogPreset.crash, label: Text('Crash')),
                ],
                selected: {_preset},
                onSelectionChanged: logs.running
                    ? null
                    : (p) => setState(() => _preset = p.first),
              ),
              if (logs.running)
                XButton(
                  label: 'Stop',
                  icon: Icons.stop,
                  variant: XButtonVariant.secondary,
                  onPressed: logs.stop,
                )
              else
                XButton(
                  label: 'Start',
                  icon: Icons.play_arrow,
                  disabledReason: 'Push and Crash need an app bundle ID.',
                  onPressed: pushOrCrash && _appId == null
                      ? null
                      : () => _start(logs),
                ),
            ],
          ),
          const SizedBox(height: XSpace.s3),
          Row(
            children: [
              Expanded(
                child: XTextField(
                  controller: _text,
                  label: 'Search text',
                  prefixIcon: Icons.search,
                  onChanged: (v) => logs.setFilters(text: v),
                ),
              ),
              const SizedBox(width: XSpace.s2),
              XTextField(
                controller: _process,
                label: 'Process',
                width: 170,
                onChanged: (v) => logs.setFilters(process: v),
              ),
              const SizedBox(width: XSpace.s2),
              DropdownMenu<LogLevel>(
                initialSelection: logs.minimumLevel,
                label: const Text('Level'),
                width: 140,
                dropdownMenuEntries: [
                  for (final level in LogLevel.values)
                    DropdownMenuEntry(value: level, label: level.name),
                ],
                onSelected: (level) => logs.setFilters(level: level),
              ),
              const SizedBox(width: XSpace.s1),
              XIconButton(
                tooltip: logs.paused ? 'Resume autoscroll' : 'Pause autoscroll',
                selected: logs.paused,
                onPressed: logs.togglePause,
                icon: logs.paused ? Icons.play_circle_outline : Icons.pause,
              ),
              XIconButton(
                tooltip: 'Clear',
                onPressed: logs.clear,
                icon: Icons.delete_sweep_outlined,
              ),
              XIconButton(
                tooltip: 'Copy visible lines',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: logs.visibleText())),
                icon: Icons.copy,
              ),
              XIconButton(
                tooltip: 'Save to file',
                onPressed: () => _save(logs),
                icon: Icons.save_alt,
              ),
            ],
          ),
          const SizedBox(height: XSpace.s2),
          Row(
            children: [
              XStatusBadge(
                status: switch (_state(logs)) {
                  XConsoleState.live => XStatus.running,
                  XConsoleState.paused => XStatus.warning,
                  XConsoleState.failed => XStatus.failed,
                  XConsoleState.complete => XStatus.ready,
                  XConsoleState.stopped => XStatus.idle,
                },
                label: switch (_state(logs)) {
                  XConsoleState.live => 'Following live output',
                  XConsoleState.paused => 'Paused',
                  XConsoleState.failed => 'Ended with an error',
                  XConsoleState.complete => 'Ended',
                  XConsoleState.stopped => 'Not running',
                },
              ),
              const SizedBox(width: XSpace.s3),
              Expanded(
                child: Text(
                  [
                    '${visible.length} shown / ${logs.received} received',
                    ?logs.notice,
                    if (logs.job case final job? when !job.isRunning)
                      'stopped${job.issues.isEmpty ? '' : ': ${job.issues.first.text}'}',
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: XType.support.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: XSpace.s2),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.console,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(XRadius.md),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  final m = n.metrics;
                  _follow = m.pixels >= m.maxScrollExtent - 24;
                  return false;
                },
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(XSpace.s2),
                    itemCount: visible.length,
                    itemExtent: 19,
                    itemBuilder: (context, i) => _LogRow(line: visible[i]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidePanel(LogSession logs) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'App info'),
            Tab(text: 'Push'),
            Tab(text: 'Crashes'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [_appInfoTab(), _pushTab(logs), _crashesTab()],
          ),
        ),
      ],
    ),
  );

  Widget _appInfoTab() => ListView(
    padding: const EdgeInsets.all(XSpace.s4),
    children: [
      XButton(
        label: 'Read installed app info',
        icon: Icons.info_outline,
        variant: XButtonVariant.secondary,
        disabledReason: 'Enter an app bundle ID first.',
        onPressed: _appId == null ? null : _loadInfo,
      ),
      const SizedBox(height: XSpace.s3),
      if (_info == null && _infoJob != null) JobDiagnostics(job: _infoJob!),
      if (_info != null) AppInfoView(info: _info!),
    ],
  );

  Widget _pushTab(LogSession logs) {
    final d = logs.diagnosis;
    final info = _info;
    final entitled = d?.entitlement != null || info?.push != null;
    XStatus check(bool? ok) =>
        ok == null ? XStatus.idle : (ok ? XStatus.ready : XStatus.failed);
    return ListView(
      padding: const EdgeInsets.all(XSpace.s4),
      children: [
        const XNote(
          'Start the log with the Push preset and an app, open the app, then '
          'send a test notification.',
        ),
        const SizedBox(height: XSpace.s3),
        XCheckRow(
          status: check(d == null && info == null ? null : entitled),
          label: 'aps-environment entitlement installed',
          detail: d?.entitlement ?? info?.push,
        ),
        XCheckRow(
          status: check(d == null ? null : !d.permissionDenied),
          label: 'Notification permission granted',
        ),
        XCheckRow(status: check(d?.appSeen), label: 'App running'),
        XCheckRow(
          status: check(d?.registrationSeen),
          label: 'APNs token registered',
        ),
        XCheckRow(
          status: check(d?.deliverySeen),
          label: 'Notification delivered',
        ),
        if (d != null) ...[
          const Divider(height: XSpace.s6),
          Text(
            'Verdict: ${d.verdict.replaceAll('_', ' ')}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: XSpace.s1),
          XNote(d.hint),
        ],
      ],
    );
  }

  Widget _crashesTab() {
    final crashes = _crashes;
    return ListView(
      padding: const EdgeInsets.all(XSpace.s4),
      children: [
        XButton(
          label: _appId == null
              ? 'List crash reports'
              : 'List crashes of the app',
          icon: Icons.bug_report_outlined,
          variant: XButtonVariant.secondary,
          loading: _crashJob?.isRunning ?? false,
          loadingLabel: 'Listing…',
          onPressed: _loadCrashes,
        ),
        const SizedBox(height: XSpace.s3),
        if (crashes == null && _crashJob != null)
          JobDiagnostics(job: _crashJob!),
        if (crashes != null && crashes.isEmpty)
          const XNote('No crash reports.'),
        for (final crash in crashes ?? const <CrashReport>[])
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(crash.process),
            subtitle: Text(
              '${crash.time.replaceFirst('T', ' ')}'
              '${crash.exceptionType == null ? '' : ' · ${crash.exceptionType}'}',
            ),
            trailing: XIconButton(
              tooltip: 'Save report…',
              icon: Icons.download,
              onPressed: () => _pullCrash(crash),
            ),
          ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.line});

  final DeviceLogLine line;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final color = switch (line.level) {
      'fault' || 'error' => c.error,
      'debug' => c.textMuted,
      'info' => c.textSecondary,
      _ => c.textPrimary,
    };
    final highlight = switch (line.highlight) {
      'registration' => c.primary.withValues(alpha: 0.14),
      'delivery' => c.success.withValues(alpha: 0.14),
      'error' => c.error.withValues(alpha: 0.14),
      _ => null,
    };
    return Container(
      color: highlight,
      child: Text(
        line.toText(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: XType.mono.copyWith(color: color),
      ),
    );
  }
}

/// Every tool command of this session with its full output.
class ToolOutputView extends StatefulWidget {
  const ToolOutputView({super.key});

  @override
  State<ToolOutputView> createState() => _ToolOutputViewState();
}

class _ToolOutputViewState extends State<ToolOutputView> {
  Job? _selected;

  @override
  Widget build(BuildContext context) {
    final jobs = Services.of(context).jobs;
    final c = XTheme.of(context).colors;
    return ListenableBuilder(
      listenable: jobs,
      builder: (context, _) {
        final list = jobs.jobs.reversed.toList();
        final selected = list.contains(_selected)
            ? _selected
            : list.firstOrNull;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      XSpace.s4,
                      XSpace.s3,
                      XSpace.s2,
                      XSpace.s2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Commands',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        XButton(
                          label: 'Clear finished',
                          variant: XButtonVariant.text,
                          onPressed: jobs.clearFinished,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final job in list)
                          ListTile(
                            selected: job == selected,
                            selectedTileColor: c.primary.withValues(
                              alpha: 0.12,
                            ),
                            dense: true,
                            leading: Icon(
                              statusOf(job).icon,
                              size: 18,
                              color: statusOf(job).color(context),
                            ),
                            title: Text(job.title),
                            subtitle: Text(
                              job.displayCommand,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => _selected = job),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: c.border),
            Expanded(
              child: selected == null
                  ? const XEmptyState(
                      icon: Icons.terminal,
                      title: 'No commands run yet',
                      message:
                          'Every xcross command started from XCross Studio '
                          'appears here with its full output.',
                    )
                  : Padding(
                      padding: const EdgeInsets.all(XSpace.s4),
                      child: JobConsole(
                        job: selected,
                        height: null,
                        input: true,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
