import 'dart:convert';

/// One NDJSON event from `xcross … --json` (schema:
/// `specs/010-device-logs/contracts/devicelog.schema.json`, v 1).
sealed class XcrossEvent {
  const XcrossEvent();

  /// The event on [line], or `null` for a line that is not a known v1 event
  /// (plain text, other JSON, newer event types).
  static XcrossEvent? tryParse(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('{')) return null;
    final Object? json;
    try {
      json = jsonDecode(trimmed);
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
