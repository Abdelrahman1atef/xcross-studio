// studio: 004 — ported from xtool-org/AssetKit (MIT, see
// packages/studio_ext/THIRD_PARTY_NOTICES.md): Catalog/CatalogLoader.swift
// and Schema/Contents.swift. Unlike AssetKit, a bad asset is reported and
// skipped instead of failing the whole catalog.
import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:studio_ext/src/shared/assets/rendition.dart';

/// One image of an `.imageset`.
@internal
final class CatalogImage {
  const CatalogImage({
    required this.path,
    required this.filename,
    required this.idiom,
    required this.scale,
    required this.dark,
    required this.gamut,
  });

  final String path;
  final String filename;
  final AssetIdiom idiom;
  final AssetScale? scale;
  final bool dark;
  final AssetGamut gamut;
}

@internal
final class LoadedImageSet {
  const LoadedImageSet(this.name, this.images);
  final String name;
  final List<CatalogImage> images;
}

/// One colour of a `.colorset`, components in 0…1.
@internal
final class CatalogColorEntry {
  const CatalogColorEntry({
    required this.idiom,
    required this.dark,
    required this.gamut,
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });

  final AssetIdiom idiom;
  final bool dark;
  final AssetGamut gamut;
  final double red;
  final double green;
  final double blue;
  final double alpha;
}

@internal
final class LoadedColorSet {
  const LoadedColorSet(this.name, this.colors);
  final String name;
  final List<CatalogColorEntry> colors;
}

/// One image slot of an `.appiconset`.
@internal
final class AppIconImage {
  const AppIconImage({
    required this.path,
    required this.filename,
    required this.idiom,
    required this.size,
    required this.scale,
    required this.hasAppearance,
  });

  final String path;
  final String filename;
  final AssetIdiom idiom;

  /// Point width from `"60x60"`, or `null` when unparsable.
  final double? size;
  final AssetScale? scale;

  /// Dark or tinted variants (iOS 18), which this compiler leaves out.
  final bool hasAppearance;
}

@internal
final class LoadedAppIcon {
  const LoadedAppIcon(this.name, this.images);
  final String name;
  final List<AppIconImage> images;
}

@internal
final class LoadedCatalog {
  const LoadedCatalog(this.imageSets, this.colorSets, this.appIcons);
  final List<LoadedImageSet> imageSets;
  final List<LoadedColorSet> colorSets;
  final List<LoadedAppIcon> appIcons;
}

/// Reads `.xcassets` folders: `.imageset`, `.colorset` and `.appiconset`
/// inside (possibly nested, namespaced) groups.
@internal
final class CatalogLoader {
  CatalogLoader(this.fileSystem, this.paths);

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  static const _setTypes = {'.imageset', '.colorset', '.appiconset'};

  LoadedCatalog load(List<String> catalogs, List<AssetCatalogIssue> issues) {
    final imageSets = <LoadedImageSet>[];
    final colorSets = <LoadedColorSet>[];
    final appIcons = <LoadedAppIcon>[];
    for (final catalog in catalogs) {
      if (!fileSystem.directory(catalog).existsSync()) {
        issues.add(
          AssetCatalogIssue(
            AssetCatalogIssueKind.invalid,
            paths.basename(catalog),
            '${paths.basename(catalog)} does not exist.',
          ),
        );
        continue;
      }
      _walk(catalog, '', issues, (directory, name) {
        final extension = paths.extension(directory);
        final json = _contents(directory, issues);
        if (json == null) return;
        switch (extension) {
          case '.imageset':
            imageSets.add(LoadedImageSet(name, _images(directory, json)));
          case '.colorset':
            colorSets.add(
              LoadedColorSet(name, _colors(directory, name, json, issues)),
            );
          case '.appiconset':
            appIcons.add(LoadedAppIcon(name, _appIcons(directory, json)));
        }
      });
    }
    return LoadedCatalog(imageSets, colorSets, appIcons);
  }

  void _walk(
    String directory,
    String namespace,
    List<AssetCatalogIssue> issues,
    void Function(String directory, String name) visit,
  ) {
    final children =
        fileSystem
            .directory(directory)
            .listSync(followLinks: false)
            .whereType<Directory>()
            .map((entity) => entity.path)
            .toList()
          ..sort();
    for (final child in children) {
      final extension = paths.extension(child);
      final base = paths.basenameWithoutExtension(child);
      if (_setTypes.contains(extension)) {
        visit(child, '$namespace$base');
      } else if (extension.isEmpty) {
        final json = _contents(child, issues, required: false);
        final properties = json?['properties'];
        final namespaced =
            properties is Map && properties['provides-namespace'] == true;
        _walk(
          child,
          namespaced ? '$namespace${paths.basename(child)}/' : namespace,
          issues,
          visit,
        );
      } else {
        issues.add(
          AssetCatalogIssue(
            AssetCatalogIssueKind.unsupported,
            paths.basename(child),
            '${paths.basename(child)}: "$extension" assets are not compiled '
            '(supported: image sets, colour sets and the app icon).',
          ),
        );
      }
    }
  }

  Map<String, Object?>? _contents(
    String directory,
    List<AssetCatalogIssue> issues, {
    bool required = true,
  }) {
    final file = fileSystem.file(paths.join(directory, 'Contents.json'));
    if (!file.existsSync()) {
      if (required) {
        issues.add(
          AssetCatalogIssue(
            AssetCatalogIssueKind.invalid,
            paths.basename(directory),
            '${paths.basename(directory)} has no Contents.json.',
          ),
        );
      }
      return null;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, Object?>) return decoded;
      throw const FormatException('not a JSON object');
    } on FormatException catch (error) {
      issues.add(
        AssetCatalogIssue(
          AssetCatalogIssueKind.invalid,
          paths.basename(directory),
          '${paths.basename(directory)}/Contents.json is not valid '
          '(${error.message}).',
        ),
      );
      return null;
    }
  }

  static List<Map<String, Object?>> _list(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map<String, Object?>) item,
  ];

  static bool _isDark(Object? appearances) => _list(
    appearances,
  ).any((a) => a['appearance'] == 'luminosity' && a['value'] == 'dark');

  /// Variants this compiler cannot key (high contrast, light-only, …).
  static bool _hasOtherAppearance(Object? appearances) => _list(
    appearances,
  ).any((a) => !(a['appearance'] == 'luminosity' && a['value'] == 'dark'));

  static AssetGamut _gamut(Object? value) =>
      value == 'display-P3' ? AssetGamut.displayP3 : AssetGamut.srgb;

  List<CatalogImage> _images(String directory, Map<String, Object?> json) => [
    for (final image in _list(json['images']))
      if (image['filename'] case final String filename when filename.isNotEmpty)
        if (AssetIdiom.parse(image['idiom']) case final idiom?
            when AssetIdiom.runtime.contains(idiom) &&
                !_hasOtherAppearance(image['appearances']))
          CatalogImage(
            path: paths.join(directory, filename),
            filename: filename,
            idiom: idiom,
            scale: AssetScale.parse(image['scale']),
            dark: _isDark(image['appearances']),
            gamut: _gamut(image['display-gamut']),
          ),
  ];

  List<AppIconImage> _appIcons(String directory, Map<String, Object?> json) => [
    for (final image in _list(json['images']))
      if (image['filename'] case final String filename when filename.isNotEmpty)
        if (AssetIdiom.parse(image['idiom']) case final idiom?)
          AppIconImage(
            path: paths.join(directory, filename),
            filename: filename,
            idiom: idiom,
            size: _pointSize(image['size']),
            scale: AssetScale.parse(image['scale']),
            hasAppearance: _list(image['appearances']).isNotEmpty,
          ),
  ];

  static double? _pointSize(Object? value) {
    if (value is! String) return null;
    final parts = value.split('x');
    if (parts.length != 2) return null;
    return double.tryParse(parts.first);
  }

  List<CatalogColorEntry> _colors(
    String directory,
    String name,
    Map<String, Object?> json,
    List<AssetCatalogIssue> issues,
  ) {
    final colors = <CatalogColorEntry>[];
    for (final entry in _list(json['colors'])) {
      final idiom = AssetIdiom.parse(entry['idiom']) ?? AssetIdiom.universal;
      if (!AssetIdiom.runtime.contains(idiom) ||
          _hasOtherAppearance(entry['appearances'])) {
        continue;
      }
      final color = entry['color'];
      final components = color is Map ? color['components'] : null;
      if (color is! Map || components is! Map) {
        issues.add(
          AssetCatalogIssue(
            AssetCatalogIssueKind.unsupported,
            name,
            'Colour "$name" uses a system colour reference or no components; '
            'only explicit components are compiled.',
          ),
        );
        continue;
      }
      try {
        final white = components['white'];
        final (red, green, blue) = white != null
            ? (_component(white), _component(white), _component(white))
            : (
                _component(components['red']),
                _component(components['green']),
                _component(components['blue']),
              );
        final space = color['color-space'];
        colors.add(
          CatalogColorEntry(
            idiom: idiom,
            dark: _isDark(entry['appearances']),
            gamut: entry['display-gamut'] != null
                ? _gamut(entry['display-gamut'])
                : space == 'display-p3'
                ? AssetGamut.displayP3
                : AssetGamut.srgb,
            red: red,
            green: green,
            blue: blue,
            alpha: _component(components['alpha'] ?? '1'),
          ),
        );
      } on FormatException catch (error) {
        issues.add(
          AssetCatalogIssue(
            AssetCatalogIssueKind.invalid,
            name,
            'Colour "$name" has an invalid component (${error.message}).',
          ),
        );
      }
    }
    return colors;
  }

  /// `"0.5"`, `"128"` (0–255) or `"0x80"`, as 0…1.
  static double _component(Object? value) {
    final text = '$value'.trim();
    if (text.startsWith('0x') || text.startsWith('0X')) {
      final parsed = int.tryParse(text.substring(2), radix: 16);
      if (parsed == null || parsed > 255) throw FormatException(text);
      return parsed / 255;
    }
    final parsed = value is num ? value.toDouble() : double.tryParse(text);
    if (parsed == null) throw FormatException(text);
    return parsed > 1 ? parsed / 255 : parsed;
  }
}
