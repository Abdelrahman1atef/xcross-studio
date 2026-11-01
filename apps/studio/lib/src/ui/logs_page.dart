import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';
import '../state/job.dart';
import '../state/log_session.dart';
import 'services.dart';
import 'widgets.dart';

/// Device Logs: live iPhone log, presets, app info, push checklist, crashes.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app.text.isEmpty) {
      _app.text = Services.of(context).settings.logApp ?? '';
    }
  }

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
    final logs = Services.of(context).logs;
    return Watch(
      listenable: logs,
      builder: (context) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _logColumn(logs)),
          const VerticalDivider(width: 1),
          SizedBox(width: 360, child: _sidePanel(logs)),
        ],
      ),
    );
  }

  Widget _logColumn(LogSession logs) {
    final scheme = Theme.of(context).colorScheme;
    final visible = logs.visible;
    if (_follow && !logs.paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _app,
                  decoration: InputDecoration(
                    labelText: 'App bundle ID (empty = whole device)',
                    isDense: true,
                    border: const OutlineInputBorder(),
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
              const SizedBox(width: 12),
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
              const SizedBox(width: 12),
              if (logs.running)
                FilledButton.tonalIcon(
                  onPressed: logs.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                )
              else
                FilledButton.icon(
                  onPressed:
                      (_preset == LogPreset.push ||
                              _preset == LogPreset.crash) &&
                          _appId == null
                      ? null
                      : () => _start(logs),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  decoration: const InputDecoration(
                    labelText: 'Filter text',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => logs.setFilters(text: v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _process,
                  decoration: const InputDecoration(
                    labelText: 'Process',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => logs.setFilters(process: v),
                ),
              ),
              const SizedBox(width: 8),
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
              const SizedBox(width: 8),
              IconButton(
                tooltip: logs.paused ? 'Resume' : 'Pause',
                onPressed: logs.togglePause,
                icon: Icon(logs.paused ? Icons.play_circle : Icons.pause),
              ),
              IconButton(
                tooltip: 'Clear',
                onPressed: logs.clear,
                icon: const Icon(Icons.delete_sweep),
              ),
              IconButton(
                tooltip: 'Copy visible lines',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: logs.visibleText())),
                icon: const Icon(Icons.copy),
              ),
              IconButton(
                tooltip: 'Save to file',
                onPressed: () => _save(logs),
                icon: const Icon(Icons.save_alt),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              '${visible.length} shown / ${logs.received} received',
              if (logs.paused) 'paused',
              ?logs.notice,
              if (logs.job case final job? when !job.isRunning)
                'stopped${job.issues.isEmpty ? '' : ': ${job.issues.first.text}'}',
            ].join(' · '),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(6),
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
                    padding: const EdgeInsets.all(8),
                    itemCount: visible.length,
                    itemExtent: 18,
                    itemBuilder: (context, i) =>
                        _LogRow(line: visible[i], scheme: scheme),
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

  Widget _appInfoTab() {
    final info = _info;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.tonalIcon(
          onPressed: _appId == null ? null : _loadInfo,
          icon: const Icon(Icons.info_outline),
          label: const Text('Read installed app info'),
        ),
        const SizedBox(height: 12),
        if (info == null && _infoJob != null)
          for (final line in _infoJob!.issues) Text(line.text),
        if (info != null) ...[
          Text(
            '${info.name ?? info.bundleId} ${info.version ?? ''} '
            '(${info.build ?? '-'})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text('signer: ${info.signer} · team ${info.teamId ?? '-'}'),
          const SizedBox(height: 8),
          CheckRow(
            ok: info.push != null,
            label: 'Push entitlement',
            detail: info.push ?? 'missing',
          ),
          CheckRow(
            ok: info.associatedDomains.isNotEmpty,
            label: 'Associated domains',
            detail: info.associatedDomains.isEmpty
                ? 'none'
                : info.associatedDomains.join(', '),
          ),
          const Divider(),
          for (final MapEntry(:key, :value) in info.entitlements.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText('$key: $value', style: mono),
            ),
        ],
      ],
    );
  }

  Widget _pushTab(LogSession logs) {
    final d = logs.diagnosis;
    final info = _info;
    final entitled = d?.entitlement != null || info?.push != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Start the log with the Push preset and an app, open the app, '
          'then send a test notification.',
        ),
        const SizedBox(height: 12),
        CheckRow(
          ok: d == null && info == null ? null : entitled,
          label: 'aps-environment entitlement installed',
          detail: d?.entitlement ?? info?.push,
        ),
        CheckRow(
          ok: d == null ? null : !d.permissionDenied,
          label: 'Notification permission granted',
        ),
        CheckRow(ok: d?.appSeen, label: 'App running'),
        CheckRow(ok: d?.registrationSeen, label: 'APNs token registered'),
        CheckRow(ok: d?.deliverySeen, label: 'Notification delivered'),
        if (d != null) ...[
          const Divider(),
          Text(
            'Verdict: ${d.verdict.replaceAll('_', ' ')}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(d.hint),
        ],
      ],
    );
  }

  Widget _crashesTab() {
    final crashes = _crashes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.tonalIcon(
            onPressed: _loadCrashes,
            icon: const Icon(Icons.bug_report),
            label: Text(
              _appId == null ? 'List crash reports' : 'List crashes of the app',
            ),
          ),
        ),
        if (crashes == null && _crashJob != null)
          for (final line in _crashJob!.issues)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(line.text),
            ),
        if (crashes != null && crashes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('No crash reports.'),
          ),
        if (crashes != null)
          Expanded(
            child: ListView(
              children: [
                for (final crash in crashes)
                  ListTile(
                    dense: true,
                    title: Text(crash.process),
                    subtitle: Text(
                      '${crash.time.replaceFirst('T', ' ')}'
                      '${crash.exceptionType == null ? '' : ' · ${crash.exceptionType}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Save report…',
                      icon: const Icon(Icons.download),
                      onPressed: () => _pullCrash(crash),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.line, required this.scheme});

  final DeviceLogLine line;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final color = switch (line.level) {
      'fault' => scheme.error,
      'error' => Colors.red.shade400,
      'debug' => scheme.outline,
      'info' => scheme.onSurfaceVariant,
      _ => scheme.onSurface,
    };
    final highlight = switch (line.highlight) {
      'registration' => Colors.blue.withValues(alpha: 0.12),
      'delivery' => Colors.green.withValues(alpha: 0.14),
      'error' => Colors.red.withValues(alpha: 0.14),
      _ => null,
    };
    return Container(
      color: highlight,
      child: Text(
        line.toText(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono.copyWith(color: color),
      ),
    );
  }
}
