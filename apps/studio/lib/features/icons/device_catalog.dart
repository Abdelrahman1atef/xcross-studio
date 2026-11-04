// Feature 026: the screens the gallery draws. Display data only: nothing here
// decides what is built.
//
// iPhone and iPad sizes as listed on 2026-11-04 by useyourloaf.com (iPhone 17
// lineup and the iPad list), which follows Apple's device tables. A newer device
// can be added as a custom size in the gallery. Safe areas and corners are for
// drawing guides: close, not exact. Android has no complete list, so these are
// the sizes of Android Studio's reference devices and common phones.

enum DeviceFamily {
  iPhone('iPhone'),
  iPad('iPad'),
  androidPhone('Android phone'),
  androidTablet('Android tablet and foldable'),
  custom('Custom size');

  const DeviceFamily(this.label);

  final String label;
}

enum DeviceCutout { none, notch, island, punch }

class DeviceScreen {
  const DeviceScreen({
    required this.name,
    required this.family,
    required this.width,
    required this.height,
    this.scale = 0,
    this.safeTop = 0,
    this.safeBottom = 0,
    this.corner = 0,
    this.cutout = DeviceCutout.none,
    this.android = false,
  });

  /// The models that use this screen, or what kind of device it is.
  final String name;
  final DeviceFamily family;

  /// In points on Apple devices and dp on Android, held upright.
  final double width;
  final double height;

  /// Pixels per point; 0 where it varies, as on Android.
  final int scale;
  final double safeTop;
  final double safeBottom;
  final double corner;
  final DeviceCutout cutout;

  /// Draws what Android shows, not what iOS shows.
  final bool android;

  bool get isTablet =>
      family == DeviceFamily.iPad || family == DeviceFamily.androidTablet;

  String get unit => android ? 'dp' : 'pt';

  String get sizeLabel =>
      '${_number(width)} × ${_number(height)} $unit'
      '${scale == 0 ? '' : ' @${scale}x'}';

  static String _number(double value) => value.toStringAsFixed(0);
}

const deviceScreens = <DeviceScreen>[
  // iPhone, smallest first.
  DeviceScreen(
    name: 'iPhone SE (1st gen), iPod touch (7th gen)',
    family: DeviceFamily.iPhone,
    width: 320,
    height: 568,
    scale: 2,
    safeTop: 20,
  ),
  DeviceScreen(
    name: 'iPhone SE (2nd and 3rd gen), 8, 7, 6s',
    family: DeviceFamily.iPhone,
    width: 375,
    height: 667,
    scale: 2,
    safeTop: 20,
  ),
  DeviceScreen(
    name: 'iPhone 8 Plus, 7 Plus, 6s Plus',
    family: DeviceFamily.iPhone,
    width: 414,
    height: 736,
    scale: 3,
    safeTop: 20,
  ),
  DeviceScreen(
    name: 'iPhone 11 Pro, XS, X',
    family: DeviceFamily.iPhone,
    width: 375,
    height: 812,
    scale: 3,
    safeTop: 44,
    safeBottom: 34,
    corner: 39,
    cutout: DeviceCutout.notch,
  ),
  DeviceScreen(
    name: 'iPhone 13 mini, 12 mini',
    family: DeviceFamily.iPhone,
    width: 375,
    height: 812,
    scale: 3,
    safeTop: 50,
    safeBottom: 34,
    corner: 44,
    cutout: DeviceCutout.notch,
  ),
  DeviceScreen(
    name: 'iPhone 16e, 14, 13 Pro, 13, 12 Pro, 12',
    family: DeviceFamily.iPhone,
    width: 390,
    height: 844,
    scale: 3,
    safeTop: 47,
    safeBottom: 34,
    corner: 47,
    cutout: DeviceCutout.notch,
  ),
  DeviceScreen(
    name: 'iPhone 16, 15 Pro, 15, 14 Pro',
    family: DeviceFamily.iPhone,
    width: 393,
    height: 852,
    scale: 3,
    safeTop: 59,
    safeBottom: 34,
    corner: 55,
    cutout: DeviceCutout.island,
  ),
  DeviceScreen(
    name: 'iPhone 17, 17 Pro, 16 Pro',
    family: DeviceFamily.iPhone,
    width: 402,
    height: 874,
    scale: 3,
    safeTop: 62,
    safeBottom: 34,
    corner: 62,
    cutout: DeviceCutout.island,
  ),
  DeviceScreen(
    name: 'iPhone 11, XR',
    family: DeviceFamily.iPhone,
    width: 414,
    height: 896,
    scale: 2,
    safeTop: 48,
    safeBottom: 34,
    corner: 41,
    cutout: DeviceCutout.notch,
  ),
  DeviceScreen(
    name: 'iPhone 11 Pro Max, XS Max',
    family: DeviceFamily.iPhone,
    width: 414,
    height: 896,
    scale: 3,
    safeTop: 44,
    safeBottom: 34,
    corner: 39,
    cutout: DeviceCutout.notch,
  ),
  DeviceScreen(
    name: 'iPhone Air',
    family: DeviceFamily.iPhone,
    width: 420,
    height: 912,
    scale: 3,
    safeTop: 68,
    safeBottom: 34,
    corner: 62,
    cutout: DeviceCutout.island,
  ),
  DeviceScreen(
    name: 'iPhone 14 Plus, 13 Pro Max, 12 Pro Max',
    family: DeviceFamily.iPhone,
    width: 428,
    height: 926,
    scale: 3,
    safeTop: 47,
    safeBottom: 34,
    corner: 53,
    cutout: DeviceCutout.notch,
  ),
  DeviceScreen(
    name: 'iPhone 16 Plus, 15 Pro Max, 15 Plus, 14 Pro Max',
    family: DeviceFamily.iPhone,
    width: 430,
    height: 932,
    scale: 3,
    safeTop: 59,
    safeBottom: 34,
    corner: 55,
    cutout: DeviceCutout.island,
  ),
  DeviceScreen(
    name: 'iPhone 17 Pro Max, 16 Pro Max',
    family: DeviceFamily.iPhone,
    width: 440,
    height: 956,
    scale: 3,
    safeTop: 62,
    safeBottom: 34,
    corner: 62,
    cutout: DeviceCutout.island,
  ),

  // iPad, smallest first.
  DeviceScreen(
    name: 'iPad mini (6th gen)',
    family: DeviceFamily.iPad,
    width: 744,
    height: 1133,
    scale: 2,
    safeTop: 24,
    safeBottom: 20,
    corner: 18,
  ),
  DeviceScreen(
    name: 'iPad (5th, 6th gen), Pro 9.7", Air 2, mini (4th, 5th gen)',
    family: DeviceFamily.iPad,
    width: 768,
    height: 1024,
    scale: 2,
    safeTop: 20,
  ),
  DeviceScreen(
    name: 'iPad (7th, 8th, 9th gen)',
    family: DeviceFamily.iPad,
    width: 810,
    height: 1080,
    scale: 2,
    safeTop: 20,
  ),
  DeviceScreen(
    name: 'iPad Air 11" (M2), Air (4th, 5th gen)',
    family: DeviceFamily.iPad,
    width: 820,
    height: 1180,
    scale: 2,
    safeTop: 24,
    safeBottom: 20,
    corner: 18,
  ),
  DeviceScreen(
    name: 'iPad Air (3rd gen), Pro 10.5"',
    family: DeviceFamily.iPad,
    width: 834,
    height: 1112,
    scale: 2,
    safeTop: 20,
  ),
  DeviceScreen(
    name: 'iPad Pro 11" (3rd to 6th gen)',
    family: DeviceFamily.iPad,
    width: 834,
    height: 1194,
    scale: 2,
    safeTop: 24,
    safeBottom: 20,
    corner: 18,
  ),
  DeviceScreen(
    name: 'iPad Pro 11" (M4)',
    family: DeviceFamily.iPad,
    width: 834,
    height: 1210,
    scale: 2,
    safeTop: 24,
    safeBottom: 20,
    corner: 18,
  ),
  DeviceScreen(
    name: 'iPad Pro 12.9", Air 13" (M2)',
    family: DeviceFamily.iPad,
    width: 1024,
    height: 1366,
    scale: 2,
    safeTop: 24,
    safeBottom: 20,
    corner: 18,
  ),
  DeviceScreen(
    name: 'iPad Pro 13" (M4)',
    family: DeviceFamily.iPad,
    width: 1032,
    height: 1376,
    scale: 2,
    safeTop: 24,
    safeBottom: 20,
    corner: 18,
  ),

  // Android phones.
  DeviceScreen(
    name: 'Small phone',
    family: DeviceFamily.androidPhone,
    width: 360,
    height: 640,
    safeTop: 24,
    safeBottom: 48,
    android: true,
  ),
  DeviceScreen(
    name: 'Compact phone',
    family: DeviceFamily.androidPhone,
    width: 360,
    height: 800,
    safeTop: 28,
    safeBottom: 48,
    corner: 18,
    cutout: DeviceCutout.punch,
    android: true,
  ),
  DeviceScreen(
    name: 'Medium phone',
    family: DeviceFamily.androidPhone,
    width: 384,
    height: 854,
    safeTop: 28,
    safeBottom: 48,
    corner: 20,
    cutout: DeviceCutout.punch,
    android: true,
  ),
  DeviceScreen(
    name: 'Common large phone',
    family: DeviceFamily.androidPhone,
    width: 412,
    height: 915,
    safeTop: 32,
    safeBottom: 48,
    corner: 24,
    cutout: DeviceCutout.punch,
    android: true,
  ),
  DeviceScreen(
    name: 'Very large phone',
    family: DeviceFamily.androidPhone,
    width: 480,
    height: 1040,
    safeTop: 32,
    safeBottom: 48,
    corner: 24,
    cutout: DeviceCutout.punch,
    android: true,
  ),

  // Android tablets and foldables.
  DeviceScreen(
    name: 'Foldable, closed',
    family: DeviceFamily.androidTablet,
    width: 344,
    height: 882,
    safeTop: 32,
    safeBottom: 48,
    corner: 16,
    cutout: DeviceCutout.punch,
    android: true,
  ),
  DeviceScreen(
    name: 'Small tablet',
    family: DeviceFamily.androidTablet,
    width: 600,
    height: 960,
    safeTop: 24,
    safeBottom: 48,
    android: true,
  ),
  DeviceScreen(
    name: 'Foldable, open',
    family: DeviceFamily.androidTablet,
    width: 673,
    height: 841,
    safeTop: 32,
    safeBottom: 48,
    corner: 16,
    android: true,
  ),
  DeviceScreen(
    name: 'Tablet',
    family: DeviceFamily.androidTablet,
    width: 800,
    height: 1280,
    safeTop: 24,
    safeBottom: 48,
    corner: 12,
    android: true,
  ),
  DeviceScreen(
    name: 'Large tablet',
    family: DeviceFamily.androidTablet,
    width: 1024,
    height: 1366,
    safeTop: 24,
    safeBottom: 48,
    corner: 12,
    android: true,
  ),
];

/// One iOS app icon slot.
typedef IosIconSize = ({String label, double points, int scale});

/// Every iOS icon slot of Flutter's template.
const iosIconSizes = <IosIconSize>[
  (label: 'iPhone notification', points: 20, scale: 2),
  (label: 'iPhone notification', points: 20, scale: 3),
  (label: 'iPhone settings', points: 29, scale: 2),
  (label: 'iPhone settings', points: 29, scale: 3),
  (label: 'iPhone spotlight', points: 40, scale: 2),
  (label: 'iPhone spotlight', points: 40, scale: 3),
  (label: 'iPhone home', points: 60, scale: 2),
  (label: 'iPhone home', points: 60, scale: 3),
  (label: 'iPad notification', points: 20, scale: 1),
  (label: 'iPad notification', points: 20, scale: 2),
  (label: 'iPad settings', points: 29, scale: 1),
  (label: 'iPad settings', points: 29, scale: 2),
  (label: 'iPad spotlight', points: 40, scale: 1),
  (label: 'iPad spotlight', points: 40, scale: 2),
  (label: 'iPad home', points: 76, scale: 1),
  (label: 'iPad home', points: 76, scale: 2),
  (label: 'iPad Pro home', points: 83.5, scale: 2),
  (label: 'App Store', points: 1024, scale: 1),
];

/// Android launcher icons by density folder: name and pixels.
const androidIconDensities = <(String, int)>[
  ('mdpi', 48),
  ('hdpi', 72),
  ('xhdpi', 96),
  ('xxhdpi', 144),
  ('xxxhdpi', 192),
];

/// Launcher shapes a phone may mask an adaptive icon with.
const androidIconShapes = ['square', 'squircle', 'circle'];
