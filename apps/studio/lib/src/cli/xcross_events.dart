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
      'crash' => CrashReport.fromJson(json),
      'notice' => Notice('${json['message'] ?? ''}'),
      'step' => BuildStep.fromJson(json),
      'progress' => BuildProgress.fromJson(json),
      'log' => BuildLog.fromJson(json),
      'warning' || 'error' => BuildIssue.fromJson(json),
      'artifact' => BuildArtifact.fromJson(json),
      'check' => DoctorCheckResult.fromJson(json),
      'flutter_sdks' => FlutterSdkStatus.fromJson(json),
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
