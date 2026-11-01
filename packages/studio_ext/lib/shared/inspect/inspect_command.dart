import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';

import 'package:studio_ext/src/shared/inspect/human_summary.dart';
import 'package:studio_ext/src/shared/inspect/inspect_failure.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/inspector.dart';
import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:studio_ext/src/shared/inspect/report_normalizer.dart';

/// `xcross inspect <ipa|app> [--json] [--normalize]`: a read-only report of what is inside
/// an iOS app bundle (feature 001, contracts/cli.md).
///
/// Never modifies the input and never contacts the network or a device.
/// Fatal problems are thrown as [CliError] with a `[inspect.<code>]` prefix
/// (exit code 1); with `--json` the error document is written first.
final class InspectCommand extends Command<void> {
  InspectCommand({
    required HostFileSystemInterface fileSystem,
    required void Function(String) write,
  }) : _fileSystem = fileSystem,
       _write = write {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print one JSON document (schema v1) instead of the summary.',
    );
    argParser.addFlag(
      'normalize',
      negatable: false,
      help:
          'With --json: replace volatile fields (hashes, sizes, profile '
          'UUIDs and dates) so builds of the same source compare equal.',
    );
  }

  final HostFileSystemInterface _fileSystem;
  final void Function(String) _write;

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Report what is inside an .ipa or .app: Info.plist, entitlements per '
      'Mach-O, provisioning profile, icons, launch screen and frameworks.';

  @override
  String get invocation => 'xcross inspect <ipa|app> [--json] [--normalize]';

  @override
  Future<void> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('Pass exactly one .ipa file or .app directory.');
    }
    final json = results.flag('json');
    final normalize = results.flag('normalize');
    if (normalize && !json) usageException('--normalize requires --json.');
    InspectSource? source;
    try {
      source = InspectSource.open(_fileSystem, results.rest.single);
      final report = inspectBundle(source);
      if (json) {
        final document = report.toJson();
        _write(
          encodeReportJson(
            normalize ? normalizeReportJson(document) : document,
          ),
        );
      } else {
        _write(renderHumanSummary(report));
      }
    } on InspectFailure catch (failure) {
      if (json) _write(encodeReportJson(failure.toJson()));
      throw CliError(
        '[${failure.code}] ${failure.message}\nhint: ${failure.hint}',
      );
    } finally {
      source?.close();
    }
  }
}
