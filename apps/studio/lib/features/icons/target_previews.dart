// Feature 024: each platform's icon and splash, on a drawing of where it shows.
// The images are the CLI's; only the surroundings are drawn here.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

const _wallpaper = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3A4A6B), Color(0xFF1E2A44), Color(0xFF6B4A6B)],
);

Widget _image(Uint8List? bytes, {double? size, BoxFit fit = BoxFit.cover}) =>
    bytes == null
    ? SizedBox.square(dimension: size)
    : Image.memory(
        bytes,
        width: size,
        height: size,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );

class _Caption extends StatelessWidget {
  const _Caption(this.label, {required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: XSpace.s1),
      Text(label, style: XType.support),
    ],
  );
}

class _Screen extends StatelessWidget {
  const _Screen({required this.child, this.width = 300, this.height = 170});

  final Widget child;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    padding: const EdgeInsets.all(XSpace.s3),
    decoration: BoxDecoration(
      gradient: _wallpaper,
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );
}

/// An app on a home screen: the icon cut to [shape], with a name under it.
class _HomeIcon extends StatelessWidget {
  const _HomeIcon({required this.image, required this.shape});

  static const size = 60.0;

  final Uint8List? image;
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: _image(image, size: size),
      ),
      const SizedBox(height: 4),
      const Text(
        'App Name',
        style: TextStyle(color: Colors.white, fontSize: 11),
      ),
    ],
  );
}

ShapeBorder _ios(double size) => RoundedSuperellipseBorder(
  borderRadius: BorderRadius.circular(size * 0.225),
);

/// iOS: home screen and a notification.
class IosIconPreview extends StatelessWidget {
  const IosIconPreview({super.key, required this.images});

  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: XSpace.s3,
    runSpacing: XSpace.s3,
    children: [
      _Caption(
        'Home screen',
        child: _Screen(
          child: Center(
            child: _HomeIcon(
              image: images['full'],
              shape: _ios(_HomeIcon.size),
            ),
          ),
        ),
      ),
      _Caption(
        'Notification',
        child: _Screen(
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(XSpace.s2),
              decoration: BoxDecoration(
                color: const Color(0xE6F2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipPath(
                    clipper: ShapeBorderClipper(shape: _ios(32)),
                    child: _image(images['full'], size: 32),
                  ),
                  const SizedBox(width: XSpace.s2),
                  const Flexible(
                    child: Text(
                      'Your order is on its way',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Android: each launcher shape, as the launcher masks the adaptive layers.
class AndroidIconPreview extends StatelessWidget {
  const AndroidIconPreview({
    super.key,
    required this.images,
    required this.shape,
  });

  final Map<String, Uint8List> images;

  /// The chosen `--shape`, marked in its caption.
  final String shape;

  static ShapeBorder shapeOf(String name, double size) => switch (name) {
    'square' => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(size * 0.16),
    ),
    'circle' => const CircleBorder(),
    _ => RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(size * 0.38),
    ),
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: XSpace.s3,
    runSpacing: XSpace.s3,
    children: [
      for (final name in const ['square', 'squircle', 'circle'])
        _Caption(
          name == shape ? '${_title(name)} (legacy icon)' : _title(name),
          child: _Screen(
            width: 150,
            height: 130,
            child: Center(
              child: _HomeIcon(
                image: images['adaptive'],
                shape: shapeOf(name, _HomeIcon.size),
              ),
            ),
          ),
        ),
    ],
  );

  static String _title(String name) =>
      '${name[0].toUpperCase()}${name.substring(1)}';
}

/// Android's status bar and notification shade: white on whatever is behind.
class NotificationPreview extends StatelessWidget {
  const NotificationPreview({super.key, required this.images});

  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) {
    final shape = images['silhouette'];
    if (shape == null) {
      return const XNote(
        'The logo has no transparency and no one-colour border, so a '
        'notification icon would be a white square. Use a logo on a '
        'transparent background.',
      );
    }
    Widget bar(Color color) => Container(
      width: 220,
      padding: const EdgeInsets.symmetric(
        horizontal: XSpace.s3,
        vertical: XSpace.s2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text(
            '9:41',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: XSpace.s2),
          _image(shape, size: 18, fit: BoxFit.contain),
          const Spacer(),
          const Icon(Icons.wifi, color: Colors.white, size: 14),
          const Icon(Icons.battery_full, color: Colors.white, size: 14),
        ],
      ),
    );
    return Wrap(
      spacing: XSpace.s3,
      runSpacing: XSpace.s3,
      children: [
        _Caption('Status bar', child: bar(const Color(0xFF1F2933))),
        _Caption('On a colour', child: bar(const Color(0xFF3F51B5))),
        _Caption(
          'Large',
          child: Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(XSpace.s2),
            color: const Color(0xFF1F2933),
            child: _image(shape, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}

/// A browser tab, and how a maskable icon sits in a phone's circle.
class WebIconPreview extends StatelessWidget {
  const WebIconPreview({super.key, required this.images});

  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: XSpace.s3,
    runSpacing: XSpace.s3,
    children: [
      _Caption(
        'Browser tab',
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(XSpace.s2),
          decoration: BoxDecoration(
            color: const Color(0xFFDEE1E6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: XSpace.s2,
              vertical: XSpace.s1,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _image(images['full'], size: 16),
                const SizedBox(width: XSpace.s2),
                const Expanded(
                  child: Text(
                    'App Name',
                    style: TextStyle(color: Colors.black87, fontSize: 12),
                  ),
                ),
                const Icon(Icons.close, size: 12, color: Colors.black54),
              ],
            ),
          ),
        ),
      ),
      _Caption(
        'Installed (maskable)',
        child: _Screen(
          width: 150,
          height: 130,
          child: Center(
            child: _HomeIcon(
              image: images['maskable'],
              shape: const CircleBorder(),
            ),
          ),
        ),
      ),
    ],
  );
}

/// The Dock: macOS shows the icon's own shape, with a margin.
class MacIconPreview extends StatelessWidget {
  const MacIconPreview({super.key, required this.images});

  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) => _Caption(
    'Dock',
    child: _Screen(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.all(XSpace.s2),
          decoration: BoxDecoration(
            color: const Color(0x55FFFFFF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: _ios(52)),
              child: _image(images['full'], size: 52),
            ),
          ),
        ),
      ),
    ),
  );
}

/// watchOS's round icon.
class WatchIconPreview extends StatelessWidget {
  const WatchIconPreview({super.key, required this.images});

  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) => _Caption(
    'Apple Watch',
    child: Container(
      width: 150,
      height: 170,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(36),
      ),
      child: ClipOval(child: _image(images['full'], size: 96)),
    ),
  );
}

/// A wide banner: tvOS, Android TV or the Play Store's feature graphic.
class BannerPreview extends StatelessWidget {
  const BannerPreview({super.key, required this.images, required this.label});

  final Map<String, Uint8List> images;
  final String label;

  @override
  Widget build(BuildContext context) => _Caption(
    label,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 400,
        child: _image(images['banner'], fit: BoxFit.contain),
      ),
    ),
  );
}

/// A large look at the icon in iOS's shape.
class LargeIconPreview extends StatelessWidget {
  const LargeIconPreview({super.key, required this.bytes, this.size = 200});

  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: ShapeBorderClipper(shape: _ios(size)),
    child: SizedBox.square(
      dimension: size,
      child: bytes == null
          ? const ColoredBox(color: Color(0x22808080))
          : _image(bytes, size: size),
    ),
  );
}

/// A phone showing a launch screen: [color] with [image] centred, drawn at
/// [scale] logical pixels per image pixel.
class SplashPhone extends StatelessWidget {
  const SplashPhone({
    super.key,
    required this.label,
    required this.color,
    required this.image,
    this.scale = 0.2,
    this.radius = 26,
    this.overlay,
  });

  static const width = 164.0;
  static const height = 340.0;

  final String label;
  final Color color;
  final Uint8List? image;
  final double scale;
  final double radius;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) => _Caption(
    label,
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF111111), width: 4),
      ),
      clipBehavior: Clip.antiAlias,
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (image != null)
              Transform.scale(
                scale: scale,
                child: Image.memory(
                  image!,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ?overlay,
          ],
        ),
      ),
    ),
  );
}

/// Android 12's icon circle on a [SplashPhone].
class Android12Guide extends StatelessWidget {
  const Android12Guide({super.key, required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x99FF9F0A)),
      ),
    ),
  );
}
