// studio: 023, 024 — `xcross icons generate` and `icons preview`: every icon a
// project needs from one design (specs/023-icon-studio,
// specs/024-icon-splash-studio).
import 'dart:convert';
import 'dart:io' show stdin;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_check.dart';
import 'package:studio_ext/src/shared/icons/icon_composer.dart';
import 'package:studio_ext/src/shared/icons/icon_generator.dart';
import 'package:studio_ext/src/shared/icons/icon_options.dart';
import 'package:studio_ext/src/shared/icons/icon_targets.dart';

/// Options whose value is text, by their command-line name.
const _textOptions = [
  'background',
  'background2',
  'background3',
  'background4',
  'background-type',
  'background-image',
  'gradient-angle',
  'padding',
  'foreground',
  'effect',
  'texture',
  'badge-image',
  'targets',
  'name',
  'shape',
];

/// Options holding a path, stored relative to the project.
const _pathOptions = ['source', 'background-image', 'badge-image'];

const _flagOptions = ['trim', 'themed'];

/// `xcross icons generate`: one design in, every file out.
final class IconsGenerateCommand extends Command<void> {
  IconsGenerateCommand({
    required HostFileSystemInterface fileSystem,
    required String Function() currentDirectory,
    required void Function(String) write,
    DateTime Function()? now,
  }) : _fileSystem = fileSystem,
       _currentDirectory = currentDirectory,
       _write = write,
       _now = now ?? DateTime.now {
    argParser
      ..addOption(
        'background',
        valueHelp: 'auto|#RRGGBB',
        defaultsTo: 'auto',
        help:
            "Colour behind the image. auto: the image's own border colour "
            'when it is one opaque colour, else white.',
      )
      ..addOption(
        'padding',
        valueHelp: 'n or top,right,bottom,left',
        defaultsTo: '0',
        help:
            'Margin around the image, each 0–45, in percent of the side. Use '
            '10–15 for a logo; 0 for a finished 1024 px icon.',
      )
      ..addFlag(
        'trim',
        negatable: false,
        help: 'Remove transparent or one-colour borders from the image first.',
      )
      ..addOption(
        'foreground',
        valueHelp: '#RRGGBB',
        help: 'Recolour the image, keeping its transparency.',
      )
      ..addOption(
        'effect',
        allowed: const ['none', 'drop-shadow', 'cast-shadow', 'score'],
        defaultsTo: 'none',
        help: 'Shadow or fold on the logo.',
      )
      ..addOption(
        'background-type',
        allowed: const ['color', 'gradient', 'mesh', 'image'],
        defaultsTo: 'color',
        help: 'gradient: --background to --background2. mesh: four corners.',
      )
      ..addOption('background2', valueHelp: '#RRGGBB')
      ..addOption('background3', valueHelp: '#RRGGBB')
      ..addOption('background4', valueHelp: '#RRGGBB')
      ..addOption(
        'gradient-angle',
        valueHelp: 'degrees',
        defaultsTo: '135',
        help: '0 goes up, 90 right.',
      )
      ..addOption(
        'background-image',
        valueHelp: 'png',
        help: 'Fills the square, cropped, not stretched.',
      )
      ..addOption(
        'texture',
        allowed: const [
          'none',
          'argyle',
          'concentric',
          'contour',
          'coral',
          'fabric',
          'halftone',
          'maze',
          'mosaic',
          'polka',
          'stipple',
          'waves',
        ],
        defaultsTo: 'none',
        help: 'A subtle pattern over the background.',
      )
      ..addOption(
        'badge-image',
        valueHelp: 'png',
        help: 'Drawn across the bottom, as wide as the icon.',
      )
      ..addOption(
        'targets',
        valueHelp: 'list',
        help:
            'Comma list of ios, android, notification, web, macos, watchos, '
            'tvos, android-tv, play-banner; or all (the folders the project '
            'has). Without it: the iOS set.',
      )
      ..addOption(
        'name',
        valueHelp: 'name',
        defaultsTo: IconTargets.defaultName,
        help: 'File name of the Android and notification icons.',
      )
      ..addOption(
        'shape',
        allowed: const ['square', 'squircle', 'circle'],
        defaultsTo: 'squircle',
        help: 'Android launcher outline.',
      )
      ..addFlag(
        'themed',
        negatable: false,
        help: 'Add the monochrome layer Android 13+ tints.',
      )
      ..addOption(
        'output',
        valueHelp: 'dir',
        help:
            'Write here instead of the project (nothing in the project '
            'changes).',
      )
      ..addOption(
        'zip',
        valueHelp: 'file',
        help: 'Write one archive (nothing in the project changes).',
      )
      ..addFlag(
        'config',
        negatable: false,
        help: 'Read the settings saved in ${AssetsFile.name}.',
      )
      ..addFlag(
        'save-config',
        negatable: false,
        help: 'Save these settings in ${AssetsFile.name}.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print one JSON object instead of the report.',
      )
      ..addOption(
        'project',
        valueHelp: 'dir',
        help: 'The Flutter project (default: the current folder).',
      );
  }

  final HostFileSystemInterface _fileSystem;
  final String Function() _currentDirectory;
  final void Function(String) _write;
  final DateTime Function() _now;

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Make every icon from one image: padding, colours, effects, textures; '
      'iOS, Android, notification, web, macOS and more. Replaced files are '
      'backed up to .xcross/icon-backups/.';

  @override
  String get invocation =>
      'xcross icons generate <image.png> [design options] [--targets <list>] '
      '[--output <dir> | --zip <file>] [--config] [--save-config] [--json] '
      '[--project <dir>]';

  @override
  Future<void> run() async {
    final results = argResults!;
    final cwd = _currentDirectory();
    final root = projectOption(this, _fileSystem, cwd);

    final Map<String, Object?> saved;
    try {
      saved = results.flag('config')
          ? AssetsFile.read(_fileSystem, root, 'icons')
          : const {};
    } on IconOptionError catch (error) {
      usageException(error.message);
    }
    final values = <String, Object?>{...saved};
    for (final option in _textOptions) {
      if (results.wasParsed(option)) values[option] = results.option(option);
    }
    for (final flag in _flagOptions) {
      if (results.wasParsed(flag)) values[flag] = true;
    }
    if (results.rest.length > 1) usageException('Pass one PNG image.');
    final sourceArgument = results.rest.isEmpty
        ? (saved['source'] as String?)
        : results.rest.single;
    if (sourceArgument == null) usageException('Pass one PNG image.');

    // Paths in the assets file are relative to the project, others to here.
    final base = results.rest.isEmpty ? root : cwd;
    final sourcePath = p.isAbsolute(sourceArgument)
        ? sourceArgument
        : p.join(base, sourceArgument);

    final IconOptions options;
    try {
      options = IconOptions.parse(
        values,
        readImage: (path) => _readPng(
          p.isAbsolute(path)
              ? path
              : p.join(results.flag('config') ? root : cwd, path),
        ),
      );
    } on IconOptionError catch (error) {
      usageException(error.message);
    }

    final output = results.option('output');
    final zip = results.option('zip');
    if (output != null && zip != null) {
      usageException('Pass --output or --zip, not both.');
    }
    final toProject = output == null && zip == null;
    final legacy = options.targets == null;
    if (toProject &&
        legacy &&
        !_fileSystem.directory(p.join(root, 'ios')).existsSync()) {
      throw CliError(
        '[icons.no_project] $root has no ios folder.\n'
        'hint: Run it in a Flutter project, pass --project <dir>, or write '
        'the set elsewhere with --output <dir>.',
      );
    }

    final source = _readPng(sourcePath);
    final composer = IconComposer(source, options.design);

    if (legacy && zip == null) {
      _writeIosSet(composer, options, source, root: root, output: output);
    } else {
      await _writeTargets(
        composer,
        options,
        source,
        root: root,
        output: output,
        zip: zip,
        allTargets: '${values['targets']}'.trim() == 'all',
      );
    }

    if (results.flag('save-config')) {
      AssetsFile.write(_fileSystem, root, 'icons', {
        'source': AssetsFile.relativePath(sourcePath, root),
        for (final MapEntry(:key, :value) in values.entries)
          key: _pathOptions.contains(key) && value is String
              ? AssetsFile.relativePath(
                  p.isAbsolute(value) ? value : p.join(cwd, value),
                  root,
                )
              : value,
      });
    }
  }

  RgbaImage _readPng(String path) {
    try {
      final file = _fileSystem.file(path);
      if (!file.existsSync()) {
        throw const FormatException('the file does not exist');
      }
      final bytes = file.readAsBytesSync();
      if (!PngDecoder.isPng(bytes)) {
        throw const FormatException('it is not a PNG');
      }
      return PngDecoder.decode(bytes);
    } on FormatException catch (error) {
      throw CliError(
        '[icons.source_unreadable] Cannot read $path: ${error.message}.\n'
        'hint: Pass a PNG, ideally 1024×1024 or larger.',
      );
    }
  }

  /// Feature 023: the iOS set, flat in `--output`, or in the project.
  void _writeIosSet(
    IconComposer composer,
    IconOptions options,
    RgbaImage source, {
    required String root,
    required String? output,
  }) {
    final results = argResults!;
    final master = IconMaster(
      composer.draw(IconGenerator.side, IconGenerator.side),
      composer.colors.first,
      upscaled: composer.upscaledAt(IconGenerator.side),
    );
    final result = IconGenerator.write(
      fileSystem: _fileSystem,
      files: IconGenerator.files(master),
      now: _now(),
      projectRoot: output == null ? root : null,
      output: output,
    );
    final check = output == null
        ? IconCheck(fileSystem: _fileSystem, projectRoot: root).run()
        : null;
    final padding = options.design.padding;

    if (results.flag('json')) {
      _write(
        '${jsonEncode({
          'v': 1,
          'type': 'icons_generate',
          'path': result.path,
          'written': result.written,
          'backup': result.backup,
          'background': iconColorHex(master.background),
          'padding': padding.isUniform ? padding.top : padding.text,
          'upscaled': master.upscaled,
          'source': {'width': source.width, 'height': source.height},
          'check': check?.toJson(),
        })}\n',
      );
      return;
    }
    final out = StringBuffer()
      ..writeln(
        'Wrote ${result.written.length} icons and Contents.json to '
        '${result.path}',
      )
      ..writeln(
        '  Background ${iconColorHex(master.background)} · margin '
        '${padding.text}% · source ${source.width}×${source.height}',
      );
    if (result.backup != null) {
      out.writeln('  The old set is in ${result.backup}');
    }
    if (master.upscaled) out.write(_upscaledWarning(source));
    if (check != null) out.write(check.render());
    _write(out.toString());
  }

  static String _upscaledWarning(RgbaImage source) =>
      'warning: [icons.upscaled] The image (${source.width}×${source.height}) '
      'was enlarged to fill the icon; it can look soft.\n'
      '  hint: Use a 1024×1024 or larger source.\n';

  /// Feature 024: named targets, into the project, a folder or an archive.
  Future<void> _writeTargets(
    IconComposer composer,
    IconOptions options,
    RgbaImage source, {
    required String root,
    required String? output,
    required String? zip,
    required bool allTargets,
  }) async {
    final results = argResults!;
    final toProject = output == null && zip == null;
    final targets = options.targets ?? const [IconTarget.ios];
    final selected = <IconTarget>[];
    final notes = <String>[];
    for (final target in targets) {
      final folder = target.projectFolder;
      if (toProject && folder == null) {
        throw CliError(
          '[icons.target_missing] A Flutter project has no place for '
          '${target.option}.\n'
          'hint: Write it with --output <dir> or --zip <file>.',
        );
      }
      if (toProject &&
          !_fileSystem.directory(p.join(root, folder)).existsSync()) {
        if (allTargets) {
          notes.add(
            'Skipped ${target.option}: the project has no $folder folder.',
          );
          continue;
        }
        throw CliError(
          '[icons.target_missing] $root has no $folder folder for '
          '${target.option}.\n'
          'hint: Remove it from --targets, or write it with --output <dir>.',
        );
      }
      selected.add(target);
    }

    final files = <String, Uint8List>{};
    final counts = <String, Object?>{};
    final issues = <IconIssue>[];
    if (composer.upscaledAt(IconGenerator.side)) {
      issues.add(
        IconIssue(
          'icons.upscaled',
          'warning',
          'The image (${source.width}×${source.height}) was enlarged to fill '
              'the icon; it can look soft.',
          hint: 'Use a 1024×1024 or larger source.',
        ),
      );
    }
    if (options.design.foreground != null &&
        !IconComposer.hasTransparency(composer.logo)) {
      issues.add(
        const IconIssue(
          'icons.tint_opaque',
          'warning',
          'The image has no transparency, so recolouring fills all of it.',
          hint: 'Use a logo on a transparent background.',
        ),
      );
    }
    for (final target in selected) {
      final built = IconTargets.build(
        target,
        composer,
        name: options.name,
        shape: options.shape,
        themed: options.themed,
      );
      files.addAll(built.files);
      issues.addAll(built.issues);
      counts[target.option] = {'files': built.files.length};
      if (target == IconTarget.web) {
        final manifest = _fileSystem.file(p.join(root, 'web', 'manifest.json'));
        if (manifest.existsSync()) {
          final updated = IconTargets.updatedManifest(
            manifest.readAsStringSync(),
          );
          if (updated != null) {
            files['web/manifest.json'] = Uint8List.fromList(
              utf8.encode(updated),
            );
          }
        }
      }
    }

    String? backup;
    final String path;
    if (zip != null) {
      path = p.isAbsolute(zip) ? zip : p.join(_currentDirectory(), zip);
      _writeZip(path, files);
    } else if (output != null) {
      path = p.isAbsolute(output)
          ? output
          : p.join(_currentDirectory(), output);
      _writeFiles(path, files);
    } else {
      path = root;
      backup = _backUp(root, files.keys);
      _writeFiles(root, files);
    }

    final errors = issues.where((i) => i.severity == 'error').length;
    if (results.flag('json')) {
      _write(
        '${jsonEncode({
          'v': 1,
          'type': 'icons_generate',
          'path': path,
          'written': files.keys.toList()..sort(),
          'backup': backup,
          'background': iconColorHex(composer.colors.first),
          'targets': counts,
          'notes': notes,
          'issues': [
            for (final issue in issues) {'code': issue.code, 'severity': issue.severity, 'message': issue.message, 'hint': issue.hint},
          ],
        })}\n',
      );
    } else {
      final out = StringBuffer()
        ..writeln('Wrote ${files.length} files to $path');
      for (final MapEntry(:key, :value) in counts.entries) {
        out.writeln('  $key: ${(value! as Map)['files']} files');
      }
      if (backup != null) out.writeln('  Replaced files are in $backup');
      notes.forEach(out.writeln);
      for (final issue in issues) {
        out
          ..writeln('${issue.severity}: [${issue.code}] ${issue.message}')
          ..writeln('  hint: ${issue.hint}');
      }
      _write(out.toString());
    }
    if (errors > 0) {
      throw CliError(
        '[icons.generate_failed] $errors '
        'error${errors == 1 ? '' : 's'} while making the icons.',
      );
    }
  }

  void _writeFiles(String base, Map<String, Uint8List> files) {
    for (final MapEntry(:key, :value) in files.entries) {
      final file = _fileSystem.file(p.joinAll([base, ...key.split('/')]));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(value);
    }
  }

  void _writeZip(String path, Map<String, Uint8List> files) {
    final archive = Archive();
    for (final name in files.keys.toList()..sort()) {
      archive.add(
        // A fixed time, so the same design gives the same archive.
        ArchiveFile.bytes(name, files[name]!)..lastModTime = 0,
      );
    }
    final file = _fileSystem.file(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  }

  /// Copies the files about to be replaced under
  /// `.xcross/icon-backups/<stamp>/`, keeping their paths.
  String? _backUp(String root, Iterable<String> paths) {
    final existing = [
      for (final path in paths)
        if (_fileSystem
            .file(p.joinAll([root, ...path.split('/')]))
            .existsSync())
          path,
    ];
    if (existing.isEmpty) return null;
    final backup = p.join(root, '.xcross', 'icon-backups', backupStamp(_now()));
    for (final path in existing) {
      final target = _fileSystem.file(p.joinAll([backup, ...path.split('/')]));
      target.parent.createSync(recursive: true);
      _fileSystem
          .file(p.joinAll([root, ...path.split('/')]))
          .copySync(target.path);
    }
    return backup;
  }
}

/// `yyyyMMdd-HHmmss`, the backup folder's name.
String backupStamp(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

/// The project folder: `--project`, else the current one.
String projectOption(
  Command<void> command,
  HostFileSystemInterface fileSystem,
  String cwd,
) {
  final option = command.argResults!.option('project');
  final root = option ?? cwd;
  if (option != null && !fileSystem.directory(root).existsSync()) {
    command.usageException('--project $root does not exist.');
  }
  return root;
}

/// `xcross icons preview --serve --output <dir>`: stays running and draws each
/// design it is sent, so the desktop app shows what the CLI really makes
/// without starting a process per change (AC-024-17).
final class IconsPreviewCommand extends Command<void> {
  IconsPreviewCommand({
    required HostFileSystemInterface fileSystem,
    required void Function(String) write,
    Stream<List<int>>? input,
  }) : _fileSystem = fileSystem,
       _write = write,
       _input = input {
    argParser
      ..addFlag(
        'serve',
        negatable: false,
        help: 'Read one JSON design per line until the input closes.',
      )
      ..addOption(
        'output',
        valueHelp: 'dir',
        mandatory: true,
        help: 'Folder for the preview images.',
      );
  }

  /// Each request's images replace the last one's.
  static const previewSize = 512;

  final HostFileSystemInterface _fileSystem;
  final void Function(String) _write;
  final Stream<List<int>>? _input;

  @override
  String get name => 'preview';

  @override
  String get description =>
      'Draw designs on request (for the desktop app): one JSON design per line '
      'in, one JSON line with image paths out.';

  @override
  Future<void> run() async {
    final output = argResults!.option('output')!;
    _fileSystem.directory(output).createSync(recursive: true);
    final images = <String, RgbaImage>{};
    RgbaImage read(String path) {
      final key =
          '$path|${_fileSystem.file(path).lastModifiedSync().millisecondsSinceEpoch}';
      return images.putIfAbsent(key, () {
        images.removeWhere((other, _) => other.startsWith('$path|'));
        return PngDecoder.decode(_fileSystem.file(path).readAsBytesSync());
      });
    }

    final lines = (_input ?? stdin)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final previous = <String>[];
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Object? seq;
      try {
        final request = jsonDecode(line);
        if (request is! Map<String, Object?>) {
          throw const IconOptionError('a design must be a JSON object');
        }
        seq = request['seq'];
        final paths = _draw(request, read, output, '${seq ?? 0}');
        _write(
          '${jsonEncode({'v': 1, 'type': 'icons_preview', 'seq': seq, 'paths': paths})}\n',
        );
        for (final old in previous) {
          if (!paths.values.contains(old)) {
            final file = _fileSystem.file(old);
            if (file.existsSync()) file.deleteSync();
          }
        }
        previous
          ..clear()
          ..addAll(paths.values.cast<String>());
      } on Object catch (error) {
        final message = error is IconOptionError ? error.message : '$error';
        _write(
          '${jsonEncode({'v': 1, 'type': 'icons_preview', 'seq': seq, 'error': message})}\n',
        );
      }
    }
  }

  Map<String, Object?> _draw(
    Map<String, Object?> request,
    RgbaImage Function(String) read,
    String output,
    String seq,
  ) {
    final source = request['source'];
    if (source is! String) {
      throw const IconOptionError('the design has no source image');
    }
    final options = IconOptions.parse(request, readImage: read);
    final composer = IconComposer(read(source), options.design);
    const size = previewSize;
    final variants = <String, RgbaImage?>{
      'full': composer.draw(size, size),
      'adaptive': composer.draw(size, size, viewport: 72 / 108),
      'maskable': composer.draw(size, size, viewport: 0.8),
      'silhouette': composer.silhouette(size, size),
      'banner': composer.draw(640, 360),
    };
    final paths = <String, Object?>{};
    for (final MapEntry(:key, :value) in variants.entries) {
      if (value == null) continue;
      final path = p.join(output, 'preview-$seq-$key.png');
      _fileSystem.file(path).writeAsBytesSync(PngEncoder.encode(value));
      paths[key] = path;
    }
    return paths;
  }
}
