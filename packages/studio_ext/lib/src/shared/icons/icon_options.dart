// studio: 024 — icon options, from the command line, the assets file or a
// preview request (specs/024-icon-splash-studio).
import 'dart:convert';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:studio_ext/src/shared/icons/icon_generator.dart';
import 'package:studio_ext/src/shared/icons/icon_targets.dart';

/// A value that makes no sense; the message names the option.
@internal
final class IconOptionError implements Exception {
  const IconOptionError(this.message);
  final String message;
}

/// One design with where it goes. All values are the option names and their
/// text, as `xcross_assets.json` and preview requests hold them.
@internal
@immutable
final class IconOptions {
  const IconOptions({
    required this.design,
    this.targets,
    this.name = IconTargets.defaultName,
    this.shape = IconShape.squircle,
    this.themed = false,
  });

  /// [values] by option name; [readImage] loads the PNGs they name.
  factory IconOptions.parse(
    Map<String, Object?> values, {
    required RgbaImage Function(String path) readImage,
  }) {
    String? text(String key) {
      final value = values[key];
      return value == null ? null : '$value';
    }

    bool flag(String key) => values[key] == true || values[key] == 'true';

    IconColor? color(String key) {
      final value = text(key);
      if (value == null) return null;
      final parsed = IconGenerator.parseColor(value);
      if (parsed == null) {
        throw IconOptionError('--$key must be #RRGGBB.');
      }
      return parsed;
    }

    final backgroundText = text('background') ?? 'auto';
    final IconColor? background;
    if (backgroundText == 'auto') {
      background = null;
    } else {
      background = IconGenerator.parseColor(backgroundText);
      if (background == null) {
        throw const IconOptionError('--background must be auto or #RRGGBB.');
      }
    }

    final paddingText = text('padding') ?? '0';
    final padding = IconPadding.parse(paddingText);
    if (padding == null) {
      throw const IconOptionError(
        '--padding must be one number, or top,right,bottom,left, each from 0 '
        'to 45, leaving room for the logo.',
      );
    }

    final effect = IconEffect.parse(text('effect') ?? 'none');
    if (effect == null) {
      throw IconOptionError(
        '--effect must be one of '
        '${IconEffect.values.map((e) => e.option).join(', ')}.',
      );
    }
    final type = IconBackgroundType.parse(text('background-type') ?? 'color');
    if (type == null) {
      throw const IconOptionError(
        '--background-type must be color, gradient, mesh or image.',
      );
    }
    final texture = IconTexture.parse(text('texture') ?? 'none');
    if (texture == null) {
      throw IconOptionError(
        '--texture must be one of '
        '${IconTexture.values.map((e) => e.name).join(', ')}.',
      );
    }
    final shape = IconShape.parse(text('shape') ?? 'squircle');
    if (shape == null) {
      throw const IconOptionError(
        '--shape must be square, squircle or circle.',
      );
    }
    final angle = double.tryParse(text('gradient-angle') ?? '135');
    if (angle == null) {
      throw const IconOptionError('--gradient-angle must be a number.');
    }
    final name = text('name') ?? IconTargets.defaultName;
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw const IconOptionError(
        '--name must be lower case letters, digits and _, starting with a '
        'letter (Android resource names).',
      );
    }

    final backgroundImagePath = text('background-image');
    if (type == IconBackgroundType.image && backgroundImagePath == null) {
      throw const IconOptionError(
        '--background-type image needs --background-image <png>.',
      );
    }
    final badgePath = text('badge-image');

    return IconOptions(
      design: IconDesign(
        trim: flag('trim'),
        padding: padding,
        foreground: color('foreground'),
        effect: effect,
        backgroundType: type,
        colors: [
          ?background,
          ?color('background2'),
          ?color('background3'),
          ?color('background4'),
        ],
        gradientAngle: angle,
        backgroundImage: backgroundImagePath == null
            ? null
            : readImage(backgroundImagePath),
        texture: texture,
        badge: badgePath == null ? null : readImage(badgePath),
      ),
      targets: parseTargets(text('targets')),
      name: name,
      shape: shape,
      themed: flag('themed'),
    );
  }

  final IconDesign design;

  /// Null when none were named (feature 023's `ios`, written flat).
  final List<IconTarget>? targets;
  final String name;
  final IconShape shape;
  final bool themed;

  /// `--targets`: a comma list or `all`.
  static List<IconTarget>? parseTargets(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    if (text.trim() == 'all') return IconTarget.projectTargets;
    final targets = <IconTarget>[];
    for (final part in text.split(',')) {
      final target = IconTarget.parse(part.trim());
      if (target == null) {
        throw IconOptionError(
          'Unknown target "${part.trim()}". Use all, or a list of '
          '${IconTarget.values.map((t) => t.option).join(', ')}.',
        );
      }
      if (!targets.contains(target)) targets.add(target);
    }
    return targets;
  }
}

/// `xcross_assets.json`: saved icon and splash settings, committed with the
/// project so a team can regenerate them (AC-024-20).
@internal
abstract final class AssetsFile {
  static const name = 'xcross_assets.json';

  static String pathIn(String projectRoot) => p.join(projectRoot, name);

  /// The settings of [section] (`icons`, `splash`), empty when not saved.
  static Map<String, Object?> read(
    HostFileSystemInterface fileSystem,
    String projectRoot,
    String section,
  ) {
    final file = fileSystem.file(pathIn(projectRoot));
    if (!file.existsSync()) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw IconOptionError('$name is not valid JSON: ${error.message}.');
    }
    if (decoded is! Map<String, Object?>) {
      throw const IconOptionError('$name must hold one JSON object.');
    }
    final values = decoded[section];
    return values is Map<String, Object?> ? values : {};
  }

  /// Stores [values] as [section], keeping the other section.
  static void write(
    HostFileSystemInterface fileSystem,
    String projectRoot,
    String section,
    Map<String, Object?> values,
  ) {
    final file = fileSystem.file(pathIn(projectRoot));
    Object? decoded;
    if (file.existsSync()) {
      try {
        decoded = jsonDecode(file.readAsStringSync());
      } on FormatException {
        decoded = null;
      }
    }
    final body = <String, Object?>{
      'version': 1,
      if (decoded is Map<String, Object?>) ...decoded,
      section: values,
    };
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(body)}\n',
    );
  }

  /// [path] relative to the project when inside it, with `/` separators, so
  /// the file works on every machine.
  static String relativePath(String path, String projectRoot) {
    if (!p.isWithin(projectRoot, path)) return path;
    return p.relative(path, from: projectRoot).replaceAll(r'\', '/');
  }
}
