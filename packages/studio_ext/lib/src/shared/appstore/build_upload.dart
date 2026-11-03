// studio: 019 — App Store Connect Build Upload API: create, reserve, send the
// parts to their presigned URLs, commit (specs/019-upload-processing).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/appstore/command_exit.dart';

/// Called after each part is sent.
@internal
typedef UploadProgress =
    void Function(int part, int parts, int bytesSent, int totalBytes);

/// One presigned upload operation of a reserved file.
@internal
@immutable
final class UploadOperation {
  const UploadOperation({
    required this.method,
    required this.url,
    required this.offset,
    required this.length,
    required this.partNumber,
    required this.headers,
  });

  factory UploadOperation.fromJson(Map<String, dynamic> json, int index) {
    final Object? rawHeaders = json['requestHeaders'];
    return UploadOperation(
      method: '${json['method'] ?? 'PUT'}',
      url: '${json['url']}',
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      length: (json['length'] as num?)?.toInt() ?? 0,
      partNumber: (json['partNumber'] as num?)?.toInt() ?? index + 1,
      headers: {
        if (rawHeaders case final List<Object?> headers)
          for (final header in headers)
            if (header case {
              'name': final String name,
              'value': final String value,
            })
              name: value,
      },
    );
  }

  final String method;
  final String url;
  final int offset;
  final int length;
  final int partNumber;
  final Map<String, String> headers;
}

/// What an interrupted upload leaves behind so the next run can resume.
@internal
@immutable
final class UploadResumeState {
  const UploadResumeState({
    required this.uploadId,
    required this.fileId,
    required this.sha256,
    required this.done,
  });

  static UploadResumeState? read(File file) {
    if (!file.existsSync()) return null;
    try {
      final Object? json = jsonDecode(file.readAsStringSync());
      if (json case {
        'uploadId': final String uploadId,
        'fileId': final String fileId,
        'sha256': final String sha256,
        'done': final List<Object?> done,
      }) {
        return UploadResumeState(
          uploadId: uploadId,
          fileId: fileId,
          sha256: sha256,
          done: {
            for (final part in done)
              if (part is int) part,
          },
        );
      }
    } on Object {
      // A broken state file means a fresh upload.
    }
    return null;
  }

  final String uploadId;
  final String fileId;
  final String sha256;
  final Set<int> done;

  void write(File file) => file.writeAsStringSync(
    jsonEncode({
      'uploadId': uploadId,
      'fileId': fileId,
      'sha256': sha256,
      'done': done.toList()..sort(),
    }),
  );
}

/// Digests of the IPA.
@internal
@immutable
final class FileDigests {
  const FileDigests({
    required this.md5,
    required this.sha256,
    required this.size,
  });

  static Future<FileDigests> of(File file) async {
    final md5Sink = DigestCollector();
    final shaSink = DigestCollector();
    final md5Input = crypto.md5.startChunkedConversion(md5Sink);
    final shaInput = crypto.sha256.startChunkedConversion(shaSink);
    var size = 0;
    await for (final chunk in file.openRead()) {
      md5Input.add(chunk);
      shaInput.add(chunk);
      size += chunk.length;
    }
    md5Input.close();
    shaInput.close();
    return FileDigests(
      md5: md5Sink.value.toString(),
      sha256: shaSink.value.toString(),
      size: size,
    );
  }

  final String md5;
  final String sha256;
  final int size;
}

/// Collects one [Digest].
@internal
final class DigestCollector implements Sink<crypto.Digest> {
  late crypto.Digest value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}

/// Uploads one IPA through the Build Upload API.
@internal
final class BuildUploader {
  BuildUploader({
    required this.api,
    this.attempts = 3,
    Future<void> Function(Duration delay)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final AscApi api;

  /// Tries per part.
  final int attempts;
  final Future<void> Function(Duration delay) _sleep;

  /// Uploads [ipa] as [version] ([build]) of [appId] and returns the build
  /// upload's id. An interrupted run leaves [stateFile] for the next one.
  Future<String> upload({
    required String appId,
    required File ipa,
    required String version,
    required String build,
    required File stateFile,
    UploadProgress? onProgress,
    void Function(String message)? onNote,
  }) async {
    final digests = await FileDigests.of(ipa);
    var state = await _resumable(stateFile, digests, onNote);
    List<UploadOperation> operations;
    if (state == null) {
      final upload = AscApi.data(
        await api.post('/v1/buildUploads', {
          'data': {
            'type': 'buildUploads',
            'attributes': {
              'cfBundleShortVersionString': version,
              'cfBundleVersion': build,
              'platform': 'IOS',
            },
            'relationships': {
              'app': {
                'data': {'type': 'apps', 'id': appId},
              },
            },
          },
        }),
      );
      final file = AscApi.data(
        await api.post('/v1/buildUploadFiles', {
          'data': {
            'type': 'buildUploadFiles',
            'attributes': {
              'assetType': 'ASSET',
              'fileName': ipa.uri.pathSegments.last,
              'fileSize': digests.size,
              'uti': 'com.apple.ipa',
            },
            'relationships': {
              'buildUpload': {
                'data': {'type': 'buildUploads', 'id': upload.id},
              },
            },
          },
        }),
      );
      state = UploadResumeState(
        uploadId: upload.id,
        fileId: file.id,
        sha256: digests.sha256,
        done: const {},
      );
      operations = operationsOf(file);
    } else {
      operations = operationsOf(
        AscApi.data(await api.get('/v1/buildUploadFiles/${state.fileId}')),
      );
    }
    state.write(stateFile);

    final done = {...state.done};
    var sent = 0;
    for (final operation in operations) {
      if (done.contains(operation.partNumber)) {
        sent += operation.length;
        continue;
      }
      await _send(ipa, operation);
      done.add(operation.partNumber);
      sent += operation.length;
      UploadResumeState(
        uploadId: state.uploadId,
        fileId: state.fileId,
        sha256: state.sha256,
        done: done,
      ).write(stateFile);
      onProgress?.call(done.length, operations.length, sent, digests.size);
    }

    await api.patch('/v1/buildUploadFiles/${state.fileId}', {
      'data': {
        'type': 'buildUploadFiles',
        'id': state.fileId,
        'attributes': {
          'uploaded': true,
          'sourceFileChecksums': {
            'file': {'hash': digests.md5, 'algorithm': 'MD5'},
          },
        },
      },
    });
    if (stateFile.existsSync()) stateFile.deleteSync();
    return state.uploadId;
  }

  /// The upload operations of a reserved file, in part order.
  @visibleForTesting
  static List<UploadOperation> operationsOf(AscResource file) {
    final raw = file.attributes['uploadOperations'];
    if (raw is! List) return const [];
    return [
      for (final (index, entry) in raw.indexed)
        if (entry is Map)
          UploadOperation.fromJson(entry.cast<String, dynamic>(), index),
    ]..sort((a, b) => a.partNumber.compareTo(b.partNumber));
  }

  /// The saved state when it is for this IPA and Apple still waits for it.
  Future<UploadResumeState?> _resumable(
    File stateFile,
    FileDigests digests,
    void Function(String message)? onNote,
  ) async {
    final saved = UploadResumeState.read(stateFile);
    if (saved == null) return null;
    if (saved.sha256 != digests.sha256) {
      onNote?.call(
        'The IPA changed since the interrupted upload; starting over.',
      );
      return null;
    }
    try {
      final upload = AscApi.data(
        await api.get('/v1/buildUploads/${saved.uploadId}'),
      );
      if (uploadState(upload) != 'AWAITING_UPLOAD') return null;
    } on Object {
      return null;
    }
    onNote?.call(
      'Resuming the interrupted upload (${saved.done.length} parts already '
      'sent).',
    );
    return saved;
  }

  /// The `state.state` of a build upload resource.
  static String? uploadState(AscResource upload) =>
      switch (upload.attributes['state']) {
        {'state': final String state} => state,
        final String state => state,
        _ => null,
      };

  Future<void> _send(File ipa, UploadOperation operation) async {
    final bytes = await _read(ipa, operation.offset, operation.length);
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await _sleep(Duration(seconds: 2 << attempt));
      try {
        final request = http.Request(operation.method, Uri.parse(operation.url))
          ..headers.addAll(operation.headers)
          ..bodyBytes = bytes;
        final response = await http.Response.fromStream(
          await api.httpClient.send(request),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) return;
        lastError = 'HTTP ${response.statusCode}';
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw CommandExit(
      '[publish.upload_failed] Part ${operation.partNumber} could not be '
      'sent after $attempts tries ($lastError). Run the same command again to '
      'resume the upload.',
    );
  }

  static Future<Uint8List> _read(File file, int offset, int length) async {
    final handle = await file.open();
    try {
      await handle.setPosition(offset);
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }
}
