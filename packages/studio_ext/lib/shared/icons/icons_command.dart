// studio: 023 — `xcross icons check|generate`: the app icon set, checked and
// made from one image (specs/023-icon-studio).
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:studio_ext/shared/icons/icons_generate_command.dart';
import 'package:studio_ext/src/shared/icons/icon_check.dart';

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
    addSubcommand(IconsPreviewCommand(fileSystem: fileSystem, write: write));
  }

  @override
  String get name => 'icons';

  @override
  String get description =>
      'Check the app icon set, or make it from one image (every size, no '
      'alpha channel).';
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
    final root = projectOption(this, _fileSystem, _currentDirectory());
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
