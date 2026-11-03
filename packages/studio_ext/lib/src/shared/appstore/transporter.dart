// studio: 019 — a user-installed Apple Transporter as the upload fallback
// (specs/019-upload-processing, AC-019-9). xcross never downloads it.
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Locates `iTMSTransporter` and builds its command lines.
@internal
abstract final class Transporter {
  /// Overrides the lookup.
  static const variable = 'XCROSS_TRANSPORTER';

  /// Where Apple's installers put it (Windows and Linux); the first that
  /// exists wins. No OS check: a path that does not exist is skipped.
  static List<String> candidates(Map<String, String> environment) {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    return [
      ?environment[variable],
      r'C:\Program Files (x86)\itms\iTMSTransporter.cmd',
      r'C:\Program Files\itms\iTMSTransporter.cmd',
      '/usr/local/itms/bin/iTMSTransporter',
      if (home != null) p.join(home, 'itms', 'bin', 'iTMSTransporter'),
    ];
  }

  /// The installed Transporter, or null.
  static String? locate(
    Map<String, String> environment, {
    required bool Function(String path) exists,
  }) {
    final check = exists;
    for (final candidate in candidates(environment)) {
      if (candidate.trim().isNotEmpty && check(candidate)) return candidate;
    }
    return null;
  }

  /// Apple's download page, shown when it is missing.
  static const downloadPage =
      'https://help.apple.com/itc/transporteruserguide/#/apdA3A0E59E1';

  /// `-m upload` (or `-m verify` when [verify]) with API key authentication.
  static List<String> arguments({
    required String ipa,
    required String keyId,
    required String issuerId,
    bool verify = false,
  }) => [
    '-m',
    if (verify) 'verify' else 'upload',
    '-assetFile',
    ipa,
    '-apiKey',
    keyId,
    '-apiIssuer',
    issuerId,
    '-v',
    'informational',
  ];
}
