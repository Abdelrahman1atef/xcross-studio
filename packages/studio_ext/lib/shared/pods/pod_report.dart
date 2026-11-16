import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// A report entry for a pod that was left out or encountered conversion issues.
@immutable
final class PodReport {
  const PodReport({
    required this.code,
    required this.reason,
    required this.plugin,
    required this.pod,
    this.pluginVersion,
    this.podVersion,
    this.kind,
    this.source,
    this.requiredBy = const [],
    this.detail,
    this.engine,
    this.flutter,
    this.swift,
    this.host,
    this.buildTarget,
    this.mode,
  });

  factory PodReport.fromJson(Map<String, Object?> json) {
    return PodReport(
      code: json['code']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      plugin: json['plugin']?.toString() ?? '',
      pod: json['pod']?.toString() ?? '',
      pluginVersion: json['pluginVersion']?.toString(),
      podVersion: json['podVersion']?.toString(),
      kind: json['kind']?.toString(),
      source: json['source']?.toString(),
      requiredBy: switch (json['requiredBy']) {
        final List<Object?> list => list.map((e) => e.toString()).toList(),
        _ => const [],
      },
      detail: json['detail']?.toString(),
      engine: json['engine']?.toString(),
      flutter: json['flutter']?.toString(),
      swift: json['swift']?.toString(),
      host: json['host']?.toString(),
      buildTarget: json['buildTarget']?.toString(),
      mode: json['mode']?.toString(),
    );
  }

  final String code;
  final String reason;
  final String plugin;
  final String pod;
  final String? pluginVersion;
  final String? podVersion;
  final String? kind;
  final String? source;
  final List<String> requiredBy;
  final String? detail;
  final String? engine;
  final String? flutter;
  final String? swift;
  final String? host;
  final String? buildTarget;
  final String? mode;

  Map<String, Object?> toJson() => {
    'code': code,
    'reason': reason,
    'plugin': plugin,
    if (pluginVersion != null) 'pluginVersion': pluginVersion,
    'pod': pod,
    if (podVersion != null) 'podVersion': podVersion,
    if (kind != null) 'kind': kind,
    if (source != null) 'source': source,
    'requiredBy': requiredBy,
    if (detail != null) 'detail': detail,
    if (engine != null) 'engine': engine,
    if (flutter != null) 'flutter': flutter,
    if (swift != null) 'swift': swift,
    if (host != null) 'host': host,
    if (buildTarget != null) 'buildTarget': buildTarget,
    if (mode != null) 'mode': mode,
  };

  /// Applies redactions to remove tokens, user home paths, and project paths.
  PodReport redact({String? homeDir, String? projectDir}) {
    String sanitize(String input) {
      var result = input;
      if (projectDir != null && projectDir.isNotEmpty) {
        result = result.replaceAll(projectDir, '<project>');
        result = result.replaceAll(
          projectDir.replaceAll(r'\', '/'),
          '<project>',
        );
      }
      if (homeDir != null && homeDir.isNotEmpty) {
        result = result.replaceAll(homeDir, '~');
        result = result.replaceAll(homeDir.replaceAll(r'\', '/'), '~');
      }
      // Redact potential bearer tokens, secret keys, or long auth hex/base64 strings
      result = result.replaceAllMapped(
        RegExp(r'(Bearer\s+|token=)[A-Za-z0-9_.-]+', caseSensitive: false),
        (match) => '${match.group(1)}[REDACTED]',
      );
      result = result.replaceAll(
        RegExp('ghp_[A-Za-z0-9]{20,}', caseSensitive: false),
        '[REDACTED]',
      );
      return result;
    }

    String? sanitizedDetail = detail;
    if (sanitizedDetail != null) {
      sanitizedDetail = sanitize(sanitizedDetail);
      // Cap compiler / error lines to 20
      final lines = sanitizedDetail.split('\n');
      if (lines.length > 20) {
        sanitizedDetail = '${lines.take(20).join('\n')}\n... (truncated)';
      }
    }

    return PodReport(
      code: code,
      reason: reason,
      plugin: plugin,
      pod: pod,
      pluginVersion: pluginVersion,
      podVersion: podVersion,
      kind: kind,
      source: source,
      requiredBy: requiredBy.map(sanitize).toList(),
      detail: sanitizedDetail,
      engine: engine,
      flutter: flutter,
      swift: swift,
      host: host,
      buildTarget: buildTarget,
      mode: mode,
    );
  }

  /// Formats the four-part user warning described in §12.1.
  String formatWarning() {
    final podLabel = podVersion != null ? '$pod $podVersion' : pod;
    final (whyText, youCanText) = _reasonExplanation(podLabel);

    final buffer = StringBuffer();
    buffer.writeln(
      '⚠ Plugin "$plugin" is left out of this build: its features will not work in the app.',
    );
    buffer.writeln('  Why: $whyText');
    buffer.writeln('  You can: $youCanText');
    buffer.write(
      '  Report: send this to the xcross developers so they can fix it: xcross pods report $pod',
    );
    return buffer.toString();
  }

  (String why, String youCan) _reasonExplanation(String podLabel) {
    return switch (reason) {
      'no_slice' => (
        'pod "$podLabel" has no slice for the ${buildTarget ?? 'iOS build'}${detail != null ? ' ($detail)' : ''}.',
        'build for a real iPhone instead (device builds include it).',
      ),
      'resolve_conflict' => (
        'no version of pod "$pod" fits the requirements of ${requiredBy.isEmpty ? 'the plugins' : requiredBy.join(', ')}.',
        'run "pod update" or adjust plugin versions to align requirements.',
      ),
      'lock_stale' => (
        'Podfile.lock pin for "$pod" is stale and no longer satisfies constraints.',
        'run "pod install" on macOS or remove Podfile.lock to resolve afresh.',
      ),
      'download_failed' => (
        'failed to download source for pod "$podLabel"${detail != null ? ': $detail' : ''}.',
        'check your network connection, proxy settings, or install Git if missing.',
      ),
      'bitcode' => (
        'dynamic framework for pod "$podLabel" contains Bitcode, which Apple deprecated.',
        'use a newer release of the pod that ships without Bitcode.',
      ),
      'swift_binary_incompatible' => (
        'pod "$podLabel" was built without Swift library evolution (.swiftinterface missing).',
        'ask the pod author for a build with BUILD_LIBRARY_FOR_DISTRIBUTION=YES.',
      ),
      'duplicate_with_swift_package' => (
        'pod "$pod" conflicts with a Swift package dependency of the same name.',
        'update the plugin to use the Swift package directly.',
      ),
      'converter_off' => (
        'pod "$pod" requires the pod converter, but XCROSS_POD_CONVERTER is off.',
        'enable the converter by setting XCROSS_POD_CONVERTER=on.',
      ),
      'compile_failed' => (
        'SwiftPM failed compiling pod "$podLabel"${detail != null ? ': $detail' : ''}.',
        'check the compiler output or report this conversion issue.',
      ),
      'duplicate_symbols' => (
        'linker found duplicate symbols in pod "$podLabel"${detail != null ? ': $detail' : ''}.',
        'exclude conflicting dependencies or report this to developers.',
      ),
      _ => (
        'pod "$podLabel" cannot be converted${detail != null ? ': $detail' : ''}.',
        'nothing to do on your side; this pod is not supported yet.',
      ),
    };
  }
}

/// Reads and writes `build/xcross-ios/pods-report.json`.
final class PodsReportFile {
  const PodsReportFile();

  static const defaultRelativePath = 'build/xcross-ios/pods-report.json';

  List<PodReport> load(File file) {
    if (!file.existsSync()) return const [];
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is List) {
        return [
          for (final item in json)
            if (item is Map<String, Object?>) PodReport.fromJson(item),
        ];
      }
      if (json is Map<String, Object?> && json['reports'] is List) {
        return [
          for (final item in json['reports']! as List)
            if (item is Map<String, Object?>) PodReport.fromJson(item),
        ];
      }
    } on Object {
      // Ignore missing or unreadable report file
    }
    return const [];
  }

  void save(File file, List<PodReport> reports) {
    file.parent.createSync(recursive: true);
    final data = {
      'version': 1,
      'reports': reports.map((r) => r.toJson()).toList(),
    };
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }
}
