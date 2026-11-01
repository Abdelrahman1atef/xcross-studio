import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/inspector.dart';

import 'test_file_system.dart';

/// Opens [path] with the test file system, inspects it and closes it.
InspectReport inspectPath(String path) {
  final source = InspectSource.open(const IoFileSystem(), path);
  try {
    return inspectBundle(source);
  } finally {
    source.close();
  }
}

/// Codes of [report]'s issues, in report order.
List<String> issueCodes(InspectReport report) => [
  for (final issue in report.issues) issue.code,
];

/// The executable at [path] in [report].
ExecutableInfo executableAt(InspectReport report, String path) =>
    report.executables.singleWhere((e) => e.path == path);
