// studio: 023 — `xcross icons check`: every size iOS uses, what App Store
// Connect rejects and how the logo sits (specs/023-icon-studio).
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_slots.dart';

/// A problem with the icon set, with its fix.
@internal
@immutable
final class IconIssue {
  const IconIssue(
    this.code,
    this.severity,
    this.message, {
    required this.hint,
    this.file,
  });

  final String code;

  /// `error`, `warning` or `info`.
  final String severity;
  final String message;
  final String hint;
  final String? file;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity,
    'message': message,
    'hint': hint,
    'file': ?file,
  };
}

/// One slot and what was found for it.
@internal
@immutable
final class IconSlotState {
  const IconSlotState(this.slot, this.status, {this.file, this.actual});

  final IconSlot slot;

  /// `ok`, `missing`, `wrong_size` or `unreadable`.
  final String status;
  final String? file;

  /// `100x100` for `wrong_size`.
  final String? actual;

  Map<String, Object?> toJson() => {
    'role': slot.role.name,
    'label': slot.role.label,
    'idiom': slot.idiom,
    'points': slot.points,
    'scale': slot.scale,
    'pixels': slot.pixels,
    'file': file,
    'status': status,
    'actual': actual,
    'required': slot.required,
  };
}

/// The result of [IconCheck.run].
@internal
final class IconReport {
  IconReport({
    required this.path,
    required this.style,
    required this.slots,
    required this.issues,
    this.source,
    this.placement,
  });

  /// The `.appiconset` folder, or null when the project has none.
  final String? path;

  /// `all-sizes`, `single-size`, or null without a set.
  final String? style;
  final List<IconSlotState> slots;
  final List<IconIssue> issues;

  /// The file placement was measured on.
  final String? source;
  final IconPlacement? placement;

  String? get name => path == null ? null : p.basenameWithoutExtension(path!);

  int get errors => issues.where((i) => i.severity == 'error').length;
  int get warnings => issues.where((i) => i.severity == 'warning').length;

  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'icons_check',
    'set': name,
    'path': path,
    'style': style,
    'source': source,
    'slots': [for (final slot in slots) slot.toJson()],
    'placement': placement?.toJson(),
    'issues': [for (final issue in _ordered) issue.toJson()],
    'errors': errors,
    'warnings': warnings,
  };

  List<IconIssue> get _ordered => [
    for (final severity in const ['error', 'warning', 'info'])
      ...issues.where((issue) => issue.severity == severity),
  ];

  /// The text report: slots, placement, then issues (errors first).
  String render() {
    final out = StringBuffer();
    if (path == null) {
      out.writeln('No app icon set.');
    } else {
      out.writeln('App icon set: $path ($style)');
      for (final state in slots) {
        final mark = switch (state.status) {
          'ok' => '✓',
          _ when !state.slot.required && state.status == 'missing' => '!',
          _ => '✗',
        };
        final size = switch (state.slot.idiom) {
          'universal' => 'every size',
          'ios-marketing' => '',
          _ => '${state.slot.pointsText} pt @${state.slot.scale}x',
        };
        out.writeln(
          '  $mark ${state.slot.role.label.padRight(21)}'
          '${size.padRight(13)}'
          '${'${state.slot.pixels} px'.padRight(9)}'
          '${state.file ?? ''}'
          '${state.status == 'ok' ? '' : '  ${state.status.replaceAll('_', ' ')}'}'
          '${state.actual == null ? '' : ' (${state.actual})'}',
        );
      }
      final placement = this.placement;
      if (placement != null) {
        out.writeln('  Placement    ${describePlacement(placement)}');
      }
    }
    if (issues.isNotEmpty) out.writeln('Issues:');
    for (final issue in _ordered) {
      out
        ..writeln('  ${issue.severity}: [${issue.code}] ${issue.message}')
        ..writeln('    hint: ${issue.hint}');
    }
    out.writeln(
      errors == 0 && warnings == 0
          ? 'The icon set is ready.'
          : '$errors error${errors == 1 ? '' : 's'}, '
                '$warnings warning${warnings == 1 ? '' : 's'}.',
    );
    return out.toString();
  }

  /// One line: background, logo size, centring, corners.
  static String describePlacement(IconPlacement placement) {
    if (placement.fullBleed) return 'full-bleed artwork (not measured)';
    final box = placement.box;
    final parts = ['background ${iconColorHex(placement.background!)}'];
    if (box == null) {
      parts.add('no logo (one colour)');
    } else {
      parts
        ..add('logo ${(box.$3 * 100).round()}% × ${(box.$4 * 100).round()}%')
        ..add(
          placement.offset.$1.abs() <= IconCheck.centerTolerance &&
                  placement.offset.$2.abs() <= IconCheck.centerTolerance
              ? 'centred'
              : 'off centre',
        )
        ..add(
          placement.outsideMask > IconCheck.clipTolerance
              ? 'cut by the corners'
              : 'inside the corners',
        );
    }
    return parts.join(' · ');
  }
}

/// PNG header facts: size and whether it can hold alpha.
@internal
@immutable
final class IconPngInfo {
  const IconPngInfo(this.width, this.height, {required this.alphaChannel});

  /// Null when [bytes] is not a PNG.
  static IconPngInfo? read(Uint8List bytes) {
    if (bytes.length < 33 || !PngDecoder.isPng(bytes)) return null;
    final data = ByteData.sublistView(bytes);
    final colorType = bytes[25];
    var alpha = colorType == 4 || colorType == 6;
    var offset = 8;
    while (!alpha && offset + 8 <= bytes.length) {
      final length = data.getUint32(offset);
      final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
      if (type == 'tRNS') alpha = true;
      if (type == 'IDAT' || type == 'IEND') break;
      offset += 12 + length;
    }
    return IconPngInfo(
      data.getUint32(16),
      data.getUint32(20),
      alphaChannel: alpha,
    );
  }

  final int width;
  final int height;

  /// Colour type 4 or 6, or a `tRNS` chunk.
  final bool alphaChannel;
}

/// Checks a Flutter project's app icon set.
@internal
final class IconCheck {
  IconCheck({required this.fileSystem, required this.projectRoot});

  final HostFileSystemInterface fileSystem;
  final String projectRoot;

  /// Centre offsets up to 3% of the side count as centred.
  static const centerTolerance = 0.03;

  /// Up to 0.2% of the logo may fall outside the corners (anti-aliasing).
  static const clipTolerance = 0.002;

  /// A logo narrower and lower than this share of the side looks small.
  static const smallLogo = 0.45;

  static const _generateHint =
      'Make the set with `xcross icons generate <image.png>` (or "Make icon '
      'set…" on the App icon page).';

  IconReport run() {
    _reported.clear();
    final path = IconSetLocator.find(fileSystem, projectRoot);
    if (path == null) {
      return IconReport(
        path: null,
        style: null,
        slots: const [],
        issues: [
          IconIssue(
            'icons.no_set',
            'error',
            'No app icon set in '
                '${p.relative(IconSetLocator.catalog(projectRoot), from: projectRoot)}.',
            hint: _generateHint,
          ),
        ],
      );
    }
    final IconSet set;
    try {
      set = IconSet.read(fileSystem, path);
    } on FormatException catch (error) {
      return IconReport(
        path: path,
        style: null,
        slots: const [],
        issues: [
          IconIssue(
            'icons.contents_invalid',
            'error',
            '${p.basename(path)}: ${error.message}.',
            hint: _generateHint,
          ),
        ],
      );
    }
    return set.singleSize ? _singleSize(set) : _allSizes(set);
  }

  IconReport _singleSize(IconSet set) {
    final issues = <IconIssue>[];
    final name = set.universalEntry!.fileName;
    final state = _slot(IconSlots.universal, name, set.path, issues);
    final placement = state.status == 'ok' || state.status == 'wrong_size'
        ? _measure(set.path, name!, issues)
        : null;
    _variants(set, issues);
    return IconReport(
      path: set.path,
      style: 'single-size',
      slots: [state],
      issues: issues,
      source: placement == null ? null : name,
      placement: placement,
    );
  }

  IconReport _allSizes(IconSet set) {
    final issues = <IconIssue>[];
    final states = <IconSlotState>[];
    final ipad = IconSetLocator.supportsIpad(fileSystem, projectRoot);
    for (final slot in IconSlots.forApp(ipad: ipad)) {
      final entry = set.entryFor(slot);
      states.add(_slot(slot, entry?.fileName, set.path, issues));
    }
    // Placement is measured on the App Store icon, else the largest
    // readable one.
    final readable =
        states
            .where((s) => s.status == 'ok' || s.status == 'wrong_size')
            .toList()
          ..sort((a, b) => b.slot.pixels.compareTo(a.slot.pixels));
    final source = readable.isEmpty ? null : readable.first.file;
    final placement = source == null
        ? null
        : _measure(set.path, source, issues);
    _variants(set, issues);
    return IconReport(
      path: set.path,
      style: 'all-sizes',
      slots: states,
      issues: issues,
      source: source,
      placement: placement,
    );
  }

  /// Reported once per file: iPhone and iPad slots share files.
  final _reported = <String>{};

  IconSlotState _slot(
    IconSlot slot,
    String? fileName,
    String setPath,
    List<IconIssue> issues,
  ) {
    final where = slot.idiom == 'universal'
        ? 'The icon'
        : '${slot.role.label} ${slot.pointsText} pt @${slot.scale}x '
              '(${slot.pixels} px)';
    final file = fileName == null
        ? null
        : fileSystem.file(p.join(setPath, fileName));
    if (file == null || !file.existsSync()) {
      issues.add(
        IconIssue(
          'icons.missing',
          slot.required ? 'error' : 'warning',
          fileName == null
              ? '$where has no image.'
              : '$where: $fileName is missing.',
          hint: slot.required
              ? _generateHint
              : 'iOS scales another size, which can look soft. '
                    '$_generateHint',
          file: fileName,
        ),
      );
      return IconSlotState(slot, 'missing', file: fileName);
    }
    final bytes = file.readAsBytesSync();
    final info = IconPngInfo.read(bytes);
    if (info == null) {
      if (_reported.add('unreadable $fileName')) {
        issues.add(
          IconIssue(
            'icons.unreadable',
            'error',
            '$fileName is not a PNG.',
            hint: 'Export it as PNG. $_generateHint',
            file: fileName,
          ),
        );
      }
      return IconSlotState(slot, 'unreadable', file: fileName);
    }
    final wrongSize = info.width != slot.pixels || info.height != slot.pixels;
    if (wrongSize && _reported.add('size ${slot.pixels} $fileName')) {
      issues.add(
        IconIssue(
          'icons.wrong_size',
          'error',
          '$where: $fileName is ${info.width}×${info.height}, not '
              '${slot.pixels}×${slot.pixels}.',
          hint: 'Export it at ${slot.pixels}×${slot.pixels}. $_generateHint',
          file: fileName,
        ),
      );
    }
    if (slot.role == IconRole.appStore && info.alphaChannel) {
      if (_reported.add('alpha $fileName')) {
        issues.add(
          IconIssue(
            'icons.alpha',
            'error',
            '$fileName has an alpha channel; App Store Connect rejects it '
                '(ITMS-90717).',
            hint:
                'Export it without transparency on a solid background, or run '
                '`xcross icons generate '
                '${p.relative(p.join(setPath, fileName), from: projectRoot)} '
                '--background <colour>`, which flattens it.',
            file: fileName,
          ),
        );
      }
    } else if (info.alphaChannel && _reported.add('alpha $fileName')) {
      final transparent = _hasTransparency(bytes);
      if (transparent) {
        issues.add(
          IconIssue(
            'icons.alpha',
            'warning',
            '$fileName has transparent pixels; iOS shows them black.',
            hint: 'Put the icon on a solid background. $_generateHint',
            file: fileName,
          ),
        );
      }
    }
    return IconSlotState(
      slot,
      wrongSize ? 'wrong_size' : 'ok',
      file: fileName,
      actual: wrongSize ? '${info.width}x${info.height}' : null,
    );
  }

  static bool _hasTransparency(Uint8List bytes) {
    try {
      final rgba = PngDecoder.decode(bytes).rgba;
      for (var i = 3; i < rgba.length; i += 4) {
        if (rgba[i] < 255) return true;
      }
      return false;
    } on FormatException {
      return false;
    }
  }

  IconPlacement? _measure(
    String setPath,
    String fileName,
    List<IconIssue> issues,
  ) {
    final RgbaImage image;
    try {
      image = PngDecoder.decode(
        fileSystem.file(p.join(setPath, fileName)).readAsBytesSync(),
      );
    } on FormatException catch (error) {
      issues.add(
        IconIssue(
          'icons.unreadable',
          'error',
          '$fileName cannot be decoded: ${error.message}.',
          hint: 'Export it again as PNG. $_generateHint',
          file: fileName,
        ),
      );
      return null;
    }
    final placement = IconAnalyzer.analyze(image);
    if (placement.prerounded) {
      issues.add(
        IconIssue(
          'icons.prerounded',
          'warning',
          '$fileName already has rounded or transparent corners; iOS rounds '
              'the icon itself, so the corners show as a '
              'frame.',
          hint:
              'Export the icon square and full-bleed, without rounded '
              'corners.',
          file: fileName,
        ),
      );
    }
    final box = placement.box;
    if (box == null) return placement;
    if (placement.outsideMask > clipTolerance) {
      issues.add(
        IconIssue(
          'icons.clipped',
          'warning',
          "iOS's rounded corners cut "
              '${(placement.outsideMask * 100).toStringAsFixed(1)}% of the '
              'logo.',
          hint:
              'Leave more space around the logo: `xcross icons generate '
              '<logo.png> --padding 12`.',
          file: fileName,
        ),
      );
    }
    final (dx, dy) = placement.offset;
    if (dx.abs() > centerTolerance || dy.abs() > centerTolerance) {
      String side(double value, String positive, String negative) =>
          '${(value.abs() * 1024).round()} px '
          '${value > 0 ? positive : negative}';
      final parts = [
        if (dx.abs() > centerTolerance) side(dx, 'right', 'left'),
        if (dy.abs() > centerTolerance) side(dy, 'low', 'high'),
      ];
      issues.add(
        IconIssue(
          'icons.off_center',
          'warning',
          'The logo sits ${parts.join(' and ')} of centre (in the 1024 px '
              'icon).',
          hint:
              'Centre it in the image, or make the set from the logo alone: '
              '`xcross icons generate <logo.png>` centres it.',
          file: fileName,
        ),
      );
    }
    if (box.$3 < smallLogo && box.$4 < smallLogo) {
      issues.add(
        IconIssue(
          'icons.logo_small',
          'warning',
          'The logo fills only ${(box.$3 * 100).round()}% of the icon; on '
              'the home screen it looks small.',
          hint:
              'Crop the logo tight and make the set with a smaller margin: '
              '`xcross icons generate <logo.png> --padding 10`.',
          file: fileName,
        ),
      );
    }
    return placement;
  }

  void _variants(IconSet set, List<IconIssue> issues) {
    if (!set.hasVariants) return;
    issues.add(
      const IconIssue(
        'icons.variants',
        'info',
        'The set has dark or tinted variants (iOS 18); they are not checked.',
        hint:
            '`xcross icons generate` writes the default look and keeps the '
            'old set, with its variants, in the backup.',
      ),
    );
  }
}
