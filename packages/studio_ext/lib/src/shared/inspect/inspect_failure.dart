import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/inspect_codes.dart';

/// A fatal `xcross inspect` failure: no report can be produced.
@internal
final class InspectFailure implements Exception {
  InspectFailure(InspectCode code, this.message)
    : code = code.code,
      hint = code.hint;

  /// Stable fatal code, e.g. `inspect.no_app`.
  final String code;

  /// One sentence without secrets or absolute paths.
  final String message;

  /// Concrete fix.
  final String hint;

  /// The `--json` error document (contracts/inspect.schema.json).
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'error': {'code': code, 'message': message, 'hint': hint},
  };

  @override
  String toString() => '[$code] $message';
}
