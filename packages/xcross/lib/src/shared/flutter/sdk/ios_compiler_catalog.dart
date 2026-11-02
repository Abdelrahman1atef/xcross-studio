// studio: 014 — which Flutter versions have a published iOS AOT compiler for
// this host, and which one to use when the active Flutter has none.
import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/update/semver.dart';

/// The Flutter versions with a published iOS release compiler for a host.
@internal
final class CompilerCatalog {
  const CompilerCatalog({
    required this.versions,
    required this.fetchedAt,
    this.stale = false,
  });

  /// Stable Flutter versions, newest first.
  final List<String> versions;
  final DateTime fetchedAt;

  /// True when the list came from an old cache because the network failed.
  final bool stale;
}

/// A Flutter version to use instead of the active one.
@internal
final class FlutterSdkSuggestion {
  const FlutterSdkSuggestion(this.version, {required this.sameLine});

  final String version;

  /// True when [version] shares major.minor with the active Flutter.
  final bool sameLine;
}

/// The newest version in [available] for builds with Flutter [current]:
/// the newest of the same major.minor line, else the newest overall.
/// `null` when [current] itself is available or nothing is.
@internal
FlutterSdkSuggestion? suggestFlutterSdk(
  String current,
  List<String> available,
) {
  if (available.contains(current)) return null;
  final parsed = [
    for (final version in available)
      if (XcrossSemver.tryParse(version) case final semver?
          when !semver.isPreRelease)
        (version, semver),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  if (parsed.isEmpty) return null;
  final active = XcrossSemver.tryParse(current);
  if (active != null) {
    for (final (version, semver) in parsed) {
      if (semver.major == active.major && semver.minor == active.minor) {
        return FlutterSdkSuggestion(version, sameLine: true);
      }
    }
  }
  return FlutterSdkSuggestion(parsed.first.$1, sameLine: false);
}

/// Reads the xcross_gen_snapshot release list from GitHub and caches it under
/// `<cacheRoot>/gen-snapshot/catalog.json`, so a later offline run still
/// knows the answer.
@internal
final class IosCompilerCatalog {
  IosCompilerCatalog({
    required this.fileSystem,
    required this.paths,
    required this.cacheRoot,
    required this.platform,
    required this.createHttpClient,
    this.apiUrl = defaultApiUrl,
    this.maxAge = const Duration(hours: 6),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const defaultApiUrl =
      'https://api.github.com/repos/arxdeus/xcross_gen_snapshot/releases';

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String cacheRoot;

  /// xcross_gen_snapshot host platform, such as `windows-x64`.
  final String platform;
  final http.Client Function() createHttpClient;
  final String apiUrl;
  final Duration maxAge;
  final DateTime Function() _now;

  String get cachePath => paths.join(cacheRoot, 'gen-snapshot', 'catalog.json');

  /// Asset that marks a release as usable for release builds on [platform].
  String get releaseAsset => 'gen_snapshot-release-$platform.zip';

  /// The catalog: from the cache when younger than [maxAge] (unless
  /// [refresh]), else from GitHub, else from a stale cache.
  Future<CompilerCatalog> load({bool refresh = false}) async {
    final cached = _readCache();
    if (!refresh &&
        cached != null &&
        _now().difference(cached.fetchedAt) < maxAge) {
      return _forPlatform(cached);
    }
    try {
      final fresh = await _fetch();
      _writeCache(fresh);
      return _forPlatform(fresh);
    } on Object {
      if (cached != null) return _forPlatform(cached, stale: true);
      rethrow;
    }
  }

  CompilerCatalog _forPlatform(
    CompilerReleases releases, {
    bool stale = false,
  }) {
    final versions = [
      for (final MapEntry(key: version, value: assets)
          in releases.assets.entries)
        if (assets.contains(releaseAsset))
          if (XcrossSemver.tryParse(version) case final semver?
              when !semver.isPreRelease)
            (version, semver),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return CompilerCatalog(
      versions: [for (final (version, _) in versions) version],
      fetchedAt: releases.fetchedAt,
      stale: stale,
    );
  }

  Future<CompilerReleases> _fetch() async {
    final assets = <String, List<String>>{};
    for (var page = 1; page <= 5; page++) {
      final client = createHttpClient();
      try {
        final response = await client
            .get(
              Uri.parse('$apiUrl?per_page=100&page=$page'),
              headers: const {
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'xcross',
              },
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'HTTP ${response.statusCode} listing $apiUrl',
            uri: Uri.parse(apiUrl),
          );
        }
        final Object? decoded = jsonDecode(response.body);
        if (decoded is! List<Object?>) {
          throw const FormatException('The release list is not a JSON list');
        }
        for (final release in decoded) {
          if (release case {
            'tag_name': final String tag,
            'assets': final List<Object?> files,
          }) {
            assets[tag] = [
              for (final file in files)
                if (file case {'name': final String name}) name,
            ];
          }
        }
        if (decoded.length < 100) break;
      } finally {
        client.close();
      }
    }
    return CompilerReleases(assets, _now().toUtc());
  }

  CompilerReleases? _readCache() {
    final file = fileSystem.file(cachePath);
    if (!file.existsSync()) return null;
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded case {
        'fetched_at': final String fetched,
        'releases': final Map<String, Object?> releases,
      }) {
        final fetchedAt = DateTime.tryParse(fetched);
        if (fetchedAt == null) return null;
        return CompilerReleases({
          for (final MapEntry(:key, :value) in releases.entries)
            if (value is List<Object?>) key: [for (final v in value) '$v'],
        }, fetchedAt);
      }
    } on Object {
      // A broken cache is refetched.
    }
    return null;
  }

  void _writeCache(CompilerReleases releases) {
    try {
      final file = fileSystem.file(cachePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'fetched_at': releases.fetchedAt.toIso8601String(),
          'releases': releases.assets,
        }),
      );
    } on FileSystemException {
      // The list is still returned; only the offline fallback is lost.
    }
  }
}

/// Release tags and their asset names, as listed or cached.
@internal
final class CompilerReleases {
  const CompilerReleases(this.assets, this.fetchedAt);

  final Map<String, List<String>> assets;
  final DateTime fetchedAt;
}
