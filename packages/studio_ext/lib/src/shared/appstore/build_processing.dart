// studio: 019 — what App Store Connect does with an upload
// (specs/019-upload-processing, AC-019-2, AC-019-5).
import 'dart:async';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/appstore/build_upload.dart';

/// One of Apple's validation messages on an upload.
@internal
@immutable
final class UploadIssue {
  const UploadIssue(this.severity, this.code, this.description);

  /// `error`, `warning` or `info`.
  final String severity;
  final String code;
  final String description;

  Map<String, Object?> toJson() => {
    'severity': severity,
    'code': code,
    'description': description,
  };
}

/// The end state of an upload.
@internal
@immutable
final class UploadOutcome {
  const UploadOutcome(this.state, this.issues);

  /// `COMPLETE`, `FAILED`, or the last state seen before a timeout.
  final String state;
  final List<UploadIssue> issues;
}

/// The wait ran out.
@internal
final class ProcessingTimeout implements Exception {
  const ProcessingTimeout(this.lastState);

  final String? lastState;
}

/// Polls build uploads and builds.
@internal
final class BuildProcessing {
  BuildProcessing(
    this.api, {
    this.interval = const Duration(seconds: 20),
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? sleep,
  }) : _clock = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  final AscApi api;
  final Duration interval;
  final DateTime Function() _clock;
  final Future<void> Function(Duration delay) _sleep;

  /// The build of [appId] with build number [build] for [version], if App
  /// Store Connect has one.
  Future<AscResource?> findBuild({
    required String appId,
    required String version,
    required String build,
  }) async {
    final builds = AscApi.dataList(
      await api.get(
        '/v1/builds',
        query: {
          'filter[app]': appId,
          'filter[version]': build,
          'filter[preReleaseVersion.version]': version,
          'limit': '5',
        },
      ),
    );
    return builds.firstOrNull;
  }

  /// Polls the build upload [uploadId] until `COMPLETE` or `FAILED`.
  Future<UploadOutcome> waitForUpload(
    String uploadId, {
    required Duration timeout,
    void Function(String state)? onState,
  }) async {
    final deadline = _clock().add(timeout);
    String? last;
    while (true) {
      final upload = AscApi.data(await api.get('/v1/buildUploads/$uploadId'));
      final state = BuildUploader.uploadState(upload) ?? 'UNKNOWN';
      if (state != last) {
        last = state;
        onState?.call(state);
      }
      if (state == 'COMPLETE' || state == 'FAILED') {
        return UploadOutcome(state, issuesOf(upload));
      }
      if (!_clock().isBefore(deadline)) throw ProcessingTimeout(last);
      await _sleep(interval);
    }
  }

  /// Polls the build's `processingState` until it is not `PROCESSING`.
  Future<({String id, String state})> waitForProcessing({
    required String appId,
    required String version,
    required String build,
    required Duration timeout,
    void Function(String state)? onState,
  }) async {
    final deadline = _clock().add(timeout);
    String? last;
    while (true) {
      final found = await findBuild(
        appId: appId,
        version: version,
        build: build,
      );
      final state = found?.string('processingState') ?? 'NOT_FOUND_YET';
      if (state != last) {
        last = state;
        onState?.call(state);
      }
      if (found != null && state != 'PROCESSING') {
        return (id: found.id, state: state);
      }
      if (!_clock().isBefore(deadline)) throw ProcessingTimeout(last);
      await _sleep(interval);
    }
  }

  /// Apple's errors, warnings and infos on a build upload.
  @visibleForTesting
  static List<UploadIssue> issuesOf(AscResource upload) {
    final Object? state = upload.attributes['state'];
    if (state is! Map<Object?, Object?>) return const [];
    return [
      for (final (key, severity) in const [
        ('errors', 'error'),
        ('warnings', 'warning'),
        ('infos', 'info'),
      ])
        if (state[key] case final List<Object?> details)
          for (final detail in details)
            if (detail is Map)
              UploadIssue(
                severity,
                '${detail['code'] ?? ''}',
                '${detail['description'] ?? ''}',
              ),
    ];
  }
}
