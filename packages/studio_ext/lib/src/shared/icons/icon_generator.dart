// studio: 023 — `xcross icons generate`: a complete icon set from one image
// (specs/023-icon-studio).
import 'dart:io';
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_composer.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:studio_ext/src/shared/icons/icon_slots.dart';

/// The 1024 px icon every size is made from.
@internal
@immutable
final class IconMaster {
  const IconMaster(this.image, this.background, {required this.upscaled});

  /// Opaque 1024 × 1024 RGBA.
  final RgbaImage image;
  final IconColor background;

  /// The source was enlarged to fill its place (it was smaller).
  final bool upscaled;
}

/// What [IconGenerator.write] did.
@internal
@immutable
final class IconWriteResult {
  const IconWriteResult(this.path, this.written, this.backup);

  /// The `.appiconset` (or `--output`) folder.
  final String path;
  final List<String> written;
  final String? backup;
}

/// Composes and writes app icon sets.
@internal
abstract final class IconGenerator {
  static const side = 1024;

  /// `#RRGGBB` or `RRGGBB`; null when malformed.
  static IconColor? parseColor(String text) {
    final match = RegExp(
      r'^#?([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    int channel(int group) => int.parse(match.group(group)!, radix: 16);
    return (channel(1), channel(2), channel(3));
  }

  /// The colour of [image]'s outer border when it is one opaque colour.
  static IconColor? borderColor(RgbaImage image) =>
      IconComposer.borderColorOf(image);

  /// [source] fitted (aspect kept) and centred inside a margin of
  /// [padding] percent of the side, over [background] (default: the
  /// source's border colour when it is one opaque colour, else white).
  /// Transparency is flattened onto the background.
  static IconMaster compose(
    RgbaImage source, {
    IconColor? background,
    double padding = 0,
  }) {
    final composer = IconComposer(
      source,
      IconDesign(padding: IconPadding.all(padding), colors: [?background]),
    );
    return IconMaster(
      composer.draw(side, side),
      composer.colors.first,
      upscaled: composer.upscaledAt(side),
    );
  }

  /// Every file of the Flutter template set as RGB PNG bytes.
  static Map<String, Uint8List> files(IconMaster master) => {
    for (final MapEntry(key: name, value: pixels) in IconSlots.files.entries)
      name: PngEncoder.encodeOpaque(master.image.resized(pixels, pixels)),
  };

  /// Writes [files] and `Contents.json` into [output] when given, else into
  /// the project's icon set, after copying the old set to
  /// `.xcross/icon-backups/<stamp>/`.
  static IconWriteResult write({
    required HostFileSystemInterface fileSystem,
    required Map<String, Uint8List> files,
    required DateTime now,
    String? projectRoot,
    String? output,
  }) {
    assert(projectRoot != null || output != null, 'nowhere to write');
    String? backup;
    final String target;
    if (output != null) {
      target = output;
    } else {
      final catalog = IconSetLocator.catalog(projectRoot!);
      target =
          IconSetLocator.find(fileSystem, projectRoot) ??
          p.join(catalog, 'AppIcon.appiconset');
      final catalogContents = fileSystem.file(p.join(catalog, 'Contents.json'));
      if (!catalogContents.existsSync()) {
        fileSystem.directory(catalog).createSync(recursive: true);
        catalogContents.writeAsStringSync(
          '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n',
        );
      }
      backup = _backUp(fileSystem, projectRoot, target, now);
    }
    final directory = fileSystem.directory(target)..createSync(recursive: true);
    if (output == null) {
      // The old files are in the backup; names that are not rewritten would
      // stay as unassigned images.
      for (final entity in directory.listSync()) {
        if (entity is File) {
          fileSystem.file(p.join(target, p.basename(entity.path))).deleteSync();
        }
      }
    }
    final written = <String>[];
    for (final MapEntry(key: name, value: bytes) in files.entries) {
      fileSystem.file(p.join(target, name)).writeAsBytesSync(bytes);
      written.add(name);
    }
    fileSystem
        .file(p.join(target, 'Contents.json'))
        .writeAsStringSync(IconSlots.contentsJson());
    return IconWriteResult(target, written..sort(), backup);
  }

  static String? _backUp(
    HostFileSystemInterface fileSystem,
    String projectRoot,
    String setPath,
    DateTime now,
  ) {
    final source = fileSystem.directory(setPath);
    if (!source.existsSync()) return null;
    final names = [
      for (final entity in source.listSync())
        if (entity is File) p.basename(entity.path),
    ];
    if (names.isEmpty) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final backup = p.join(
      projectRoot,
      '.xcross',
      'icon-backups',
      stamp,
      p.basename(setPath),
    );
    fileSystem.directory(backup).createSync(recursive: true);
    for (final name in names) {
      fileSystem.file(p.join(setPath, name)).copySync(p.join(backup, name));
    }
    return backup;
  }
}
