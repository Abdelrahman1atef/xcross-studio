import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/design_system.dart';
import '../features/build/build_run_page.dart';
import '../features/common/job_views.dart';
import '../features/common/readiness_views.dart';
import '../features/devices/devices_page.dart';
import '../features/icons/icons_page.dart';
import '../features/logs/logs_debug_page.dart';
import '../features/onboarding/setup_wizard.dart';
import '../features/overview/overview_page.dart';
import '../features/project/project_page.dart';
import '../features/release/archives_page.dart';
import '../features/release/release_page.dart';
import '../features/settings/settings_page.dart';
import '../features/signing/signing_page.dart';
import '../src/product.dart';
import '../src/state/job.dart';
import '../src/state/readiness.dart';
import 'app_controller.dart';
import 'quick_commands.dart';
import 'services.dart';

/// Label, icon and shortcut of each destination.
extension DestinationLook on Destination {
  String get label => switch (this) {
    Destination.overview => 'Overview',
    Destination.build => 'Build & Run',
    Destination.devices => 'Devices',
    Destination.signing => 'Signing',
    Destination.logs => 'Logs & Debug',
    Destination.project => 'Project',
    Destination.icons => 'App icon',
    Destination.release => 'Release',
    Destination.archives => 'Archives',
    Destination.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    Destination.overview => Icons.space_dashboard_outlined,
    Destination.build => Icons.play_circle_outline,
    Destination.devices => Icons.phone_iphone,
    Destination.signing => Icons.verified_user_outlined,
    Destination.logs => Icons.receipt_long_outlined,
    Destination.project => Icons.tune_outlined,
    Destination.icons => Icons.apps,
    Destination.release => Icons.rocket_launch_outlined,
    Destination.archives => Icons.archive_outlined,
    Destination.settings => Icons.settings_outlined,
  };

  String get shortcut => switch (this) {
    Destination.logs => 'Ctrl+L',
    Destination.settings => 'Ctrl+,',
    _ => 'Ctrl+${index + 1}',
  };
}

/// The XCross Studio window (design system §5).
class StudioShell extends StatefulWidget {
  const StudioShell({super.key, this.startupChecks = true});

  /// Run the doctor, read the version and list devices on start.
  final bool startupChecks;

  /// Below this width the sidebar becomes an icon rail (§5.2).
  static const wideBreakpoint = 1100.0;

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  bool _wizardShown = false;
  late StudioServices _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = Services.of(context);
    _services.app.openWizard = () => showSetupWizard(context);
    _services.app.openConsole = () {
      if (!_services.settings.consoleOpen) {
        _services.settings.update((s) => s.consoleOpen = true);
      }
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.startupChecks) return;
      final services = Services.of(context);
      services.devices.refresh();
      // Feature 017: plug/unplug updates the device list live.
      services.devices.watch();
      services.readiness.readVersion();
      services.projectHealth.ensureLoaded();
      services.readiness.runDoctor().done.then((_) => _maybeOpenWizard());
    });
  }

  /// First launch: open the wizard while the doctor reports failures and
  /// the user has not closed it before.
  void _maybeOpenWizard() {
    if (!mounted || _wizardShown) return;
    final services = Services.of(context);
    if (services.settings.wizardDismissed || !services.readiness.needsSetup) {
      return;
    }
    _wizardShown = true;
    showSetupWizard(context);
  }

  void _go(Destination destination) => _services.app.go(destination);

  void _toggleConsole() =>
      _services.settings.update((s) => s.consoleOpen = !s.consoleOpen);

  List<QuickCommand> _quickCommands() {
    final services = _services;
    return [
      for (final d in Destination.values)
        QuickCommand('Go to ${d.label}', d.icon, () => _go(d)),
      QuickCommand(
        'Run checks (flutter doctor)',
        Icons.health_and_safety_outlined,
        services.readiness.runDoctor,
      ),
      QuickCommand('Refresh devices', Icons.refresh, services.devices.refresh),
      QuickCommand(
        'Open setup wizard',
        Icons.auto_awesome_outlined,
        () => showSetupWizard(context),
      ),
      QuickCommand('Show or hide the console', Icons.terminal, _toggleConsole),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            _go(Destination.settings),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _go(Destination.logs),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
            _toggleConsole,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showQuickCommands(context, _quickCommands()),
        for (final (i, key) in [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
          LogicalKeyboardKey.digit7,
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.digit9,
        ].indexed)
          SingleActivator(key, control: true): () => _go(Destination.values[i]),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([
              services.app,
              services.settings,
              services.readiness,
              services.jobs,
              services.devices,
              services.projectHealth,
            ]),
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= StudioShell.wideBreakpoint;
                return XAppShell(
                  topBar: _TopBar(
                    compact: !wide,
                    onQuickCommands: () =>
                        showQuickCommands(context, _quickCommands()),
                  ),
                  sidebar: _Sidebar(compact: !wide),
                  body: IndexedStack(
                    index: services.app.destination.index,
                    children: [
                      const OverviewPage(),
                      BuildRunPage(
                        onInstall: (ipa) {
                          services.settings.update((s) => s.lastIpa = ipa);
                          _go(Destination.devices);
                        },
                      ),
                      const DevicesPage(),
                      const SigningPage(),
                      const LogsDebugPage(),
                      const ProjectPage(),
                      const IconsPage(),
                      const ReleasePage(),
                      const ArchivesPage(),
                      const SettingsPage(),
                    ],
                  ),
                  dock: _ConsoleDock(maxHeight: constraints.maxHeight * 0.6),
                  statusBar: _StatusBar(compact: !wide),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onQuickCommands, required this.compact});

  final VoidCallback onQuickCommands;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final c = XTheme.of(context).colors;
    final project = services.settings.projectPath;
    final device = services.devices.selected;
    final devices = services.devices.devices ?? const [];
    final projectName = project == null
        ? 'No project'
        : project.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;
    return Container(
      height: 52,
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: XSpace.s4),
      child: Row(
        children: [
          Icon(Icons.close_rounded, color: c.primary, size: 26),
          if (!compact) ...[
            const SizedBox(width: XSpace.s2),
            Text(productName, style: XType.card.copyWith(color: c.textPrimary)),
          ],
          SizedBox(width: compact ? XSpace.s3 : XSpace.s6),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Tooltip(
                    message: project ?? 'Open a project on Overview',
                    child: ActionChip(
                      avatar: const Icon(Icons.folder_outlined, size: 16),
                      label: Text(
                        'Project: $projectName',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => services.app.go(Destination.overview),
                    ),
                  ),
                ),
                if (services.projectHealth.count > 0) ...[
                  const SizedBox(width: XSpace.s2),
                  Tooltip(
                    message: services.projectHealth.items.first.title,
                    child: ActionChip(
                      key: const ValueKey('todo-chip'),
                      avatar: Icon(
                        Icons.error_outline,
                        size: 16,
                        color: c.warning,
                      ),
                      label: Text('${services.projectHealth.count} to do'),
                      onPressed: () => services.app.goProject(
                        services.projectHealth.items.first.tab,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: XSpace.s2),
                Flexible(
                  child: PopupMenuButton<String>(
                    tooltip: 'Choose the iPhone',
                    onSelected: (udid) {
                      if (udid == '_refresh') {
                        services.devices.refresh();
                      } else if (udid == '_devices') {
                        services.app.go(Destination.devices);
                      } else {
                        services.devices.select(udid);
                      }
                    },
                    itemBuilder: (context) => [
                      for (final d in devices)
                        PopupMenuItem(
                          value: d.udid,
                          child: Text('${d.name} · iOS ${d.osVersion ?? '?'}'),
                        ),
                      const PopupMenuItem(
                        value: '_refresh',
                        child: Text('Refresh'),
                      ),
                      const PopupMenuItem(
                        value: '_devices',
                        child: Text('Open Devices'),
                      ),
                    ],
                    // Feature 017: a live badge (green: connected, grey:
                    // none, warning: the device service is down).
                    child: Chip(
                      key: const ValueKey('device-badge'),
                      avatar: Icon(
                        services.devices.serviceDown
                            ? Icons.usb_off
                            : Icons.phone_iphone,
                        size: 16,
                        color: services.devices.serviceDown
                            ? c.warning
                            : device == null
                            ? c.textMuted
                            : c.success,
                      ),
                      label: Text(
                        services.devices.serviceDown
                            ? 'Device service not reachable'
                            : device == null
                            ? (services.devices.refreshing
                                  ? 'iPhone: looking…'
                                  : 'Plug in an iPhone')
                            : 'iPhone: ${device.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (services.readiness.needsSetup)
            Padding(
              padding: const EdgeInsets.only(right: XSpace.s2),
              child: compact
                  ? XIconButton(
                      icon: Icons.warning_amber_rounded,
                      tooltip: 'Fix setup',
                      destructive: true,
                      onPressed: () => services.app.openWizard?.call(),
                    )
                  : XButton(
                      label: 'Fix setup',
                      icon: Icons.warning_amber_rounded,
                      variant: XButtonVariant.text,
                      onPressed: () => services.app.openWizard?.call(),
                    ),
            ),
          if (compact)
            XIconButton(
              icon: Icons.bolt_outlined,
              tooltip: 'Quick commands (Ctrl+K)',
              onPressed: onQuickCommands,
            )
          else
            XButton(
              label: 'Quick commands  Ctrl+K',
              icon: Icons.bolt_outlined,
              variant: XButtonVariant.secondary,
              onPressed: onQuickCommands,
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final c = XTheme.of(context).colors;
    return Container(
      width: compact ? 68 : 224,
      color: c.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: XSpace.s2,
        vertical: XSpace.s3,
      ),
      child: Column(
        children: [
          for (final d in Destination.values)
            Padding(
              padding: const EdgeInsets.only(bottom: XSpace.s1),
              child: XSidebarItem(
                icon: d.icon,
                label: d.label,
                compact: compact,
                shortcut: d.shortcut,
                badge: d == Destination.project
                    ? services.projectHealth.count
                    : 0,
                selected: services.app.destination == d,
                onTap: () => services.app.go(d),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsoleDock extends StatelessWidget {
  const _ConsoleDock({required this.maxHeight});

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    final jobs = services.jobs.jobs;
    final chosen = services.app.consoleJob;
    final Job? job = jobs.contains(chosen) ? chosen : jobs.lastOrNull;
    final running = jobs.where((j) => j.isRunning).length;
    return XConsoleDock(
      open: settings.consoleOpen,
      height: settings.consoleHeight,
      maxHeight: maxHeight < 160 ? 160 : maxHeight,
      onToggle: () => settings.update((s) => s.consoleOpen = !s.consoleOpen),
      onResize: (h) => settings.update((s) => s.consoleHeight = h),
      title: Row(
        children: [
          const Text('Console'),
          const SizedBox(width: XSpace.s3),
          if (job != null) ...[
            XStatusBadge(
              status: statusOf(job),
              compact: true,
              label: job.title,
            ),
            if (running > 0) ...[
              const SizedBox(width: XSpace.s3),
              Text('$running running'),
            ],
          ] else
            const Text('No commands yet'),
        ],
      ),
      actions: [
        if (job != null && job.isRunning)
          XIconButton(
            icon: Icons.stop_circle_outlined,
            tooltip: 'Stop ${job.title}',
            destructive: true,
            onPressed: job.cancel,
          ),
        if (job != null)
          XIconButton(
            icon: Icons.copy,
            tooltip: 'Copy output',
            onPressed: () => Clipboard.setData(
              ClipboardData(
                text: [for (final l in job.lines) l.text].join('\n'),
              ),
            ),
          ),
        if (jobs.length > 1)
          PopupMenuButton<Job>(
            tooltip: 'Choose a command',
            icon: const Icon(Icons.list, size: 18),
            onSelected: (j) => services.app.showJob(j),
            itemBuilder: (context) => [
              for (final j in jobs.reversed.take(20))
                PopupMenuItem(value: j, child: Text(j.title)),
            ],
          ),
        XIconButton(
          icon: Icons.open_in_new,
          tooltip: 'Open in Logs & Debug',
          onPressed: () => services.app.go(Destination.logs),
        ),
      ],
      child: job == null
          ? const Center(
              child: XNote('Commands you start appear here with their output.'),
            )
          : JobConsole(
              job: job,
              height: null,
              input: true,
              showTitle: false,
              showHeader: false,
            ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final c = XTheme.of(context).colors;
    final readiness = services.readiness;
    final running = services.jobs.jobs.where((j) => j.isRunning).length;
    XStatusBadge badge(String name, AreaHealth area) => XStatusBadge(
      compact: true,
      status: statusOfHealth(area.health),
      label:
          '$name ${switch (area.health) {
            Health.ok => 'ready',
            Health.warning => 'needs attention',
            Health.failed => 'failed',
            Health.checking => 'checking',
            Health.unknown => 'not checked',
          }}',
    );
    return Container(
      height: 30,
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: XSpace.s4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(child: badge('Toolchain', readiness.toolchain)),
                const SizedBox(width: XSpace.s4),
                Flexible(child: badge('Signing', readiness.signing)),
                const SizedBox(width: XSpace.s4),
                Flexible(child: badge('Device', readiness.device)),
              ],
            ),
          ),
          if (running > 0) ...[
            Flexible(
              child: XStatusBadge(
                compact: true,
                status: XStatus.running,
                label: '$running task${running == 1 ? '' : 's'} running',
              ),
            ),
            const SizedBox(width: XSpace.s4),
          ],
          if (!compact)
            Text(
              readiness.cliVersion ?? 'xcross version unknown',
              overflow: TextOverflow.ellipsis,
              style: XType.support.copyWith(color: c.textMuted),
            ),
        ],
      ),
    );
  }
}
