// studio: 024 — the native splash screen's images and files
// (specs/024-icon-splash-studio, User Story 2).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';

/// Margins around the logo, in points. Positive only: a larger top margin
/// moves the logo down, because the image stays centred on the screen.
@internal
@immutable
final class SplashMargin {
  const SplashMargin(this.top, this.right, this.bottom, this.left);
  static const none = SplashMargin(0, 0, 0, 0);

  final double top;
  final double right;
  final double bottom;
  final double left;

  /// `n` or `top,right,bottom,left`; null when malformed or negative.
  static SplashMargin? parse(String text) {
    final numbers = text
        .split(',')
        .map((t) => double.tryParse(t.trim()))
        .toList();
    if (numbers.any((value) => value == null || value < 0)) return null;
    final values = numbers.cast<double>();
    if (values.length == 1) {
      return SplashMargin(values[0], values[0], values[0], values[0]);
    }
    if (values.length != 4) return null;
    return SplashMargin(values[0], values[1], values[2], values[3]);
  }
}

/// A splash: one colour and one logo, light and dark.
@internal
@immutable
final class SplashDesign {
  const SplashDesign({
    required this.logo,
    this.darkLogo,
    this.background = (255, 255, 255),
    this.darkBackground,
    this.logoWidth = 120,
    this.padding = IconPadding.none,
    this.margin = SplashMargin.none,
    this.branding,
    this.darkBranding,
    this.ipadLogoWidth,
    this.androidLogoWidth,
    this.android12IconWidth,
    this.android12IconBackground,
    this.darkAndroid12IconBackground,
    this.brandingWidth = SplashImages.defaultBrandingWidth,
    this.brandingBottom = SplashImages.defaultBrandingBottom,
  });

  final RgbaImage logo;
  final RgbaImage? darkLogo;
  final IconColor background;
  final IconColor? darkBackground;

  /// Points (iOS) and dp (Android).
  final double logoWidth;

  /// Space kept clear inside the logo's width, in percent of its size, so more
  /// padding makes the logo smaller, and uneven padding also moves it. A launch
  /// screen centres its image, so space added around the logo would not show.
  final IconPadding padding;
  final SplashMargin margin;
  final RgbaImage? branding;
  final RgbaImage? darkBranding;

  /// Sizes for one kind of device; each defaults to [logoWidth] (AC-026-19).
  final double? ipadLogoWidth;
  final double? androidLogoWidth;
  final double? android12IconWidth;

  /// Android 12's icon background, drawn by the system (AC-026-20).
  final IconColor? android12IconBackground;
  final IconColor? darkAndroid12IconBackground;

  /// The branding's width in points or dp (AC-026-21).
  final double brandingWidth;

  /// How far above the bottom Android 11 and older draw the branding, in dp.
  final double brandingBottom;

  /// This design with the logo shown at [width].
  SplashDesign withLogoWidth(double width) => SplashDesign(
    logo: logo,
    darkLogo: darkLogo,
    background: background,
    darkBackground: darkBackground,
    logoWidth: width,
    padding: padding,
    margin: margin,
    branding: branding,
    darkBranding: darkBranding,
    brandingWidth: brandingWidth,
    brandingBottom: brandingBottom,
  );

  bool get hasDark => darkLogo != null || darkBackground != null;

  /// The logo's height in points at [logoWidth].
  double get logoHeight => logoWidth * logo.height / logo.width;

  /// The logo's box with its margin, in points.
  (double, double) get canvasSize => (
    logoWidth + margin.left + margin.right,
    logoHeight + margin.top + margin.bottom,
  );

  /// Margins that cancel out: the image is centred, so nothing moves.
  bool get marginHasNoEffect =>
      margin.top == margin.bottom &&
      margin.left == margin.right &&
      (margin.top > 0 || margin.left > 0);
}

/// Draws a logo into its transparent canvas.
@internal
abstract final class SplashImages {
  /// The tallest common iPhone screen, in points: a branding image sits near
  /// the bottom of an image this tall (AC-024-7).
  static const brandedHeight = 760.0;

  /// The branding image's width unless another is chosen.
  static const defaultBrandingWidth = 180.0;

  /// How far up Android 11 and older draw it unless another is chosen.
  static const defaultBrandingBottom = 32.0;

  /// [design]'s logo ([dark] for the dark one) at [scale] pixels per point.
  /// With [withBranding], the image is tall enough to hold the branding near
  /// the bottom of the screen, with the logo still centred.
  static RgbaImage logoCanvas(
    SplashDesign design, {
    required double scale,
    bool dark = false,
    bool withBranding = false,
  }) {
    final logo = dark ? (design.darkLogo ?? design.logo) : design.logo;
    final (canvasWidth, canvasHeight) = design.canvasSize;
    final branding = withBranding
        ? (dark ? (design.darkBranding ?? design.branding) : design.branding)
        : null;
    final pointsWide = branding == null
        ? canvasWidth
        : math.max(canvasWidth, design.brandingWidth);
    final pointsTall = branding == null
        ? canvasHeight
        : math.max(canvasHeight, brandedHeight);
    final width = math.max(1, (pointsWide * scale).round());
    final height = math.max(1, (pointsTall * scale).round());
    final out = RgbaImage(width, height, Uint8List(width * height * 4));

    final fitted = _fitted(design, design.logoWidth);
    _blit(
      out,
      logo.resized(
        math.max(1, (fitted.width * scale).round()),
        math.max(1, (fitted.height * scale).round()),
      ),
      (((pointsWide - canvasWidth) / 2 + design.margin.left + fitted.left) *
              scale)
          .round(),
      (((pointsTall - canvasHeight) / 2 + design.margin.top + fitted.top) *
              scale)
          .round(),
    );
    if (branding != null) {
      final bandWidth = math.max(1, (design.brandingWidth * scale).round());
      final bandHeight = math.max(
        1,
        (branding.height * bandWidth / branding.width).round(),
      );
      _blit(
        out,
        branding.resized(bandWidth, bandHeight),
        (width - bandWidth) ~/ 2,
        height - bandHeight,
      );
    }
    return out;
  }

  /// Where the logo goes inside its box of [boxWidth], in points from the box's
  /// corner: padding is a share of each side, and the logo keeps its shape.
  static ({double left, double top, double width, double height}) _fitted(
    SplashDesign design,
    double boxWidth,
  ) {
    final logo = design.logo;
    final aspect = logo.height / logo.width;
    final boxHeight = boxWidth * aspect;
    final padding = design.padding;
    final innerWidth = boxWidth * (1 - (padding.left + padding.right) / 100);
    final innerHeight = boxHeight * (1 - (padding.top + padding.bottom) / 100);
    final width = math.min(innerWidth, innerHeight / aspect);
    final height = width * aspect;
    return (
      left: boxWidth * padding.left / 100 + (innerWidth - width) / 2,
      top: boxHeight * padding.top / 100 + (innerHeight - height) / 2,
      width: width,
      height: height,
    );
  }

  /// Android 12's icon background, in light or dark.
  static IconColor? _iconBackground(SplashDesign design, {bool dark = false}) =>
      dark
      ? design.darkAndroid12IconBackground ?? design.android12IconBackground
      : design.android12IconBackground;

  /// The Android 12 icon's canvas in dp: 240 with an icon background, else 288.
  static double android12Canvas(SplashDesign design, {bool dark = false}) =>
      _iconBackground(design, dark: dark) == null ? 288 : 240;

  /// The circle Android 12 shows of it, in dp: outside this it masks the icon.
  static double android12Circle(SplashDesign design, {bool dark = false}) =>
      _iconBackground(design, dark: dark) == null ? 192 : 160;

  /// The largest side that always fits the circle: its inscribed square.
  static double android12SafeSide(SplashDesign design) =>
      android12Circle(design) / math.sqrt2;

  /// The logo's box in the Android 12 icon, in dp. A width chosen for Android
  /// 12 is used as it is. The general logo width is kept inside the circle, as
  /// nobody asked for this logo to be cut.
  static double android12BoxWidth(SplashDesign design) {
    if (design.android12IconWidth case final width?) return width;
    final longest = math.max(design.logoWidth, design.logoHeight);
    final safe = android12SafeSide(design);
    return longest <= safe
        ? design.logoWidth
        : design.logoWidth * safe / longest;
  }

  /// The Android 12 icon at [scale] pixels per dp: the logo in the middle of a
  /// transparent canvas, moved by its margin like every other splash image.
  static RgbaImage android12Icon(
    SplashDesign design, {
    required double scale,
    bool dark = false,
  }) {
    final logo = dark ? (design.darkLogo ?? design.logo) : design.logo;
    final canvas = android12Canvas(design, dark: dark);
    final pixels = (canvas * scale).round();
    final out = RgbaImage(pixels, pixels, Uint8List(pixels * pixels * 4));
    final box = android12BoxWidth(design);
    final fitted = _fitted(design, box);
    final margin = design.margin;
    _blit(
      out,
      logo.resized(
        math.max(1, (fitted.width * scale).round()),
        math.max(1, (fitted.height * scale).round()),
      ),
      (((canvas - box) / 2 + fitted.left + (margin.left - margin.right) / 2) *
              scale)
          .round(),
      (((canvas - box * logo.height / logo.width) / 2 +
                  fitted.top +
                  (margin.top - margin.bottom) / 2) *
              scale)
          .round(),
    );
    return out;
  }

  /// The general logo width had to shrink to stay inside Android 12's circle.
  static bool android12Shrunk(SplashDesign design) =>
      design.android12IconWidth == null &&
      math.max(design.logoWidth, design.logoHeight) > android12SafeSide(design);

  /// Part of the logo falls outside Android 12's circle, so Android cuts it.
  static bool android12Cut(SplashDesign design) {
    final icon = android12Icon(design, scale: 1);
    final centre = (icon.width - 1) / 2;
    final radius = android12Circle(design) / 2;
    for (var y = 0; y < icon.height; y++) {
      for (var x = 0; x < icon.width; x++) {
        if (icon.rgba[(y * icon.width + x) * 4 + 3] < 32) continue;
        final dx = x - centre;
        final dy = y - centre;
        if (dx * dx + dy * dy > radius * radius) return true;
      }
    }
    // A logo so large it runs off the canvas leaves no pixel to find there.
    final fitted = _fitted(design, android12BoxWidth(design));
    return math.max(fitted.width, fitted.height) > android12Canvas(design);
  }

  static void _blit(RgbaImage out, RgbaImage image, int left, int top) {
    for (var y = 0; y < image.height; y++) {
      final targetY = top + y;
      if (targetY < 0 || targetY >= out.height) continue;
      for (var x = 0; x < image.width; x++) {
        final targetX = left + x;
        if (targetX < 0 || targetX >= out.width) continue;
        final from = (y * image.width + x) * 4;
        final to = (targetY * out.width + targetX) * 4;
        out.rgba.setRange(to, to + 4, image.rgba, from);
      }
    }
  }
}

/// A colour for Android XML and for catalog colour sets.
@internal
String splashHex(IconColor color) {
  String two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${two(color.$1)}${two(color.$2)}${two(color.$3)}';
}

const _iosCatalog = 'ios/Runner/Assets.xcassets';
const _androidRes = 'android/app/src/main/res';

/// Every file of a splash, by project-relative path.
@internal
abstract final class SplashFiles {
  static const iosStoryboard = 'ios/Runner/Base.lproj/LaunchScreen.storyboard';
  static const iosImageSet = '$_iosCatalog/LaunchImage.imageset';
  static const iosColorSet = '$_iosCatalog/LaunchBackground.colorset';

  /// What flutter_native_splash leaves: an image with the colour set's name.
  static const iosLeftoverImageSet = '$_iosCatalog/LaunchBackground.imageset';

  static Map<String, Uint8List> ios(SplashDesign design) {
    final files = <String, Uint8List>{};
    final images = <Map<String, Object?>>[];
    final hasDarkImage = design.darkLogo != null || design.darkBranding != null;
    final withBranding = design.branding != null;
    for (final scale in const [1, 2, 3]) {
      final suffix = scale == 1 ? '' : '@${scale}x';
      final name = 'LaunchImage$suffix.png';
      files['$iosImageSet/$name'] = PngEncoder.encode(
        SplashImages.logoCanvas(
          design,
          scale: scale.toDouble(),
          withBranding: withBranding,
        ),
      );
      images.add({
        'idiom': 'universal',
        'filename': name,
        'scale': '${scale}x',
      });
      if (hasDarkImage) {
        final darkName = 'LaunchImageDark$suffix.png';
        files['$iosImageSet/$darkName'] = PngEncoder.encode(
          SplashImages.logoCanvas(
            design,
            scale: scale.toDouble(),
            dark: true,
            withBranding: withBranding,
          ),
        );
        images.add({
          'idiom': 'universal',
          'filename': darkName,
          'scale': '${scale}x',
          'appearances': [
            {'appearance': 'luminosity', 'value': 'dark'},
          ],
        });
      }
    }
    // iPads have their own size; iPhones keep the universal images.
    if (design.ipadLogoWidth case final width?) {
      final ipad = design.withLogoWidth(width);
      void add(String name, {required bool dark}) {
        files['$iosImageSet/$name'] = PngEncoder.encode(
          SplashImages.logoCanvas(
            ipad,
            scale: 2,
            dark: dark,
            withBranding: withBranding,
          ),
        );
        images.add({
          'idiom': 'ipad',
          'filename': name,
          'scale': '2x',
          if (dark)
            'appearances': [
              {'appearance': 'luminosity', 'value': 'dark'},
            ],
        });
      }

      add('LaunchImage-iPad@2x.png', dark: false);
      if (hasDarkImage) add('LaunchImageDark-iPad@2x.png', dark: true);
    }
    files['$iosImageSet/Contents.json'] = _json({
      'images': images,
      'info': _xcodeInfo,
    });
    files['$iosColorSet/Contents.json'] = _json({
      'colors': [
        _colorEntry(design.background),
        if (design.darkBackground != null)
          _colorEntry(design.darkBackground!, dark: true),
      ],
      'info': _xcodeInfo,
    });
    files[iosStoryboard] = _text(storyboard(design));
    return files;
  }

  static const _xcodeInfo = {'author': 'xcode', 'version': 1};

  static Map<String, Object?> _colorEntry(
    IconColor color, {
    bool dark = false,
  }) {
    String component(int value) => (value / 255).toStringAsFixed(3);
    return {
      'idiom': 'universal',
      if (dark)
        'appearances': [
          {'appearance': 'luminosity', 'value': 'dark'},
        ],
      'color': {
        'color-space': 'srgb',
        'components': {
          'red': component(color.$1),
          'green': component(color.$2),
          'blue': component(color.$3),
          'alpha': '1.000',
        },
      },
    };
  }

  /// The launch storyboard: the colour set behind the centred image set. On a
  /// Mac, Xcode compiles it; on Windows and Linux, xcross reads it into the
  /// launch screen when it builds the app.
  static String storyboard(SplashDesign design) {
    final (width, height) = design.branding != null
        ? (
            math.max(design.canvasSize.$1, design.brandingWidth),
            math.max(design.canvasSize.$2, SplashImages.brandedHeight),
          )
        : design.canvasSize;
    final w = width.round();
    final h = height.round();
    return '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="12121" systemVersion="16G29" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="12089"/>
    </dependencies>
    <scenes>
        <!--View Controller-->
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <layoutGuides>
                        <viewControllerLayoutGuide type="top" id="Ydg-fD-yQy"/>
                        <viewControllerLayoutGuide type="bottom" id="xbc-2k-c8Z"/>
                    </layoutGuides>
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4"/>
                        </subviews>
                        <color key="backgroundColor" name="LaunchBackground"/>
                        <constraints>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="1a2-6s-vTC"/>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="4X2-HB-R7a"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
    <resources>
        <image name="LaunchImage" width="$w" height="$h"/>
        <namedColor name="LaunchBackground">
            <color red="${(design.background.$1 / 255).toStringAsFixed(3)}" green="${(design.background.$2 / 255).toStringAsFixed(3)}" blue="${(design.background.$3 / 255).toStringAsFixed(3)}" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
        </namedColor>
    </resources>
</document>
''';
  }

  /// Density folders with their pixels per dp.
  static const _densities = [
    ('mdpi', 1.0),
    ('hdpi', 1.5),
    ('xhdpi', 2.0),
    ('xxhdpi', 3.0),
    ('xxxhdpi', 4.0),
  ];

  static Map<String, Uint8List> android(SplashDesign design) {
    final files = <String, Uint8List>{};
    final darkImages = design.darkLogo != null;
    final logos = design.androidLogoWidth == null
        ? design
        : design.withLogoWidth(design.androidLogoWidth!);
    for (final (density, scale) in _densities) {
      final folder = '$_androidRes/drawable-$density';
      files['$folder/splash_logo.png'] = PngEncoder.encode(
        SplashImages.logoCanvas(logos, scale: scale),
      );
      files['$folder/android12_splash.png'] = PngEncoder.encode(
        SplashImages.android12Icon(design, scale: scale),
      );
      if (design.branding != null) {
        final branding = design.branding!;
        final width = (design.brandingWidth * scale).round();
        files['$folder/splash_branding.png'] = PngEncoder.encode(
          branding.resized(
            width,
            (branding.height * width / branding.width).round(),
          ),
        );
      }
      final night = '$_androidRes/drawable-night-$density';
      if (darkImages) {
        files['$night/splash_logo.png'] = PngEncoder.encode(
          SplashImages.logoCanvas(logos, scale: scale, dark: true),
        );
      }
      // A dark icon background alone also changes its canvas.
      if (darkImages || design.darkAndroid12IconBackground != null) {
        files['$night/android12_splash.png'] = PngEncoder.encode(
          SplashImages.android12Icon(design, scale: scale, dark: true),
        );
      }
      if (design.darkBranding != null) {
        final branding = design.darkBranding!;
        final width = (design.brandingWidth * scale).round();
        files['$_androidRes/drawable-night-$density/splash_branding.png'] =
            PngEncoder.encode(
              branding.resized(
                width,
                (branding.height * width / branding.width).round(),
              ),
            );
      }
    }
    final hasBranding = design.branding != null;
    final bottom = design.brandingBottom;
    final light = _launchBackground(
      design.background,
      branding: hasBranding,
      bottom: bottom,
    );
    files['$_androidRes/drawable/launch_background.xml'] = _text(light);
    files['$_androidRes/drawable-v21/launch_background.xml'] = _text(light);
    files['$_androidRes/values-v31/styles.xml'] = _text(
      _styles31(
        design.background,
        night: false,
        branding: hasBranding,
        iconBackground: design.android12IconBackground,
      ),
    );
    final dark = design.darkBackground;
    final darkIcon = design.darkAndroid12IconBackground;
    if (dark != null || darkImages || darkIcon != null) {
      final color = dark ?? design.background;
      final night = _launchBackground(
        color,
        branding: hasBranding,
        bottom: bottom,
      );
      files['$_androidRes/drawable-night/launch_background.xml'] = _text(night);
      files['$_androidRes/drawable-night-v21/launch_background.xml'] = _text(
        night,
      );
      files['$_androidRes/values-night-v31/styles.xml'] = _text(
        _styles31(
          color,
          night: true,
          branding: hasBranding,
          iconBackground: darkIcon ?? design.android12IconBackground,
        ),
      );
    }
    return files;
  }

  static String _launchBackground(
    IconColor color, {
    required bool branding,
    required double bottom,
  }) =>
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <item>\n'
      '        <shape android:shape="rectangle">\n'
      '            <solid android:color="${splashHex(color)}"/>\n'
      '        </shape>\n'
      '    </item>\n'
      '    <item>\n'
      '        <bitmap android:gravity="center" android:src="@drawable/splash_logo"/>\n'
      '    </item>\n'
      '${branding ? '    <item android:bottom="${bottom.round()}dp">\n        <bitmap android:gravity="bottom" android:src="@drawable/splash_branding"/>\n    </item>\n' : ''}'
      '</layer-list>\n';

  static String _styles31(
    IconColor color, {
    required bool night,
    required bool branding,
    IconColor? iconBackground,
  }) {
    final parent = night
        ? '@android:style/Theme.Black.NoTitleBar'
        : '@android:style/Theme.Light.NoTitleBar';
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <style name="LaunchTheme" parent="$parent">\n'
        '        <item name="android:windowSplashScreenBackground">${splashHex(color)}</item>\n'
        '        <item name="android:windowSplashScreenAnimatedIcon">@drawable/android12_splash</item>\n'
        '${iconBackground == null ? '' : '        <item name="android:windowSplashScreenIconBackgroundColor">${splashHex(iconBackground)}</item>\n'}'
        '${branding ? '        <item name="android:windowSplashScreenBrandingImage">@drawable/splash_branding</item>\n' : ''}'
        '    </style>\n'
        '    <style name="NormalTheme" parent="$parent">\n'
        '        <item name="android:windowBackground">?android:colorBackground</item>\n'
        '    </style>\n'
        '</resources>\n';
  }

  static Uint8List _text(String text) => Uint8List.fromList(utf8.encode(text));

  static Uint8List _json(Object? value) =>
      _text('${const JsonEncoder.withIndent('  ').convert(value)}\n');
}
