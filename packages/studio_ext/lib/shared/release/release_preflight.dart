// studio: 018 — the release checks that need only the project's sources, run
// before a build compiles anything (specs/018-app-store-build).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/release/release_checks.dart';

/// What the checks before a build found.
final class PreflightResult {
  PreflightResult._(this._report);

  final ReleaseReport _report;

  int get errors => _report.errors;
  int get warnings => _report.warnings;

  /// Errors and warnings, one `[code] message` each (info findings, such as
  /// background modes a plugin explains, are left out), errors first.
  List<PreflightFinding> get findings => [
    for (final issue in _report.issues)
      if (issue.severity != ReleaseSeverity.info)
        PreflightFinding(
          code: issue.code,
          isError: issue.severity == ReleaseSeverity.error,
          message: issue.message,
          hint: issue.hint,
        ),
  ];

  Map<String, Object?> toJson() => _report.toJson();
}

/// One finding of [PreflightResult].
final class PreflightFinding {
  const PreflightFinding({
    required this.code,
    required this.isError,
    required this.message,
    this.hint,
  });

  final String code;
  final bool isError;
  final String message;
  final String? hint;

  /// `[code] message`, then the hint on a second line.
  String get text => '[$code] $message${hint == null ? '' : '\nhint: $hint'}';
}

/// Checks the Flutter project in [projectRoot]: the App Store icon, the
/// purpose strings its plugins need, background modes, the privacy manifest
/// and the export-compliance answer, from its sources alone.
PreflightResult preflightProject({
  required HostFileSystemInterface fileSystem,
  required p.Context paths,
  required String projectRoot,
}) => PreflightResult._(
  runPreflightChecks(
    ReleaseProject(fileSystem: fileSystem, paths: paths, root: projectRoot),
  ),
);
