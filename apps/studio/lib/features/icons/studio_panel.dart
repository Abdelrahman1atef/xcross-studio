// Feature 024: the icon and splash studio. Controls name the choices, the
// `xcross` CLI draws and writes.
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';
import 'clipart_set.dart';
import 'preview_server.dart';
import 'source_render.dart';
import 'splash_panel.dart';
import 'studio_controls.dart';
import 'studio_model.dart';
import 'target_previews.dart';

/// What a write or export did, for the page's summary.
class StudioResult {
  const StudioResult(this.message, {this.toProject = false});

  final String message;

  /// The project changed, so the page checks it again.
  final bool toProject;
}

/// The tabbed card on the App icon page.
class StudioPanel extends StatefulWidget {
  const StudioPanel({
    super.key,
    required this.project,
    required this.onClose,
    required this.onResult,
  });

  /// Null: nothing to write into; exports still work.
  final String? project;
  final VoidCallback onClose;
  final ValueChanged<StudioResult> onResult;

  @override
  State<StudioPanel> createState() => _StudioPanelState();
}

class _StudioPanelState extends State<StudioPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => XCard(
    title: 'Icon and splash studio',
    trailing: XIconButton(
      icon: Icons.close,
      tooltip: 'Close',
      onPressed: widget.onClose,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('App icon'),
                icon: Icon(Icons.apps),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Splash screen'),
                icon: Icon(Icons.smartphone),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (selection) =>
                setState(() => _tab = selection.first),
          ),
        ),
        const SizedBox(height: XSpace.s3),
        // Both stay alive, so switching tabs keeps what was chosen.
        Visibility(
          visible: _tab == 0,
          maintainState: true,
          child: _IconTab(project: widget.project, onResult: widget.onResult),
        ),
        Visibility(
          visible: _tab == 1,
          maintainState: true,
          child: SplashTab(project: widget.project, onResult: widget.onResult),
        ),
      ],
    ),
  );
}

/// Target names, as the strip shows them.
const _targetLabels = {
  'ios': 'iOS',
  'android': 'Android',
  'notification': 'Notification',
  'web': 'Web',
  'macos': 'macOS',
  'watchos': 'watchOS',
  'tvos': 'tvOS',
  'android-tv': 'Android TV',
  'play-banner': 'Play Store banner',
};

const _projectTargets = ['ios', 'android', 'notification', 'web', 'macos'];
const _exportTargets = ['watchos', 'tvos', 'android-tv', 'play-banner'];

const _fontFamilies = {
  '': 'App default',
  'Segoe UI': 'Segoe UI',
  'Arial': 'Arial',
  'Verdana': 'Verdana',
  'Georgia': 'Georgia',
  'Times New Roman': 'Times New Roman',
  'Courier New': 'Courier New',
  'Impact': 'Impact',
};

class _IconTab extends StatefulWidget {
  const _IconTab({required this.project, required this.onResult});

  final String? project;
  final ValueChanged<StudioResult> onResult;

  @override
  State<_IconTab> createState() => _IconTabState();
}

class _IconTabState extends State<_IconTab> {
  final _design = IconStudioDesign();
  PreviewServer? _server;
  final _text = TextEditingController(text: 'Aa');
  final _name = TextEditingController(text: 'ic_launcher');
  final _badge = TextEditingController();
  final _search = TextEditingController();

  String _previewTarget = 'ios';

  /// The source as a PNG: the picked file, or text and clipart rendered.
  String? _sourcePng;
  String? _sourceFor;
  String? _sourceError;
  String? _badgePng;
  String? _badgeFor;
  Job? _job;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    if (project != null) {
      final saved = savedAssets(project, 'icons');
      _design.restore(saved, project);
      _name.text = _design.name;
      if (saved['targets'] == null) {
        // What the project has a folder for (AC-024-15).
        final present = [
          for (final target in const ['ios', 'android', 'web', 'macos'])
            if (Directory(p.join(project, target)).existsSync()) target,
        ];
        if (present.isNotEmpty) {
          _design.targets
            ..clear()
            ..addAll(present);
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _server = PreviewServer(Services.of(context).jobs)
        ..addListener(_onPreview);
      unawaited(_changed());
    });
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _server?.dispose();
    _text.dispose();
    _name.dispose();
    _badge.dispose();
    _search.dispose();
    super.dispose();
  }

  /// What identifies the source, to render it only when it changes.
  String get _sourceKey => switch (_design.sourceType) {
    IconSourceType.image => 'image:${_design.imagePath}',
    IconSourceType.text =>
      'text:${_design.text}:${_design.fontFamily}:'
          '${_design.bold}:${_design.italic}',
    IconSourceType.clipart =>
      'clipart:${_design.clipart?.name}:${_design.clipartStyle.name}',
  };

  Future<void> _changed() async {
    final server = _server;
    if (server == null) return;
    setState(() {});
    final source = await _prepareSource();
    final badge = await _prepareBadge();
    if (!mounted || source == null || _design.invalid != null) return;
    server.request(_design.previewRequest(source, badgeImage: badge));
  }

  Future<String?> _prepareSource() async {
    final key = _sourceKey;
    if (key == _sourceFor) return _sourcePng;
    _sourceFor = key;
    _sourceError = null;
    final design = _design;
    try {
      final picked = design.imagePath;
      final clipart = design.clipart;
      if (design.sourceType == IconSourceType.image &&
          (picked == null || p.extension(picked).toLowerCase() == '.png')) {
        _sourcePng = picked;
      } else if (design.sourceType == IconSourceType.clipart &&
          clipart == null) {
        _sourcePng = null;
      } else {
        final bytes = await switch (design.sourceType) {
          IconSourceType.image => SourceRender.toPng(picked!),
          IconSourceType.text => SourceRender.text(
            design.text,
            fontFamily: design.fontFamily,
            bold: design.bold,
            italic: design.italic,
          ),
          IconSourceType.clipart => SourceRender.clipart(
            clipart!.of(design.clipartStyle),
          ),
        };
        // Typed on meanwhile: the newer call draws it.
        if (key != _sourceKey) return null;
        _sourcePng = await _writeTemp('source.png', bytes);
      }
    } on Exception catch (error) {
      _sourcePng = null;
      _sourceError = 'Could not read that image: $error';
    }
    if (mounted) setState(() {});
    return _sourcePng;
  }

  Future<String?> _prepareBadge() async {
    final text = _design.badge.trim();
    if (text.isEmpty) {
      _badgePng = _design.savedBadge;
      _badgeFor = null;
      return _badgePng;
    }
    final color = StudioColor.parse(_design.badgeColor) ?? Colors.red;
    final key = '$text:${_design.badgeColor}';
    if (key != _badgeFor) {
      _badgeFor = key;
      _badgePng = await _writeTemp(
        'badge.png',
        await SourceRender.badge(text, color),
      );
    }
    return _badgePng;
  }

  Future<String> _writeTemp(String name, List<int> bytes) async {
    final file = File(p.join(_server!.folder.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  List<String> _command({
    required String source,
    required Iterable<String> targets,
    String? badge,
    String? output,
    String? zip,
    bool save = false,
  }) => XcrossCommands.iconsDesign(
    source,
    {
      ..._design.options(badgeImage: badge ?? _badgePng),
      'targets': targets.join(','),
    },
    flags: _design.flags(),
    output: output,
    zip: zip,
    save: save,
  );

  /// In the project: what the saved settings name is copied into it first, so
  /// it stays there for a teammate.
  Future<void> _write(String project) async {
    final source = _sourcePng;
    final badge = _badgePng;
    final background = _design.backgroundImage;
    if (source == null) return;
    final String keptSource;
    final String? keptBadge;
    try {
      keptSource = await keepInProject(
        project,
        source,
        name: _design.sourceType == IconSourceType.image
            ? null
            : 'icon-source.png',
      );
      keptBadge = badge == null
          ? null
          : await keepInProject(project, badge, name: 'icon-badge.png');
      if (background != null) {
        _design.backgroundImage = await keepInProject(project, background);
      }
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _sourceError = 'Could not copy ${error.path}: ${error.message}',
        );
      }
      return;
    }
    await _run(
      _command(
        source: keptSource,
        badge: keptBadge,
        targets: _design.targets,
        save: true,
      ),
      project: project,
      toProject: true,
    );
  }

  Future<void> _exportFolder() async {
    final source = _sourcePng;
    if (source == null) return;
    final folder = await getDirectoryPath(confirmButtonText: 'Export here');
    if (folder == null) return;
    await _run(
      _command(
        source: source,
        targets: {..._design.targets, ..._design.exportTargets},
        output: folder,
      ),
      project: widget.project,
    );
  }

  Future<void> _exportZip() async {
    final source = _sourcePng;
    if (source == null) return;
    final location = await getSaveLocation(
      suggestedName: 'app-icons.zip',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Zip', extensions: ['zip']),
      ],
    );
    if (location == null) return;
    await _run(
      _command(
        source: source,
        targets: {..._design.targets, ..._design.exportTargets},
        zip: location.path,
      ),
      project: widget.project,
    );
  }

  Future<void> _run(
    List<String> command, {
    required String? project,
    bool toProject = false,
  }) async {
    IconsGenerateResult? result;
    final job = Services.of(context).jobs.run(
      toProject ? 'Write icons' : 'Export icons',
      command,
      workingDirectory: project,
      onEvent: (event) {
        if (event is IconsGenerateResult) result = event;
      },
    );
    setState(() => _job = job);
    final status = await job.done;
    if (!mounted) return;
    setState(() {});
    final written = result;
    if (status == JobStatus.succeeded && written != null) {
      widget.onResult(
        StudioResult(
          'Wrote ${written.written.length} icon files'
          '${written.backup == null ? '' : '. Replaced files are in ${written.backup}'}.',
          toProject: toProject,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSection(
          'Source',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<IconSourceType>(
                segments: const [
                  ButtonSegment(
                    value: IconSourceType.image,
                    label: Text('Image'),
                  ),
                  ButtonSegment(
                    value: IconSourceType.text,
                    label: Text('Text'),
                  ),
                  ButtonSegment(
                    value: IconSourceType.clipart,
                    label: Text('Clipart'),
                  ),
                ],
                selected: {design.sourceType},
                onSelectionChanged: (selection) =>
                    update(() => design.sourceType = selection.first),
              ),
            ),
            ...switch (design.sourceType) {
              IconSourceType.image => [
                XFilePickerField(
                  label: 'Image',
                  value: design.imagePath,
                  directory: false,
                  extensions: const [
                    'png',
                    'jpg',
                    'jpeg',
                    'webp',
                    'bmp',
                    'gif',
                  ],
                  onChanged: (value) => update(
                    () => design.imagePath = value == null || value.isEmpty
                        ? null
                        : value,
                  ),
                ),
                Row(
                  children: [
                    Switch(
                      value: design.trim,
                      onChanged: (value) => update(() => design.trim = value),
                    ),
                    const SizedBox(width: XSpace.s2),
                    Expanded(
                      child: Text(
                        'Trim transparent or one-colour borders',
                        style: XType.support,
                      ),
                    ),
                  ],
                ),
              ],
              IconSourceType.text => [
                XTextField(
                  controller: _text,
                  label: 'Text',
                  onChanged: (value) => update(() => design.text = value),
                ),
                StudioDropdown(
                  label: 'Font',
                  value: design.fontFamily ?? '',
                  options: {
                    ..._fontFamilies,
                    if (design.fontFamily != null &&
                        !_fontFamilies.containsKey(design.fontFamily))
                      design.fontFamily!: 'Picked font',
                  },
                  onChanged: (value) => update(
                    () => design.fontFamily = value.isEmpty ? null : value,
                  ),
                ),
                Wrap(
                  spacing: XSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Bold'),
                      selected: design.bold,
                      onSelected: (value) => update(() => design.bold = value),
                    ),
                    FilterChip(
                      label: const Text('Italic'),
                      selected: design.italic,
                      onSelected: (value) =>
                          update(() => design.italic = value),
                    ),
                    XButton(
                      label: 'Font file…',
                      icon: Icons.font_download_outlined,
                      variant: XButtonVariant.secondary,
                      onPressed: _pickFont,
                    ),
                  ],
                ),
              ],
              IconSourceType.clipart => [_clipartPicker(update)],
            },
            if (_sourceError != null) XNote(_sourceError!),
          ],
        ),
        StudioSection(
          'Foreground',
          children: [
            StudioColor(
              label: 'Colour',
              value: design.foreground,
              allowNone: true,
              noneLabel: 'Original',
              onChanged: (value) => update(() => design.foreground = value),
            ),
            StudioDropdown(
              label: 'Effect',
              value: design.effect,
              options: const {
                'none': 'None',
                'drop-shadow': 'Drop shadow',
                'cast-shadow': 'Cast shadow',
                'score': 'Score',
              },
              onChanged: (value) => update(() => design.effect = value),
            ),
            StudioSides(
              label: 'Padding',
              sides: design.padding,
              max: 45,
              onChanged: _changed,
            ),
          ],
        ),
        StudioSection(
          'Background',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                // Four labels fill the column; a tick would wrap them.
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'color', label: Text('Colour')),
                  ButtonSegment(value: 'gradient', label: Text('Gradient')),
                  ButtonSegment(value: 'mesh', label: Text('Mesh')),
                  ButtonSegment(value: 'image', label: Text('Image')),
                ],
                selected: {design.backgroundType},
                onSelectionChanged: (selection) => update(() {
                  design.backgroundType = selection.first;
                  // Auto is one colour taken from the image, not a blend.
                  if (selection.first != 'color' &&
                      design.background == 'auto') {
                    design.background = '#0A84FF';
                  }
                }),
              ),
            ),
            if (design.backgroundType == 'image')
              XFilePickerField(
                label: 'Background image (PNG)',
                value: design.backgroundImage,
                directory: false,
                extensions: const ['png'],
                onChanged: (value) => update(
                  () => design.backgroundImage = value == null || value.isEmpty
                      ? null
                      : value,
                ),
              )
            else ...[
              StudioColor(
                label: design.backgroundType == 'color' ? 'Colour' : 'Colour 1',
                value: design.background,
                allowAuto: design.backgroundType == 'color',
                onChanged: (value) =>
                    update(() => design.background = value ?? 'auto'),
              ),
              if (design.backgroundType != 'color')
                StudioColor(
                  label: 'Colour 2',
                  value: design.background2,
                  onChanged: (value) =>
                      update(() => design.background2 = value ?? '#000000'),
                ),
              if (design.backgroundType == 'gradient')
                StudioSlider(
                  label: 'Angle',
                  value: design.gradientAngle,
                  max: 360,
                  unit: '°',
                  onChanged: (value) =>
                      update(() => design.gradientAngle = value),
                ),
              if (design.backgroundType == 'mesh') ...[
                StudioColor(
                  label: 'Colour 3',
                  value: design.background3,
                  onChanged: (value) =>
                      update(() => design.background3 = value ?? '#000000'),
                ),
                StudioColor(
                  label: 'Colour 4',
                  value: design.background4,
                  onChanged: (value) =>
                      update(() => design.background4 = value ?? '#000000'),
                ),
              ],
            ],
            StudioDropdown(
              label: 'Texture',
              value: design.texture,
              options: const {
                'none': 'None',
                'argyle': 'Argyle',
                'concentric': 'Concentric',
                'contour': 'Contour',
                'coral': 'Coral',
                'fabric': 'Fabric',
                'halftone': 'Halftone',
                'maze': 'Maze',
                'mosaic': 'Mosaic',
                'polka': 'Polka',
                'stipple': 'Stipple',
                'waves': 'Waves',
              },
              onChanged: (value) => update(() => design.texture = value),
            ),
          ],
        ),
        StudioSection(
          'More',
          children: [
            XTextField(
              controller: _badge,
              label: 'Badge text (optional)',
              onChanged: (value) => update(() => design.badge = value),
            ),
            if (design.badge.trim().isEmpty && design.savedBadge != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'The saved design has a badge image. Type to replace it.',
                      style: XType.support,
                    ),
                  ),
                  XIconButton(
                    icon: Icons.close,
                    tooltip: 'Remove the badge',
                    onPressed: () => update(() => design.savedBadge = null),
                  ),
                ],
              ),
            if (design.badge.trim().isNotEmpty)
              StudioColor(
                label: 'Badge colour',
                value: design.badgeColor,
                onChanged: (value) =>
                    update(() => design.badgeColor = value ?? '#E5484D'),
              ),
            XTextField(
              controller: _name,
              label: 'Android file name',
              onChanged: (value) => update(() => design.name = value.trim()),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'square', label: Text('Square')),
                  ButtonSegment(value: 'squircle', label: Text('Squircle')),
                  ButtonSegment(value: 'circle', label: Text('Circle')),
                ],
                selected: {design.shape},
                onSelectionChanged: (selection) =>
                    update(() => design.shape = selection.first),
              ),
            ),
            Row(
              children: [
                Switch(
                  value: design.themed,
                  onChanged: (value) => update(() => design.themed = value),
                ),
                const SizedBox(width: XSpace.s2),
                Expanded(
                  child: Text(
                    'Themed Android icon (Android 13+ tints it)',
                    style: XType.support,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickFont() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Font', extensions: ['ttf', 'otf']),
      ],
    );
    if (file == null) return;
    final family = await SourceRender.loadFont(file.path);
    _design.fontFamily = family;
    await _changed();
  }

  Widget _clipartPicker(void Function(VoidCallback) update) {
    final design = _design;
    final results = searchClipart(_search.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: XTextField(
                controller: _search,
                label: 'Search',
                prefixIcon: Icons.search,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: XSpace.s2),
            SizedBox(
              width: 120,
              child: StudioDropdown(
                label: 'Style',
                value: design.clipartStyle.name,
                options: const {
                  'filled': 'Filled',
                  'outline': 'Outline',
                  'round': 'Round',
                },
                onChanged: (value) => update(
                  () => design.clipartStyle = ClipartStyle.values.byName(value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: XSpace.s2),
        SizedBox(
          height: 176,
          child: results.isEmpty
              ? const XNote('No symbol has that name.')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 44,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final item = results[index];
                    final selected = design.clipart?.name == item.name;
                    return Tooltip(
                      message: item.name,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => update(() => design.clipart = item),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.2)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            item.of(design.clipartStyle),
                            semanticLabel: item.name,
                            size: 22,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _preview() {
    final images = _server?.images ?? const {};
    final error = _server?.error;
    final invalid = _design.invalid;
    final hasSource = _sourcePng != null;
    final project = widget.project;
    final running = _job?.isRunning ?? false;
    final source = _sourcePng;
    final disabled = !hasSource ? 'Choose a source first' : invalid;
    final preview = _previewTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: XSpace.s1,
          runSpacing: XSpace.s1,
          children: [
            for (final MapEntry(:key, value: label) in _targetLabels.entries)
              ChoiceChip(
                label: Text(label),
                selected: preview == key,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _previewTarget = key),
              ),
          ],
        ),
        const SizedBox(height: XSpace.s3),
        if (error != null) ...[XNote(error), const SizedBox(height: XSpace.s2)],
        if (invalid != null) ...[
          XNote(invalid),
          const SizedBox(height: XSpace.s2),
        ],
        if (!hasSource)
          const XNote('Pick an image, type some text or choose a symbol.')
        else if (images.isEmpty && error == null)
          const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (images.isNotEmpty)
          Wrap(
            spacing: XSpace.s4,
            runSpacing: XSpace.s3,
            children: [
              if (preview != 'tvos' &&
                  preview != 'android-tv' &&
                  preview != 'play-banner' &&
                  preview != 'notification')
                LargeIconPreview(bytes: images['full']),
              switch (preview) {
                'android' => AndroidIconPreview(
                  images: images,
                  shape: _design.shape,
                ),
                'notification' => NotificationPreview(images: images),
                'web' => WebIconPreview(images: images),
                'macos' => MacIconPreview(images: images),
                'watchos' => WatchIconPreview(images: images),
                'tvos' => BannerPreview(images: images, label: 'tvOS'),
                'android-tv' => BannerPreview(
                  images: images,
                  label: 'Android TV',
                ),
                'play-banner' => BannerPreview(
                  images: images,
                  label: 'Play Store feature graphic',
                ),
                _ => IosIconPreview(images: images),
              },
            ],
          ),
        const SizedBox(height: XSpace.s4),
        Text('Write to the project', style: XType.support),
        const SizedBox(height: XSpace.s1),
        Wrap(
          spacing: XSpace.s1,
          runSpacing: XSpace.s1,
          children: [
            for (final target in _projectTargets)
              FilterChip(
                label: Text(_targetLabels[target]!),
                selected: _design.targets.contains(target),
                visualDensity: VisualDensity.compact,
                onSelected: (value) => setState(() {
                  if (value) {
                    _design.targets.add(target);
                  } else {
                    _design.targets.remove(target);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: XSpace.s2),
        Text('Exports also include', style: XType.support),
        const SizedBox(height: XSpace.s1),
        Wrap(
          spacing: XSpace.s1,
          runSpacing: XSpace.s1,
          children: [
            for (final target in _exportTargets)
              FilterChip(
                label: Text(_targetLabels[target]!),
                selected: _design.exportTargets.contains(target),
                visualDensity: VisualDensity.compact,
                onSelected: (value) => setState(() {
                  if (value) {
                    _design.exportTargets.add(target);
                  } else {
                    _design.exportTargets.remove(target);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: XSpace.s3),
        if (source != null)
          XCommandPreview(
            arguments: _command(source: source, targets: _design.targets),
          ),
        const SizedBox(height: XSpace.s2),
        Wrap(
          spacing: XSpace.s2,
          runSpacing: XSpace.s2,
          children: [
            XButton(
              label: 'Write to project',
              icon: Icons.save_outlined,
              loading: running,
              loadingLabel: 'Writing…',
              disabledReason:
                  disabled ??
                  (project == null
                      ? 'Open a Flutter project first'
                      : _design.targets.isEmpty
                      ? 'Choose what to write'
                      : null),
              onPressed:
                  running ||
                      disabled != null ||
                      project == null ||
                      _design.targets.isEmpty
                  ? null
                  : () => _write(project),
            ),
            XButton(
              label: 'Export folder…',
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
