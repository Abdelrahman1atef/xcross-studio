import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/pods/pod_archive.dart';
import 'package:studio_ext/src/shared/pods/pod_file_selector.dart';

@internal
final class PodDownloadFailed implements Exception {
  const PodDownloadFailed(this.reason);
  final String reason;
  @override
  String toString() => 'pod.download_failed: $reason';
}

@internal
final class PodHttpSource {
  const PodHttpSource({
    required this.url,
    this.type,
    this.flatten = false,
    this.sha1Value,
    this.sha256Value,
  });
  final Uri url;
  final String? type;
  final bool flatten;
  final String? sha1Value;
  final String? sha256Value;
}

@internal
final class PodGitSource {
  const PodGitSource({
    required this.url,
    this.tag,
    this.commit,
    this.branch,
    this.submodules = false,
  });
  final Uri url;
  final String? tag;
  final String? commit;
  final String? branch;
  final bool submodules;
}

@internal
final class PodGitResult {
  const PodGitResult(this.exitCode, this.stderr, [this.stdout = '']);
  final int exitCode;
  final String stderr;
  final String stdout;
}

@internal
typedef PodGitRunner =
    Future<PodGitResult> Function(
      List<String> arguments,
      String workingDirectory,
    );

/// Downloads a source archive with bounded retries and digest verification.
@internal
final class PodSourceDownloader {
  const PodSourceDownloader({
    required this.client,
    required this.archive,
    this.gitRunner,
    this.directoryFactory,
    this.fileFactory,
    this.githubToken,
    this.bigRepoLimitKb = 200 * 1024,
    this.retries = 3,
    this.stallTimeout = const Duration(seconds: 120),
    this.events,
  });
  final http.Client client;
  final PodArchive archive;
  final PodGitRunner? gitRunner;
  final Directory Function(String)? directoryFactory;
  final File Function(String)? fileFactory;
  final String? githubToken;
  final int bigRepoLimitKb;
  final int retries;
  final Duration stallTimeout;
  final LogEvents? events;

  Future<void> fetchHttp(
    PodHttpSource source,
    Directory destination, {
    void Function(int done, int? total)? onProgress,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < retries; attempt++) {
      final temporary = archive.fileFactory(
        '${destination.path}.download-${DateTime.now().microsecondsSinceEpoch}-$attempt',
      );
      try {
        final request = http.Request('GET', source.url)
          ..headers['User-Agent'] = 'xcross';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw PodDownloadFailed(
            'HTTP ${response.statusCode} from ${source.url.host}',
          );
        }
        await temporary.parent.create(recursive: true);
        final sink = temporary.openWrite();
        var done = 0;
        events?.event('step', {
          'name': 'pod_download',
          'status': 'start',
          'pod': destination.uri.pathSegments
              .where((part) => part.isNotEmpty)
              .last,
          'bytesDone': 0,
          'bytesTotal': response.contentLength,
        });
        try {
          await for (final chunk in response.stream.timeout(stallTimeout)) {
            sink.add(chunk);
            done += chunk.length;
            onProgress?.call(done, response.contentLength);
            events?.event('step', {
              'name': 'pod_download',
              'status': 'progress',
              'bytesDone': done,
              'bytesTotal': response.contentLength,
            });
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        final bytes = await temporary.readAsBytes();
        if (source.sha256Value != null &&
            sha256.convert(bytes).toString().toLowerCase() !=
                source.sha256Value!.toLowerCase()) {
          throw const PodDownloadFailed('checksum mismatch (sha256)');
        }
        if (source.sha1Value != null &&
            sha1.convert(bytes).toString().toLowerCase() !=
                source.sha1Value!.toLowerCase()) {
          throw const PodDownloadFailed('checksum mismatch (sha1)');
        }
        final type = source.type ?? _type(source.url.path);
        await archive.extract(
          bytes,
          type,
          destination,
          flatten: source.flatten,
        );
        events?.event('step', {
          'name': 'pod_download',
          'status': 'done',
          'bytesDone': done,
          'bytesTotal': response.contentLength,
        });
        return;
      } on Object catch (error) {
        lastError = error;
        if (error is PodDownloadFailed &&
            error.reason.startsWith('checksum mismatch')) {
          break;
        }
        if (attempt + 1 < retries) {
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
        }
      } finally {
        if (temporary.existsSync()) await temporary.delete();
      }
    }
    events?.event('step', {'name': 'pod_download', 'status': 'failed'});
    if (lastError is PodDownloadFailed) throw lastError;
    throw PodDownloadFailed(
      'network or archive error (${lastError.runtimeType})',
    );
  }

  Future<String?> fetchGit(
    PodGitSource source,
    Directory destination, {
    List<String>? specGlobs,
    bool Function(Directory source)? sourceComplete,
  }) async {
    if (specGlobs != null && specGlobs.isNotEmpty) {
      final partialCommit = await fetchPartialGitHub(
        source: source,
        destination: destination,
        globs: specGlobs,
      );
      if (partialCommit != null) {
        return partialCommit;
      }
    }
    final archiveUrl = githubArchiveUrl(source);
    if (archiveUrl != null) {
      final createDirectory = directoryFactory;
      if (sourceComplete != null && createDirectory == null) {
        throw const PodDownloadFailed(
          'source validation needs a staging directory',
        );
      }
      final archiveDestination = createDirectory == null
          ? destination
          : createDirectory(
              '${destination.path}.tmp-archive-${DateTime.now().microsecondsSinceEpoch}',
            );
      try {
        await fetchHttp(
          PodHttpSource(url: archiveUrl, type: 'tgz', flatten: true),
          archiveDestination,
        );
        if (sourceComplete != null && !sourceComplete(archiveDestination)) {
          throw const PodDownloadFailed(
            'archive omitted required source files',
          );
        }
        if (archiveDestination.path != destination.path) {
          if (destination.existsSync()) {
            await archiveDestination.delete(recursive: true);
          } else {
            await archiveDestination.rename(destination.path);
          }
        }
        return source.commit;
      } on PodDownloadFailed {
        // Git is the fallback for export-ignore gaps and LFS pointers.
        if (archiveDestination.path != destination.path &&
            archiveDestination.existsSync()) {
          await archiveDestination.delete(recursive: true);
        }
      }
    }
    final runner = gitRunner;
    final createDirectory = directoryFactory;
    if (runner == null || createDirectory == null) {
      throw const PodDownloadFailed('install Git to download this pod');
    }
    final staging = createDirectory(
      '${destination.path}.tmp-git-${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create(recursive: true);
    try {
      var pinnedCommit = source.commit;
      if (source.branch != null) {
        final lookup = await _git(runner, [
          'ls-remote',
          source.url.toString(),
          'refs/heads/${source.branch}',
        ], staging.path);
        pinnedCommit = lookup.stdout.trim().split(RegExp(r'\s+')).first;
        if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(pinnedCommit)) {
          throw const PodDownloadFailed('could not resolve git branch');
        }
      }
      if (pinnedCommit != null) {
        await _git(runner, ['init'], staging.path);
        await _git(runner, [
          'remote',
          'add',
          'origin',
          source.url.toString(),
        ], staging.path);
        await _git(runner, [
          'fetch',
          '--depth',
          '1',
          'origin',
          pinnedCommit,
        ], staging.path);
        await _git(runner, ['checkout', 'FETCH_HEAD'], staging.path);
      } else {
        if (source.tag == null) {
          throw const PodDownloadFailed('git source has no ref');
        }
        await _git(runner, [
          'clone',
          '--depth',
          '1',
          '--branch',
          source.tag!,
          source.url.toString(),
          '.',
        ], staging.path);
        pinnedCommit = (await _git(runner, [
          'rev-parse',
          'HEAD',
        ], staging.path)).stdout.trim();
      }
      if (source.submodules) {
        await _git(runner, [
          'submodule',
          'update',
          '--init',
          '--recursive',
        ], staging.path);
      }
      if (destination.existsSync()) {
        await staging.delete(recursive: true);
      } else {
        await staging.rename(destination.path);
      }
      return pinnedCommit;
    } on Object {
      if (staging.existsSync()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<String?> fetchPartialGitHub({
    required PodGitSource source,
    required Directory destination,
    required List<String> globs,
  }) async {
    if (source.url.host.toLowerCase() != 'github.com' || source.submodules) {
      return null;
    }
    final parts = source.url.pathSegments
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 2) return null;
    final owner = parts[0];
    final repo = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    final ref = source.commit ?? source.tag ?? source.branch;
    if (ref == null) return null;

    final headers = <String, String>{
      'User-Agent': 'xcross',
      'Accept': 'application/vnd.github.v3+json',
      if (githubToken != null && githubToken!.isNotEmpty)
        'Authorization': 'Bearer $githubToken',
    };

    try {
      final repoUri = Uri.https('api.github.com', '/repos/$owner/$repo');
      final repoResponse = await client
          .get(repoUri, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (repoResponse.statusCode != 200) {
        return null;
      }
      final repoData = jsonDecode(repoResponse.body) as Map<String, dynamic>;
      final sizeKb = (repoData['size'] as num?)?.toInt() ?? 0;
      if (sizeKb <= bigRepoLimitKb) {
        return null;
      }

      final treeUri = Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/git/trees/$ref',
        {'recursive': '1'},
      );
      final treeResponse = await client
          .get(treeUri, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (treeResponse.statusCode != 200) {
        return null;
      }
      final treeData = jsonDecode(treeResponse.body) as Map<String, dynamic>;
      final treeList = treeData['tree'] as List<dynamic>?;
      if (treeList == null) return null;

      final regexes = [for (final g in globs) PodFileSelector.globToRegex(g)];
      final licenseRegex = RegExp(
        r'^license(\.[a-z0-9]+)?$',
        caseSensitive: false,
      );

      final matchingBlobs = <String>[];
      for (final entry in treeList) {
        if (entry is Map<String, dynamic> && entry['type'] == 'blob') {
          final path = entry['path'] as String? ?? '';
          if (regexes.any((r) => r.hasMatch(path)) ||
              licenseRegex.hasMatch(path)) {
            matchingBlobs.add(path);
          }
        }
      }

      if (matchingBlobs.isEmpty) return null;

      final makeFile = fileFactory ?? archive.fileFactory;
      final rawHeaders = <String, String>{
        'User-Agent': 'xcross',
        if (githubToken != null && githubToken!.isNotEmpty)
          'Authorization': 'Bearer $githubToken',
      };

      for (final relativePath in matchingBlobs) {
        final rawUri = Uri.https(
          'raw.githubusercontent.com',
          '/$owner/$repo/$ref/$relativePath',
        );
        final fileResponse = await client
            .get(rawUri, headers: rawHeaders)
            .timeout(const Duration(seconds: 30));
        if (fileResponse.statusCode != 200) {
          return null;
        }
        final targetPath = '${destination.path}/$relativePath';
        final file = makeFile(targetPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(fileResponse.bodyBytes);
      }

      final commitSha = (treeData['sha'] as String?) ?? ref;
      return commitSha;
    } on Object {
      return null;
    }
  }

  Uri? githubArchiveUrl(PodGitSource source) {
    if (source.url.host.toLowerCase() != 'github.com' || source.submodules) {
      return null;
    }
    final parts = source.url.pathSegments
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 2) return null;
    final ref = source.commit ?? source.tag;
    if (ref == null) return null;
    final repo = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    return Uri.https('codeload.github.com', '/${parts[0]}/$repo/tar.gz/$ref');
  }

  Future<PodGitResult> _git(
    PodGitRunner runner,
    List<String> args,
    String cwd,
  ) async {
    final result = await runner(args, cwd);
    if (result.exitCode != 0) {
      throw PodDownloadFailed(
        'git ${args.first} failed; check Git and source access',
      );
    }
    return result;
  }

  String _type(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.zip')) return 'zip';
    if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) return 'tgz';
    if (lower.endsWith('.tar.bz2') || lower.endsWith('.tbz')) return 'tbz';
    if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) return 'txz';
    if (lower.endsWith('.tar')) return 'tar';
    throw PodDownloadFailed('unsupported archive type: $path');
  }
}
