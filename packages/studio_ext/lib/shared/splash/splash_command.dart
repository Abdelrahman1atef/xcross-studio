// studio: 024 — `xcross splash generate|check`: the native splash screen
// (specs/024-icon-splash-studio, User Story 2).
import 'dart:convert';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/asset_files_writer.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_design.dart';
import 'package:studio_ext/src/shared/icons/icon_generator.dart';
import 'package:studio_ext/src/shared/icons/icon_options.dart';
import 'package:studio_ext/src/shared/splash/splash_check.dart';
import 'package:studio_ext/src/shared/splash/splash_design.dart';

const _textOptions = [
  'background',
  'dark-background',
  'dark-logo',
  'logo-width',
  'padding',
  'margin',
  'branding',
  'dark-branding',
  'platforms',
];

const _pathOptions = ['source', 'dark-logo', 'branding', 'dark-branding'];

/// A splash design from option values, as the command line, the assets file
/// and a preview request hold them.
SplashDesign parseSplashDesign(
  Map<String, Object?> values, {
  required RgbaImage logo,
  required RgbaImage Function(String path) readImage,
}) {
  String? text(String key) {
    final value = values[key];
    return value == null ? null : '$value';
  }

  IconColor color(String key, IconColor fallback) {
    final value = text(key);
    if (value == null) return fallback;
    final parsed = IconGenerator.parseColor(value);
    if (parsed == null) throw IconOptionError('--$key must be #RRGGBB.');
    return parsed;
  }

  final darkText = text('dark-background');
  final width = double.tryParse(text('logo-width') ?? '120');
  if (width == null || width < 16 || width > 1024) {
    throw const IconOptionError('--logo-width must be from 16 to 1024 points.');
  }
  final padding = IconPadding.parse(text('padding') ?? '0');
  if (padding == null) {
    throw const IconOptionError(
      '--padding must be one number, or top,right,bottom,left, each from 0 to '
      '45.',
    );
  }
  final margin = SplashMargin.parse(text('margin') ?? '0');
  if (margin == null) {
    throw const IconOptionError(
      '--margin must be one number, or top,right,bottom,left, in points.',
    );
  }
  RgbaImage? image(String key) {
    final path = text(key);
    return path == null ? null : readImage(path);
  }

  return SplashDesign(
    logo: logo,
    darkLogo: image('dark-logo'),
    background: color('background', (255, 255, 255)),
    darkBackground: darkText == null
        ? null
        : color('dark-background', (0, 0, 0)),
    logoWidth: width,
    padding: padding,
    margin: margin,
    branding: image('branding'),
    darkBranding: image('dark-branding'),
  );
}

/// `xcross splash …`.
final class SplashCommand extends Command<void> {
  SplashCommand({
    required HostFileSystemInterface fileSystem,
    required String Function() currentDirectory,
    required void Function(String) write,
    DateTime Function()? now,
  }) {
    addSubcommand(
      SplashCheckCommand(
        fileSystem: fileSystem,
        currentDirectory: currentDirectory,
        write: write,
      ),
    );
    addSubcommand(
      SplashGenerateCommand(
        fileSystem: fileSystem,
        currentDirectory: currentDirectory,
        write: write,
        now: now,
      ),
    );
  }

  @override
  String get name => 'splash';

  @override
  String get description =>
      'Check the native splash screen, or make it from a logo (iOS and '
      'Android, light and dark).';
}

String _project(
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

/// `xcross splash check [--json] [--project <dir>]`.
final class SplashCheckCommand extends Command<void> {
  SplashCheckCommand({
    required HostFileSystemInterface fileSystem,
    required String Function() currentDirectory,
    required void Function(String) write,
  }) : _fileSystem = fileSystem,
       _currentDirectory = currentDirectory,
       _write = write {
    argParser
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

  @override
  String get name => 'check';

  @override
  String get description =>
      'Show what the app displays at launch on iOS and Android, and what is '
      'wrong with it.';

  @override
  Future<void> run() async {
    final root = _project(this, _fileSystem, _currentDirectory());
    final report = SplashCheck(
      fileSystem: _fileSystem,
      projectRoot: root,
    ).run();
    _write(
      argResults!.flag('json')
          ? '${jsonEncode(report.toJson())}\n'
          : report.render(),
    );
    if (report.errors > 0) {
      throw CliError(
        '[splash.check_failed] ${report.errors} '
        'error${report.errors == 1 ? '' : 's'} in the splash screen.\n'
        'hint: Fix them, or make it with `xcross splash generate <logo.png>`.',
      );
    }
  }
}

/// `xcross splash generate <logo.png>`.
final class SplashGenerateCommand extends Command<void> {
  SplashGenerateCommand({
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
        valueHelp: '#RRGGBB',
        defaultsTo: '#FFFFFF',
        help: 'The screen colour.',
      )
      ..addOption(
        'dark-background',
        valueHelp: '#RRGGBB',
        help: 'The screen colour in dark mode.',
      )
      ..addOption('dark-logo', valueHelp: 'png', help: 'The logo in dark mode.')
      ..addOption(
        'logo-width',
        valueHelp: 'points',
        defaultsTo: '120',
        help: 'The width the logo is shown at.',
      )
      ..addOption(
        'padding',
        valueHelp: 'n or top,right,bottom,left',
        defaultsTo: '0',
        help: 'Space around the logo, in percent of its width.',
      )
      ..addOption(
        'margin',
        valueHelp: 'n or top,right,bottom,left',
        defaultsTo: '0',
        help:
            'Space around the logo, in points. A larger top margin moves it '
            'down.',
      )
      ..addOption(
        'branding',
        valueHelp: 'png',
        help: 'A small image near the bottom of the screen.',
      )
      ..addOption(
        'dark-branding',
        valueHelp: 'png',
        help: 'The branding image in dark mode.',
      )
      ..addOption(
        'platforms',
        valueHelp: 'ios,android',
        help: 'Default: the folders the project has.',
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
      'Make the iOS and Android splash screens from a logo. Replaced files '
      'are backed up to .xcross/icon-backups/.';

  @override
  String get invocation =>
      'xcross splash generate <logo.png> [options] [--output <dir> | --zip '
      '<file>] [--config] [--save-config] [--json] [--project <dir>]';

  @override
  Future<void> run() async {
    final results = argResults!;
    final cwd = _currentDirectory();
    final root = _project(this, _fileSystem, cwd);
    final fromConfig = results.flag('config');

    final Map<String, Object?> saved;
    try {
      saved = fromConfig
          ? AssetsFile.read(_fileSystem, root, 'splash')
          : const {};
    } on IconOptionError catch (error) {
      usageException(error.message);
    }
    final values = <String, Object?>{...saved};
    for (final option in _textOptions) {
      if (results.wasParsed(option)) values[option] = results.option(option);
    }
    if (results.rest.length > 1) usageException('Pass one PNG logo.');
    final argument = results.rest.isEmpty
        ? (saved['source'] as String?)
        : results.rest.single;
    if (argument == null) usageException('Pass one PNG logo.');
    final logoPath = p.isAbsolute(argument)
        ? argument
        : p.join(results.rest.isEmpty ? root : cwd, argument);

    final output = results.option('output');
    final zip = results.option('zip');
    if (output != null && zip != null) {
      usageException('Pass --output or --zip, not both.');
    }
    final toProject = output == null && zip == null;
    final platforms = _platforms(values['platforms'], root, toProject);

    final SplashDesign design;
    try {
      design = parseSplashDesign(
        values,
        logo: _readPng(logoPath),
        readImage: (path) => _readPng(
          p.isAbsolute(path) ? path : p.join(fromConfig ? root : cwd, path),
        ),
      );
    } on IconOptionError catch (error) {
      usageException(error.message);
    }

    final files = <String, Uint8List>{
      if (platforms.contains('ios')) ...SplashFiles.ios(design),
      if (platforms.contains('android')) ...SplashFiles.android(design),
    };
    final issues = <Map<String, Object?>>[
      if (platforms.contains('android') &&
          SplashImages.android12Clipped(design))
        {
          'code': 'splash.android12_clipped',
          'severity': 'warning',
          'message':
              'At ${design.logoWidth.round()} points the logo would be cut by '
              "Android 12's circle, so its icon uses a smaller size "
              '(${SplashImages.android12SafeSide.round()} dp).',
          'hint': 'Use a smaller --logo-width, or a square logo.',
        },
    ];

    final writer = AssetFilesWriter(_fileSystem);
    String? backup;
    final String path;
    if (zip != null) {
      path = p.isAbsolute(zip) ? zip : p.join(cwd, zip);
      writer.writeZip(path, files);
    } else if (output != null) {
      path = p.isAbsolute(output) ? output : p.join(cwd, output);
      writer.writeFiles(path, files);
    } else {
      path = root;
      backup = writer.backUp(root, files.keys, _now());
      writer.writeFiles(root, files);
    }
    final check = toProject
        ? SplashCheck(fileSystem: _fileSystem, projectRoot: root).run()
        : null;

    if (results.flag('save-config')) {
      AssetsFile.write(_fileSystem, root, 'splash', {
        'source': AssetsFile.relativePath(logoPath, root),
        for (final MapEntry(:key, :value) in values.entries)
          key: _pathOptions.contains(key) && value is String
              ? AssetsFile.relativePath(
                  p.isAbsolute(value) ? value : p.join(cwd, value),
                  root,
                )
              : value,
      });
    }

    if (results.flag('json')) {
      _write(
        '${jsonEncode({'v': 1, 'type': 'splash_generate', 'path': path, 'written': files.keys.toList()..sort(), 'backup': backup, 'platforms': platforms, 'issues': issues, 'check': check?.toJson()})}\n',
      );
      return;
    }
    final out = StringBuffer()..writeln('Wrote ${files.length} files to $path');
    if (backup != null) out.writeln('  Replaced files are in $backup');
    for (final issue in issues) {
      out
        ..writeln(
          '${issue['severity']}: [${issue['code']}] ${issue['message']}',
        )
        ..writeln('  hint: ${issue['hint']}');
    }
    if (check != null) out.write(check.render());
    _write(out.toString());
  }

  List<String> _platforms(Object? value, String root, bool toProject) {
    final named = value == null
        ? null
        : '$value'.split(',').map((part) => part.trim()).toList();
    for (final platform in named ?? const <String>[]) {
      if (platform != 'ios' && platform != 'android') {
        usageException('--platforms takes ios and android.');
      }
    }
    if (!toProject) return named ?? const ['ios', 'android'];
    bool has(String folder) =>
        _fileSystem.directory(p.join(root, folder)).existsSync();
    if (named == null) {
      final found = [if (has('ios')) 'ios', if (has('android')) 'android'];
      if (found.isEmpty) {
        throw CliError(
          '[icons.no_project] $root has no ios or android folder.\n'
          'hint: Run it in a Flutter project, pass --project <dir>, or write '
          'elsewhere with --output <dir>.',
        );
      }
      return found;
    }
    for (final platform in named) {
      if (!has(platform)) {
        throw CliError(
          '[icons.target_missing] $root has no $platform folder.\n'
          'hint: Remove it from --platforms, or write it with --output <dir>.',
        );
      }
    }
    return named;
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
        'hint: Pass a PNG with a transparent background.',
      );
    }
  }
}
