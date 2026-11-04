// studio: 018 — the local part of App Store validation, before an upload
// (specs/018-app-store-build, AC-018-9…AC-018-14).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/inspector.dart';
import 'package:studio_ext/src/shared/inspect/macho_reader.dart';
import 'package:studio_ext/src/shared/inspect/plist_reader.dart';
import 'package:studio_ext/src/shared/release/macho_build_version.dart';
import 'package:studio_ext/src/shared/release/release_tables.dart';

/// How bad a [ReleaseIssue] is: errors block an upload.
@internal
enum ReleaseSeverity { error, warning, info }

/// One finding of `xcross release check`.
@internal
@immutable
final class ReleaseIssue {
  const ReleaseIssue(
    this.code,
    this.severity,
    this.message, {
    this.path,
    this.hint,
  });

  /// `release.*`, never renamed once released.
  final String code;
  final ReleaseSeverity severity;
  final String message;
  final String? path;
  final String? hint;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity.name,
    'message': message,
    'path': path,
    'hint': hint,
  };
}

/// The result of one check run.
@internal
final class ReleaseReport {
  ReleaseReport({
    required this.input,
    required this.configuration,
    required List<ReleaseIssue> issues,
  }) : issues = List.unmodifiable(
         <ReleaseIssue>[...issues]..sort((ReleaseIssue a, ReleaseIssue b) {
           final bySeverity = a.severity.index.compareTo(b.severity.index);
           return bySeverity != 0 ? bySeverity : a.code.compareTo(b.code);
         }),
       );

  final String input;
  final Map<String, Object?> configuration;

  /// Errors first, then warnings, then info; by code within each.
  final List<ReleaseIssue> issues;

  int get errors =>
      issues.where((i) => i.severity == ReleaseSeverity.error).length;
  int get warnings =>
      issues.where((i) => i.severity == ReleaseSeverity.warning).length;

  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'release_check',
    'input': input,
    'configuration': configuration,
    'issues': [for (final issue in issues) issue.toJson()],
    'errors': errors,
    'warnings': warnings,
  };
}

/// The Flutter project an app was built from, for the checks that need its
/// sources (plugins, icon set, bundle ID).
@internal
final class ReleaseProject {
  ReleaseProject({
    required this.fileSystem,
    required this.paths,
    required this.root,
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String root;

  String _join(List<String> parts) => paths.joinAll([root, ...parts]);

  String? _read(List<String> parts) {
    final file = fileSystem.file(_join(parts));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  /// iOS plugins `flutter pub get` resolved, plus direct dependencies.
  late final Set<String> plugins = () {
    final names = <String>{};
    final resolved = _read(['.flutter-plugins-dependencies']);
    if (resolved != null) {
      try {
        final Object? decoded = jsonDecode(resolved);
        if (decoded case {'plugins': {'ios': final List<Object?> entries}}) {
          for (final entry in entries) {
            if (entry case {'name': final String name}) names.add(name);
          }
        }
      } on FormatException {
        // A broken list is pub's to report.
      }
    }
    final pubspec = _read(['pubspec.yaml']);
    if (pubspec != null) names.addAll(directDependencies(pubspec));
    return names;
  }();

  /// Whether the project has its own `xcross_overrides/<plugin>` folder.
  bool hasOverride(String plugin) =>
      fileSystem.directory(_join(['xcross_overrides', plugin])).existsSync();

  /// Package names directly under the top-level `dependencies:` key of a
  /// pubspec (a line scan: no YAML parser is needed for names).
  @visibleForTesting
  static Set<String> directDependencies(String pubspec) {
    final names = <String>{};
    var inside = false;
    int? indent;
    for (final raw in const LineSplitter().convert(pubspec)) {
      final line = raw.replaceFirst(RegExp(r'\s+#.*$'), '');
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      final lead = line.length - line.trimLeft().length;
      if (lead == 0) {
        inside = line.startsWith('dependencies:');
        indent = null;
        continue;
      }
      if (!inside) continue;
      indent ??= lead;
      if (lead != indent) continue;
      final match = RegExp(
        r'^\s+([A-Za-z_][A-Za-z0-9_]*)\s*:',
      ).firstMatch(line);
      if (match != null) names.add(match.group(1)!);
    }
    return names;
  }

  /// The shortest `PRODUCT_BUNDLE_IDENTIFIER` in the iOS project (the app
  /// target's; extensions extend it), ignoring test targets.
  late final String? bundleId = () {
    final pbxproj = _read(['ios', 'Runner.xcodeproj', 'project.pbxproj']);
    if (pbxproj == null) return null;
    final ids =
        <String>{
            for (final match in RegExp(
              r'''PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";\s]+)"?;''',
            ).allMatches(pbxproj))
              match.group(1)!,
          }.where((id) => !id.contains(r'$') && !id.endsWith('Tests')).toList()
          ..sort((a, b) => a.length.compareTo(b.length));
    return ids.isEmpty ? null : ids.first;
  }();

  static const _iconSet = ['ios', 'Runner', 'Assets.xcassets'];

  /// The App Store icon of the app icon set. `problem` explains a missing or
  /// unreadable set; otherwise `fileName` is null when the set has no
  /// 1024 px entry, and `bytes` null when its file is missing.
  ({String? problem, String? fileName, Uint8List? bytes}) marketingIcon() {
    final setName = _appIconSet();
    if (setName == null) {
      return (problem: 'no app icon set', fileName: null, bytes: null);
    }
    final contents = _read([..._iconSet, setName, 'Contents.json']);
    if (contents == null) {
      return (problem: 'no Contents.json', fileName: null, bytes: null);
    }
    Object? json;
    try {
      json = jsonDecode(contents) as Object?;
    } on FormatException {
      return (
        problem: 'Contents.json is not JSON',
        fileName: null,
        bytes: null,
      );
    }
    if (json case {'images': final List<Object?> images}) {
      for (final image in images) {
        if (image case {'size': '1024x1024', 'filename': final String name}) {
          final file = fileSystem.file(_join([..._iconSet, setName, name]));
          return (
            problem: null,
            fileName: name,
            bytes: file.existsSync() ? file.readAsBytesSync() : null,
          );
        }
      }
    }
    return (problem: null, fileName: null, bytes: null);
  }

  String? _appIconSet() {
    final directory = fileSystem.directory(_join(_iconSet));
    if (!directory.existsSync()) return null;
    final sets = [
      for (final entity in directory.listSync())
        if (entity.path.endsWith('.appiconset')) paths.basename(entity.path),
    ]..sort();
    if (sets.isEmpty) return null;
    return sets.contains('AppIcon.appiconset')
        ? 'AppIcon.appiconset'
        : sets.first;
  }
}

/// Runs every release check on [source] (and [project] when known).
@internal
ReleaseReport runReleaseChecks(
  InspectSource source, {
  ReleaseProject? project,
  DateTime? now,
}) =>
    ReleaseChecker(source, project: project, now: now ?? DateTime.now()).run();

/// One check run; see [runReleaseChecks].
@internal
final class ReleaseChecker {
  ReleaseChecker(this.source, {required this.project, required this.now});

  final InspectSource source;
  final ReleaseProject? project;
  final DateTime now;
  final List<ReleaseIssue> _issues = [];

  late final InspectReport _report = inspectBundle(source);
  late final Map<String, Object?> _info = () {
    final bytes = source.read('Info.plist');
    return (bytes == null ? null : readPlist(bytes)?.dictionary) ?? const {};
  }();
  late final ExecutableInfo? _main = _report.executables
      .where((e) => e.role == ExecutableRole.main)
      .firstOrNull;
  late final MachOBuildVersion? _buildVersion = () {
    final main = _main;
    if (main == null) return null;
    try {
      final bytes = source.read(main.path);
      return bytes == null ? null : MachOBuildVersion.read(bytes);
    } on FormatException {
      return null;
    }
  }();

  void _add(
    String code,
    ReleaseSeverity severity,
    String message, {
    String? path,
    String? hint,
  }) => _issues.add(
    ReleaseIssue(code, severity, message, path: path, hint: hint),
  );

  ReleaseReport run() {
    _signing();
    _toolchain();
    _permissions();
    _privacy();
    _assets();
    if (project == null) {
      _add(
        'release.project_unknown',
        ReleaseSeverity.info,
        'No Flutter project found next to the input: the plugin '
            'permission table, the App Store icon and the project bundle ID were '
            'not checked.',
        hint: 'Run in the project folder or pass --project <dir>.',
      );
    }
    return ReleaseReport(
      input: source.name,
      configuration: _configuration(),
      issues: _issues,
    );
  }

  // --- Signing (AC-018-9) -------------------------------------------------

  void _signing() {
    final signed =
        _report.signature.present &&
        (_main?.signature.kind ?? SignatureKind.none) != SignatureKind.none;
    if (!signed) {
      _add(
        'release.not_signed',
        ReleaseSeverity.error,
        'The app is not signed.',
        hint:
            'Build with `xcross flutter build --release --ipa --export-method '
            'app-store` (App Store Connect team key, Admin or App Manager).',
      );
      return;
    }
    final profile = _report.profile;
    if (profile == null) {
      _add(
        'release.profile_not_app_store',
        ReleaseSeverity.error,
        'The app has no embedded provisioning profile.',
        path: 'embedded.mobileprovision',
        hint: 'Export with --export-method app-store.',
      );
    } else {
      if (profile.kind != ProfileKind.appStore) {
        _add(
          'release.profile_not_app_store',
          ReleaseSeverity.error,
          'The app is signed with a ${profile.kind.wire} profile; App Store '
              'Connect accepts App Store profiles only.',
          path: 'embedded.mobileprovision',
          hint: 'Export with --export-method app-store.',
        );
      }
      _expiry(profile, 'embedded.mobileprovision');
    }
    final entitlements = _main?.entitlements ?? const {};
    if (entitlements['get-task-allow'] == true) {
      _add(
        'release.get_task_allow',
        ReleaseSeverity.error,
        'The app is signed with get-task-allow (a debuggable, development '
            'signature).',
        path: _main?.path,
        hint: 'Export with --export-method app-store.',
      );
    }
    if (entitlements['aps-environment'] == 'development') {
      _add(
        'release.aps_development',
        ReleaseSeverity.error,
        'aps-environment is "development"; App Store builds need '
            '"production".',
        path: _main?.path,
        hint: 'Sign with an App Store profile (it grants production).',
      );
    }
    for (final extension in _report.extensions) {
      final kind = extension.profile?.kind;
      if (kind != ProfileKind.appStore) {
        _add(
          'release.extension_profile',
          ReleaseSeverity.error,
          '${extension.path} is signed with '
              '${kind == null ? 'no profile' : 'a ${kind.wire} profile'}.',
          path: extension.path,
          hint: 'Every extension needs its own App Store profile.',
        );
      }
      if (extension.profile case final profile?) {
        _expiry(profile, '${extension.path}/embedded.mobileprovision');
      }
    }
  }

  void _expiry(ProfileSummary profile, String path) {
    final expires = DateTime.tryParse(profile.expirationDate ?? '');
    if (expires != null && expires.isBefore(now)) {
      _add(
        'release.profile_expired',
        ReleaseSeverity.error,
        'The provisioning profile expired on '
            '${profile.expirationDate!.substring(0, 10)}.',
        path: path,
        hint: 'Export again; xcross issues a new profile.',
      );
    }
  }

  // --- Toolchain and identity (AC-018-10) ---------------------------------

  void _toolchain() {
    final build = _buildVersion;
    final platformVersion = _string('DTPlatformVersion');
    final sdkMajor =
        build?.sdkMajor ?? _major(platformVersion) ?? _major(_sdkName());
    if (sdkMajor != null && sdkMajor < ReleaseTables.minimumSdkMajor) {
      _add(
        'release.sdk_too_old',
        ReleaseSeverity.error,
        'The app was built with iOS SDK '
            '${build?.sdk ?? platformVersion ?? sdkMajor}; App Store Connect needs '
            'SDK ${ReleaseTables.minimumSdkMajor} or later.',
        path: _main?.path,
        hint:
            'Install an Xcode ${ReleaseTables.minimumSdkMajor}+ .xip with '
            '`xcross sdk install`, then build again.',
      );
    }
    final missing = [
      for (final key in ReleaseTables.dtKeys)
        if (_string(key) == null) key,
    ];
    if (missing.isNotEmpty) {
      _add(
        'release.dt_keys_missing',
        ReleaseSeverity.warning,
        'Info.plist lacks ${missing.join(', ')}; App Store Connect reads them '
            'to identify the toolchain.',
        path: 'Info.plist',
        hint:
            'Build with a current xcross; reinstall the SDK with '
            '`xcross sdk install` to record the Xcode build.',
      );
    }
    final minimum = _string('MinimumOSVersion');
    final minimumMajor = _major(minimum);
    if (minimumMajor == null ||
        minimumMajor < ReleaseTables.minimumDeploymentTarget) {
      _add(
        'release.deployment_target',
        ReleaseSeverity.error,
        minimum == null
            ? 'Info.plist has no MinimumOSVersion.'
            : 'MinimumOSVersion is $minimum; App Store builds need iOS '
                  '${ReleaseTables.minimumDeploymentTarget} or later.',
        path: 'Info.plist',
        hint: 'Raise IPHONEOS_DEPLOYMENT_TARGET in ios/Runner.xcodeproj.',
      );
    }
    final version = RegExp(r'^\d+(\.\d+){0,2}$');
    for (final key in ['CFBundleShortVersionString', 'CFBundleVersion']) {
      final value = _string(key);
      if (value == null || !version.hasMatch(value)) {
        _add(
          'release.version_invalid',
          ReleaseSeverity.error,
          value == null
              ? 'Info.plist has no $key.'
              : '$key "$value" is not one to three period-separated '
                    'numbers.',
          path: 'Info.plist',
          hint: 'Set version: 1.2.3+4 in pubspec.yaml.',
        );
      }
    }
    final projectId = project?.bundleId;
    final signedId = _string('CFBundleIdentifier');
    if (projectId != null && signedId != null && projectId != signedId) {
      _add(
        'release.bundle_id_mismatch',
        ReleaseSeverity.error,
        'The app is $signedId but the project is $projectId; the App Store '
            'record must match the signed ID.',
        path: 'Info.plist',
        hint:
            'Sign under the real App ID (`xcross project bundle-id original`).',
      );
    }
  }

  // --- Permissions (AC-018-11) --------------------------------------------

  void _permissions() {
    final plugins = project?.plugins ?? const <String>{};
    for (final plugin in plugins.toList()..sort()) {
      for (final requirement
          in ReleaseTables.pluginUsage[plugin] ?? const <UsageRequirement>[]) {
        if (requirement.anyOf.any((key) => _info.containsKey(key))) continue;
        _add(
          'release.permission_missing',
          ReleaseSeverity.error,
          '$plugin uses the ${requirement.resource} but Info.plist has no '
              '${requirement.anyOf.join(' or ')}; iOS ends the app when it asks.',
          path: 'Info.plist',
          hint:
              'Add ${requirement.anyOf.first} to ios/Runner/Info.plist with '
              'a sentence saying why the app needs it.',
        );
      }
    }
    final usageKey = RegExp(r'^NS\w*UsageDescription$');
    final placeholder = RegExp(
      'todo|placeholder|lorem|xxx|description here',
      caseSensitive: false,
    );
    for (final key in _info.keys.where(usageKey.hasMatch).toList()..sort()) {
      final value = _info[key];
      final text = value is String ? value.trim() : '';
      if (text.length < 10 || placeholder.hasMatch(text) || text == key) {
        _add(
          'release.permission_placeholder',
          ReleaseSeverity.warning,
          '$key is "${text.length > 40 ? '${text.substring(0, 40)}…' : text}"; '
              'App Review rejects empty or placeholder purpose strings.',
          path: 'Info.plist',
          hint: 'Explain what the app does with it, in a full sentence.',
        );
      }
    }
    if (_info['NSAppTransportSecurity'] case {'NSAllowsArbitraryLoads': true}) {
      _add(
        'release.ats_arbitrary_loads',
        ReleaseSeverity.warning,
        'NSAllowsArbitraryLoads turns off App Transport Security for every '
            'domain; App Review asks for a justification.',
        path: 'Info.plist',
        hint: 'Use NSExceptionDomains for the hosts that need it.',
      );
    }
    final modes = _info['UIBackgroundModes'];
    if (modes is List) {
      for (final mode in modes.whereType<String>()) {
        final explainedBy = [
          for (final plugin
              in ReleaseTables.backgroundModePlugins[mode] ?? const <String>[])
            if (plugins.contains(plugin)) plugin,
        ];
        final known = project != null;
        _add(
          'release.background_mode',
          known && explainedBy.isEmpty
              ? ReleaseSeverity.warning
              : ReleaseSeverity.info,
          explainedBy.isNotEmpty
              ? 'Background mode "$mode" (used by ${explainedBy.join(', ')}).'
              : known
              ? 'Background mode "$mode" has no plugin that explains it; App '
                    'Review asks what it is for.'
              : 'Background mode "$mode".',
          path: 'Info.plist',
        );
      }
    }
  }

  // --- Privacy (AC-018-12) ------------------------------------------------

  void _privacy() {
    final manifests = [
      for (final file in source.files)
        if (file.endsWith('PrivacyInfo.xcprivacy')) file,
    ];
    if (!manifests.contains('PrivacyInfo.xcprivacy')) {
      _add(
        'release.privacy_manifest_missing',
        ReleaseSeverity.warning,
        'The app has no PrivacyInfo.xcprivacy at its root.',
        path: 'PrivacyInfo.xcprivacy',
        hint:
            'Add ios/Runner/PrivacyInfo.xcprivacy (data collected, '
            'required-reason APIs) to the Runner target.',
      );
    }
    for (final framework in _report.frameworks) {
      final name = framework.name.replaceAll(
        RegExp(r'\.(framework|dylib)$'),
        '',
      );
      if (!ReleaseTables.sdksNeedingManifest.contains(name)) continue;
      if (framework.kind != FrameworkKind.framework) continue;
      if (!manifests.any((m) => m.startsWith('${framework.path}/'))) {
        _add(
          'release.privacy_manifest_missing',
          ReleaseSeverity.warning,
          "$name is on Apple's list of SDKs that must ship a privacy "
              'manifest, and ${framework.path} has none.',
          path: framework.path,
          hint:
              'Update $name to a release that includes PrivacyInfo.xcprivacy.',
        );
      }
    }
    for (final plugin
        in (project?.plugins ?? const <String>{}).toList()..sort()) {
      if (!ReleaseTables.sdksNeedingManifest.contains(plugin)) continue;
      final bundled = manifests.any(
        (m) =>
            m.split('/').any((segment) => segment.startsWith(plugin)) &&
            m != 'PrivacyInfo.xcprivacy',
      );
      if (!bundled) {
        _add(
          'release.privacy_manifest_missing',
          ReleaseSeverity.warning,
          "Plugin $plugin is on Apple's list of SDKs that must ship a "
              'privacy manifest, and no bundle of it carries one.',
          hint: (project?.hasOverride(plugin) ?? false)
              ? 'Drafts from older xcross versions left the manifest out: run '
                    '`xcross plugin shim $plugin --force` (this replaces the '
                    'draft), then build again. If it is still missing, update '
                    '$plugin to a release that includes its privacy bundle.'
              : 'Update $plugin to a release that includes its privacy bundle.',
        );
      }
    }
    _requiredReasons(manifests);
    if (!_info.containsKey('ITSAppUsesNonExemptEncryption')) {
      _add(
        'release.encryption_unset',
        ReleaseSeverity.warning,
        'ITSAppUsesNonExemptEncryption is not set, so App Store Connect asks '
            'the export compliance questions for every build.',
        path: 'Info.plist',
        hint:
            'Set uses_non_exempt_encryption: false (or true) under xcross: in '
            "pubspec.yaml after checking the app's encryption.",
      );
    }
    _secrets();
  }

  void _requiredReasons(List<String> manifests) {
    final declared = <String>{};
    for (final path in manifests) {
      final Uint8List? bytes;
      try {
        bytes = source.read(path);
      } on FormatException {
        continue;
      }
      final root = bytes == null ? null : readPlist(bytes)?.dictionary;
      final types = root?['NSPrivacyAccessedAPITypes'];
      if (types is! List) continue;
      for (final Object? entry in types) {
        if (entry case {'NSPrivacyAccessedAPIType': final String category}) {
          declared.add(category);
        }
      }
    }
    final used = <String, String>{};
    for (final executable in _report.executables) {
      final Uint8List? bytes;
      try {
        bytes = source.read(executable.path);
      } on FormatException {
        continue;
      }
      if (bytes == null) continue;
      final text = latin1.decode(bytes, allowInvalid: true);
      for (final MapEntry(key: category, value: symbols)
          in ReleaseTables.requiredReasonSymbols.entries) {
        if (used.containsKey(category) || declared.contains(category)) {
          continue;
        }
        if (symbols.any(text.contains)) used[category] = executable.path;
      }
    }
    for (final MapEntry(key: category, value: path) in used.entries) {
      _add(
        'release.required_reason_undeclared',
        ReleaseSeverity.warning,
        '$path uses a $category API, but no privacy manifest in the app '
            'declares a reason for it.',
        path: path,
        hint:
            'Add $category with its approved reason to '
            'ios/Runner/PrivacyInfo.xcprivacy (or update the SDK that uses it).',
      );
    }
  }

  static final _privateKey = RegExp(
    '-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
  );
  static final _awsKey = RegExp(r'\bAKIA[0-9A-Z]{16}\b');
  static const _keyFiles = ['.p8', '.p12', '.pfx', '.pem', '.key'];

  void _secrets() {
    for (final file in source.files) {
      final lower = file.toLowerCase();
      if (_keyFiles.any(lower.endsWith)) {
        _add(
          'release.secret_in_bundle',
          ReleaseSeverity.error,
          '$file looks like a key or certificate file shipped inside the app.',
          path: file,
          hint: "Remove it from the app's resources and rotate the key.",
        );
        continue;
      }
      final size = source.sizeOf(file) ?? 0;
      if (size == 0 || size > 4 * 1024 * 1024) continue;
      final Uint8List? bytes;
      try {
        bytes = source.read(file);
      } on FormatException {
        continue;
      }
      if (bytes == null || hasMachOMagic(bytes)) continue;
      final text = latin1.decode(bytes, allowInvalid: true);
      final what = _privateKey.hasMatch(text)
          ? 'a private key'
          : _awsKey.hasMatch(text)
          ? 'an AWS access key'
          : null;
      if (what == null) continue;
      _add(
        'release.secret_in_bundle',
        ReleaseSeverity.error,
        '$file contains $what; anything in the app can be extracted.',
        path: file,
        hint: 'Remove it from the app and rotate it; keep secrets on a server.',
      );
    }
  }

  // --- Store assets (AC-018-13) -------------------------------------------

  void _assets() {
    final project = this.project;
    if (project != null) {
      final icon = project.marketingIcon();
      if (icon.problem case final problem?) {
        _add(
          'release.marketing_icon',
          ReleaseSeverity.error,
          'No usable app icon set ($problem).',
          path: 'ios/Runner/Assets.xcassets',
          hint: 'Add an AppIcon set with a 1024×1024 icon.',
        );
      } else if (icon.fileName == null) {
        _add(
          'release.marketing_icon',
          ReleaseSeverity.error,
          'The app icon set has no 1024×1024 App Store icon.',
          path: 'ios/Runner/Assets.xcassets',
          hint: 'Add a 1024×1024 PNG without transparency to the icon set.',
        );
      } else {
        final bytes = icon.bytes;
        final problem = bytes == null ? 'is missing' : _pngProblem(bytes);
        if (problem != null) {
          _add(
            'release.marketing_icon',
            ReleaseSeverity.error,
            'The App Store icon ${icon.fileName} $problem.',
            path: 'ios/Runner/Assets.xcassets',
            hint:
                'Export it as a 1024×1024 PNG without an alpha channel '
                '(App Store Connect rejects transparency: ITMS-90717).',
          );
        }
      }
    }
    if (_report.resources.launchScreen.kind == LaunchScreenKind.none) {
      _add(
        'release.launch_screen_missing',
        ReleaseSeverity.error,
        'The app declares no launch screen (UILaunchScreen or a launch '
            'storyboard).',
        path: 'Info.plist',
        hint:
            'Keep ios/Runner/Base.lproj/LaunchScreen.storyboard in the project.',
      );
    }
    final family = _report.bundle.deviceFamily;
    if (family.contains(2) && _info['UIRequiresFullScreen'] != true) {
      final orientations =
          _info['UISupportedInterfaceOrientations~ipad'] ??
          _info['UISupportedInterfaceOrientations'];
      final present = orientations is List
          ? orientations.whereType<String>().toSet()
          : <String>{};
      final missing = [
        for (final orientation in ReleaseTables.allOrientations)
          if (!present.contains(orientation)) orientation,
      ];
      if (missing.isNotEmpty) {
        _add(
          'release.ipad_multitasking',
          ReleaseSeverity.error,
          'The app supports iPad but not every orientation (missing '
              '${missing.join(', ')}), and does not set UIRequiresFullScreen.',
          path: 'Info.plist',
          hint:
              'Support all four iPad orientations, or set UIRequiresFullScreen '
              '(ITMS-90474).',
        );
      }
    }
  }

  /// Why a marketing icon PNG is unacceptable, or `null`.
  @visibleForTesting
  static String? pngProblem(Uint8List bytes) => _pngProblem(bytes);

  static String? _pngProblem(Uint8List bytes) {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length < 33 ||
        !List.generate(8, (i) => bytes[i] == signature[i]).every((b) => b)) {
      return 'is not a PNG';
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16);
    final height = data.getUint32(20);
    if (width != 1024 || height != 1024) {
      return 'is $width×$height, not 1024×1024';
    }
    final colorType = bytes[25];
    if (colorType == 4 || colorType == 6) return 'has an alpha channel';
    // A tRNS chunk adds transparency to palette and grey images.
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(offset);
      final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
      if (type == 'tRNS') return 'has transparency (tRNS)';
      if (type == 'IDAT' || type == 'IEND') break;
      offset += 12 + length;
    }
    return null;
  }

  // --- Configuration ------------------------------------------------------

  Map<String, Object?> _configuration() {
    final bundle = _report.bundle;
    final profile = _report.profile;
    final orientations = _info['UISupportedInterfaceOrientations'];
    return {
      'bundleId': bundle.bundleId,
      'name': bundle.name,
      'displayName': bundle.displayName,
      'version': bundle.shortVersion,
      'build': bundle.buildNumber,
      'minimumOS': bundle.minimumOSVersion,
      'devices': [
        if (bundle.deviceFamily.contains(1)) 'iPhone',
        if (bundle.deviceFamily.contains(2)) 'iPad',
      ],
      'orientations': orientations is List
          ? orientations.whereType<String>().toList()
          : const <String>[],
      'sdk': _buildVersion?.sdk ?? _string('DTPlatformVersion'),
      'xcode': _string('DTXcode'),
      'entitlements': (_main?.entitlements?.keys.toList() ?? <String>[])
        ..sort(),
      'profile': profile == null
          ? null
          : {
              'kind': profile.kind.wire,
              'name': profile.name,
              'teamId': profile.teamId,
              'expirationDate': profile.expirationDate,
            },
      'extensions': _report.extensions.length,
      'usesNonExemptEncryption': _info['ITSAppUsesNonExemptEncryption'],
    };
  }

  String? _string(String key) {
    final value = _info[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? _sdkName() => _string('DTSDKName')?.replaceAll(RegExp('[^0-9.]'), '');

  static int? _major(String? version) {
    if (version == null) return null;
    return int.tryParse(version.split('.').first);
  }
}
