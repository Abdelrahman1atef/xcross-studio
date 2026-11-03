import 'dart:convert';

/// One NDJSON event from `xcross … --json` (schemas:
/// `specs/010-device-logs/contracts/devicelog.schema.json` and, with
/// `XCROSS_EVENTS=ndjson`, `specs/012-build-events/contracts/events.schema.json`;
/// v 1).
sealed class XcrossEvent {
  const XcrossEvent();

  /// The event on [line], or `null` for a line that is not a known v1 event
  /// (plain text, other JSON, newer event types).
  static XcrossEvent? tryParse(String line) => split(line).event;

  /// Splits [line] into leading text and an event. Tools that write straight
  /// to stdout can leave a partial line, so an event may follow text on the
  /// same line.
  static ({String text, XcrossEvent? event}) split(String line) {
    final trimmed = line.trim();
    if (trimmed.startsWith('{')) {
      final event = _decode(trimmed);
      if (event != null) return (text: '', event: event);
    }
    final start = line.indexOf('{"v":1,"type":');
    if (start > 0) {
      final event = _decode(line.substring(start).trim());
      if (event != null) return (text: line.substring(0, start), event: event);
    }
    return (text: line, event: null);
  }

  static XcrossEvent? _decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> || json['v'] != 1) return null;
    return switch (json['type']) {
      'devicelog' => DeviceLogLine.fromJson(json),
      'diagnosis' => PushDiagnosis.fromJson(json),
      'appinfo' => AppInfo.fromJson(json),
      'app' => InstalledApp.fromJson(json),
      'device' => ConnectedDevice.fromJson(json),
      'devices' => DeviceSnapshot.fromJson(json),
      'crash' => CrashReport.fromJson(json),
      'notice' => Notice('${json['message'] ?? ''}'),
      'step' => BuildStep.fromJson(json),
      'progress' => BuildProgress.fromJson(json),
      'log' => BuildLog.fromJson(json),
      'warning' || 'error' => BuildIssue.fromJson(json),
      'artifact' => BuildArtifact.fromJson(json),
      'check' => DoctorCheckResult.fromJson(json),
      'flutter_sdks' => FlutterSdkStatus.fromJson(json),
      'bundle_id' => BundleIdStatus.fromJson(json),
      // Feature 022: the release steps.
      'release_check' => ReleaseCheckReport.fromJson(json),
      'release_gate' => ReleaseGateResult.fromJson(json),
      'publish' => PublishEvent.fromJson(json),
      'testflight_status' => TestFlightStatus.fromJson(json),
      'appstore_status' => AppStoreStatus.fromJson(json),
      // Feature 023: the app icon set.
      'icons_check' => IconsCheckReport.fromJson(json),
      'icons_generate' => IconsGenerateResult.fromJson(json),
      'done' => BuildDone(
        json['exitCode'] is int ? json['exitCode']! as int : 1,
      ),
      _ => null,
    };
  }
}

String? _string(Object? value) => value is String ? value : null;

/// `devicelog`: one line of the iPhone's system log.
class DeviceLogLine extends XcrossEvent {
  const DeviceLogLine({
    required this.time,
    required this.process,
    required this.pid,
    required this.level,
    required this.message,
    this.subsystem,
    this.category,
    this.highlight,
  });

  factory DeviceLogLine.fromJson(Map<String, Object?> json) => DeviceLogLine(
    time: _string(json['time']) ?? '',
    process: _string(json['process']) ?? '?',
    pid: json['pid'] is int ? json['pid']! as int : 0,
    level: _string(json['level']) ?? 'notice',
    message: _string(json['message']) ?? '',
    subsystem: _string(json['subsystem']),
    category: _string(json['category']),
    highlight: _string(json['highlight']),
  );

  final String time;
  final String process;
  final int pid;
  final String level;
  final String message;
  final String? subsystem;
  final String? category;

  /// `registration`, `delivery` or `error` for push-preset lines.
  final String? highlight;

  /// `HH:MM:SS.mmm` from the device timestamp.
  String get clock {
    final t = time.indexOf('T');
    if (t < 0) return time;
    final rest = time.substring(t + 1);
    final dot = rest.indexOf('.');
    if (dot < 0) return rest;
    final fraction = rest.substring(dot + 1).padRight(3, '0').substring(0, 3);
    return '${rest.substring(0, dot)}.$fraction';
  }

  /// The line as `xcross logs` prints it without `--json`.
  String toText() =>
      '${highlight == null ? '' : '★ '}$clock $process[$pid] '
      '${level.isEmpty ? '?' : level[0].toUpperCase()} $message';
}

/// `diagnosis`: the push preset's verdict.
class PushDiagnosis extends XcrossEvent {
  const PushDiagnosis({
    required this.bundleId,
    required this.entitlement,
    required this.appSeen,
    required this.registrationSeen,
    required this.deliverySeen,
    required this.permissionDenied,
    required this.verdict,
    required this.hint,
  });

  factory PushDiagnosis.fromJson(Map<String, Object?> json) => PushDiagnosis(
    bundleId: _string(json['bundleId']) ?? '',
    entitlement: _string(json['entitlement']),
    appSeen: json['appSeen'] == true,
    registrationSeen: json['registrationSeen'] == true,
    deliverySeen: json['deliverySeen'] == true,
    permissionDenied: json['permissionDenied'] == true,
    verdict: _string(json['verdict']) ?? '',
    hint: _string(json['hint']) ?? '',
  );

  final String bundleId;
  final String? entitlement;
  final bool appSeen;
  final bool registrationSeen;
  final bool deliverySeen;
  final bool permissionDenied;
  final String verdict;
  final String hint;
}

/// `appinfo`: an installed app's signer and entitlements.
class AppInfo extends XcrossEvent {
  const AppInfo({
    required this.bundleId,
    required this.signer,
    required this.entitlements,
    required this.associatedDomains,
    this.name,
    this.version,
    this.build,
    this.executable,
    this.teamId,
    this.push,
  });

  factory AppInfo.fromJson(Map<String, Object?> json) => AppInfo(
    bundleId: _string(json['bundleId']) ?? '',
    name: _string(json['name']),
    version: _string(json['version']),
    build: _string(json['build']),
    executable: _string(json['executable']),
    signer: _string(json['signer']) ?? 'other',
    teamId: _string(json['teamId']),
    entitlements: json['entitlements'] is Map
        ? (json['entitlements']! as Map).cast<String, Object?>()
        : const {},
    push: _string(json['push']),
    associatedDomains: [
      if (json['associatedDomains'] case final List<Object?> domains)
        for (final domain in domains) '$domain',
    ],
  );

  final String bundleId;
  final String? name;
  final String? version;
  final String? build;
  final String? executable;
  final String signer;
  final String? teamId;
  final Map<String, Object?> entitlements;

  /// `aps-environment`, `null` when missing.
  final String? push;
  final List<String> associatedDomains;
}

/// `app`: one installed user app (from `xcross app list`).
class InstalledApp extends XcrossEvent {
  const InstalledApp({
    required this.bundleId,
    this.name,
    this.version,
    this.build,
    this.executable,
  });

  factory InstalledApp.fromJson(Map<String, Object?> json) => InstalledApp(
    bundleId: _string(json['bundleId']) ?? '',
    name: _string(json['name']),
    version: _string(json['version']),
    build: _string(json['build']),
    executable: _string(json['executable']),
  );

  final String bundleId;
  final String? name;
  final String? version;
  final String? build;
  final String? executable;

  String get label => name == null ? bundleId : '$name ($bundleId)';
}

/// `device`: one connected iPhone (from `xcross devices`).
class ConnectedDevice extends XcrossEvent {
  const ConnectedDevice({
    required this.udid,
    required this.name,
    required this.connection,
    this.osVersion,
  });

  factory ConnectedDevice.fromJson(Map<String, Object?> json) =>
      ConnectedDevice(
        udid: _string(json['udid']) ?? '',
        name: _string(json['name']) ?? 'iPhone',
        osVersion: _string(json['osVersion']),
        connection: _string(json['connection']) ?? 'usb',
      );

  final String udid;
  final String name;
  final String? osVersion;
  final String connection;

  /// iOS 15/16 open apps through a developer disk image or from the icon.
  bool get legacy {
    final major = int.tryParse((osVersion ?? '').split('.').first);
    return major != null && major < 17;
  }
}

/// `crash`: one crash report on the device.
class CrashReport extends XcrossEvent {
  const CrashReport({
    required this.name,
    required this.process,
    required this.time,
    this.exceptionType,
  });

  factory CrashReport.fromJson(Map<String, Object?> json) => CrashReport(
    name: _string(json['name']) ?? '',
    process: _string(json['process']) ?? '?',
    time: _string(json['time']) ?? '',
    exceptionType: _string(json['exceptionType']),
  );

  final String name;
  final String process;
  final String time;
  final String? exceptionType;
}

/// `notice`: status such as "waiting for Runner".
class Notice extends XcrossEvent {
  const Notice(this.message);
  final String message;
}

// Build events (XCROSS_EVENTS=ndjson, feature 012).

/// `step`: a build step started, finished or failed.
class BuildStep extends XcrossEvent {
  const BuildStep({
    required this.name,
    required this.status,
    this.message,
    this.elapsedMs,
  });

  factory BuildStep.fromJson(Map<String, Object?> json) => BuildStep(
    name: _string(json['name']) ?? '',
    status: _string(json['status']) ?? 'start',
    message: _string(json['message']),
    elapsedMs: json['elapsedMs'] is int ? json['elapsedMs']! as int : null,
  );

  final String name;

  /// `start`, `done` or `failed`.
  final String status;
  final String? message;
  final int? elapsedMs;
}

/// `progress`: a download or extraction; [fraction] is null when unknown.
class BuildProgress extends XcrossEvent {
  const BuildProgress({required this.label, this.fraction});

  factory BuildProgress.fromJson(Map<String, Object?> json) => BuildProgress(
    label: _string(json['label']) ?? '',
    fraction: json['fraction'] is num
        ? (json['fraction']! as num).toDouble()
        : null,
  );

  final String label;
  final double? fraction;
}

/// `log`: a line the CLI printed (status, trace, step output, raw output).
class BuildLog extends XcrossEvent {
  const BuildLog({
    required this.level,
    required this.message,
    this.stream,
    this.step,
  });

  factory BuildLog.fromJson(Map<String, Object?> json) => BuildLog(
    level: _string(json['level']) ?? 'info',
    message: _string(json['message']) ?? '',
    stream: _string(json['stream']),
    step: _string(json['step']),
  );

  final String level;
  final String message;
  final String? stream;
  final String? step;
}

/// `warning` / `error`: a problem with its stable code and fix hint.
class BuildIssue extends XcrossEvent {
  const BuildIssue({
    required this.isError,
    required this.message,
    this.code,
    this.hint,
  });

  factory BuildIssue.fromJson(Map<String, Object?> json) => BuildIssue(
    isError: json['type'] == 'error',
    code: _string(json['code']),
    message: _string(json['message']) ?? '',
    hint: _string(json['hint']),
  );

  final bool isError;
  final String? code;
  final String message;
  final String? hint;
}

/// `artifact`: a built `.app` or `.ipa`.
class BuildArtifact extends XcrossEvent {
  const BuildArtifact({required this.kind, required this.path});

  factory BuildArtifact.fromJson(Map<String, Object?> json) => BuildArtifact(
    kind: _string(json['kind']) ?? 'app',
    path: _string(json['path']) ?? '',
  );

  /// `app` or `ipa`.
  final String kind;
  final String path;
}

/// `check`: one doctor check.
class DoctorCheckResult extends XcrossEvent {
  const DoctorCheckResult({
    required this.section,
    required this.name,
    required this.status,
    required this.message,
    this.path,
  });

  factory DoctorCheckResult.fromJson(Map<String, Object?> json) =>
      DoctorCheckResult(
        section: _string(json['section']) ?? '',
        name: _string(json['name']) ?? '',
        status: _string(json['status']) ?? 'success',
        message: _string(json['message']) ?? '',
        path: _string(json['path']),
      );

  final String section;
  final String name;

  /// `success`, `warning` or `failure`.
  final String status;
  final String message;
  final String? path;
}

/// `done`: the command finished with [exitCode].
class BuildDone extends XcrossEvent {
  const BuildDone(this.exitCode);
  final int exitCode;
}

/// `flutter_sdks`: the Flutter used for iOS builds and the fix for a missing
/// iOS compiler (from `xcross flutter sdk list --json`, feature 014).
class FlutterSdkStatus extends XcrossEvent {
  const FlutterSdkStatus({
    required this.platform,
    required this.managed,
    required this.available,
    this.activeRoot,
    this.activeVersion,
    this.activeManaged = false,
    this.compiler = 'unknown',
    this.detail,
    this.suggested,
  });

  factory FlutterSdkStatus.fromJson(Map<String, Object?> json) {
    final active = json['active'] is Map
        ? (json['active']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return FlutterSdkStatus(
      platform: _string(json['platform']) ?? '',
      activeRoot: _string(active['root']),
      activeVersion: _string(active['version']),
      activeManaged: active['managed'] == true,
      compiler: _string(active['compiler']) ?? 'unknown',
      detail: _string(active['detail']),
      managed: [
        if (json['managed'] case final List<Object?> list)
          for (final sdk in list)
            if (sdk case {'version': final String version}) version,
      ],
      available: [
        if (json['available'] case final List<Object?> list)
          for (final version in list) '$version',
      ],
      suggested: _string(json['suggested']),
    );
  }

  final String platform;
  final String? activeRoot;
  final String? activeVersion;

  /// True when iOS builds use a Flutter that xcross installed.
  final bool activeManaged;

  /// `available`, `missing` or `unknown`.
  final String compiler;
  final String? detail;

  /// Versions xcross installed.
  final List<String> managed;

  /// Versions with an iOS compiler for this computer, newest first.
  final List<String> available;

  /// The version `xcross flutter sdk auto` would install, when needed.
  final String? suggested;
}

/// `bundle_id`: the App ID the open project is signed under (from
/// `xcross project bundle-id --json`, feature 016).
class BundleIdStatus extends XcrossEvent {
  const BundleIdStatus({
    required this.next,
    this.bundleId,
    this.saved,
    this.override,
    this.settingsPath,
  });

  factory BundleIdStatus.fromJson(Map<String, Object?> json) => BundleIdStatus(
    bundleId: _string(json['bundleId']),
    saved: _string(json['saved']),
    override: _string(json['override']),
    settingsPath: _string(json['settingsPath']),
    next: _string(json['next']) ?? 'original',
  );

  final String? bundleId;

  /// `original`, `prefixed`, or `null` when nothing is saved.
  final String? saved;

  /// `XCROSS_BUNDLE_ID`, when set.
  final String? override;
  final String? settingsPath;

  /// What the next build uses: `original` or `prefixed`.
  final String next;

  bool get usesRealAppId => next == 'original';
}

/// `devices`: the full list of connected iPhones, from
/// `xcross devices --watch --json` (feature 017), at start and after every
/// change.
class DeviceSnapshot extends XcrossEvent {
  const DeviceSnapshot(this.devices);

  factory DeviceSnapshot.fromJson(Map<String, Object?> json) => DeviceSnapshot([
    if (json['devices'] case final List<Object?> list)
      for (final entry in list)
        if (entry is Map<String, Object?>) ConnectedDevice.fromJson(entry),
  ]);

  final List<ConnectedDevice> devices;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

List<Map<String, Object?>> _maps(Object? value) => [
  if (value is List)
    for (final entry in value)
      if (entry is Map) entry.cast<String, Object?>(),
];

/// One issue of `xcross release check` (feature 018).
class ReleaseIssue {
  const ReleaseIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.hint,
    this.path,
  });

  factory ReleaseIssue.fromJson(Map<String, Object?> json) => ReleaseIssue(
    code: _string(json['code']) ?? '',
    severity: _string(json['severity']) ?? 'info',
    message: _string(json['message']) ?? '',
    hint: _string(json['hint']),
    path: _string(json['path']),
  );

  final String code;

  /// `error`, `warning` or `info`.
  final String severity;
  final String message;
  final String? hint;
  final String? path;
}

/// `release_check`: `xcross release check --json`.
class ReleaseCheckReport extends XcrossEvent {
  const ReleaseCheckReport({
    required this.configuration,
    required this.issues,
    this.input,
  });

  factory ReleaseCheckReport.fromJson(Map<String, Object?> json) =>
      ReleaseCheckReport(
        input: _string(json['input']),
        configuration: _map(json['configuration']),
        issues: [
          for (final issue in _maps(json['issues']))
            ReleaseIssue.fromJson(issue),
        ],
      );

  final String? input;
  final Map<String, Object?> configuration;
  final List<ReleaseIssue> issues;

  int get errors => issues.where((i) => i.severity == 'error').length;
  int get warnings => issues.where((i) => i.severity == 'warning').length;
}

/// `release_gate`: `xcross release gate --json` (feature 022).
class ReleaseGateResult extends XcrossEvent {
  const ReleaseGateResult(this.steps);

  factory ReleaseGateResult.fromJson(Map<String, Object?> json) =>
      ReleaseGateResult([
        for (final step in _maps(json['steps']))
          (
            name: _string(step['name']) ?? '',
            passed: step['passed'] == true,
            tail: [
              if (step['tail'] case final List<Object?> lines)
                for (final line in lines) '$line',
            ],
          ),
      ]);

  final List<({String name, bool passed, List<String> tail})> steps;

  bool get passed => steps.isNotEmpty && steps.every((s) => s.passed);
}

/// `publish`: one event of `xcross publish --json` (feature 019).
class PublishEvent extends XcrossEvent {
  const PublishEvent(this.event, this.fields);

  factory PublishEvent.fromJson(Map<String, Object?> json) =>
      PublishEvent(_string(json['event']) ?? '', json);

  /// `start`, `progress`, `uploaded`, `state`, `issue`, `published`, `note`.
  final String event;
  final Map<String, Object?> fields;
}

/// `testflight_status`: `xcross testflight status --json` (feature 020).
class TestFlightStatus extends XcrossEvent {
  const TestFlightStatus(this.builds);

  factory TestFlightStatus.fromJson(Map<String, Object?> json) =>
      TestFlightStatus(_maps(json['builds']));

  /// `version`, `buildNumber`, `processingState`, `internalBuildState`,
  /// `externalBuildState`, `groups`, …
  final List<Map<String, Object?>> builds;
}

/// `appstore_status`: `xcross appstore status --json` (feature 021).
class AppStoreStatus extends XcrossEvent {
  const AppStoreStatus({
    this.version,
    this.state,
    this.build,
    this.submissions = const [],
  });

  factory AppStoreStatus.fromJson(Map<String, Object?> json) => AppStoreStatus(
    version: _string(json['version']),
    state: _string(json['state']),
    build: _string(json['build']),
    submissions: _maps(json['submissions']),
  );

  final String? version;
  final String? state;
  final String? build;
  final List<Map<String, Object?>> submissions;
}

double? _double(Object? value) => value is num ? value.toDouble() : null;

/// One slot of `icons_check` (feature 023).
class IconSlotStatus {
  const IconSlotStatus({
    required this.role,
    required this.label,
    required this.idiom,
    required this.points,
    required this.scale,
    required this.pixels,
    required this.status,
    required this.required,
    this.file,
    this.actual,
  });

  factory IconSlotStatus.fromJson(Map<String, Object?> json) => IconSlotStatus(
    role: _string(json['role']) ?? '',
    label: _string(json['label']) ?? '',
    idiom: _string(json['idiom']) ?? '',
    points: _double(json['points']) ?? 0,
    scale: json['scale'] is int ? json['scale']! as int : 1,
    pixels: json['pixels'] is int ? json['pixels']! as int : 0,
    status: _string(json['status']) ?? 'missing',
    required: json['required'] == true,
    file: _string(json['file']),
    actual: _string(json['actual']),
  );

  /// `notification`, `settings`, `spotlight`, `home`, `ipadHome`,
  /// `ipadProHome`, `appStore`.
  final String role;
  final String label;

  /// `iphone`, `ipad`, `ios-marketing`, `universal`.
  final String idiom;
  final double points;
  final int scale;
  final int pixels;

  /// `ok`, `missing`, `wrong_size`, `unreadable`.
  final String status;
  final bool required;
  final String? file;
  final String? actual;

  String get pointsText =>
      points == points.roundToDouble() ? '${points.round()}' : '$points';
}

/// `placement` of `icons_check`: fractions of the icon's side.
class IconPlacementInfo {
  const IconPlacementInfo({
    required this.offset,
    required this.outsideMask,
    required this.prerounded,
    required this.transparent,
    required this.fullBleed,
    this.background,
    this.box,
  });

  factory IconPlacementInfo.fromJson(Map<String, Object?> json) {
    List<double>? numbers(Object? value) =>
        value is List ? [for (final item in value) _double(item) ?? 0] : null;
    final offset = numbers(json['offset']) ?? const [0, 0];
    final box = numbers(json['box']);
    return IconPlacementInfo(
      background: _string(json['background']),
      box: box != null && box.length == 4
          ? (left: box[0], top: box[1], width: box[2], height: box[3])
          : null,
      offset: (
        dx: offset.isNotEmpty ? offset[0] : 0,
        dy: offset.length > 1 ? offset[1] : 0,
      ),
      outsideMask: _double(json['outsideMask']) ?? 0,
      prerounded: json['prerounded'] == true,
      transparent: json['transparent'] == true,
      fullBleed: json['fullBleed'] == true,
    );
  }

  /// `#RRGGBB`, or null for full-bleed artwork.
  final String? background;
  final ({double left, double top, double width, double height})? box;
  final ({double dx, double dy}) offset;
  final double outsideMask;
  final bool prerounded;
  final bool transparent;
  final bool fullBleed;
}

/// `icons_check`: `xcross icons check --json` (feature 023).
class IconsCheckReport extends XcrossEvent {
  const IconsCheckReport({
    required this.slots,
    required this.issues,
    this.path,
    this.style,
    this.source,
    this.placement,
  });

  factory IconsCheckReport.fromJson(Map<String, Object?> json) =>
      IconsCheckReport(
        path: _string(json['path']),
        style: _string(json['style']),
        source: _string(json['source']),
        slots: [
          for (final slot in _maps(json['slots']))
            IconSlotStatus.fromJson(slot),
        ],
        placement: json['placement'] is Map
            ? IconPlacementInfo.fromJson(_map(json['placement']))
            : null,
        issues: [
          for (final issue in _maps(json['issues']))
            ReleaseIssue.fromJson({...issue, 'path': issue['file']}),
        ],
      );

  /// The `.appiconset` folder; null when the project has none.
  final String? path;

  /// `all-sizes` or `single-size`.
  final String? style;

  /// The file placement was measured on (the App Store icon).
  final String? source;
  final List<IconSlotStatus> slots;
  final IconPlacementInfo? placement;
  final List<ReleaseIssue> issues;

  int get errors => issues.where((i) => i.severity == 'error').length;
  int get warnings => issues.where((i) => i.severity == 'warning').length;
}

/// `icons_generate`: `xcross icons generate … --json` (feature 023).
class IconsGenerateResult extends XcrossEvent {
  const IconsGenerateResult({
    required this.written,
    this.path,
    this.backup,
    this.background,
    this.check,
  });

  factory IconsGenerateResult.fromJson(Map<String, Object?> json) =>
      IconsGenerateResult(
        path: _string(json['path']),
        written: [
          if (json['written'] case final List<Object?> names)
            for (final name in names) '$name',
        ],
        backup: _string(json['backup']),
        background: _string(json['background']),
        check: json['check'] is Map
            ? IconsCheckReport.fromJson(_map(json['check']))
            : null,
      );

  final String? path;
  final List<String> written;

  /// Where the old set was copied, if there was one.
  final String? backup;
  final String? background;
  final IconsCheckReport? check;
}
