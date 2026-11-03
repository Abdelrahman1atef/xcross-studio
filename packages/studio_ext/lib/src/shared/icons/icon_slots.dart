// studio: 023 — the icon sizes an iOS app uses and the set that holds them
// (specs/023-icon-studio).
import 'dart:convert';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Where iOS shows an icon size.
@internal
enum IconRole {
  notification('Notification'),
  settings('Settings'),
  spotlight('Spotlight'),
  home('Home screen'),
  ipadHome('iPad home screen'),
  ipadProHome('iPad Pro home screen'),
  appStore('App Store');

  const IconRole(this.label);

  final String label;
}

/// One entry of an app icon set: an idiom, a point size and a scale.
@internal
@immutable
final class IconSlot {
  const IconSlot(
    this.idiom,
    this.points,
    this.scale,
    this.role, {
    this.required = false,
  });

  /// `iphone`, `ipad`, `ios-marketing`, or `universal` (single-size sets).
  final String idiom;
  final double points;
  final int scale;
  final IconRole role;

  /// A missing required slot is an error; others are warnings (iOS scales
  /// another size).
  final bool required;

  int get pixels => (points * scale).round();

  /// `20`, `83.5`.
  String get pointsText =>
      points == points.roundToDouble() ? '${points.round()}' : '$points';

  /// `Contents.json`'s `size`: `20x20`, `83.5x83.5`.
  String get sizeText => '${pointsText}x$pointsText';

  /// `Contents.json`'s `scale`: `2x`.
  String get scaleText => '${scale}x';

  /// The Flutter template's file name: `Icon-App-20x20@2x.png`. iPhone and
  /// iPad entries of the same size and scale share it.
  String get fileName => 'Icon-App-$sizeText@${scale}x.png';
}

/// The slots of the Flutter template's `AppIcon.appiconset`.
@internal
abstract final class IconSlots {
  static const iphone = [
    IconSlot('iphone', 20, 2, IconRole.notification),
    IconSlot('iphone', 20, 3, IconRole.notification),
    IconSlot('iphone', 29, 1, IconRole.settings),
    IconSlot('iphone', 29, 2, IconRole.settings),
    IconSlot('iphone', 29, 3, IconRole.settings),
    IconSlot('iphone', 40, 2, IconRole.spotlight),
    IconSlot('iphone', 40, 3, IconRole.spotlight),
    IconSlot('iphone', 60, 2, IconRole.home, required: true),
    IconSlot('iphone', 60, 3, IconRole.home, required: true),
  ];

  static const ipad = [
    IconSlot('ipad', 20, 1, IconRole.notification),
    IconSlot('ipad', 20, 2, IconRole.notification),
    IconSlot('ipad', 29, 1, IconRole.settings),
    IconSlot('ipad', 29, 2, IconRole.settings),
    IconSlot('ipad', 40, 1, IconRole.spotlight),
    IconSlot('ipad', 40, 2, IconRole.spotlight),
    IconSlot('ipad', 76, 1, IconRole.ipadHome),
    IconSlot('ipad', 76, 2, IconRole.ipadHome, required: true),
    IconSlot('ipad', 83.5, 2, IconRole.ipadProHome, required: true),
  ];

  static const appStore = IconSlot(
    'ios-marketing',
    1024,
    1,
    IconRole.appStore,
    required: true,
  );

  /// The one image of a single-size set (Xcode 14+): every size is made
  /// from it.
  static const universal = IconSlot(
    'universal',
    1024,
    1,
    IconRole.appStore,
    required: true,
  );

  static const all = [...iphone, ...ipad, appStore];

  /// The slots an app needs: iPad sizes only when it runs on iPad.
  static List<IconSlot> forApp({required bool ipad}) => [
    ...iphone,
    if (ipad) ...IconSlots.ipad,
    appStore,
  ];

  /// Every distinct file of the set with its pixel size (15 files).
  static Map<String, int> get files => {
    for (final slot in all) slot.fileName: slot.pixels,
  };

  /// `Contents.json` for [all] (19 entries).
  static String contentsJson() =>
      '${const JsonEncoder.withIndent('  ').convert({
        'images': [
          for (final slot in all) {'size': slot.sizeText, 'idiom': slot.idiom, 'filename': slot.fileName, 'scale': slot.scaleText},
        ],
        'info': {'version': 1, 'author': 'xcode'},
      })}\n';
}

/// One `images` entry of an `.appiconset/Contents.json`.
@internal
@immutable
final class IconSetEntry {
  const IconSetEntry({
    required this.idiom,
    required this.size,
    this.scale,
    this.fileName,
    this.platform,
    this.appearance,
  });

  final String idiom;

  /// `20x20`.
  final String size;

  /// `2x`; single-size entries have none.
  final String? scale;
  final String? fileName;
  final String? platform;

  /// `dark` or `tinted` for iOS 18 variants; null for the default look.
  final String? appearance;
}

/// An `.appiconset` folder and its `Contents.json` entries.
@internal
final class IconSet {
  IconSet({required this.path, required this.entries});

  /// Reads [path]/Contents.json. Throws [FormatException] when it is not an
  /// icon set's JSON.
  factory IconSet.read(HostFileSystemInterface fileSystem, String path) {
    final file = fileSystem.file(p.join(path, 'Contents.json'));
    if (!file.existsSync()) {
      throw const FormatException('Contents.json is missing');
    }
    final Object? json = jsonDecode(file.readAsStringSync());
    if (json is! Map || json['images'] is! List) {
      throw const FormatException('Contents.json has no "images" list');
    }
    final entries = <IconSetEntry>[];
    for (final Object? image in json['images'] as List) {
      if (image is! Map<Object?, Object?>) continue;
      final idiom = image['idiom'];
      final size = image['size'];
      if (idiom is! String || size is! String) continue;
      String? appearance;
      if (image['appearances'] case final List<Object?> list) {
        for (final item in list) {
          if (item case {'value': final String value}) appearance = value;
        }
      }
      entries.add(
        IconSetEntry(
          idiom: idiom,
          size: size,
          scale: _text(image['scale']),
          fileName: _text(image['filename']),
          platform: _text(image['platform']),
          appearance: appearance,
        ),
      );
    }
    return IconSet(path: path, entries: entries);
  }

  final String path;
  final List<IconSetEntry> entries;

  static String? _text(Object? value) => value is String ? value : null;

  /// `AppIcon` for `…/AppIcon.appiconset`.
  String get name => p.basenameWithoutExtension(path);

  /// One universal 1024 px image (Xcode 14+ "single size").
  bool get singleSize =>
      universalEntry != null &&
      !entries.any((e) => e.idiom == 'iphone' || e.idiom == 'ipad');

  IconSetEntry? get universalEntry {
    for (final entry in entries) {
      if (entry.idiom == 'universal' &&
          entry.size == '1024x1024' &&
          entry.appearance == null &&
          (entry.platform == null || entry.platform == 'ios')) {
        return entry;
      }
    }
    return null;
  }

  /// Dark or tinted variants (`appearances`).
  bool get hasVariants => entries.any((e) => e.appearance != null);

  /// The default-look entry for [slot].
  IconSetEntry? entryFor(IconSlot slot) {
    for (final entry in entries) {
      if (entry.idiom == slot.idiom &&
          entry.size == slot.sizeText &&
          (entry.scale ?? '1x') == slot.scaleText &&
          entry.appearance == null) {
        return entry;
      }
    }
    return null;
  }
}

/// Finds the app icon set of a Flutter project.
@internal
abstract final class IconSetLocator {
  /// `ios/Runner/Assets.xcassets`.
  static String catalog(String projectRoot) =>
      p.join(projectRoot, 'ios', 'Runner', 'Assets.xcassets');

  /// `AppIcon.appiconset`, else the first `.appiconset` of the catalog, or
  /// null when there is none.
  static String? find(HostFileSystemInterface fileSystem, String projectRoot) {
    final directory = fileSystem.directory(catalog(projectRoot));
    if (!directory.existsSync()) return null;
    final names = [
      for (final entity in directory.listSync())
        if (entity.path.endsWith('.appiconset')) p.basename(entity.path),
    ]..sort();
    if (names.isEmpty) return null;
    final name = names.contains('AppIcon.appiconset')
        ? 'AppIcon.appiconset'
        : names.first;
    return p.join(catalog(projectRoot), name);
  }

  /// Whether the app runs on iPad: a `TARGETED_DEVICE_FAMILY` with `2` in
  /// the Xcode project, or none set (Flutter's template targets both).
  static bool supportsIpad(
    HostFileSystemInterface fileSystem,
    String projectRoot,
  ) {
    final pbxproj = fileSystem.file(
      p.join(projectRoot, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    );
    if (!pbxproj.existsSync()) return true;
    final families = [
      for (final match in RegExp(
        r'TARGETED_DEVICE_FAMILY\s*=\s*"?([0-9, ]+)"?;',
      ).allMatches(pbxproj.readAsStringSync()))
        match.group(1)!,
    ];
    if (families.isEmpty) return true;
    return families.any(
      (family) => family.split(',').map((part) => part.trim()).contains('2'),
    );
  }
}
