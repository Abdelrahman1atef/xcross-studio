import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/app_info_view.dart';
import '../common/job_views.dart';

/// Devices (§6.3): connected iPhones with each readiness requirement shown
/// explicitly, app installation and installed apps.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  Job? _install;
  Job? _tunnel;
  bool _launch = true;
  List<InstalledApp>? _apps;
  Job? _appsJob;
  AppInfo? _info;
  Job? _infoJob;

  Future<void> _loadApps() async {
    final services = Services.of(context);
    final future = services.jobs.collect(
      'List apps',
      XcrossCommands.appList(udid: services.settings.udid),
    );
    setState(() => _apps = null);
    final (job, events) = await future;
    if (!mounted) return;
    setState(() {
      _appsJob = job;
      _apps = events.whereType<InstalledApp>().toList();
    });
  }

  Future<void> _appInfo(String bundleId) async {
    final services = Services.of(context);
    final future = services.jobs.collect(
      'App info',
      XcrossCommands.appInfo(bundleId, udid: services.settings.udid),
    );
    setState(() => _info = null);
    final (job, events) = await future;
    if (!mounted) return;
    setState(() {
      _infoJob = job;
      _info = events.whereType<AppInfo>().firstOrNull;
    });
  }

  List<XRequirement> _requirements(ConnectedDevice device) {
    final major = int.tryParse((device.osVersion ?? '').split('.').first);
    return [
      XRequirement(
        XStatus.ready,
        'Connected over ${device.connection.toUpperCase()}',
        detail:
            'listed by usbmux; unlock the phone and tap Trust if a '
            'command reports it is not trusted',
      ),
      if (major == null)
        const XRequirement(XStatus.idle, 'iOS version unknown')
      else if (major < 15)
        XRequirement(
          XStatus.failed,
          'iOS ${device.osVersion} is not supported',
          detail: 'XCross Studio needs iOS 15 or newer',
        )
      else if (device.legacy)
        XRequirement(
          XStatus.warning,
          'iOS ${device.osVersion}: release and profile only',
          detail:
              'debug needs a debugger; apps open through your developer '
              'disk image (below) or from their icon',
        )
      else
        XRequirement(
          XStatus.ready,
          'iOS ${device.osVersion}',
          detail: 'debug runs need the developer tunnel (Prepare USB tunnel)',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    final controller = services.devices;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, controller]),
      builder: (context, _) {
        final devices = controller.devices;
        final selected = controller.selected;
        return WorkspaceLayout(
          title: 'Devices',
          subtitle: 'iPhones connected to this computer.',
          actions: [
            XButton(
              label: 'Refresh',
              icon: Icons.refresh,
              variant: XButtonVariant.secondary,
              loading: controller.refreshing,
              loadingLabel: 'Looking…',
              onPressed: controller.refresh,
            ),
          ],
          children: [
            if (devices == null)
              const XCard(child: XNote('Looking for iPhones…'))
            else if (devices.isEmpty)
              XCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const XEmptyState(
                      icon: Icons.phone_iphone,
                      title: 'No iPhone connected',
                      message:
                          'Connect the iPhone by USB, unlock it and tap '
                          '"Trust" on the phone, then refresh.',
                    ),
                    if (controller.listing != null)
                      JobDiagnostics(job: controller.listing!),
                  ],
                ),
              )
            else
              for (final device in devices)
                XDeviceCard(
                  name: device.name,
                  osVersion: device.osVersion,
                  transport: device.connection.toUpperCase(),
                  udid: device.udid,
                  state: XDeviceState.connected,
                  selected: device.udid == settings.udid,
                  onTap: () => controller.select(device.udid),
                  requirements: _requirements(device),
                  actions: [
                    if (device.udid != settings.udid)
                      XButton(
                        label: 'Use this iPhone',
                        variant: XButtonVariant.secondary,
                        onPressed: () => controller.select(device.udid),
                      ),
                    if (!device.legacy)
                      XButton(
                        label: 'Prepare USB tunnel',
                        icon: Icons.cable,
                        variant: XButtonVariant.secondary,
                        loading: _tunnel?.isRunning ?? false,
                        loadingLabel: 'Tunnel running…',
                        onPressed: () => setState(
                          () => _tunnel = services.jobs.run(
                            'Tunnel',
                            XcrossCommands.tunnel(),
                          ),
                        ),
                      ),
                  ],
                ),
            if (selected != null && !selected.legacy)
              const XNote(
                'Prepare USB tunnel runs "xcross tunnel" (mount the developer '
                'disk image, start the iOS 17+ tunnel). It needs an '
                'Administrator terminal on Windows or sudo on Linux; started '
                'from here without those rights it stops with an explanation.',
                icon: Icons.info_outline,
              ),
            if (_tunnel != null) JobConsole(job: _tunnel!, height: 160),
            XCard(
              title: 'Install an app (.ipa)',
              subtitle:
                  'Signs with your Apple ID or API key and installs over USB '
                  '(iOS 15+). Your file is never modified.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  XFilePickerField(
                    label: '.ipa file',
                    directory: false,
                    extensions: const ['ipa'],
                    value: settings.lastIpa,
                    onChanged: (path) =>
                        settings.update((s) => s.lastIpa = path),
                  ),
                  const SizedBox(height: XSpace.s3),
                  XFilePickerField(
                    label: 'Developer disk image folder (iOS 15/16, optional)',
                    hint:
                        'DeveloperDiskImage.dmg + .signature from your own '
                        "Xcode's DeviceSupport, directly or in version folders "
                        'such as 16.4.',
                    value: settings.ddiDirectory,
                    onChanged: (path) =>
                        settings.update((s) => s.ddiDirectory = path),
                  ),
                  const SizedBox(height: XSpace.s3),
                  Wrap(
                    spacing: XSpace.s2,
                    runSpacing: XSpace.s2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Open after install'),
                        selected: _launch,
                        onSelected: (v) => setState(() => _launch = v),
                      ),
                      XButton(
                        label: 'Sign & install',
                        icon: Icons.install_mobile,
                        loading:
                            (_install?.isRunning ?? false) &&
                            _install!.title == 'Install',
                        loadingLabel: 'Installing…',
                        disabledReason: 'Choose an .ipa file first.',
                        onPressed:
                            settings.lastIpa == null ||
                                (_install?.isRunning ?? false)
                            ? null
                            : () => setState(
                                () => _install = services.jobs.run(
                                  'Install',
                                  XcrossCommands.install(
                                    settings.lastIpa!,
                                    udid: settings.udid,
                                    ddi: settings.ddiDirectory,
                                    launch: _launch,
                                  ),
                                  structured: true,
                                ),
                              ),
                      ),
                      XButton(
                        label: 'Sign only (.ipa)',
                        icon: Icons.draw_outlined,
                        variant: XButtonVariant.secondary,
                        loading:
                            (_install?.isRunning ?? false) &&
                            _install!.title == 'Sign only',
                        loadingLabel: 'Signing…',
                        disabledReason: 'Choose an .ipa file first.',
                        onPressed:
                            settings.lastIpa == null ||
                                (_install?.isRunning ?? false)
                            ? null
                            : () => setState(
                                () => _install = services.jobs.run(
                                  'Sign only',
                                  XcrossCommands.sign(
                                    settings.lastIpa!,
                                    udid: settings.udid,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (_install != null) ...[
                    const SizedBox(height: XSpace.s3),
                    JobPanel(job: _install!, consoleHeight: 200),
                  ],
                ],
              ),
            ),
            XCard(
              title: 'Installed apps',
              trailing: XButton(
                label: 'Load apps',
                icon: Icons.apps,
                variant: XButtonVariant.secondary,
                loading: _appsJob?.isRunning ?? false,
                loadingLabel: 'Loading…',
                onPressed: _loadApps,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_apps == null && _appsJob == null)
                    const XNote('Lists the apps you installed on the iPhone.'),
                  if (_apps != null && _apps!.isEmpty && _appsJob != null)
                    JobDiagnostics(job: _appsJob!),
                  for (final app in _apps ?? const <InstalledApp>[])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${app.label}  ${app.version ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          XButton(
                            label: 'App info',
                            variant: XButtonVariant.text,
                            onPressed: () => _appInfo(app.bundleId),
                          ),
                          XButton(
                            label: 'Logs',
                            variant: XButtonVariant.text,
                            onPressed: () {
                              settings.update((s) => s.logApp = app.bundleId);
                              services.app.go(Destination.logs);
                            },
                          ),
                        ],
                      ),
                    ),
                  if (_info != null) ...[
                    const Divider(height: XSpace.s6),
                    AppInfoView(info: _info!),
                  ] else if (_infoJob != null && !_infoJob!.isRunning)
                    JobDiagnostics(job: _infoJob!),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
