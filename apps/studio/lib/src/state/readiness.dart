import 'package:flutter/foundation.dart';

import '../cli/xcross_commands.dart';
import '../cli/xcross_events.dart';
import 'job.dart';
import 'settings.dart';

/// Health of one readiness area, from real `flutter doctor` checks.
enum Health { ok, warning, failed, checking, unknown }

/// The readiness areas the Overview cards and the status bar show.
enum ReadinessArea {
  flutter,
  swift,
  llvm,
  darwinSdk,

  /// The iOS release compiler (`gen_snapshot`) for the active Flutter
  /// (feature 014).
  iosCompiler,
  auth,
  device,

  /// Push notifications of the open project (feature 016); only shown when
  /// the doctor reports push checks.
  push,
}

/// One area's health and the message of its worst check.
class AreaHealth {
  const AreaHealth(this.health, {this.message, this.checks = const []});

  final Health health;
  final String? message;
  final List<DoctorCheckResult> checks;
}

/// Runs `xcross flutter doctor` (with `XCROSS_EVENTS=ndjson`) and
/// `xcross --version`, and groups the `check` events into areas (feature
/// 013). It never invents a check: an area without checks is `unknown`.
class ReadinessController extends ChangeNotifier {
  ReadinessController(this.jobs, this.settings);

  final JobCenter jobs;
  final Settings settings;

  Job? doctor;
  Job? _versionJob;

  /// First line of `xcross --version`, once known.
  String? cliVersion;

  bool get checking => doctor?.isRunning ?? false;

  /// The checks of the latest doctor run.
  List<DoctorCheckResult> get checks => doctor?.checks ?? const [];

  /// Runs the doctor (in the project folder when one is open).
  Job runDoctor() {
    final job = jobs.run(
      'Doctor',
      XcrossCommands.doctor(),
      workingDirectory: settings.projectPath,
      structured: true,
    );
    doctor?.removeListener(notifyListeners);
    doctor = job..addListener(notifyListeners);
    notifyListeners();
    return job;
  }

  /// Reads `xcross --version` once per call.
  Future<void> readVersion() async {
    if (_versionJob?.isRunning ?? false) return;
    final job = jobs.run('Version', XcrossCommands.version());
    _versionJob = job;
    await job.done;
    final line = job.lines
        .skip(1)
        .map((l) => l.text.trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    cliVersion = job.status == JobStatus.succeeded && line.isNotEmpty
        ? line
        : null;
    notifyListeners();
  }

  /// The area a check belongs to, from its name; `null` for checks that
  /// are not about host readiness (the project itself, the host OS).
  static ReadinessArea? areaOf(DoctorCheckResult check) {
    final name = check.name.toLowerCase();
    if (check.section == 'Push notifications' ||
        name.startsWith('push ') ||
        name == 'firebase config') {
      return ReadinessArea.push;
    }
    if (name.contains('darwin sdk')) return ReadinessArea.darwinSdk;
    // "AOT compiler (release)": only the release compiler decides readiness.
    if (name.contains('aot compiler')) {
      return name.contains('release') ? ReadinessArea.iosCompiler : null;
    }
    if (name.contains('flutter sdk') || name == 'flutter') {
      return ReadinessArea.flutter;
    }
    if (name.contains('swift') || name.contains('sdkroot')) {
      return ReadinessArea.swift;
    }
    if (name.contains('clang') ||
        name.contains('llvm') ||
        name.contains('linker') ||
        name.contains('lld')) {
      return ReadinessArea.llvm;
    }
    if (name.contains('auth') || name.contains('credential')) {
      return ReadinessArea.auth;
    }
    if (name.contains('device')) return ReadinessArea.device;
    return null;
  }

  /// Health of [area] from the latest checks.
  AreaHealth area(ReadinessArea area) {
    final matching = [
      for (final check in checks)
        if (areaOf(check) == area) check,
    ];
    if (matching.isEmpty) {
      return AreaHealth(checking ? Health.checking : Health.unknown);
    }
    DoctorCheckResult? worst(String status) =>
        matching.where((c) => c.status == status).firstOrNull;
    final failure = worst('failure');
    if (failure != null) {
      return AreaHealth(
        Health.failed,
        message: '${failure.name}: ${failure.message}',
        checks: matching,
      );
    }
    final warning = worst('warning');
    if (warning != null) {
      return AreaHealth(
        Health.warning,
        message: '${warning.name}: ${warning.message}',
        checks: matching,
      );
    }
    return AreaHealth(
      Health.ok,
      message: matching.first.message,
      checks: matching,
    );
  }

  /// Toolchain summary (Flutter, Swift, LLVM, Darwin SDK, iOS compiler) for
  /// the status bar.
  AreaHealth get toolchain => _combine([
    ReadinessArea.flutter,
    ReadinessArea.swift,
    ReadinessArea.llvm,
    ReadinessArea.darwinSdk,
    ReadinessArea.iosCompiler,
  ]);

  AreaHealth get signing => area(ReadinessArea.auth);
  AreaHealth get device => area(ReadinessArea.device);

  /// Whether a doctor run finished with at least one failing area.
  bool get needsSetup =>
      !checking &&
      ReadinessArea.values.any(
        // Push is about the project, not the computer.
        (a) => a != ReadinessArea.push && area(a).health == Health.failed,
      );

  AreaHealth _combine(List<ReadinessArea> areas) {
    final all = [for (final a in areas) area(a)];
    for (final health in [Health.failed, Health.warning]) {
      final hit = all.where((a) => a.health == health).firstOrNull;
      if (hit != null) return hit;
    }
    if (all.any((a) => a.health == Health.checking)) {
      return const AreaHealth(Health.checking);
    }
    if (all.every((a) => a.health == Health.ok)) {
      return const AreaHealth(Health.ok);
    }
    return const AreaHealth(Health.unknown);
  }

  @override
  void dispose() {
    doctor?.removeListener(notifyListeners);
    super.dispose();
  }
}
