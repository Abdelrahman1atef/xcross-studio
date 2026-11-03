// studio: 023 — `xcross icons check|generate`: the app icon set, checked and
// made from one image (specs/023-icon-studio).
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/assets/png_codec.dart';
import 'package:studio_ext/src/shared/icons/icon_analysis.dart';
import 'package:studio_ext/src/shared/icons/icon_check.dart';
import 'package:studio_ext/src/shared/icons/icon_generator.dart';

/// `xcross icons …`: the app icon set.
final class IconsCommand extends Command<void> {
  IconsCommand({
    required HostFileSystemInterface fileSystem,
    required String Function() currentDirectory,
    required void Function(String) write,
    DateTime Function()? now,
  }) {
    addSubcommand(
      IconsCheckCommand(
        fileSystem: fileSystem,
        currentDirectory: currentDirectory,
        write: write,
      ),
    );
    addSubcommand(
      IconsGenerateCommand(
        fileSystem: fileSystem,
        currentDirectory: currentDirectory,
        write: write,
        now: now,
      ),
    );
  }

  @override
  String get name => 'icons';

  @override
  String get description =>
      'Check the app icon set, or make it from one image (every size, no '
      'alpha channel).';
}

/// The project folder: `--project`, else the current one.
String _projectOption(
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

/// `xcross icons check [--json] [--project <dir>]`.
final class IconsCheckCommand extends Command<void> {
  IconsCheckCommand({
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
      'List every icon size iOS uses (notification, Settings, Spotlight, home '
      'screen, App Store) and check sizes, transparency and logo placement.';

  @override
  String get invocation => 'xcross icons check [--json] [--project <dir>]';

  @override
  Future<void> run() async {
    final root = _projectOption(this, _fileSystem, _currentDirectory());
    final report = IconCheck(fileSystem: _fileSystem, projectRoot: root).run();
    _write(
      argResults!.flag('json')
          ? '${jsonEncode(report.toJson())}\n'
          : report.render(),
    );
    if (report.errors > 0) {
      throw CliError(
        '[icons.check_failed] ${report.errors} '
        'error${report.errors == 1 ? '' : 's'} in the app icon set.\n'
        'hint: Fix them, or make the set with `xcross icons generate '
        '<image.png>`.',
      );
    }
  }
}

/// `xcross icons generate`: one image in, every size of the set out.
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
        valueHelp: '0-30',
        defaultsTo: '0',
        help:
            'Margin around the image, in percent of the side. Use 10–15 for a '
            'logo; 0 for a finished 1024 px icon.',
      )
      ..addOption(
        'output',
        valueHelp: 'dir',
        help:
            'Write the set into this folder instead of the project (nothing '
            'in the project changes).',
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
      'Make every icon size from one square image: centred, on a solid '
      'background, without an alpha channel. The old set is backed up to '
      '.xcross/icon-backups/.';

  @override
  String get invocation =>
      'xcross icons generate <image.png> [--background auto|#RRGGBB] '
      '[--padding <0-30>] [--output <dir>] [--json] [--project <dir>]';

  @override
  Future<void> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('Pass one PNG image.');
    }
    final backgroundText = results.option('background')!;
    final IconColor? background;
    if (backgroundText == 'auto') {
      background = null;
    } else {
      background = IconGenerator.parseColor(backgroundText);
      if (background == null) {
        usageException('--background must be auto or #RRGGBB.');
      }
    }
    final padding = double.tryParse(results.option('padding')!);
    if (padding == null || padding < 0 || padding > 30) {
      usageException('--padding must be a number from 0 to 30.');
    }
    final cwd = _currentDirectory();
    final output = results.option('output');
    final root = _projectOption(this, _fileSystem, cwd);
    final sourcePath = p.isAbsolute(results.rest.single)
        ? results.rest.single
        : p.join(cwd, results.rest.single);

    final RgbaImage source;
    try {
      final file = _fileSystem.file(sourcePath);
      if (!file.existsSync()) {
        throw const FormatException('the file does not exist');
      }
      final bytes = file.readAsBytesSync();
      if (!PngDecoder.isPng(bytes)) {
        throw const FormatException('it is not a PNG');
      }
      source = PngDecoder.decode(bytes);
    } on FormatException catch (error) {
      throw CliError(
        '[icons.source_unreadable] Cannot read $sourcePath: '
        '${error.message}.\n'
        'hint: Pass a PNG, ideally 1024×1024 or larger.',
      );
    }
    if (output == null &&
        !_fileSystem.directory(p.join(root, 'ios')).existsSync()) {
      throw CliError(
        '[icons.no_project] $root has no ios folder.\n'
        'hint: Run it in a Flutter project, pass --project <dir>, or write '
        'the set elsewhere with --output <dir>.',
      );
    }

    final master = IconGenerator.compose(
      source,
      background: background,
      padding: padding,
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

    if (results.flag('json')) {
      _write(
        '${jsonEncode({
          'v': 1,
          'type': 'icons_generate',
          'path': result.path,
          'written': result.written,
          'backup': result.backup,
          'background': iconColorHex(master.background),
          'padding': padding,
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
        '${_number(padding)}% · source ${source.width}×${source.height}',
      );
    if (result.backup != null) {
      out.writeln('  The old set is in ${result.backup}');
    }
    if (master.upscaled) {
      out
        ..writeln(
          'warning: [icons.upscaled] The image (${source.width}×'
          '${source.height}) was enlarged to fill the icon; it can look '
          'soft.',
        )
        ..writeln('  hint: Use a 1024×1024 or larger source.');
    }
    if (check != null) out.write(check.render());
    _write(out.toString());
  }

  static String _number(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);
}
