// Feature 024: the splash tab. The CLI draws the logo canvas and writes the
// files; this names the choices and shows them on a phone.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';
import 'preview_server.dart';
import 'studio_controls.dart';
import 'studio_model.dart';
import 'studio_panel.dart';
import 'target_previews.dart';

class SplashTab extends StatefulWidget {
  const SplashTab({super.key, required this.project, required this.onResult});

  final String? project;
  final ValueChanged<StudioResult> onResult;

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

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    if (project != null) {
      _design.restore(savedAssets(project, 'splash'), project);
      _hasDark = _design.darkBackground != null || _design.darkLogo != null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _server = PreviewServer(Services.of(context).jobs)
        ..addListener(_onPreview);
      _changed();
    });
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _server?.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    if (_design.logo == null || _design.invalid != null) return;
    _server?.request(_design.previewRequest());
  }

  Future<void> _write(String project) async {
    final design = _design;
    final logo = design.logo;
    if (logo == null) return;
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
      return;
    }
    if (mounted) setState(() => _copyError = null);
    await _run(
      XcrossCommands.splashGenerate(kept, design.options(), save: true),
      project: project,
      toProject: true,
    );
  }

  Future<void> _exportFolder() async {
    final logo = _design.logo;
    if (logo == null) return;
    final folder = await getDirectoryPath(confirmButtonText: 'Export here');
    if (folder == null) return;
    await _run(
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

  Future<void> _run(
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
    if (!mounted) return;
    setState(() {
      final written = result;
      if (written != null) {
        _check = SplashCheckReport(issues: written.issues);
      }
    });
    final written = result;
    if (status == JobStatus.succeeded && written != null) {
      widget.onResult(
        StudioResult(
          'Wrote ${written.written.length} splash files'
          '${written.backup == null ? '' : '. Replaced files are in ${written.backup}'}.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controls = _controls();
    final preview = _preview();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              preview,
              const SizedBox(height: XSpace.s3),
              controls,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 400, child: controls),
            const SizedBox(width: XSpace.s4),
            Expanded(child: preview),
          ],
        );
      },
    );
  }

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
              onChanged: (value) => update(() => design.logo = path(value)),
            ),
            StudioSlider(
              label: 'Width',
              value: design.logoWidth,
              min: 40,
              max: 300,
              unit: ' pt',
              onChanged: (value) => update(() => design.logoWidth = value),
            ),
            StudioSides(
              label: 'Padding',
              sides: design.padding,
              max: 45,
              onChanged: _changed,
            ),
            StudioSides(
              label: 'Margin',
              sides: design.margin,
              max: 200,
              unit: ' pt',
              onChanged: _changed,
            ),
            const XNote(
              'A launch screen centres its image, so a larger top margin moves '
              'the logo down, and a larger bottom margin moves it up.',
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
    final images = _server?.images ?? const {};
    final error = _server?.error ?? _copyError;
    final invalid = design.invalid;
    final project = widget.project;
    final running = _job?.isRunning ?? false;
    final logo = design.logo;
    final disabled = logo == null ? 'Pick a logo first' : invalid;
    final background = StudioColor.parse(
      _dark ? (design.darkBackground ?? design.background) : design.background,
    );
    final color = background ?? Colors.white;
    final image = _dark
        ? (images['darkLogo'] ?? images['logo'])
        : images['logo'];
    final android12 = _dark
        ? (images['darkAndroid12'] ?? images['android12'])
        : images['android12'];

    // The previews show a 390 pt wide phone; the images are 2 px per point.
    const phoneScale = SplashPhone.width / 390 / 2;
    // Android 12's icon is 2 px per dp on a 412 dp wide phone.
    const androidScale = SplashPhone.width / 412 / 2;
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
        if (logo == null)
          const XNote('Pick a logo to see the splash on a phone.')
        else
          Wrap(
            spacing: XSpace.s3,
            runSpacing: XSpace.s3,
            children: [
              if (design.ios)
                SplashPhone(
                  label: 'iPhone',
                  color: color,
                  image: image,
                  scale: phoneScale,
                ),
              if (design.android)
                SplashPhone(
                  label: 'Android',
                  color: color,
                  image: image,
                  scale: phoneScale,
                  radius: 18,
                ),
              if (design.android)
                SplashPhone(
                  label: 'Android 12+ (safe circle)',
                  color: color,
                  image: android12,
                  scale: androidScale,
                  radius: 18,
                  overlay: const Android12Guide(
                    diameter: 192 * SplashPhone.width / 412,
                  ),
                ),
            ],
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
          const SizedBox(height: XSpace.s2),
        ],
        if (logo != null)
          XCommandPreview(
            arguments: XcrossCommands.splashGenerate(logo, design.options()),
          ),
        const SizedBox(height: XSpace.s2),
        Wrap(
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
        ),
        if (_job != null) ...[
          const SizedBox(height: XSpace.s2),
          JobConsole(job: _job!, height: 120, showTitle: false),
        ],
      ],
    );
  }
}
