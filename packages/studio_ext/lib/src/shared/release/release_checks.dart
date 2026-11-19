// studio: 018 — the local part of App Store validation, before an upload
// (specs/018-app-store-build, AC-018-9…AC-018-14).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/pods/pod_report.dart';
import 'package:studio_ext/shared/release/macho_minimum_os.dart'; // studio: 018
import 'package:studio_ext/shared/release/swift_runtime.dart'; // studio: 018
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/inspector.dart';
import 'package:studio_ext/src/shared/inspect/macho_reader.dart';
import 'package:studio_ext/src/shared/inspect/plist_reader.dart';
import 'package:studio_ext/src/shared/release/app_icon_catalog.dart'; // studio: 004
import 'package:studio_ext/src/shared/release/macho_build_version.dart';
import 'package:studio_ext/src/shared/release/release_structure.dart'; // studio: 018
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
    this.fix,
  });

  /// `release.*`, never renamed once released.
  final String code;
  final ReleaseSeverity severity;
  final String message;
  final String? path;
  final String? hint;

  /// The xcross arguments that fix the issue in the project (run in the
  /// project folder, then build again), when xcross can do it: a GUI shows
  /// them as a Fix button. Null when the developer has to do it.
  final List<String>? fix;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity.name,
    'message': message,
    'path': path,
    'hint': hint,
    if (fix != null) 'fix': fix,
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

  /// This report with what App Store Connect said added: [online] is whether
  /// it was asked at all (false: the key or the network was missing).
  ReleaseReport withOnline(List<ReleaseIssue> asked, {required bool online}) =>
      ReleaseReport(
        input: input,
        configuration: {...configuration, 'online': online},
        issues: [...issues, ...asked],
      );

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
  late final Set<String> plugins = {
    ..._resolvedIos.keys,
    if (_read(['pubspec.yaml']) case final pubspec?)
      ...directDependencies(pubspec),
  };

  /// iOS plugins `flutter pub get` marked `native_build: false`: Dart or FFI
  /// only, with no iOS code of their own in the app (path_provider_foundation
  /// 2.6 and later), so there is no plugin bundle for a manifest to be in.
  late final Set<String> pluginsWithoutNativeCode = {
    for (final MapEntry(key: name, value: native) in _resolvedIos.entries)
      if (!native) name,
  };

  /// `.flutter-plugins-dependencies` iOS entries: name → has native code.
  late final Map<String, bool> _resolvedIos = () {
    final entries = <String, bool>{};
    final resolved = _read(['.flutter-plugins-dependencies']);
    if (resolved == null) return entries;
    try {
      final Object? decoded = jsonDecode(resolved);
      if (decoded case {'plugins': {'ios': final List<Object?> list}}) {
        for (final entry in list) {
          if (entry case {'name': final String name}) {
            entries[name] = switch (entry) {
              {'native_build': false} => false,
              _ => true,
            };
          }
        }
      }
    } on FormatException {
      // A broken list is pub's to report.
    }
    return entries;
  }();

  /// The app's `ios/Runner/Info.plist` as written in the project (build
  /// variables such as `$(FLUTTER_BUILD_NAME)` are not resolved); empty when
  /// it is missing or unreadable.
  Map<String, Object?> infoPlist() {
    final file = fileSystem.file(_join(['ios', 'Runner', 'Info.plist']));
    if (!file.existsSync()) return const {};
    return readPlist(file.readAsBytesSync())?.dictionary ?? const {};
  }

  /// Whether the Runner target has its own privacy manifest.
  bool get hasPrivacyManifest => fileSystem
      .file(_join(['ios', 'Runner', 'PrivacyInfo.xcprivacy']))
      .existsSync();

  /// `key: value` under the top-level `xcross:` key of `pubspec.yaml`, or
  /// null (a line scan, as for [directDependencies]).
  String? xcrossSetting(String key) {
    final pubspec = _read(['pubspec.yaml']);
    if (pubspec == null) return null;
    var inside = false;
    for (final raw in const LineSplitter().convert(pubspec)) {
      final line = raw.replaceFirst(RegExp(r'\s+#.*$'), '');
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (!line.startsWith(' ') && !line.startsWith('	')) {
        inside = line.startsWith('xcross:');
        continue;
      }
      if (!inside) continue;
      final match = RegExp(
        r'^\s+' + RegExp.escape(key) + r'\s*:\s*(.*?)\s*$',
      ).firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }

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

/// The permission, App Transport Security and background-mode findings for
/// an app whose Info.plist is [info] and that uses [plugins]. [known] is
/// whether the Flutter project (so the plugin list) is known. Shared by the
/// check of a built app and the one before the build.
@internal
List<ReleaseIssue> permissionIssues(
  Map<String, Object?> info,
  Set<String> plugins, {
  required bool known,
}) {
  final issues = <ReleaseIssue>[];
  void add(
    String code,
    ReleaseSeverity severity,
    String message, {
    String? path,
    String? hint,
  }) =>
      issues.add(ReleaseIssue(code, severity, message, path: path, hint: hint));

  for (final plugin in plugins.toList()..sort()) {
    for (final requirement
        in ReleaseTables.pluginUsage[plugin] ?? const <UsageRequirement>[]) {
      if (requirement.anyOf.any((key) => info.containsKey(key))) continue;
      add(
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
  for (final key
      in info.keys.where(ReleaseTables.isUsageKey).toList()..sort()) {
    final value = info[key];
    final text = value is String ? value.trim() : '';
    if (ReleaseTables.isPlaceholderPurpose(key, value)) {
      add(
        'release.permission_placeholder',
        ReleaseSeverity.warning,
        '$key is "${text.length > 40 ? '${text.substring(0, 40)}…' : text}"; '
            'App Review rejects empty or placeholder purpose strings.',
        path: 'Info.plist',
        hint: 'Explain what the app does with it, in a full sentence.',
      );
    }
  }
  if (info['NSAppTransportSecurity'] case {'NSAllowsArbitraryLoads': true}) {
    add(
      'release.ats_arbitrary_loads',
      ReleaseSeverity.warning,
      'NSAllowsArbitraryLoads turns off App Transport Security for every '
          'domain; App Review asks for a justification.',
      path: 'Info.plist',
      hint: 'Use NSExceptionDomains for the hosts that need it.',
    );
  }
  final modes = info['UIBackgroundModes'];
  if (modes is List) {
    for (final mode in modes.whereType<String>()) {
      final explainedBy = [
        for (final plugin
            in ReleaseTables.backgroundModePlugins[mode] ?? const <String>[])
          if (plugins.contains(plugin)) plugin,
      ];
      add(
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
  return issues;
}

/// What is wrong with the App Store icon of [project]'s icon set: none, an
/// unusable PNG (size, alpha channel, transparency), or no 1024 px icon at
/// all. Shared by the check of a built app and the one before the build.
@internal
List<ReleaseIssue> marketingIconIssues(ReleaseProject project) {
  final icon = project.marketingIcon();
  if (icon.problem case final problem?) {
    return [
      ReleaseIssue(
        'release.marketing_icon',
        ReleaseSeverity.error,
        'No usable app icon set ($problem).',
        path: 'ios/Runner/Assets.xcassets',
        hint: 'Add an AppIcon set with a 1024×1024 icon.',
      ),
    ];
  }
  if (icon.fileName == null) {
    return const [
      ReleaseIssue(
        'release.marketing_icon',
        ReleaseSeverity.error,
        'The app icon set has no 1024×1024 App Store icon.',
        path: 'ios/Runner/Assets.xcassets',
        hint: 'Add a 1024×1024 PNG without transparency to the icon set.',
      ),
    ];
  }
  final bytes = icon.bytes;
  final problem = bytes == null
      ? 'is missing'
      : ReleaseChecker.pngProblem(bytes);
  if (problem == null) return const [];
  return [
    ReleaseIssue(
      'release.marketing_icon',
      ReleaseSeverity.error,
      'The App Store icon ${icon.fileName} $problem.',
      path: 'ios/Runner/Assets.xcassets',
      hint:
          'Export it as a 1024×1024 PNG without an alpha channel '
          '(App Store Connect rejects transparency: ITMS-90717).',
    ),
  ];
}

/// The checks that need no built app, only the project's sources: they run
/// before `xcross flutter build --export-method app-store` compiles anything,
/// so an App Store rejection found here costs seconds, not a whole build.
/// The codes are the ones `xcross release check` uses for the same findings.
@internal
ReleaseReport runPreflightChecks(ReleaseProject project) {
  final info = project.infoPlist();
  final issues = <ReleaseIssue>[
    ...marketingIconIssues(project),
    ...permissionIssues(info, project.plugins, known: true),
  ];
  if (!project.hasPrivacyManifest) {
    issues.add(
      const ReleaseIssue(
        'release.privacy_manifest_missing',
        ReleaseSeverity.warning,
        'The app has no PrivacyInfo.xcprivacy at its root.',
        path: 'ios/Runner/PrivacyInfo.xcprivacy',
        hint:
            'Add ios/Runner/PrivacyInfo.xcprivacy (data collected, '
            'required-reason APIs) to the Runner target: '
            '`xcross privacy init` does both.',
        fix: ['privacy', 'init'],
      ),
    );
  }
  if (!info.containsKey('ITSAppUsesNonExemptEncryption') &&
      project.xcrossSetting('uses_non_exempt_encryption') == null) {
    issues.add(
      const ReleaseIssue(
        'release.encryption_unset',
        ReleaseSeverity.warning,
        'ITSAppUsesNonExemptEncryption is not set, so App Store Connect asks '
            'the export compliance questions for every build.',
        path: 'pubspec.yaml',
        hint:
            'Set uses_non_exempt_encryption: false (or true) under xcross: in '
            "pubspec.yaml after checking the app's encryption.",
      ),
    );
  }
  return ReleaseReport(
    input: project.root,
    configuration: const {'stage': 'preflight'},
    issues: issues,
  );
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
    List<String>? fix,
  }) => _issues.add(
    ReleaseIssue(code, severity, message, path: path, hint: hint, fix: fix),
  );

  ReleaseReport run() {
    _signing();
    _toolchain();
    _frameworkMinimumOS();
    _swiftSupport();
    _issues.addAll(
      structureIssues(source: source, report: _report, binaries: _binaries),
    );
    _permissions();
    _permissionsFromCode();
    _privacy();
    _assets();
    _podsReport();
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

  /// A framework whose code needs a newer iOS than its Info.plist says: App
  /// Store Connect refuses the upload (90208). Native-asset frameworks such
  /// as objective_c.framework said 13.0 while built for the app's target.
  void _frameworkMinimumOS() {
    for (final framework in _report.frameworks) {
      if (framework.kind != FrameworkKind.framework) continue;
      final Map<String, Object?> info;
      final Uint8List? binary;
      try {
        final plist = source.read('${framework.path}/Info.plist');
        info = (plist == null ? null : readPlist(plist)?.dictionary) ?? {};
        final executable =
            info['CFBundleExecutable'] as String? ??
            framework.name.replaceAll(RegExp(r'\.framework$'), '');
        binary = source.read('${framework.path}/$executable');
      } on FormatException {
        continue;
      }
      final declared = info['MinimumOSVersion'];
      final needed = binary == null ? null : machOMinimumOS(binary);
      if (declared is! String || needed == null) continue;
      if (compareOsVersions(needed, declared) <= 0) continue;
      _add(
        'release.framework_minimum_os',
        ReleaseSeverity.error,
        "${framework.name}'s code needs iOS $needed, but its Info.plist says "
            'MinimumOSVersion $declared; App Store Connect refuses the upload '
            '(90208).',
        path: '${framework.path}/Info.plist',
        hint:
            'Build again with xcross 2.0.9-xs.6 or later, which sets the '
            "framework's MinimumOSVersion from its code.",
      );
    }
  }

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

  // --- SwiftSupport (AC-018-16) -------------------------------------------

  /// Every binary of the app, read once.
  late final Map<String, Uint8List> _binaries = () {
    final binaries = <String, Uint8List>{};
    for (final executable in _report.executables) {
      try {
        final bytes = source.read(executable.path);
        if (bytes != null) binaries[executable.path] = bytes;
      } on FormatException {
        // An unreadable file is the inspector's to report.
      }
    }
    return binaries;
  }();

  /// App Store Connect wants `SwiftSupport/iphoneos/` at the root of an IPA
  /// whose binaries load Swift runtime libraries (90426 "Invalid Swift
  /// Support"). Only an `.ipa` has a root to look in.
  void _swiftSupport() {
    if (source.kind != InputKind.ipa) return;
    final loaded = swiftRuntimeLibraries(_binaries.values);
    if (loaded.isEmpty) return;
    const folder = 'SwiftSupport/iphoneos/';
    final packed = {
      for (final file in source.outsideFiles)
        if (file.startsWith(folder)) file.substring(folder.length),
    };
    if (packed.isEmpty) {
      _add(
        'release.swift_support_missing',
        ReleaseSeverity.error,
        'The app loads Swift libraries (${(loaded.keys.toList()..sort()).take(3).join(', ')}'
            '${loaded.length > 3 ? ', …' : ''}) but the IPA has no '
            'SwiftSupport folder; App Store Connect refuses it (90426).',
        path: 'SwiftSupport',
        hint:
            'Install the SDK again with `xcross sdk install <Xcode.xip>` (it '
            'now keeps the Swift runtime libraries), then build again.',
      );
      return;
    }
    final missing = [
      for (final library in loaded.values)
        if (library.required && !packed.contains(library.fileName))
          library.fileName,
    ]..sort();
    if (missing.isNotEmpty) {
      _add(
        'release.swift_support_missing',
        ReleaseSeverity.error,
        'SwiftSupport/iphoneos lacks ${missing.join(', ')}, which the app '
            'loads; App Store Connect refuses it (90426).',
        path: 'SwiftSupport/iphoneos',
        hint: 'Build again with a current xcross.',
      );
    }
    // App Store Connect also wants each SwiftSupport library inside the app's
    // own Frameworks folder (90429).
    final notEmbedded = [
      for (final name in packed)
        if (name.endsWith('.dylib') && !source.hasFile('Frameworks/$name'))
          name,
    ]..sort();
    if (notEmbedded.isNotEmpty) {
      _add(
        'release.swift_support_not_embedded',
        ReleaseSeverity.error,
        'SwiftSupport holds ${notEmbedded.take(3).join(', ')}'
            '${notEmbedded.length > 3 ? ', …' : ''} but the app has no copy '
            'in Frameworks; App Store Connect refuses it (90429).',
        path: 'Frameworks',
        hint: 'Build again with a current xcross.',
      );
    }
  }

  // --- Permissions (AC-018-11) --------------------------------------------

  void _permissions() => _issues.addAll(
    permissionIssues(
      _info,
      project?.plugins ?? const <String>{},
      known: project != null,
    ),
  );

  /// The purpose strings App Store Connect finds by reading the code
  /// (AC-018-17): a call such as `requestAlwaysAuthorization` in any binary,
  /// whatever plugin it came from, needs its keys.
  void _permissionsFromCode() {
    for (final rule in ReleaseTables.usageSymbols) {
      String? where;
      for (final MapEntry(key: path, value: bytes) in _binaries.entries) {
        if (latin1.decode(bytes, allowInvalid: true).contains(rule.symbol)) {
          where = path;
          break;
        }
      }
      if (where == null) continue;
      final missing = [
        for (final key in rule.allOf)
          if (!_info.containsKey(key)) key,
      ];
      if (missing.isEmpty) continue;
      _add(
        'release.permission_missing_for_call',
        ReleaseSeverity.warning,
        '$where calls ${rule.symbol} (${rule.resource}) but Info.plist has '
            'no ${missing.join(' or ')}; App Store Connect warns about every '
            'missing purpose string (90683).',
        path: 'Info.plist',
        hint:
            'Add ${missing.join(' and ')} to ios/Runner/Info.plist with a '
            'sentence saying why the app needs it.',
      );
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
            'required-reason APIs) to the Runner target: '
            '`xcross privacy init` does both, then build again.',
        fix: project == null ? null : const ['privacy', 'init'],
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
        final isPod = framework.path.contains('pod-');
        _add(
          isPod
              ? 'pod.sdk_privacy_manifest_missing'
              : 'release.privacy_manifest_missing',
          ReleaseSeverity.warning,
          "$name is on Apple's list of SDKs that must ship a privacy "
          'manifest, and ${framework.path} has none.',
          path: framework.path,
          hint:
              'Update $name to a release that includes PrivacyInfo.xcprivacy.',
        );
      }
    }
    final checkedBundles = <String>{};
    for (final file in source.files) {
      final match = RegExp(r'^([^/]+\.bundle)/').firstMatch(file);
      if (match == null) continue;
      final bundle = match.group(1)!;
      if (!checkedBundles.add(bundle)) continue;
      final name = bundle.replaceAll(
        RegExp(r'(\.bundle|Resources\.bundle)$'),
        '',
      );
      if (!ReleaseTables.sdksNeedingManifest.contains(name)) continue;
      if (!manifests.any((m) => m.startsWith('$bundle/'))) {
        _add(
          'pod.sdk_privacy_manifest_missing',
          ReleaseSeverity.warning,
          "$name is on Apple's list of SDKs that must ship a privacy "
              'manifest, and $bundle has none.',
          path: bundle,
          hint:
              'Update $name to a release that includes PrivacyInfo.xcprivacy.',
        );
      }
    }
    for (final plugin
        in (project?.plugins ?? const <String>{}).toList()..sort()) {
      if (!ReleaseTables.sdksNeedingManifest.contains(plugin)) continue;
      // No iOS code of its own: nothing of it in the app for Apple to check.
      if (project!.pluginsWithoutNativeCode.contains(plugin)) continue;
      final bundled = manifests.any(
        (m) =>
            m.split('/').any((segment) => segment.startsWith(plugin)) &&
            m != 'PrivacyInfo.xcprivacy',
      );
      if (!bundled) {
        final override = project!.hasOverride(plugin);
        _add(
          'release.privacy_manifest_missing',
          ReleaseSeverity.warning,
          "Plugin $plugin is on Apple's list of SDKs that must ship a "
              'privacy manifest, and no bundle of it carries one.',
          hint: override
              ? 'Drafts from older xcross versions left the manifest out: run '
                    '`xcross plugin shim $plugin --force` (this replaces the '
                    'draft), then build again. If it is still missing, update '
                    '$plugin to a release that includes its privacy bundle.'
              : 'Update $plugin to a release that includes its privacy bundle.',
          fix: override ? ['plugin', 'shim', plugin, '--force'] : null,
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
    if (project != null) _issues.addAll(marketingIconIssues(project));
    _iconCatalog();
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

  /// The icon set records App Store Connect reads the app icon from. Without
  /// them (an IPA from an xcross engine older than the icon fix) it shows its
  /// grey placeholder instead of the logo, and nothing else reports it.
  void _iconCatalog() {
    final declared = _iconName();
    final bytes = source.read('Assets.car');
    if (bytes == null) {
      if (declared == null) return; // no asset catalog icon at all
      _iconCatalogError(
        'Info.plist names the app icon "$declared" but the app has no '
        'Assets.car',
      );
      return;
    }
    final name = declared ?? 'AppIcon';
    final AppIconCatalogEntry entry;
    try {
      entry = AppIconCatalog.read(bytes, name);
    } on FormatException catch (error) {
      _iconCatalogError('Assets.car could not be read (${error.message})');
      return;
    }
    if (entry.idioms.isEmpty) {
      _iconCatalogError(
        entry.named
            ? 'Assets.car has no icon set record for "$name"'
            : 'Assets.car has no app icon named "$name"',
      );
    } else if (!entry.idioms.contains(AppIconCatalog.idiomMarketing)) {
      _iconCatalogError(
        'Assets.car has no App Store (1024 px, ios-marketing) icon set for '
        '"$name"',
      );
    }
  }

  void _iconCatalogError(String problem) => _add(
    'release.icon_catalog',
    ReleaseSeverity.error,
    '$problem: App Store Connect will show a blank placeholder icon instead '
        'of the app icon. The IPA was built with an xcross engine that does '
        'not have the app icon fix.',
    path: 'Assets.car',
    hint:
        'Update or rebuild the xcross engine (XCross Studio: install the '
        'engine again; from source: dart run tool/build_xcross.dart), then '
        'build the IPA again.',
  );

  /// `CFBundleIconName`, top level or in `CFBundleIcons`' primary icon.
  String? _iconName() {
    if (_string('CFBundleIconName') case final name?) return name;
    if (_info['CFBundleIcons'] case {
      'CFBundlePrimaryIcon': {'CFBundleIconName': final String name},
    } when name.isNotEmpty) {
      return name;
    }
    return null;
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

  void _podsReport() {
    final proj = project;
    if (proj == null) return;
    final file = proj.fileSystem.file(
      proj.paths.join(proj.root, 'build', 'xcross-ios', 'pods-report.json'),
    );
    if (!file.existsSync()) return;

    final reports = const PodsReportFile().load(file);
    for (final report in reports) {
      if (!report.code.startsWith('pod.')) continue;
      final isError =
          report.code == 'pod.compile_failed' ||
          report.code == 'pod.duplicate_symbols';
      _add(
        report.code,
        isError ? ReleaseSeverity.error : ReleaseSeverity.warning,
        report.formatWarning(),
        path: report.pod,
        hint: 'Run "xcross pods report ${report.pod}" for diagnostic details.',
      );
    }
  }
}
