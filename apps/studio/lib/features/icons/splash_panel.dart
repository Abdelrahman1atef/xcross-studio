// Feature 024: the splash tab. The CLI draws the logo canvas and writes the
// files; this names the choices and shows them on a phone.
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';
import 'device_catalog.dart';
import 'device_gallery.dart';
import 'preview_server.dart';
import 'studio_board.dart';
import 'studio_controls.dart';
import 'studio_model.dart';
import 'studio_panel.dart';

class SplashTab extends StatefulWidget {
  const SplashTab({
    super.key,
    required this.project,
    required this.onResult,
    required this.board,
  });

  final String? project;
  final ValueChanged<StudioResult> onResult;
  final StudioBoard board;

  @override
  State<SplashTab> createState() => _SplashTabState();
}

class _SplashTabState extends State<SplashTab> {
  final _design = SplashStudioDesign();
  PreviewServer? _server;
  bool _dark = false;
  bool _hasDark = false;
  Job? _job;
  SplashCheckReport? _check;
  String? _copyError;

  /// The logo is the icon's source, until another is chosen (AC-026-14).
  bool _logoFromIcon = false;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    if (project != null) {
      _design.restore(savedAssets(project, 'splash'), project);
      _hasDark = _design.darkBackground != null || _design.darkLogo != null;
    }
    widget.board
      ..splash = _design
      ..writeSplash = _write
      ..exportSplash = _exportTo
      ..addListener(_onBoard);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _server = PreviewServer(Services.of(context).jobs)..addListener(_publish);
      _changed();
    });
  }

  /// Follows the icon's source while no other logo is chosen.
  void _onBoard() {
    if (!mounted) return;
    final source = widget.board.iconSource;
    if ((_design.logo == null || _logoFromIcon) && source != _design.logo) {
      _design.logo = source;
      _logoFromIcon = source != null;
      _changed();
    } else {
      setState(() {});
    }
  }

  /// Hands the latest images to the other tabs.
  void _publish() {
    if (!mounted) return;
    widget.board
      ..splashImages = _design.logo == null
          ? const {}
          : _server?.images ?? const {}
      ..changed();
  }

  @override
  void dispose() {
    widget.board.removeListener(_onBoard);
    _server?.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    if (_design.logo == null) _publish();
    if (_design.logo == null || _design.invalid != null) return;
    _server?.request(_design.previewRequest());
  }

  Future<bool> _write(String project) async {
    final design = _design;
    final logo = design.logo;
    if (logo == null) return false;
    // What the saved design names has to stay with the project.
    final String kept;
    try {
      kept = await keepInProject(project, logo);
      Future<String?> keep(String? path) async =>
          path == null ? null : keepInProject(project, path);
      design.darkLogo = await keep(design.darkLogo);
      design.branding = await keep(design.branding);
      design.darkBranding = await keep(design.darkBranding);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _copyError = 'Could not copy ${error.path}: ${error.message}',
        );
      }
      return false;
    }
    if (mounted) setState(() => _copyError = null);
    return _run(
      XcrossCommands.splashGenerate(kept, design.options(), save: true),
      project: project,
      toProject: true,
    );
  }

  Future<void> _exportFolder() async {
    final folder = await getDirectoryPath(confirmButtonText: 'Export here');
    if (folder != null) await _exportTo(folder);
  }

  Future<void> _exportZip() async {
    final logo = _design.logo;
    if (logo == null) return;
    final location = await getSaveLocation(
      suggestedName: 'splash.zip',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Zip', extensions: ['zip']),
      ],
    );
    if (location == null) return;
    await _run(
      XcrossCommands.splashGenerate(
        logo,
        _design.options(),
        zip: location.path,
      ),
      project: widget.project,
    );
  }

  Future<bool> _exportTo(String folder) async {
    final logo = _design.logo;
    if (logo == null) return false;
    return _run(
      XcrossCommands.splashGenerate(logo, _design.options(), output: folder),
      project: widget.project,
    );
  }

  Future<void> _runCheck(String project) async {
    SplashCheckReport? report;
    final job = Services.of(context).jobs.run(
      'Check the splash',
      XcrossCommands.splashCheck(),
      workingDirectory: project,
      onEvent: (event) {
        if (event is SplashCheckReport) report = event;
      },
    );
    setState(() => _job = job);
    await job.done;
    if (mounted) setState(() => _check = report);
  }

  Future<bool> _run(
    List<String> command, {
    required String? project,
    bool toProject = false,
  }) async {
    SplashGenerateResult? result;
    final job = Services.of(context).jobs.run(
      toProject ? 'Write splash' : 'Export splash',
      command,
      workingDirectory: project,
      onEvent: (event) {
        if (event is SplashGenerateResult) result = event;
      },
    );
    setState(() {
      _job = job;
      _check = null;
    });
    final status = await job.done;
    if (!mounted) return false;
    setState(() {
      final written = result;
      if (written != null) {
        _check = SplashCheckReport(issues: written.issues);
      }
    });
    final written = result;
    if (status == JobStatus.succeeded && written != null) {
      final ios = toProject && written.written.any((f) => f.startsWith('ios/'));
      widget.onResult(
        StudioResult(
          'Wrote ${written.written.length} splash files'
          '${written.removed.isEmpty ? '' : ' and removed an old background image'}'
          '${written.backup == null ? '' : '. Replaced files are in ${written.backup}'}.'
          '${ios ? ' iOS keeps showing the splash it saved: to see this one, restart the iPhone, then install again. Deleting the app is not enough.' : ''}',
        ),
      );
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => StudioLayout(
    controls: _controls(),
    preview: _preview(),
    actions: _actions(),
  );

  Widget _controls() {
    final design = _design;
    void update(VoidCallback change) {
      change();
      _changed();
    }

    String? path(String? value) =>
        value == null || value.isEmpty ? null : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSection(
          'Logo',
          children: [
            XFilePickerField(
              label: 'Logo (PNG with a transparent background)',
              value: design.logo,
              directory: false,
              extensions: const ['png'],
              onChanged: (value) => update(() {
                design.logo = path(value);
                _logoFromIcon = false;
              }),
            ),
            if (_logoFromIcon)
              const XNote(
                "This is the icon's image. Pick a logo to use another one.",
              ),
            StudioSlider(
              label: 'Width',
              value: design.logoWidth,
              min: 16,
              max: 1024,
              unit: ' pt',
              onChanged: (value) => update(() => design.logoWidth = value),
            ),
            Row(
              children: [
                Switch(
                  value: design.separateSizes,
                  onChanged: (value) => update(() {
                    final width = value ? design.logoWidth : null;
                    design
                      ..ipadLogoWidth = width
                      ..androidLogoWidth = width
                      // Starts where it already is, not cut by the circle.
                      ..android12IconWidth = width == null
                          ? null
                          : min(width, design.android12SafeWidth);
                  }),
                ),
                const SizedBox(width: XSpace.s2),
                Expanded(
                  child: Text(
                    'A different size on each kind of device',
                    style: XType.support,
                  ),
                ),
              ],
            ),
            if (design.separateSizes) ...[
              StudioSlider(
                label: 'iPad',
                value: design.ipadLogoWidth ?? design.logoWidth,
                min: 16,
                max: 1024,
                unit: ' pt',
                onChanged: (value) =>
                    update(() => design.ipadLogoWidth = value),
              ),
              StudioSlider(
                label: 'Android',
                value: design.androidLogoWidth ?? design.logoWidth,
                min: 16,
                max: 1024,
                unit: ' dp',
                onChanged: (value) =>
                    update(() => design.androidLogoWidth = value),
              ),
              StudioSlider(
                label: 'Android 12+',
                value: design.android12IconWidth ?? design.android12SafeWidth,
                min: 16,
                max: SplashStudioDesign.android12MaxWidth,
                unit: ' dp',
                onChanged: (value) =>
                    update(() => design.android12IconWidth = value),
              ),
              XNote(
                'All iPhones share one size: iOS has one launch image for them. '
                'Android 12+ shows the logo through a circle, '
                '${design.android12IconBackground == null ? 192 : 160} dp '
                'across, and cuts what falls outside, as its phone shows.',
              ),
            ] else if (design.logoWidth > design.android12SafeWidth) ...[
              XNote(
                'Android 12+ keeps this logo at about '
                '${design.android12SafeWidth.round()} dp, so its circle does '
                'not cut it. Turn on a different size to choose it there.',
              ),
            ],
            StudioSides(
              label: 'Padding',
              sides: design.padding,
              max: 45,
              step: 0.5,
              onChanged: _changed,
            ),
            const XNote(
              'Padding makes the logo smaller inside its width. Different values '
              'also move it.',
            ),
            StudioSides(
              label: 'Margin',
              sides: design.margin,
              max: 1000,
              unit: ' pt',
              alwaysSplit: true,
              onChanged: _changed,
            ),
            const XNote(
              'Margin moves the logo by half the difference between opposite '
              'sides: a top of 80 moves it 40 down. Equal margins cancel out, '
              'because a splash centres its image.',
            ),
          ],
        ),
        StudioSection(
          'Background',
          children: [
            StudioColor(
              label: 'Colour',
              value: design.background,
              onChanged: (value) =>
                  update(() => design.background = value ?? '#FFFFFF'),
            ),
            StudioColor(
              label: 'Android 12+ icon background',
              value: design.android12IconBackground,
              allowNone: true,
              noneLabel: 'None',
              onChanged: (value) =>
                  update(() => design.android12IconBackground = value),
            ),
          ],
        ),
        StudioSection(
          'Dark mode',
          children: [
            Row(
              children: [
                Switch(
                  value: _hasDark,
                  onChanged: (value) => update(() {
                    _hasDark = value;
                    design.darkBackground = value
                        ? (design.darkBackground ?? '#000000')
                        : null;
                    if (!value) {
                      design.darkLogo = null;
                      _dark = false;
                    }
                  }),
                ),
                const SizedBox(width: XSpace.s2),
                Expanded(child: Text('A dark variant', style: XType.support)),
              ],
            ),
            if (_hasDark) ...[
              StudioColor(
                label: 'Dark colour',
                value: design.darkBackground,
                onChanged: (value) =>
                    update(() => design.darkBackground = value ?? '#000000'),
              ),
              StudioColor(
                label: 'Android 12+ icon background, dark',
                value: design.darkAndroid12IconBackground,
                allowNone: true,
                noneLabel: 'Same as light',
                onChanged: (value) =>
                    update(() => design.darkAndroid12IconBackground = value),
              ),
              XFilePickerField(
                label: 'Dark logo (optional)',
                value: design.darkLogo,
                directory: false,
                extensions: const ['png'],
                onChanged: (value) =>
                    update(() => design.darkLogo = path(value)),
              ),
            ],
          ],
        ),
        StudioSection(
          'Branding',
          children: [
            XFilePickerField(
              label: 'Image near the bottom (optional)',
              value: design.branding,
              directory: false,
              extensions: const ['png'],
              onChanged: (value) => update(() => design.branding = path(value)),
            ),
            if (_hasDark && design.branding != null)
              XFilePickerField(
                label: 'Dark branding (optional)',
                value: design.darkBranding,
                directory: false,
                extensions: const ['png'],
                onChanged: (value) =>
                    update(() => design.darkBranding = path(value)),
              ),
            if (design.branding != null) ...[
              StudioSlider(
                label: 'Width',
                value: design.brandingWidth,
                min: 16,
                max: 1024,
                unit: ' pt',
                onChanged: (value) =>
                    update(() => design.brandingWidth = value),
              ),
              StudioSlider(
                label: 'Height above bottom',
                value: design.brandingBottom,
                max: 500,
                unit: ' dp',
                onChanged: (value) =>
                    update(() => design.brandingBottom = value),
              ),
              const XNote(
                'The height is for Android 11 and older. iOS keeps branding '
                'inside its one image, and Android 12+ places it itself.',
              ),
            ],
          ],
        ),
        StudioSection(
          'Platforms',
          children: [
            Wrap(
              spacing: XSpace.s1,
              children: [
                FilterChip(
                  label: const Text('iOS'),
                  selected: design.ios,
                  onSelected: (value) => update(() => design.ios = value),
                ),
                FilterChip(
                  label: const Text('Android'),
                  selected: design.android,
                  onSelected: (value) => update(() => design.android = value),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _preview() {
    final design = _design;
    final error = _server?.error ?? _copyError;
    final invalid = design.invalid;
    final logo = design.logo;
    final content = widget.board.content();
    final iPhone = deviceScreens.firstWhere(
      (screen) => screen.name.contains('iPhone 16e'),
    );
    final android = deviceScreens.firstWhere(
      (screen) => screen.name == 'Common large phone',
    );
    final iPad = deviceScreens.firstWhere(
      (screen) => screen.name.startsWith('iPad Air 11'),
    );
    // What each really draws, not one image reused (AC-026-12). The All screens
    // tab has every other size.
    Widget phone(
      String label,
      DeviceScreen screen, {
      bool android12 = true,
      bool guides = false,
      double scale = 0.42,
    }) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DeviceFrame(
          key: ValueKey('splash-tab-$label'),
          screen: screen,
          content: content,
          dark: _dark,
          android12: android12,
          guides: guides,
          scale: scale,
        ),
        const SizedBox(height: XSpace.s1),
        Text(label, style: XType.support),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasDark)
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Light')),
                ButtonSegment(value: true, label: Text('Dark')),
              ],
              selected: {_dark},
              onSelectionChanged: (selection) =>
                  setState(() => _dark = selection.first),
            ),
          ),
        const SizedBox(height: XSpace.s3),
        if (error != null) ...[XNote(error), const SizedBox(height: XSpace.s2)],
        if (invalid != null) ...[
          XNote(invalid),
          const SizedBox(height: XSpace.s2),
        ],
        if (logo == null) ...[
          const XNote('Pick a logo to put it on these phones.'),
          const SizedBox(height: XSpace.s2),
        ],
        Wrap(
          spacing: XSpace.s3,
          runSpacing: XSpace.s3,
          children: [
            if (design.ios) phone('iPhone', iPhone),
            if (design.ios && design.ipadLogoWidth != null)
              phone('iPad', iPad, scale: 0.26),
            if (design.android) phone('Android', android, android12: false),
            if (design.android)
              phone('Android 12+ (safe circle)', android, guides: true),
          ],
        ),
        const SizedBox(height: XSpace.s3),
        // The icon next to it, as the user sees them one after the other
        // (AC-026-14).
        Text(
          'The icon with this splash',
          style: XType.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: XSpace.s2),
        Align(
          alignment: Alignment.centerLeft,
          child: DeviceFrame(
            key: const ValueKey('splash-tab-icon'),
            screen: deviceScreens.firstWhere(
              (screen) => screen.name.contains('iPhone 16e'),
            ),
            content: widget.board.content(),
            home: true,
            dark: _dark,
            scale: 0.3,
          ),
        ),
        const SizedBox(height: XSpace.s3),
        if (_check != null) ...[
          for (final issue in _check!.issues)
            Padding(
              padding: const EdgeInsets.only(bottom: XSpace.s1),
              child: XCheckRow(
                status: issue.severity == 'error'
                    ? XStatus.failed
                    : XStatus.warning,
                label: issue.message,
                detail: issue.hint,
              ),
            ),
          if (_check!.issues.isEmpty)
            const XCheckRow(status: XStatus.ready, label: 'No problems found.'),
        ],
      ],
    );
  }

  Widget _actions() {
    final project = widget.project;
    final running = _job?.isRunning ?? false;
    final disabled = _design.logo == null
        ? 'Pick a logo first'
        : _design.invalid;
    final logo = _design.logo;
    final job = _job;
    final buttons = Wrap(
      spacing: XSpace.s2,
      runSpacing: XSpace.s2,
      children: [
        XButton(
          label: 'Write splash to project',
          icon: Icons.save_outlined,
          loading: running,
          loadingLabel: 'Writing…',
          disabledReason:
              disabled ??
              (project == null ? 'Open a Flutter project first' : null),
          onPressed: running || disabled != null || project == null
              ? null
              : () => _write(project),
        ),
        XButton(
          label: 'Export splash…',
          icon: Icons.folder_outlined,
          variant: XButtonVariant.secondary,
          disabledReason: disabled,
          onPressed: running || disabled != null ? null : _exportFolder,
        ),
        XButton(
          label: 'Export zip…',
          icon: Icons.archive_outlined,
          variant: XButtonVariant.secondary,
          disabledReason: disabled,
          onPressed: running || disabled != null ? null : _exportZip,
        ),
        XButton(
          label: 'Check splash',
          icon: Icons.fact_check_outlined,
          variant: XButtonVariant.secondary,
          disabledReason: project == null
              ? 'Open a Flutter project first'
              : null,
          onPressed: running || project == null
              ? null
              : () => _runCheck(project),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (logo != null) ...[
          XCommandPreview(
            arguments: XcrossCommands.splashGenerate(logo, _design.options()),
          ),
          const SizedBox(height: XSpace.s2),
        ],
        buttons,
        // A write that ended well says so above; the rest needs its output.
        if (job != null && job.status != JobStatus.succeeded) ...[
          const SizedBox(height: XSpace.s2),
          JobConsole(job: job, height: 120, showTitle: false),
        ],
      ],
    );
  }
}
