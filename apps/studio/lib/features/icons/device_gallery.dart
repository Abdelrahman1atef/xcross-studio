// Feature 026: the icon and splash on every screen. The CLI draws the images;
// this only places them, in each device's own points, so a frame shows what
// that device would.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import 'device_catalog.dart';
import 'target_previews.dart';

/// What the frames show: the images are 2 pixels per point (or dp).
class GalleryContent {
  const GalleryContent({
    this.name = 'App',
    this.icon,
    this.adaptiveIcon,
    this.shape = 'squircle',
    this.background = Colors.white,
    this.darkBackground,
    this.android12Background,
    this.darkAndroid12Background,
    this.logo,
    this.darkLogo,
    this.ipadLogo,
    this.darkIpadLogo,
    this.androidLogo,
    this.darkAndroidLogo,
    this.android12,
    this.darkAndroid12,
    this.branding,
    this.darkBranding,
    this.brandingWidth = 180,
    this.brandingBottom = 32,
    this.iosLogoScale = 2,
    this.notes = const [],
  });

  final String name;

  /// The icon iOS shows, and the one Android masks with its launcher's shape.
  final Uint8List? icon;
  final Uint8List? adaptiveIcon;
  final String shape;

  final Color background;
  final Color? darkBackground;
  final Color? android12Background;
  final Color? darkAndroid12Background;

  /// iOS's launch image, with any branding in it.
  final Uint8List? logo;
  final Uint8List? darkLogo;

  /// iPad's own launch image, when it has another size.
  final Uint8List? ipadLogo;
  final Uint8List? darkIpadLogo;

  /// Android's logo, without branding; [logo] when there is no branding.
  final Uint8List? androidLogo;
  final Uint8List? darkAndroidLogo;
  final Uint8List? android12;
  final Uint8List? darkAndroid12;
  final Uint8List? branding;
  final Uint8List? darkBranding;
  final double brandingWidth;
  final double brandingBottom;

  /// Pixels per point of [logo].
  final double iosLogoScale;

  /// What is missing, and how to make it.
  final List<String> notes;
}

/// The gallery's choices. Kept by the page, so they survive a tab change.
class GalleryFilters {
  final families = {
    DeviceFamily.iPhone,
    DeviceFamily.iPad,
    DeviceFamily.androidPhone,
    DeviceFamily.androidTablet,
    DeviceFamily.custom,
  };
  bool landscape = false;
  bool light = true;
  bool dark = false;
  bool splash = true;
  bool home = true;
  bool guides = false;

  /// Android 12 and newer draw a splash differently from Android 11 and older.
  bool android12 = true;
  final custom = <DeviceScreen>[];
}

/// Frames for every chosen screen.
class DeviceGallery extends StatefulWidget {
  const DeviceGallery({
    super.key,
    required this.content,
    required this.filters,
  });

  final GalleryContent content;
  final GalleryFilters filters;

  @override
  State<DeviceGallery> createState() => _DeviceGalleryState();
}

class _DeviceGalleryState extends State<DeviceGallery> {
  final _width = TextEditingController();
  final _height = TextEditingController();
  bool _customAndroid = false;
  String? _customError;

  static const smallest = 100.0;
  static const largest = 5000.0;

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _addCustom() {
    final width = double.tryParse(_width.text.trim());
    final height = double.tryParse(_height.text.trim());
    bool valid(double? value) =>
        value != null && value >= smallest && value <= largest;
    if (!valid(width) || !valid(height)) {
      setState(
        () => _customError =
            'Enter a width and height from ${smallest.round()} to '
            '${largest.round()}.',
      );
      return;
    }
    setState(() {
      _customError = null;
      widget.filters.custom.add(
        DeviceScreen(
          name: 'Custom',
          family: DeviceFamily.custom,
          width: width!,
          height: height!,
          android: _customAndroid,
        ),
      );
      _width.clear();
      _height.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filters = widget.filters;
    final content = widget.content;
    void update(VoidCallback change) => setState(change);
    final screens = [...deviceScreens, ...filters.custom];
    final showAndroid = filters.families.any(
      (family) =>
          family == DeviceFamily.androidPhone ||
          family == DeviceFamily.androidTablet,
    );
    Widget chip(String label, bool selected, ValueChanged<bool> onSelected) =>
        FilterChip(
          label: Text(label),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: onSelected,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final note in content.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: XSpace.s2),
            child: XNote(note),
          ),
        Wrap(
          spacing: XSpace.s1,
          runSpacing: XSpace.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final family in DeviceFamily.values)
              if (family != DeviceFamily.custom || filters.custom.isNotEmpty)
                chip(
                  family.label,
                  filters.families.contains(family),
                  (value) => update(
                    () => value
                        ? filters.families.add(family)
                        : filters.families.remove(family),
                  ),
                ),
          ],
        ),
        const SizedBox(height: XSpace.s2),
        Wrap(
          spacing: XSpace.s3,
          runSpacing: XSpace.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Portrait')),
                ButtonSegment(value: true, label: Text('Landscape')),
              ],
              selected: {filters.landscape},
              onSelectionChanged: (choice) =>
                  update(() => filters.landscape = choice.first),
            ),
            Wrap(
              spacing: XSpace.s1,
              children: [
                chip('Light', filters.light, (value) {
                  update(() {
                    filters.light = value || !filters.dark;
                  });
                }),
                chip('Dark', filters.dark, (value) {
                  update(() {
                    filters.dark = value || !filters.light;
                  });
                }),
              ],
            ),
            Wrap(
              spacing: XSpace.s1,
              children: [
                chip('Splash', filters.splash, (value) {
                  update(() {
                    filters.splash = value || !filters.home;
                  });
                }),
                chip('Home icon', filters.home, (value) {
                  update(() {
                    filters.home = value || !filters.splash;
                  });
                }),
              ],
            ),
            if (showAndroid)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Android 12+')),
                  ButtonSegment(
                    value: false,
                    label: Text('Android 11 and older'),
                  ),
                ],
                selected: {filters.android12},
                onSelectionChanged: (choice) =>
                    update(() => filters.android12 = choice.first),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Safe area guides', style: XType.support),
                Switch(
                  value: filters.guides,
                  onChanged: (value) => update(() => filters.guides = value),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: XSpace.s2),
        _customRow(),
        for (final family in DeviceFamily.values)
          if (filters.families.contains(family))
            if (screens.where((s) => s.family == family).toList()
                case final group when group.isNotEmpty) ...[
              const SizedBox(height: XSpace.s4),
              Text(
                family.label,
                style: XType.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: XSpace.s2),
              Wrap(
                spacing: XSpace.s4,
                runSpacing: XSpace.s4,
                children: [
                  for (final screen in group)
                    _DeviceCard(
                      screen: screen,
                      content: content,
                      filters: filters,
                    ),
                ],
              ),
            ],
      ],
    );
  }

  Widget _customRow() {
    Widget field(TextEditingController controller, String label) => SizedBox(
      width: 110,
      child: XTextField(controller: controller, label: label),
    );
    return Wrap(
      spacing: XSpace.s2,
      runSpacing: XSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        field(_width, 'Width'),
        field(_height, 'Height'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('iOS')),
            ButtonSegment(value: true, label: Text('Android')),
          ],
          selected: {_customAndroid},
          onSelectionChanged: (choice) =>
              setState(() => _customAndroid = choice.first),
        ),
        XButton(
          label: 'Add a screen',
          icon: Icons.add,
          variant: XButtonVariant.secondary,
          onPressed: _addCustom,
        ),
        if (_customError case final error?) XNote(error),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.screen,
    required this.content,
    required this.filters,
  });

  final DeviceScreen screen;
  final GalleryContent content;
  final GalleryFilters filters;

  @override
  Widget build(BuildContext context) {
    final appearances = [if (filters.light) false, if (filters.dark) true];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: XSpace.s2,
          runSpacing: XSpace.s2,
          children: [
            for (final dark in appearances) ...[
              if (filters.splash)
                DeviceFrame(
                  key: ValueKey(
                    '${screen.name}-${screen.sizeLabel}-splash-$dark',
                  ),
                  screen: screen,
                  content: content,
                  landscape: filters.landscape,
                  dark: dark,
                  android12: filters.android12,
                  guides: filters.guides,
                ),
              if (filters.home)
                DeviceFrame(
                  key: ValueKey(
                    '${screen.name}-${screen.sizeLabel}-home-$dark',
                  ),
                  screen: screen,
                  content: content,
                  landscape: filters.landscape,
                  dark: dark,
                  android12: filters.android12,
                  guides: filters.guides,
                  home: true,
                ),
            ],
          ],
        ),
        const SizedBox(height: XSpace.s1),
        SizedBox(
          width: 240,
          child: Text(
            '${screen.name}\n${screen.sizeLabel}',
            style: XType.support,
          ),
        ),
      ],
    );
  }
}

/// One device, drawn in its own points so everything keeps its true size
/// relative to the screen.
class DeviceFrame extends StatelessWidget {
  const DeviceFrame({
    super.key,
    required this.screen,
    required this.content,
    this.landscape = false,
    this.dark = false,
    this.home = false,
    this.android12 = true,
    this.guides = false,
    this.scale = pointScale,
  });

  final DeviceScreen screen;
  final GalleryContent content;
  final bool landscape;
  final bool dark;

  /// The home screen with the icon, instead of the splash.
  final bool home;
  final bool android12;
  final bool guides;

  /// Logical pixels per point: the same for all, so an iPad is larger than a
  /// phone by what it really is.
  final double scale;

  static const pointScale = 0.26;
  static const _bezel = 3.0;

  double get _width => landscape ? screen.height : screen.width;
  double get _height => landscape ? screen.width : screen.height;

  @override
  Widget build(BuildContext context) {
    final corner = screen.corner * scale;
    return RepaintBoundary(
      child: Container(
        width: _width * scale + _bezel * 2,
        height: _height * scale + _bezel * 2,
        padding: const EdgeInsets.all(_bezel),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(corner + _bezel),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(corner),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: _width,
              height: _height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (home) _homeScreen() else _splash(),
                  ?_cutout(),
                  if (guides) ..._guides(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(Uint8List bytes, {double scale = 2, double? width}) =>
      Image.memory(
        bytes,
        scale: scale,
        width: width,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );

  /// Centred at its own size: a launch screen does not scale its image, so one
  /// too large for this screen is cut off here too.
  Widget _centred(Uint8List? bytes, {double scale = 2}) => bytes == null
      ? const SizedBox.shrink()
      : OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: _image(bytes, scale: scale),
        );

  Widget _branding(double bottom, {double? maxWidth}) {
    final bytes = dark
        ? content.darkBranding ?? content.branding
        : content.branding;
    if (bytes == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Center(
        child: _image(bytes, width: maxWidth ?? content.brandingWidth),
      ),
    );
  }

  Widget _splash() {
    final background = dark
        ? content.darkBackground ?? content.background
        : content.background;
    if (!screen.android) {
      final ipad = screen.family == DeviceFamily.iPad;
      final light = ipad ? content.ipadLogo ?? content.logo : content.logo;
      final darkImage = ipad
          ? content.darkIpadLogo ?? content.darkLogo
          : content.darkLogo;
      return ColoredBox(
        color: background,
        child: _centred(
          dark ? darkImage ?? light : light,
          scale: content.iosLogoScale,
        ),
      );
    }
    if (android12) {
      // Android 12 draws its own screen: an icon, a colour and a fixed place
      // for branding, about 60 dp up and at most 200 dp wide. It shows the icon
      // through a circle, 192 dp across, or 160 dp with an icon background, and
      // what falls outside is masked.
      final iconBackground = dark
          ? content.darkAndroid12Background ?? content.android12Background
          : content.android12Background;
      final circle = iconBackground == null ? 192.0 : 160.0;
      return ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: ClipOval(
                child: SizedBox(
                  key: const ValueKey('android12-circle'),
                  width: circle,
                  height: circle,
                  child: ColoredBox(
                    color: iconBackground ?? Colors.transparent,
                    child: _centred(
                      dark
                          ? content.darkAndroid12 ?? content.android12
                          : content.android12,
                    ),
                  ),
                ),
              ),
            ),
            _branding(60, maxWidth: min(content.brandingWidth, 200)),
            if (guides) Center(child: Android12Guide(diameter: circle)),
          ],
        ),
      );
    }
    return ColoredBox(
      color: background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _centred(
            dark
                ? content.darkAndroidLogo ??
                      content.androidLogo ??
                      content.darkLogo ??
                      content.logo
                : content.androidLogo ?? content.logo,
          ),
          _branding(content.brandingBottom),
        ],
      ),
    );
  }

  Widget _homeScreen() {
    final size = screen.android ? 56.0 : (screen.isTablet ? 76.0 : 60.0);
    final icon = screen.android
        ? content.adaptiveIcon ?? content.icon
        : content.icon;
    final shape = screen.android
        ? AndroidIconPreview.shapeOf(content.shape, size)
        : RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(size * 0.2237),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF14161F), Color(0xFF2A2436)]
              : const [Color(0xFF8FB7E8), Color(0xFFD9C8EE)],
        ),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            28,
            (landscape ? 0 : screen.safeTop) + 28,
            28,
            0,
          ),
          child: SizedBox(
            width: size + 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size,
                  height: size,
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: const Color(0x33FFFFFF),
                    shape: shape,
                  ),
                  child: icon == null
                      ? null
                      : Image.memory(
                          icon,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  content.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _cutout() {
    if (screen.cutout == DeviceCutout.none) return null;
    final (width, height, top, radius) = switch (screen.cutout) {
      DeviceCutout.notch => (160.0, 30.0, 0.0, 16.0),
      DeviceCutout.island => (124.0, 36.0, 11.0, 18.0),
      _ => (20.0, 20.0, 12.0, 10.0),
    };
    final shape = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return landscape
        ? Positioned(
            left: top,
            top: (_height - width) / 2,
            child: RotatedBox(quarterTurns: 1, child: shape),
          )
        : Positioned(top: top, left: (_width - width) / 2, child: shape);
  }

  List<Widget> _guides() {
    const color = Color(0x55FF9F0A);
    // A phone on its side keeps clear of the cutout on both sides.
    final phoneOnItsSide = landscape && !screen.isTablet;
    final top = phoneOnItsSide ? 0.0 : screen.safeTop;
    final side = phoneOnItsSide ? screen.safeTop : 0.0;
    final bottom = phoneOnItsSide && screen.safeBottom > 0
        ? 21.0
        : screen.safeBottom;
    return [
      if (top > 0)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: const ColoredBox(color: color),
        ),
      if (bottom > 0)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: bottom,
          child: const ColoredBox(color: color),
        ),
      if (side > 0) ...[
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: side,
          child: const ColoredBox(color: color),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: side,
          child: const ColoredBox(color: color),
        ),
      ],
    ];
  }
}

/// Every icon size: iOS's slots, Android's densities and launcher shapes.
class IconSizesSection extends StatelessWidget {
  const IconSizesSection({super.key, required this.content, this.ios = true});

  final GalleryContent content;

  /// Off where another card already shows the iOS slots from the real files.
  final bool ios;

  static const _largestShown = 96.0;

  Widget _tile(
    Uint8List? image,
    double pixels,
    String label,
    ShapeBorder shape,
  ) {
    final size = pixels / 2 > _largestShown ? _largestShown : pixels / 2;
    return SizedBox(
      width: 112,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _largestShown,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                width: size,
                height: size,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: const Color(0x22888888),
                  shape: shape,
                ),
                child: image == null
                    ? null
                    : Image.memory(
                        image,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
          const SizedBox(height: XSpace.s1),
          Text(label, style: XType.support),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = XType.body.copyWith(fontWeight: FontWeight.w600);
    final ios12 = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final android = content.adaptiveIcon ?? content.icon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ios) ...[
          Text('iOS', style: label),
          const SizedBox(height: XSpace.s2),
          Wrap(
            spacing: XSpace.s2,
            runSpacing: XSpace.s3,
            children: [
              for (final slot in iosIconSizes)
                _tile(
                  content.icon,
                  slot.points * slot.scale,
                  '${slot.label}\n${slot.points} pt @${slot.scale}x\n'
                  '${(slot.points * slot.scale).round()} px',
                  ios12,
                ),
            ],
          ),
          const SizedBox(height: XSpace.s4),
        ],
        Text('Android densities', style: label),
        const SizedBox(height: XSpace.s2),
        Wrap(
          spacing: XSpace.s2,
          runSpacing: XSpace.s3,
          children: [
            for (final (density, pixels) in androidIconDensities)
              _tile(
                android,
                pixels.toDouble(),
                '$density\n$pixels px',
                AndroidIconPreview.shapeOf(content.shape, pixels / 2),
              ),
          ],
        ),
        const SizedBox(height: XSpace.s4),
        Text('Android launcher shapes', style: label),
        const SizedBox(height: XSpace.s2),
        Wrap(
          spacing: XSpace.s2,
          runSpacing: XSpace.s3,
          children: [
            for (final shape in androidIconShapes)
              _tile(android, 144, shape, AndroidIconPreview.shapeOf(shape, 72)),
          ],
        ),
      ],
    );
  }
}
