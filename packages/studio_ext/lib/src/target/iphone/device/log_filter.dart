import 'package:dart_mobile_device/target/iphone/device/pymd/syslog_entry.dart';
import 'package:meta/meta.dart';

import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/src/target/iphone/device/sensitive_masker.dart';

/// `--preset`.
@internal
enum LogPreset { none, flutter, crash, push }

/// Decides which device log entries are shown and how (research D4, D5).
///
/// Works on one entry at a time and keeps no buffer, so memory stays bounded
/// however chatty the device is.
@internal
final class LogFilter {
  LogFilter({
    this.appExecutable,
    this.bundleId,
    this.processes = const [],
    this.grep,
    this.minLevel = 'debug',
    this.preset = LogPreset.none,
  });

  /// The app's `CFBundleExecutable` (`--app`); null shows every process.
  final String? appExecutable;

  /// The app's bundle id, used to find system lines about the app.
  final String? bundleId;

  /// `--process` names or pids; any match passes.
  final List<String> processes;

  /// `--grep`, applied to the message.
  final RegExp? grep;

  /// `--level`: entries below it are dropped.
  final String minLevel;
  final LogPreset preset;

  static const flutterPrefix = 'flutter: ';
  static const pushSystemProcesses = {
    'apsd',
    'usernotificationsd',
    'SpringBoard',
  };
  static const crashSystemProcesses = {
    'ReportCrash',
    'SpringBoard',
    'runningboardd',
    'osanalyticshelper',
  };

  static final _registration = RegExp(
    r'register|registration|device ?token|\bAPNS\b|\btoken\b',
    caseSensitive: false,
  );
  static final _delivery = RegExp(
    'received (incoming )?(push|message|notification)|incoming message|'
    'didReceiveRemoteNotification|delivered|presenting notification',
    caseSensitive: false,
  );
  static final _pushError = RegExp(
    'aps-environment|no valid .*entitlement|failed to register|'
    'not authorized|denied|not allowed',
    caseSensitive: false,
  );
  static final _pushKeywords = RegExp(
    r'push|notification|apns|\baps\b|fcm|firebase ?messaging|token',
    caseSensitive: false,
  );
  static final _crash = RegExp(
    'Terminating app due to uncaught exception|EXC_[A-Z_]+|SIGABRT|SIGSEGV|'
    'Fatal error|jetsam|crash|exited|termination',
    caseSensitive: false,
  );

  int get _minIndex => SyslogEntry.levels.indexOf(minLevel);

  bool _isApp(SyslogEntry entry) => entry.process == appExecutable;

  bool _mentionsApp(SyslogEntry entry) {
    final id = bundleId;
    final exe = appExecutable;
    return (id != null && entry.message.contains(id)) ||
        (exe != null && entry.message.contains(exe));
  }

  /// The event to show for [entry], or null to drop it. [mask] replaces
  /// sensitive values in the shown message.
  DeviceLogEvent? apply(SyslogEntry entry, {required bool mask}) {
    final app = appExecutable;
    String message = entry.message;
    Highlight? highlight;

    switch (preset) {
      case LogPreset.none:
        if (app != null && !_isApp(entry)) return null;
      case LogPreset.flutter:
        if (app != null && !_isApp(entry)) return null;
        if (!message.startsWith(flutterPrefix)) return null;
        message = message.substring(flutterPrefix.length);
      case LogPreset.crash:
        final appProblem =
            _isApp(entry) &&
            (entry.level == 'error' ||
                entry.level == 'fault' ||
                _crash.hasMatch(message));
        final systemAboutApp =
            crashSystemProcesses.contains(entry.process) &&
            _mentionsApp(entry) &&
            _crash.hasMatch(message);
        if (!appProblem && !systemAboutApp) return null;
      case LogPreset.push:
        final fromApp = _isApp(entry);
        final fromPushSystem = pushSystemProcesses.contains(entry.process);
        final relevant =
            (fromApp && _pushKeywords.hasMatch(message)) ||
            (fromPushSystem &&
                (_mentionsApp(entry) || _pushError.hasMatch(message)));
        if (!relevant) return null;
        highlight = pushHighlight(message);
    }

    if (processes.isNotEmpty &&
        !processes.any((p) => p == entry.process || p == '${entry.pid}')) {
      return null;
    }
    if (SyslogEntry.levels.indexOf(entry.level) < _minIndex) return null;
    if (grep case final pattern? when !pattern.hasMatch(message)) return null;

    return DeviceLogEvent(
      entry: entry,
      message: mask ? SensitiveMasker.mask(message) : message,
      highlight: highlight,
    );
  }

  /// Push highlight for [message]: errors win over delivery over
  /// registration.
  static Highlight? pushHighlight(String message) {
    if (_pushError.hasMatch(message)) return Highlight.error;
    if (_delivery.hasMatch(message)) return Highlight.delivery;
    if (_registration.hasMatch(message)) return Highlight.registration;
    return null;
  }

  /// Whether [message] says notifications are not permitted for the app.
  static bool mentionsPermissionDenied(String message) => RegExp(
    'not authorized|authorization denied|denied|not allowed',
    caseSensitive: false,
  ).hasMatch(message);

  /// Whether [message] says the entitlement is missing.
  static bool mentionsEntitlementError(String message) => RegExp(
    'no valid .*aps-environment|aps-environment.*(missing|not found)',
    caseSensitive: false,
  ).hasMatch(message);
}
