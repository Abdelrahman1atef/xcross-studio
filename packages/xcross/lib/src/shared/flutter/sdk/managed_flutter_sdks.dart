// studio: 014 — Flutter SDKs that xcross installs for iOS builds only, under
// `<config root>/xcross/flutter-sdks/<version>`. The user's own Flutter
// installation is never touched.
import 'dart:io';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/config/config.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';

/// Runs a tool and throws when it fails.
@internal
typedef SdkToolRunner =
    Future<void> Function(
      String executable,
      List<String> arguments, {
      required String label,
      String? workingDirectory,
    });

/// How far a managed SDK got.
@internal
enum ManagedSdkState {
  /// Not on disk (or a leftover without `bin/flutter`).
  missing,

  /// Cloned, but `flutter --version` has not downloaded its Dart SDK yet.
  cloned,

  /// Usable: the Dart SDK and `bin/cache/flutter.version.json` exist.
  ready,
}

/// One managed SDK on disk.
@internal
final class ManagedSdk {
  const ManagedSdk(this.version, this.path, this.state);

  final String version;
  final String path;
  final ManagedSdkState state;
}

/// Installs and selects managed Flutter SDKs.
@internal
final class ManagedFlutterSdks {
  ManagedFlutterSdks({
    required this.fileSystem,
    required this.paths,
    required this.root,
    required this.flutterExecutableName,
    required this.runTool,
    required this.log,
    this.repositoryUrl = defaultRepositoryUrl,
    this.cloneRetryDelays = defaultCloneRetryDelays,
    Future<void> Function(Duration delay)? sleep,
    int? processId,
  }) : _processId = processId ?? pid,
       _sleep = sleep ?? Future<void>.delayed;

  static const defaultRepositoryUrl = 'https://github.com/flutter/flutter.git';

  /// The wait before each extra clone attempt: a dropped connection often
  /// works again a moment later. Two entries: three attempts in all.
  static const defaultCloneRetryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
  ];

  /// A plain release version: no flags, paths or branch expressions.
  static final versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// `<config root>/xcross/flutter-sdks`.
  final String root;

  /// `flutter.bat` on Windows, `flutter` elsewhere.
  final String flutterExecutableName;
  final SdkToolRunner runTool;
  final Log log;
  final String repositoryUrl;
  final List<Duration> cloneRetryDelays;
  final Future<void> Function(Duration delay) _sleep;
  final int _processId;

  String directory(String version) => paths.join(root, version);

  /// The `flutter` launcher of the SDK at [sdkRoot].
  String flutterExecutable(String sdkRoot) =>
      paths.join(sdkRoot, 'bin', flutterExecutableName);

  /// True when [path] is a managed SDK directory.
  bool isManaged(String path) =>
      paths.isWithin(root, path) &&
      paths.dirname(path) == paths.normalize(root);

  ManagedSdkState stateOf(String sdkRoot) {
    bool exists(List<String> parts) =>
        fileSystem.file(paths.joinAll([sdkRoot, ...parts])).existsSync();
    if (!exists(['bin', 'flutter'])) return ManagedSdkState.missing;
    final dartSdk = fileSystem
        .directory(paths.join(sdkRoot, 'bin', 'cache', 'dart-sdk'))
        .existsSync();
    return dartSdk && exists(['bin', 'cache', 'flutter.version.json'])
        ? ManagedSdkState.ready
        : ManagedSdkState.cloned;
  }

  /// Managed SDKs on disk, newest version first.
  List<ManagedSdk> installed() {
    final dir = fileSystem.directory(root);
    if (!dir.existsSync()) return const [];
    final sdks = <ManagedSdk>[];
    for (final entity in dir.listSync(followLinks: false)) {
      final version = paths.basename(entity.path);
      if (!versionPattern.hasMatch(version)) continue;
      final state = stateOf(entity.path);
      if (state == ManagedSdkState.missing) continue;
      sdks.add(ManagedSdk(version, entity.path, state));
    }
    int part(String v, int i) => int.parse(v.split('.')[i]);
    sdks.sort((a, b) {
      for (var i = 0; i < 3; i++) {
        final c = part(b.version, i).compareTo(part(a.version, i));
        if (c != 0) return c;
      }
      return 0;
    });
    return sdks;
  }

  /// `git clone` arguments for [version] into [target]. Long paths are on
  /// (Windows' 260-character limit otherwise fails deep checkouts). A [retry]
  /// uses HTTP/1.1, which survives the HTTP/2 stream resets (`RPC failed;
  /// curl 92`) that end many large downloads on unstable connections.
  List<String> cloneArguments(
    String version,
    String target, {
    bool retry = false,
  }) => [
    '-c',
    'core.longpaths=true',
    if (retry) ...['-c', 'http.version=HTTP/1.1'],
    'clone',
    '--depth',
    '1',
    '--branch',
    version,
    repositoryUrl,
    target,
  ];

  /// Clones [version] into [partial], trying again after a failure that may
  /// pass (a dropped or blocked connection), up to [cloneRetryDelays] more
  /// times. Throws a coded error with git's own words when it gives up.
  Future<void> _clone(String version, String partial, String git) async {
    final attempts = cloneRetryDelays.length + 1;
    for (var attempt = 1; ; attempt++) {
      try {
        await runTool(
          git,
          cloneArguments(version, partial, retry: attempt > 1),
          label: 'git',
        );
        return;
      } on Object catch (error) {
        _removePartials(version);
        final output = '$error';
        final failure = cloneFailure(output, version);
        if (attempt >= attempts || !failure.retry) {
          throw codedError(
            XcrossCodes.toolchainFlutterSdkInstallFailed,
            'Could not download Flutter $version from GitHub (tried '
            '$attempt ${attempt == 1 ? 'time' : 'times'}). '
            '${failure.reason == null ? '' : '${failure.reason} '}'
            'Git said: ${toolSaid(output)}',
          );
        }
        log.logWarn(
          'The Flutter download stopped'
          '${failure.reason == null ? '' : ': ${failure.reason}'} '
          'Trying again (${attempt + 1} of $attempts)…',
        );
        await _sleep(cloneRetryDelays[attempt - 1]);
      }
    }
  }

  /// Plain words for why `git clone` failed, read from its [output], and
  /// whether another try may work. The reason is null when git said nothing
  /// known.
  @visibleForTesting
  static ({String? reason, bool retry}) cloneFailure(
    String output,
    String version,
  ) {
    final text = output.toLowerCase();
    bool has(List<String> words) => words.any(text.contains);
    if (has(['not found in upstream', 'remote branch'])) {
      return (reason: 'GitHub has no Flutter $version.', retry: false);
    }
    if (has(['no space left', 'not enough space', 'disk full'])) {
      return (reason: 'The disk is full.', retry: false);
    }
    if (has(['filename too long'])) {
      return (reason: 'A file path is too long for Windows.', retry: false);
    }
    if (has([
      'ssl certificate',
      'certificate verify',
      'unable to get local issuer',
      'schannel',
    ])) {
      return (
        reason:
            'The secure connection to github.com was blocked (often by '
            'antivirus web protection, a proxy or a firewall).',
        retry: false,
      );
    }
    if (has([
      'could not resolve host',
      'failed to connect',
      "couldn't connect",
      'connection refused',
      'timed out',
      'proxy',
    ])) {
      return (
        reason:
            'Could not reach github.com (no internet, or a VPN, proxy or '
            'firewall blocks it).',
        retry: true,
      );
    }
    if (has([
      'rpc failed',
      'early eof',
      'unexpected disconnect',
      'remote end hung up',
      'transfer closed',
      'connection was reset',
      'connection reset',
      'index-pack failed',
      'curl 18',
      'curl 56',
      'curl 92',
    ])) {
      return (
        reason: 'The connection to github.com dropped during the download.',
        retry: true,
      );
    }
    if (has(['permission denied', 'access is denied'])) {
      return (
        reason:
            'Windows did not allow writing the download folder (an antivirus '
            'may be holding it).',
        retry: true,
      );
    }
    return (reason: null, retry: true);
  }

  /// What a failed tool printed, in one line: its `fatal:` and `error:`
  /// lines (at most three), else its last line, else the failure itself
  /// (`command failed (128): …`).
  @visibleForTesting
  static String toolSaid(String failure) {
    final lines = [
      for (final line in failure.trim().split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) return failure.trim();
    final said = <String>[];
    for (final line in lines.skip(1)) {
      final lower = line.toLowerCase();
      if (!lower.contains('fatal') && !lower.contains('error')) continue;
      if (!said.contains(line)) said.add(line);
      if (said.length == 3) break;
    }
    if (said.isEmpty && lines.length > 1) said.add(lines.last);
    return said.isEmpty ? lines.first : said.join(' / ');
  }

  /// Installs Flutter [version] (safe to run again after a failure) and
  /// returns its root.
  ///
  /// The clone goes to a `.<version>.partial-<pid>` sibling first and is
  /// renamed when complete, so a `bin/flutter` in the final folder always
  /// means a finished clone. Leftover partial folders are removed first.
  Future<String> install(String version, {required String git}) async {
    if (!versionPattern.hasMatch(version)) {
      throw codedError(
        XcrossCodes.toolchainFlutterSdkVersionUnavailable,
        '"$version" is not a Flutter release version such as 3.47.6.',
      );
    }
    final target = directory(version);
    await fileSystem.directory(root).create(recursive: true);
    _removePartials(version);
    var state = stateOf(target);
    if (state == ManagedSdkState.missing) {
      final leftover = fileSystem.directory(target);
      if (leftover.existsSync()) await leftover.delete(recursive: true);
      final partial = paths.join(root, '.$version.partial-$_processId');
      await log.logStep(
        'Downloading Flutter $version (about 1 GB, once)',
        () => _clone(version, partial, git),
      );
      try {
        await fileSystem.directory(partial).rename(target);
      } on Object catch (error) {
        _removePartials(version);
        throw codedError(
          XcrossCodes.toolchainFlutterSdkInstallFailed,
          'Flutter $version was downloaded but could not be moved into '
          'place: ${_firstLine(error)}',
        );
      }
      state = stateOf(target);
    }
    if (state != ManagedSdkState.ready) {
      try {
        await log.logStep(
          'Preparing Flutter $version (downloads its Dart SDK)',
          () => runTool(
            flutterExecutable(target),
            const ['--version'],
            label: 'flutter',
            workingDirectory: target,
          ),
        );
      } on Object catch (error) {
        throw codedError(
          XcrossCodes.toolchainFlutterSdkInstallFailed,
          'Flutter $version was downloaded but could not prepare itself: '
          '${toolSaid('$error')}',
        );
      }
      if (stateOf(target) != ManagedSdkState.ready) {
        throw codedError(
          XcrossCodes.toolchainFlutterSdkInstallFailed,
          'Flutter $version did not create bin/cache/dart-sdk and '
          'bin/cache/flutter.version.json.',
        );
      }
    }
    return target;
  }

  void _removePartials(String version) {
    final dir = fileSystem.directory(root);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(followLinks: false)) {
      if (!paths.basename(entity.path).startsWith('.$version.partial')) {
        continue;
      }
      try {
        fileSystem.directory(entity.path).deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        log.logTrace('Could not remove ${entity.path}: $error');
      }
    }
  }

  static String _firstLine(Object error) {
    final text = '$error'.trim();
    final newline = text.indexOf('\n');
    return newline < 0 ? text : text.substring(0, newline);
  }

  /// [config] (or a new one) with xcross using the Flutter SDK at
  /// [sdkRoot]; every other setting is kept. [xcrun] is written when xcross
  /// would not find its xcrun shim by itself once a config file exists.
  XcrossConfig withSdk(XcrossConfig? config, String sdkRoot, {String? xcrun}) {
    final base = config ?? XcrossConfig();
    return base.copyWith(
      roots: base.roots.copyWith(flutterSdk: sdkRoot),
      tools: {
        ...base.tools,
        'flutter': flutterExecutable(sdkRoot),
        if (xcrun != null && !base.tools.containsKey('xcrun')) 'xcrun': xcrun,
      },
    );
  }

  /// [config] without the Flutter SDK selection, or `null` when nothing else
  /// is configured (the file can then be removed, which returns xcross to
  /// using the Flutter on PATH).
  static XcrossConfig? withoutSdk(XcrossConfig config) {
    final cleared = config.copyWith(
      roots: config.roots.copyWith(flutterSdk: null),
      tools: {
        for (final MapEntry(:key, :value) in config.tools.entries)
          if (key != 'flutter') key: value,
      },
    );
    final empty =
        cleared.roots.toMap().isEmpty &&
        cleared.toolchains.isEmpty &&
        cleared.tools.isEmpty &&
        cleared.environment.isEmpty &&
        cleared.setup == null &&
        cleared.excludedCommands.isEmpty &&
        cleared.iosGenSnapshot.isEmpty;
    return empty ? null : cleared;
  }
}
