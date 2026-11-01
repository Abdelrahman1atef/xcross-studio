import 'package:flutter/material.dart';

import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';
import '../state/job.dart';
import 'services.dart';
import 'widgets.dart';

/// Device & Install: pick the iPhone, run the project on it, install an IPA.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  List<ConnectedDevice>? _devices;
  Job? _listing;
  Job? _run;
  Job? _install;
  BuildMode _mode = BuildMode.release;
  bool _launch = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || (_listing?.isRunning ?? false)) return;
    final services = Services.of(context);
    final future = services.jobs.collect(
      'List devices',
      XcrossCommands.devices(),
    );
    setState(() => _listing = null);
    final (job, events) = await future;
    if (!mounted) return;
    final devices = events.whereType<ConnectedDevice>().toList();
    setState(() {
      _listing = job;
      _devices = devices;
    });
    final settings = services.settings;
    if (devices.length == 1 && settings.udid != devices.single.udid) {
      await settings.update((s) => s.udid = devices.single.udid);
    }
  }

  ConnectedDevice? _selected(String? udid) {
    for (final device in _devices ?? const <ConnectedDevice>[]) {
      if (device.udid == udid) return device;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    return Watch(
      listenable: settings,
      builder: (context) {
        final device = _selected(settings.udid);
        final legacy = device?.legacy ?? false;
        if (legacy && _mode == BuildMode.debug) _mode = BuildMode.release;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Section(
              title: 'iPhone',
              trailing: IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
              child: _deviceList(settings.udid, (udid) {
                settings.update((s) => s.udid = udid);
              }),
            ),
            Section(
              title: 'Run the project on the iPhone',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (settings.projectPath == null)
                    const Text('Choose a project on the Project page first.')
                  else
                    Text('Project: ${settings.projectPath}'),
                  const SizedBox(height: 8),
                  if (legacy)
                    const Text(
                      'iOS 15/16: debug (hot reload) needs a debugger and is '
                      'not supported; profile and release are signed, '
                      'installed and opened (through your developer disk '
                      'image if set below, otherwise tap the app icon).',
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SegmentedButton<BuildMode>(
                        segments: [
                          ButtonSegment(
                            value: BuildMode.debug,
                            label: const Text('Debug'),
                            enabled: !legacy,
                          ),
                          const ButtonSegment(
                            value: BuildMode.profile,
                            label: Text('Profile'),
                          ),
                          const ButtonSegment(
                            value: BuildMode.release,
                            label: Text('Release'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (m) =>
                            setState(() => _mode = m.first),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed:
                            settings.projectPath == null ||
                                (_run?.isRunning ?? false)
                            ? null
                            : () => setState(
                                () => _run = services.jobs.run(
                                  'Run (${_mode.name})',
                                  XcrossCommands.run(
                                    mode: _mode,
                                    udid: settings.udid,
                                  ),
                                  workingDirectory: settings.projectPath,
                                ),
                              ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Build & run'),
                      ),
                    ],
                  ),
                  if (_run != null) ...[
                    const SizedBox(height: 12),
                    JobOutputView(job: _run!, height: 320),
                  ],
                ],
              ),
            ),
            Section(
              title: 'Install an app (.ipa)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Signs the app with your Apple ID or API key and installs '
                    'it over USB (iOS 15+). Your file is never modified.',
                  ),
                  const SizedBox(height: 12),
                  PathField(
                    label: '.ipa file',
                    directory: false,
                    extensions: const ['ipa'],
                    value: settings.lastIpa,
                    onChanged: (path) =>
                        settings.update((s) => s.lastIpa = path),
                  ),
                  const SizedBox(height: 8),
                  PathField(
                    label: 'Developer disk image folder (iOS 15/16, optional)',
                    hint:
                        'DeveloperDiskImage.dmg + .signature from your own '
                        "Xcode's DeviceSupport, directly or in version "
                        'folders such as 16.4.',
                    value: settings.ddiDirectory,
                    onChanged: (path) =>
                        settings.update((s) => s.ddiDirectory = path),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Open after install'),
                        selected: _launch,
                        onSelected: (v) => setState(() => _launch = v),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
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
                                ),
                              ),
                        icon: const Icon(Icons.install_mobile),
                        label: const Text('Sign & install'),
                      ),
                    ],
                  ),
                  if (_install != null) ...[
                    const SizedBox(height: 12),
                    JobOutputView(job: _install!, height: 260),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _deviceList(String? selected, ValueChanged<String> onSelect) {
    final devices = _devices;
    final listing = _listing;
    if (devices == null) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Looking for iPhones…'),
        ],
      );
    }
    if (devices.isEmpty) {
      final problem = listing?.issues.firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            problem?.text ??
                'No iPhone is connected by USB. Connect it, unlock it and '
                    'tap "Trust" on the phone, then refresh.',
          ),
          if (listing != null && problem != null)
            for (final line in listing.lines.where(
              (l) => l.text.startsWith('hint:'),
            ))
              Text(line.text),
        ],
      );
    }
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (udid) {
        if (udid != null) onSelect(udid);
      },
      child: Column(
        children: [
          for (final device in devices)
            RadioListTile<String>(
              value: device.udid,
              title: Text(device.name),
              subtitle: Text(
                'iOS ${device.osVersion ?? '?'} · ${device.connection.toUpperCase()}'
                '${device.legacy ? ' · release/profile only' : ''}',
              ),
              secondary: const Icon(Icons.phone_iphone),
            ),
        ],
      ),
    );
  }
}
