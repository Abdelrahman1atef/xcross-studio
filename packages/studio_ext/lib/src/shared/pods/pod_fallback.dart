import 'dart:io';

import 'package:meta/meta.dart';
import 'package:studio_ext/shared/pods/pod_report.dart';

/// Details about a failure that occurred while compiling or linking a converted pod.
@internal
@immutable
final class PodCompileFailure {
  const PodCompileFailure({
    required this.pod,
    required this.firstErrorLine,
    required this.isDuplicateSymbols,
    this.collidingPods = const [],
    this.symbolName,
    this.plugin,
    this.rawOutput,
  });

  final String pod;
  final String firstErrorLine;
  final bool isDuplicateSymbols;
  final List<String> collidingPods;
  final String? symbolName;
  final String? plugin;
  final String? rawOutput;
}

/// Thrown when strict mode or distribution mode prohibits automatic fallback.
@internal
final class PodStrictBuildException implements Exception {
  PodStrictBuildException({
    required this.pod,
    required this.firstErrorLine,
    required this.code,
  });

  final String pod;
  final String firstErrorLine;
  final String code;

  @override
  String toString() =>
      '[$code] Pod "$pod" failed to compile: $firstErrorLine\n'
      'hint: Automatic fallback is disabled in strict mode or distribution builds.';
}

/// Handles automatic fallback for converted pods that fail compilation or linking (§3.5).
@internal
final class PodFallbackHandler {
  const PodFallbackHandler({this.podsReportFile = const PodsReportFile()});

  final PodsReportFile podsReportFile;

  static final RegExp _podInPathPattern = RegExp(
    r'(?:Packages[/\\]pod-|[/\\]pod-)([A-Za-z0-9_.+-]+)[/\\]',
  );

  static final RegExp _duplicateSymbolsPattern = RegExp(
    'duplicate symbol|duplicate symbols',
    caseSensitive: false,
  );

  static final RegExp _symbolPattern = RegExp(
    r"""(?:duplicate symbol(?::|\s+in:?)|\bduplicate symbol:?)\s*['"]?([A-Za-z0-9_\$.]+)['"]?""",
    caseSensitive: false,
  );

  /// Inspects compiler/linker output to determine if a converted pod failed.
  PodCompileFailure? detectPodFailure(String errorOutput, {String? plugin}) {
    final lines = errorOutput.split('\n');
    String? firstErrorLine;
    var duplicate = false;
    final collidingPods = <String>[];

    for (final match in _podInPathPattern.allMatches(errorOutput)) {
      final name = match.group(1);
      if (name != null && !collidingPods.contains(name)) {
        collidingPods.add(name);
      }
    }

    String? symbolName;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (_duplicateSymbolsPattern.hasMatch(trimmed)) {
        duplicate = true;
        final symMatch = _symbolPattern.firstMatch(trimmed);
        if (symMatch != null && symbolName == null) {
          symbolName = symMatch.group(1);
        }
      }

      if (firstErrorLine == null) {
        if (trimmed.startsWith('error:') ||
            trimmed.contains(' error: ') ||
            trimmed.contains('duplicate symbol') ||
            trimmed.startsWith('fatal error:') ||
            trimmed.startsWith('ld64.lld:') ||
            trimmed.startsWith('ld:')) {
          firstErrorLine = trimmed;
        }
      }
    }

    if (collidingPods.isEmpty && !duplicate) {
      return null;
    }

    // Default to first meaningful line if no line explicitly matched "error:"
    firstErrorLine ??= lines
        .firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => 'unknown build error',
        )
        .trim();

    return PodCompileFailure(
      pod: collidingPods.isNotEmpty ? collidingPods.first : 'unknown',
      firstErrorLine: _shortenPaths(firstErrorLine),
      isDuplicateSymbols: duplicate,
      collidingPods: collidingPods,
      symbolName: symbolName,
      plugin: plugin,
      rawOutput: errorOutput,
    );
  }

  /// Executes fallback logic according to §3.5:
  ///
  /// - If [strict] or [distribution] is true: throws [PodStrictBuildException].
  /// - Otherwise: records the pod failure into [reportFile], logs the four-part warning,
  ///   and returns the name of the failing pod to be excluded from the subsequent rebuild.
  String handleFallback({
    required PodCompileFailure failure,
    required File reportFile,
    required String plugin,
    bool strict = false,
    bool distribution = false,
    void Function(String)? logWarning,
  }) {
    final code = failure.isDuplicateSymbols
        ? 'pod.duplicate_symbols'
        : 'pod.compile_failed';
    final reason = failure.isDuplicateSymbols
        ? 'duplicate_symbols'
        : 'compile_failed';

    if (strict || distribution) {
      throw PodStrictBuildException(
        pod: failure.pod,
        firstErrorLine: failure.firstErrorLine,
        code: code,
      );
    }

    final detail =
        failure.isDuplicateSymbols && failure.collidingPods.length > 1
        ? (failure.symbolName != null
              ? 'duplicate symbol "${failure.symbolName}" between ${failure.collidingPods.join(' and ')}'
              : 'duplicate symbols between ${failure.collidingPods.join(' and ')}')
        : failure.firstErrorLine;

    final report = PodReport(
      code: code,
      reason: reason,
      plugin: plugin,
      pod: failure.pod,
      detail: detail,
      requiredBy: [
        plugin,
        if (failure.collidingPods.length > 1)
          for (final p in failure.collidingPods)
            if (p != failure.pod) p,
      ],
    );

    // Save report to pods-report.json
    final existing = podsReportFile.load(reportFile);
    final updated = [
      for (final r in existing)
        if (r.pod != failure.pod) r,
      report,
    ];
    podsReportFile.save(reportFile, updated);

    // Log the 4-part warning
    logWarning?.call(report.formatWarning());

    return failure.pod;
  }

  static String _shortenPaths(String line) {
    return line.replaceAllMapped(
      RegExp(r'[A-Za-z]:\\[^\s:]+[/\\]Packages[/\\]pod-'),
      (_) => '<Packages>/pod-',
    );
  }
}
