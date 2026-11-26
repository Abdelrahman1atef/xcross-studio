// studio: 051 — `xcross project inspect`: the iOS setup of a Flutter project
// in one report (bundle ID, team, signing, minimum iOS, version, push,
// Firebase, other keys), each value with where it came from and whether it
// is right, so the desktop app can show it as a gate before an upload.
import 'dart:convert';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/build/flutter_app_entitlements.dart';
import 'package:xcross/src/shared/flutter/build/pbxproj.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';
import 'package:xcross/src/shared/flutter/project/pubspec_version.dart';

/// How a value stands.
@internal
enum InspectStatus { ok, info, warning, error }

/// One row of the report.
@internal
@immutable
final class InspectItem {
  const InspectItem({
    required this.id,
    required this.label,
    required this.value,
    this.status = InspectStatus.ok,
    this.message,
    this.path,
    this.secret = false,
    this.code,
  });

  /// Stable within its group (`bundle_id`, `firebase_app_id`, …).
  final String id;
  final String label;
  final String? value;
  final InspectStatus status;

  /// Why it is not `ok`, in plain words (or a note for `ok`).
  final String? message;

  /// The project-relative file the value was read from.
  final String? path;

  /// An API key or token: shown hidden by the desktop app.
  final bool secret;

  /// A stable problem code (`bundle_id.configs_differ`, …) the desktop app
  /// can attach a fix to.
  final String? code;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'value': value,
    'status': status.name,
    if (message != null) 'message': message,
    if (path != null) 'path': path,
    if (secret) 'secret': true,
    if (code != null) 'code': code,
  };
}

@internal
@immutable
final class InspectGroup {
  const InspectGroup(this.id, this.title, this.items);
  final String id;
  final String title;
  final List<InspectItem> items;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'items': [for (final item in items) item.toJson()],
  };
}

/// The whole report.
@internal
@immutable
final class ProjectInspection {
  const ProjectInspection({
    required this.projectRoot,
    required this.bundleId,
    required this.teamId,
    required this.version,
    required this.build,
    required this.groups,
  });

  final String projectRoot;

  /// The app target's bundle ID for store builds (Release).
  final String? bundleId;
  final String? teamId;
  final String? version;
  final int? build;
  final List<InspectGroup> groups;

  Iterable<InspectItem> get items => groups.expand((g) => g.items);

  int count(InspectStatus status) =>
      items.where((i) => i.status == status).length;

  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'project_inspect',
    'project': projectRoot,
    'bundleId': bundleId,
    'teamId': teamId,
    'version': version,
    'build': build,
    'errors': count(InspectStatus.error),
    'warnings': count(InspectStatus.warning),
    'groups': [for (final group in groups) group.toJson()],
  };
}

/// Reads a Flutter project's iOS setup. Never writes.
@internal
final class ProjectInspector {
  ProjectInspector({
    required this.fileSystem,
    required this.paths,
    required this.projectRoot,
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String projectRoot;

  static const _storeConfiguration = 'Release';

  String _rel(String path) =>
      paths.relative(path, from: projectRoot).replaceAll(r'\', '/');

  String? _read(List<String> parts) {
    final file = fileSystem.file(paths.joinAll([projectRoot, ...parts]));
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } on Object {
      return null;
    }
  }

  Map<String, Object>? _plist(List<String> parts) {
    final text = _read(parts);
    if (text == null) return null;
    try {
      return FlutterAppEntitlements.parseDictionary(text);
    } on FormatException {
      return null;
    }
  }

  ProjectInspection inspect() {
    final reader = PbxProjectReader(fileSystem, paths);
    final pbxPath = reader.findPbxproj(projectRoot);
    final project = pbxPath == null ? null : reader.parseFile(pbxPath);
    final app = project?.applicationTarget;
    final pbxRel = pbxPath == null ? null : _rel(pbxPath);

    final appGroup = <InspectItem>[];
    String? bundleId;
    String? teamId;

    if (project == null || app == null) {
      appGroup.add(
        InspectItem(
          id: 'ios_project',
          label: 'iOS project',
          value: null,
          status: InspectStatus.error,
          code: 'project.no_ios_app',
          message: pbxPath == null
              ? 'No ios/*.xcodeproj here. Run `flutter create --platforms ios .` '
                    'in the project folder.'
              : '$pbxRel has no app target or could not be read.',
        ),
      );
    } else {
      final configs = _configurations(project, app);
      final projectConfigs = _projectConfigurations(project);

      // Bundle ID, per configuration.
      final ids = {
        for (final MapEntry(:key, :value) in configs.entries)
          key: _string(value['PRODUCT_BUNDLE_IDENTIFIER']),
      };
      bundleId = ids[_storeConfiguration] ?? ids.values.nonNulls.firstOrNull;
      final distinct = ids.values.nonNulls.toSet();
      appGroup.add(
        InspectItem(
          id: 'bundle_id',
          label: 'Bundle ID',
          value: bundleId,
          path: pbxRel,
          status: bundleId == null
              ? InspectStatus.error
              : distinct.length > 1
              ? InspectStatus.error
              : bundleId.contains(r'$(')
              ? InspectStatus.warning
              : InspectStatus.ok,
          code: bundleId == null
              ? 'bundle_id.missing'
              : distinct.length > 1
              ? 'bundle_id.configs_differ'
              : bundleId.contains(r'$(')
              ? 'bundle_id.variable'
              : null,
          message: bundleId == null
              ? 'The app target has no PRODUCT_BUNDLE_IDENTIFIER.'
              : distinct.length > 1
              ? 'The configurations use different IDs: '
                    '${ids.entries.map((e) => '${e.key} ${e.value}').join(', ')}. '
                    'The App Store build uses $_storeConfiguration.'
              : bundleId.contains(r'$(')
              ? 'Set through a build variable; check the .xcconfig files.'
              : '${configs.keys.join(', ')} agree.',
        ),
      );

      // Other targets (tests, extensions) must sit under the app's ID.
      if (bundleId != null) {
        for (final target in project.nativeTargets) {
          if (target.id == app.id) continue;
          final name = target.string('name') ?? target.id;
          final id = _string(
            project.buildSettings(
              target,
              preferredConfiguration: _storeConfiguration,
            )['PRODUCT_BUNDLE_IDENTIFIER'],
          );
          if (id == null) continue;
          final tests =
              (target.string('productType') ?? '').contains(
                'bundle.unit-test',
              ) ||
              (target.string('productType') ?? '').contains('ui-testing');
          final fits = id.startsWith('$bundleId.');
          appGroup.add(
            InspectItem(
              id: 'target_${_slug(name)}',
              label: '$name bundle ID',
              value: id,
              path: pbxRel,
              status: fits
                  ? InspectStatus.ok
                  : tests
                  ? InspectStatus.warning
                  : InspectStatus.error,
              code: fits ? null : 'bundle_id.target_outside',
              message: fits
                  ? null
                  : tests
                  ? 'Usually $bundleId.$name; it does not affect the App Store.'
                  : 'Must start with $bundleId. or the App Store rejects the '
                        'upload.',
            ),
          );
        }
      }

      // Info.plist CFBundleIdentifier should follow the build setting.
      final info = _plist(['ios', 'Runner', 'Info.plist']);
      final infoId = _string(info?['CFBundleIdentifier']);
      if (infoId != null &&
          !infoId.contains(r'$(') &&
          bundleId != null &&
          infoId != bundleId) {
        appGroup.add(
          InspectItem(
            id: 'info_bundle_id',
            label: 'Info.plist bundle ID',
            value: infoId,
            path: 'ios/Runner/Info.plist',
            status: InspectStatus.error,
            code: 'bundle_id.info_plist',
            message:
                'Info.plist hard-codes $infoId; the project uses $bundleId. '
                r'Set it to $(PRODUCT_BUNDLE_IDENTIFIER).',
          ),
        );
      }

      // Team and signing style.
      final teams = {
        for (final MapEntry(:key, :value) in configs.entries)
          key: _string(value['DEVELOPMENT_TEAM']),
      };
      teamId = teams[_storeConfiguration] ?? teams.values.nonNulls.firstOrNull;
      final teamSet = teams.values.nonNulls.toSet();
      appGroup.add(
        InspectItem(
          id: 'team_id',
          label: 'Team ID',
          value: teamId,
          path: pbxRel,
          status: teamId == null
              ? InspectStatus.info
              : teamSet.length > 1
              ? InspectStatus.warning
              : InspectStatus.ok,
          code: teamSet.length > 1 ? 'team.configs_differ' : null,
          message: teamId == null
              ? 'Not set in the project; the signing account in use decides.'
              : teamSet.length > 1
              ? 'The configurations use different teams: '
                    '${teams.entries.map((e) => '${e.key} ${e.value}').join(', ')}.'
              : null,
        ),
      );
      final style = _string(
        configs[_storeConfiguration]?['CODE_SIGN_STYLE'] ??
            configs.values
                .map((c) => c['CODE_SIGN_STYLE'])
                .nonNulls
                .firstOrNull,
      );
      appGroup.add(
        InspectItem(
          id: 'signing',
          label: 'Signing',
          value: style ?? 'Automatic',
          path: pbxRel,
          status: InspectStatus.info,
          message: style == 'Manual'
              ? 'Manual in Xcode; xcross signs with its own profiles either way.'
              : null,
        ),
      );

      // Minimum iOS: the app target, else the project; the Podfile too.
      final target = _string(
        configs[_storeConfiguration]?['IPHONEOS_DEPLOYMENT_TARGET'] ??
            projectConfigs[_storeConfiguration]?['IPHONEOS_DEPLOYMENT_TARGET'],
      );
      final podfile = _podPlatform();
      final podHigher =
          target != null && podfile != null && _compare(podfile, target) > 0;
      appGroup.add(
        InspectItem(
          id: 'deployment_target',
          label: 'Minimum iOS',
          value: target,
          path: pbxRel,
          status: target == null
              ? InspectStatus.warning
              : podHigher
              ? InspectStatus.error
              : InspectStatus.ok,
          code: podHigher ? 'deployment_target.podfile_higher' : null,
          message: target == null
              ? 'IPHONEOS_DEPLOYMENT_TARGET is not set.'
              : podHigher
              ? "The Podfile asks for iOS $podfile, higher than the app's "
                    '$target: pods would not build. Set both to $podfile.'
              : podfile == null
              ? null
              : 'Podfile: $podfile',
        ),
      );
    }

    // Version: pubspec, and Info.plist must follow it.
    final pubspec = _read(['pubspec.yaml']);
    final version = pubspec == null ? null : PubspecVersion.read(pubspec);
    final info = _plist(['ios', 'Runner', 'Info.plist']);
    final shortVersion = _string(info?['CFBundleShortVersionString']);
    final bundleVersion = _string(info?['CFBundleVersion']);
    final hardCoded = [
      if (shortVersion != null && !shortVersion.contains(r'$('))
        'CFBundleShortVersionString = $shortVersion',
      if (bundleVersion != null && !bundleVersion.contains(r'$('))
        'CFBundleVersion = $bundleVersion',
    ];
    appGroup.add(
      InspectItem(
        id: 'version',
        label: 'Version',
        value: version == null
            ? null
            : '${version.name} (${version.build ?? 1})',
        path: 'pubspec.yaml',
        status: version == null
            ? InspectStatus.warning
            : hardCoded.isNotEmpty
            ? InspectStatus.warning
            : InspectStatus.ok,
        code: hardCoded.isNotEmpty ? 'version.info_plist_fixed' : null,
        message: version == null
            ? 'pubspec.yaml has no version: line.'
            : hardCoded.isNotEmpty
            ? 'Info.plist hard-codes ${hardCoded.join(' and ')}, so the pubspec '
                  r'version is ignored. Use $(FLUTTER_BUILD_NAME) and '
                  r'$(FLUTTER_BUILD_NUMBER).'
            : null,
      ),
    );

    final groups = [
      InspectGroup('app', 'App', appGroup),
      ?_push(project, app, info),
      ?_firebase(bundleId),
      ?_otherKeys(info),
    ];
    return ProjectInspection(
      projectRoot: projectRoot,
      bundleId: bundleId,
      teamId: teamId,
      version: version?.name,
      build: version?.build,
      groups: groups,
    );
  }

  // ------------------------------------------------------------------ push

  InspectGroup? _push(
    PbxProject? project,
    PbxObject? app,
    Map<String, Object>? info,
  ) {
    final entitlements = FlutterAppEntitlements(fileSystem, paths);
    final path = entitlements.locate(projectRoot);
    Map<String, Object>? declared;
    if (path != null) {
      try {
        declared = entitlements.read(path);
      } on FormatException {
        declared = null;
      }
    }
    final aps = _string(declared?['aps-environment']);
    final modes = info?['UIBackgroundModes'];
    final remote = modes is List && modes.contains('remote-notification');
    final messaging =
        _read(['pubspec.yaml'])?.contains('firebase_messaging') ?? false;
    if (aps == null && !remote && !messaging) return null;

    final linked = project != null && app != null
        ? _string(
            project.buildSettings(
              app,
              preferredConfiguration: _storeConfiguration,
            )['CODE_SIGN_ENTITLEMENTS'],
          )
        : null;
    final rel = path == null ? null : _rel(path);
    return InspectGroup('push', 'Push notifications', [
      InspectItem(
        id: 'aps_environment',
        label: 'Push entitlement',
        value: aps,
        path: rel,
        status: aps == null ? InspectStatus.error : InspectStatus.ok,
        code: aps == null ? 'push.no_entitlement' : null,
        message: aps == null
            ? 'aps-environment is not in the app entitlements; the iPhone gets '
                  'no push token.'
            : aps == 'development'
            ? 'App Store and TestFlight builds use production; xcross sets it '
                  'when it signs for the store.'
            : null,
      ),
      if (path != null && linked == null)
        InspectItem(
          id: 'entitlements_linked',
          label: 'Entitlements file',
          value: rel,
          status: InspectStatus.warning,
          code: 'push.entitlements_not_linked',
          message:
              'Xcode does not use it (no CODE_SIGN_ENTITLEMENTS in Release); '
              'xcross reads it anyway, Xcode on a Mac would not.',
        ),
      InspectItem(
        id: 'background_mode',
        label: 'Background notifications',
        value: remote ? 'remote-notification' : null,
        path: 'ios/Runner/Info.plist',
        status: remote ? InspectStatus.ok : InspectStatus.info,
        message: remote
            ? null
            : 'UIBackgroundModes has no remote-notification: silent pushes do '
                  'not wake the app (visible notifications still arrive).',
      ),
    ]);
  }

  // -------------------------------------------------------------- firebase

  InspectGroup? _firebase(String? bundleId) {
    const plistPath = 'ios/Runner/GoogleService-Info.plist';
    const optionsPath = 'lib/firebase_options.dart';
    const jsonPath = 'firebase.json';
    final plist = _plist(['ios', 'Runner', 'GoogleService-Info.plist']);
    final options = _read(['lib', 'firebase_options.dart']);
    final firebaseJson = _read(['firebase.json']);
    final iosOptions = options == null ? null : firebaseIosOptions(options);
    final jsonIds = firebaseJson == null
        ? const <String>{}
        : firebaseJsonIosAppIds(firebaseJson);
    if (plist == null && iosOptions == null && jsonIds.isEmpty) return null;

    final items = <InspectItem>[];
    final plistBundle = _string(plist?['BUNDLE_ID']);
    final plistApp = _string(plist?['GOOGLE_APP_ID']);
    final plistProject = _string(plist?['PROJECT_ID']);

    if (plist == null) {
      items.add(
        const InspectItem(
          id: 'plist',
          label: 'GoogleService-Info.plist',
          value: null,
          path: plistPath,
          status: InspectStatus.error,
          code: 'firebase.no_plist',
          message:
              'Missing: native Firebase on iPhone needs it. Download it for '
              'this bundle ID from the Firebase console and import it.',
        ),
      );
    }

    // The bundle ID each file is for.
    for (final (label, value, path) in [
      ('Plist bundle ID', plistBundle, plistPath),
      (
        'firebase_options.dart bundle ID',
        iosOptions?['iosBundleId'],
        optionsPath,
      ),
    ]) {
      if (value == null) continue;
      final ok = bundleId == null || value == bundleId;
      items.add(
        InspectItem(
          id: path == plistPath ? 'plist_bundle_id' : 'options_bundle_id',
          label: label,
          value: value,
          path: path,
          status: ok ? InspectStatus.ok : InspectStatus.error,
          code: ok ? null : 'firebase.bundle_mismatch',
          message: ok
              ? null
              : 'Firebase is set up for $value, the app is $bundleId: '
                    'Firebase rejects the app. Import the plist for $bundleId.',
        ),
      );
    }

    // The Firebase iOS app all three files name.
    final appIds = <String, String>{
      plistPath: ?plistApp,
      optionsPath: ?iosOptions?['appId'],
      for (final id in jsonIds) '$jsonPath ($id)': id,
    };
    final distinctApps = appIds.values.toSet();
    items.add(
      InspectItem(
        id: 'firebase_app_id',
        label: 'Firebase iOS app',
        value: plistApp ?? iosOptions?['appId'] ?? jsonIds.firstOrNull,
        path: plistApp != null ? plistPath : optionsPath,
        status: distinctApps.length > 1
            ? InspectStatus.error
            : InspectStatus.ok,
        code: distinctApps.length > 1 ? 'firebase.app_mismatch' : null,
        message: distinctApps.length > 1
            ? 'The files name different Firebase apps: '
                  '${appIds.entries.map((e) => '${e.key.split(' ').first} ${e.value}').toSet().join(', ')}.'
            : appIds.length > 1
            ? '${appIds.keys.map((k) => k.split(' ').first).toSet().join(', ')} agree.'
            : null,
      ),
    );

    final projects = <String>{?plistProject, ?iosOptions?['projectId']};
    items.add(
      InspectItem(
        id: 'firebase_project',
        label: 'Firebase project',
        value: plistProject ?? iosOptions?['projectId'],
        path: plistProject != null ? plistPath : optionsPath,
        status: projects.length > 1 ? InspectStatus.error : InspectStatus.ok,
        code: projects.length > 1 ? 'firebase.project_mismatch' : null,
        message: projects.length > 1
            ? 'The plist and firebase_options.dart name different projects: '
                  '${projects.join(', ')}.'
            : null,
      ),
    );
    if (_string(plist?['GCM_SENDER_ID']) ?? iosOptions?['messagingSenderId']
        case final sender?) {
      items.add(
        InspectItem(
          id: 'sender_id',
          label: 'Sender ID',
          value: sender,
          path: plistPath,
          status: InspectStatus.info,
        ),
      );
    }
    final plistKey = _string(plist?['API_KEY']);
    final optionsKey = iosOptions?['apiKey'];
    if (plistKey ?? optionsKey case final key?) {
      final differ =
          plistKey != null && optionsKey != null && plistKey != optionsKey;
      items.add(
        InspectItem(
          id: 'firebase_api_key',
          label: 'iOS API key',
          value: key,
          path: plistKey != null ? plistPath : optionsPath,
          secret: true,
          status: differ ? InspectStatus.warning : InspectStatus.info,
          code: differ ? 'firebase.api_key_mismatch' : null,
          message: differ
              ? 'The plist and firebase_options.dart have different keys.'
              : null,
        ),
      );
    }
    if (_string(plist?['STORAGE_BUCKET']) ?? iosOptions?['storageBucket']
        case final bucket?) {
      items.add(
        InspectItem(
          id: 'storage_bucket',
          label: 'Storage bucket',
          value: bucket,
          path: plistPath,
          status: InspectStatus.info,
        ),
      );
    }
    return InspectGroup('firebase', 'Firebase (iOS app)', items);
  }

  // ------------------------------------------------------------ other keys

  static final _keyName = RegExp(
    r'(api_?key|app_?id|client_?id|client_?token|secret)$',
    caseSensitive: false,
  );

  InspectGroup? _otherKeys(Map<String, Object>? info) {
    final items = <InspectItem>[];
    final delegate = _read(['ios', 'Runner', 'AppDelegate.swift']);
    final maps = delegate == null
        ? null
        : RegExp(
            r'''GMSServices\.provideAPIKey\(\s*"([^"]+)"''',
          ).firstMatch(delegate)?.group(1);
    if (maps != null) {
      items.add(
        InspectItem(
          id: 'google_maps_key',
          label: 'Google Maps key',
          value: maps,
          path: 'ios/Runner/AppDelegate.swift',
          secret: true,
          status: InspectStatus.info,
          message:
              'If the key is limited to iOS apps, it must allow this bundle ID '
              '(Google Cloud > Credentials).',
        ),
      );
    }
    for (final MapEntry(:key, :value) in (info ?? const {}).entries) {
      if (value is! String || !_keyName.hasMatch(key)) continue;
      if (key.startsWith('CF') || key.startsWith('NS')) continue;
      final empty = value.trim().isEmpty;
      final secret = RegExp(
        'key|token|secret',
        caseSensitive: false,
      ).hasMatch(key);
      items.add(
        InspectItem(
          id: 'info_${_slug(key)}',
          label: key,
          value: empty ? null : value,
          path: 'ios/Runner/Info.plist',
          secret: secret,
          status: empty ? InspectStatus.warning : InspectStatus.info,
          code: empty ? 'keys.empty' : null,
          message: empty ? 'Empty in Info.plist.' : null,
        ),
      );
    }
    return items.isEmpty ? null : InspectGroup('keys', 'Other keys', items);
  }

  // --------------------------------------------------------------- helpers

  /// Build settings of [target] per configuration name.
  static Map<String, Map<String, Object?>> _configurations(
    PbxProject project,
    PbxObject target,
  ) => _listSettings(project, target.string('buildConfigurationList'));

  static Map<String, Map<String, Object?>> _projectConfigurations(
    PbxProject project,
  ) => _listSettings(
    project,
    project.object(project.rootObjectId)?.string('buildConfigurationList'),
  );

  static Map<String, Map<String, Object?>> _listSettings(
    PbxProject project,
    String? listId,
  ) {
    final list = project.object(listId);
    if (list == null) return const {};
    return {
      for (final id in list.stringList('buildConfigurations'))
        if (project.object(id) case final config?
            when config.isa == 'XCBuildConfiguration')
          config.string('name') ?? id: config.map('buildSettings'),
    };
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String _slug(String text) => text
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String? _podPlatform() {
    final podfile = _read(['ios', 'Podfile']);
    if (podfile == null) return null;
    for (final line in const LineSplitter().convert(podfile)) {
      final match = RegExp(
        r'''^\s*platform\s+:ios\s*,\s*['"]([\d.]+)['"]''',
      ).firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Compares dotted version numbers.
  static int _compare(String a, String b) {
    final x = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final y = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }
}

/// The fields of the `ios` options in a FlutterFire `firebase_options.dart`
/// (`appId`, `iosBundleId`, `projectId`, `apiKey`, …), or null when it has
/// none.
@internal
Map<String, String>? firebaseIosOptions(String source) {
  final block = firebaseIosBlock(source);
  if (block == null) return null;
  return {
    for (final m in RegExp(
      r'''(\w+)\s*:\s*['"]([^'"]*)['"]''',
    ).allMatches(source.substring(block.start, block.end)))
      m.group(1)!: m.group(2)!,
  };
}

/// Where the `static const FirebaseOptions ios = FirebaseOptions(...)` block
/// is in [source].
@internal
({int start, int end})? firebaseIosBlock(String source) {
  final start = RegExp(
    r'FirebaseOptions\s+ios\s*=\s*FirebaseOptions\s*\(',
  ).firstMatch(source);
  if (start == null) return null;
  var depth = 1;
  for (var i = start.end; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return (start: start.end, end: i);
  }
  return null;
}

/// The iOS Firebase app IDs a FlutterFire `firebase.json` names.
@internal
Set<String> firebaseJsonIosAppIds(String source) {
  final ids = <String>{};
  void walk(Object? node, {required bool ios}) {
    if (node is Map) {
      for (final MapEntry(:key, :value) in node.entries) {
        final inIos = ios || key == 'ios';
        if (inIos && value is String && value.contains(':ios:')) {
          ids.add(value);
        } else {
          walk(value, ios: inIos);
        }
      }
    } else if (node is List) {
      for (final value in node) {
        walk(value, ios: ios);
      }
    }
  }

  try {
    walk(jsonDecode(source), ios: false);
  } on FormatException {
    // Not JSON: nothing to compare.
  }
  return ids;
}
