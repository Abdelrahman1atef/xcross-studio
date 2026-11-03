// studio: 016 — why push would not work, before a build
// (specs/016-push-firebase-maps, AC-016-6).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/cli/basic/doctor_models.dart';
import 'package:xcross/src/shared/config/project_settings.dart';
import 'package:xcross/src/shared/flutter/build/flutter_app_entitlements.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_id.dart';
import 'package:xcross/src/shared/flutter/build/push_entitlement.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';

/// The doctor's "Push notifications" checks for one Flutter project.
@internal
final class PushReadiness {
  PushReadiness({
    required this.fileSystem,
    required this.paths,
    required this.projectRoot,
    required this.environment,
  });

  /// Doctor section title.
  static const section = 'Push notifications';

  /// Check names (the desktop app groups them by these).
  static const entitlementCheck = 'Push entitlement';
  static const appIdCheck = 'Push App ID';
  static const firebaseCheck = 'Firebase config';

  // The App ID settings, spelled as in `BundleIdentityResolver` (a target
  // file this shared code may not import).
  static const _modeVariable = 'XCROSS_BUNDLE_ID';
  static const _settingKey = 'bundle_id';

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String projectRoot;
  final Map<String, String> environment;

  late final PushSignals _signals = PushSignals.read(
    fileSystem: fileSystem,
    projectRoot: projectRoot,
  );

  late final Map<String, Object>? _declared = _readDeclared();

  /// Whether the project wants push at all; the section is shown only then.
  bool get applies =>
      _signals.any ||
      (_declared?.containsKey(PushSignals.entitlementKey) ?? false);

  List<DoctorCheck> checks() {
    final bundleId = _bundleId();
    return [_entitlement(), _appId(bundleId), ?_firebase(bundleId)];
  }

  DoctorCheck _entitlement() {
    if (_declared?.containsKey(PushSignals.entitlementKey) ?? false) {
      return const DoctorCheck.success(
        entitlementCheck,
        'aps-environment is declared in the app entitlements',
      );
    }
    return DoctorCheck.warning(
      entitlementCheck,
      'Not declared; xcross adds aps-environment because ${_signals.reason}. '
      'Add it to ios/Runner/Runner.entitlements to make it explicit.',
    );
  }

  DoctorCheck _appId(String? bundleId) {
    final id = bundleId ?? 'the project bundle ID';
    final override = environment[_modeVariable]?.trim().toLowerCase();
    String? saved;
    try {
      saved = ProjectSettings(
        fileSystem: fileSystem,
        projectRoot: projectRoot,
      ).read(_settingKey)?.trim().toLowerCase();
    } on Object {
      saved = null;
    }
    final mode = (override == null || override.isEmpty) ? saved : override;
    final source = mode == override ? _modeVariable : 'saved';
    return switch (mode) {
      'prefixed' => DoctorCheck.failure(
        appIdCheck,
        'Signed as XCR-<identity>.$id ($source); push and Firebase are bound '
        'to $id. Run `xcross project bundle-id original`.',
      ),
      'original' => DoctorCheck.success(
        appIdCheck,
        'The real App ID $id ($source)',
      ),
      _ => DoctorCheck.success(
        appIdCheck,
        'The real App ID $id (default; a prefixed App ID the team already has '
        'is kept: `xcross project bundle-id original` makes the choice '
        'explicit)',
      ),
    };
  }

  /// `null` when the app shows no sign of Firebase.
  DoctorCheck? _firebase(String? bundleId) {
    final plist = fileSystem.file(
      paths.join(projectRoot, 'ios', 'Runner', 'GoogleService-Info.plist'),
    );
    final options = fileSystem.file(
      paths.join(projectRoot, 'lib', 'firebase_options.dart'),
    );
    final configured = <String, String>{};
    if (plist.existsSync()) {
      try {
        final value = FlutterAppEntitlements.parseDictionary(
          plist.readAsStringSync(),
        )['BUNDLE_ID'];
        if (value is String) configured['GoogleService-Info.plist'] = value;
      } on FormatException {
        return const DoctorCheck.warning(
          firebaseCheck,
          'ios/Runner/GoogleService-Info.plist is not a valid property list.',
        );
      }
    }
    if (options.existsSync()) {
      final match = RegExp(
        r'''iosBundleId:\s*['"]([^'"]+)['"]''',
      ).firstMatch(options.readAsStringSync());
      if (match != null) configured['firebase_options.dart'] = match.group(1)!;
    }
    if (configured.isEmpty) {
      return _signals.usesFirebaseMessaging
          ? const DoctorCheck.warning(
              firebaseCheck,
              'No ios/Runner/GoogleService-Info.plist and no iosBundleId in '
              'lib/firebase_options.dart; run `flutterfire configure`.',
            )
          : null;
    }
    if (bundleId == null) {
      return DoctorCheck.warning(
        firebaseCheck,
        'Firebase is set up for ${configured.values.toSet().join(', ')}, but '
        'the project bundle ID could not be read.',
      );
    }
    final wrong = {
      for (final MapEntry(:key, :value) in configured.entries)
        if (value != bundleId) key: value,
    };
    if (wrong.isNotEmpty) {
      return DoctorCheck.failure(
        firebaseCheck,
        '${wrong.entries.map((e) => '${e.key} is for ${e.value}').join('; ')}'
        ', not $bundleId: Firebase and its API key reject the app. Download '
        'the config for $bundleId (or run `flutterfire configure`).',
      );
    }
    return DoctorCheck.success(
      firebaseCheck,
      '${configured.keys.join(' and ')} match $bundleId',
    );
  }

  String? _bundleId() {
    try {
      return IosBundleId(
        fileSystem,
        paths,
        PbxProjectReader(fileSystem, paths),
      ).resolve(projectRoot);
    } on Object {
      return null;
    }
  }

  Map<String, Object>? _readDeclared() {
    final entitlements = FlutterAppEntitlements(fileSystem, paths);
    final path = entitlements.locate(projectRoot);
    if (path == null) return null;
    try {
      return entitlements.read(path);
    } on FormatException {
      return null;
    }
  }
}
