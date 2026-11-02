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
    int? processId,
  }) : _processId = processId ?? pid;

  static const defaultRepositoryUrl = 'https://github.com/flutter/flutter.git';

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

  /// `git clone` arguments for [version] into [target].
  List<String> cloneArguments(String version, String target) => [
    'clone',
    '--depth',
    '1',
    '--branch',
    version,
    repositoryUrl,
    target,
  ];

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
      try {
        await log.logStep(
          'Downloading Flutter $version (about 1 GB, once)',
          () => runTool(git, cloneArguments(version, partial), label: 'git'),
        );
        await fileSystem.directory(partial).rename(target);
      } on Object catch (error) {
        _removePartials(version);
        throw codedError(
          XcrossCodes.toolchainFlutterSdkInstallFailed,
          'Could not download Flutter $version: ${_firstLine(error)}',
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
          '${_firstLine(error)}',
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
