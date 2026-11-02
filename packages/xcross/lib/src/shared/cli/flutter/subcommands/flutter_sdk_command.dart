// studio: 014 — `xcross flutter sdk list|install|use|auto|reset`: a Flutter
// SDK whose iOS AOT compiler exists for this host, for iOS builds only.
@internal
library;

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/config/config.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/sdk/ios_compiler_catalog.dart';
import 'package:xcross/src/shared/flutter/sdk/managed_flutter_sdks.dart';

/// Whether the active Flutter has an iOS release compiler.
@internal
enum CompilerStatus { available, missing, unknown }

/// The Flutter SDK xcross builds with right now.
@internal
final class ActiveFlutter {
  const ActiveFlutter({
    required this.root,
    required this.version,
    required this.compiler,
    this.detail,
  });

  final String? root;
  final String? version;
  final CompilerStatus compiler;

  /// Why the compiler is missing or unknown, or where it comes from.
  final String? detail;
}

/// What the `sdk` commands need from the host; faked in tests.
@internal
final class FlutterSdkServices {
  const FlutterSdkServices({
    required this.log,
    required this.write,
    required this.sdks,
    required this.platform,
    required this.catalog,
    required this.activeFlutter,
    required this.loadConfig,
    required this.saveConfig,
    required this.deleteConfig,
    required this.locateGit,
    this.confirm,
    this.xcrunForConfig,
  });

  final Log log;
  final void Function(String text) write;
  final ManagedFlutterSdks sdks;

  /// xcross_gen_snapshot host platform, such as `windows-x64`.
  final String platform;
  final Future<CompilerCatalog> Function({bool refresh}) catalog;
  final Future<ActiveFlutter> Function() activeFlutter;
  final Future<({XcrossConfig? config, String? path})> Function() loadConfig;

  /// Saves [config]; returns the file path.
  final Future<String> Function(XcrossConfig config) saveConfig;

  /// Removes the config file at [path].
  final Future<void> Function(String path) deleteConfig;
  final Future<String?> Function() locateGit;

  /// Asks a yes/no question on an interactive terminal; `null` when there
  /// is none (then `--yes` is required).
  final Future<bool> Function(String question)? confirm;

  /// The xcrun shim to record when a config is created, or `null` when
  /// xcross finds it beside itself.
  final Future<String?> Function()? xcrunForConfig;
}

/// `xcross flutter sdk`.
@internal
final class FlutterSdkCommand extends Command<void> {
  FlutterSdkCommand(FlutterSdkServices services) {
    addSubcommand(FlutterSdkListCommand(services));
    addSubcommand(FlutterSdkInstallCommand(services));
    addSubcommand(FlutterSdkUseCommand(services));
    addSubcommand(FlutterSdkAutoCommand(services));
    addSubcommand(FlutterSdkResetCommand(services));
  }

  @override
  String get name => 'sdk';

  @override
  String get description =>
      'Use a Flutter version with an iOS compiler for this computer, for iOS '
      'builds only (your own Flutter is not changed).';
}

/// The plain-language reason shown by `auto` and in the GUI.
@internal
String flutterSdkExplanation({
  required String? current,
  required String suggested,
  required String platform,
  required String directory,
}) =>
    "Why: iPhone release and profile builds need Flutter's iOS compiler "
    '(gen_snapshot). Flutter publishes it for macOS only, so xcross uses '
    'builds for $platform from arxdeus/xcross_gen_snapshot, which has them up '
    'to Flutter $suggested'
    '${current == null ? '' : ', not for your Flutter $current'}. xcross '
    'therefore uses Flutter $suggested from $directory for iOS builds only. '
    'Your own Flutter is not changed; `xcross flutter sdk reset` switches '
    'back.';

/// `xcross flutter sdk list [--json] [--refresh]`.
@internal
final class FlutterSdkListCommand extends Command<void> {
  FlutterSdkListCommand(this.services) {
    argParser
      ..addFlag('json', negatable: false, help: 'One JSON document.')
      ..addFlag(
        'refresh',
        negatable: false,
        help: 'Re-read the published compiler list now.',
      );
  }

  final FlutterSdkServices services;

  @override
  String get name => 'list';

  @override
  String get description =>
      'The Flutter used for iOS builds, the ones xcross installed, and the '
      'versions with an iOS compiler for this computer.';

  @override
  Future<void> run() async {
    final args = argResults!;
    final active = await services.activeFlutter();
    final managed = services.sdks.installed();
    CompilerCatalog? catalog;
    String? catalogError;
    try {
      catalog = await services.catalog(refresh: args.flag('refresh'));
    } on Object catch (error) {
      catalogError = '$error';
    }
    final suggestion = active.version == null || catalog == null
        ? null
        : (active.compiler == CompilerStatus.available
              ? null
              : suggestFlutterSdk(active.version!, catalog.versions));
    final activeRoot = active.root;
    final isManaged = activeRoot != null && services.sdks.isManaged(activeRoot);
    if (args.flag('json')) {
      final document = {
        'v': 1,
        'type': 'flutter_sdks',
        'platform': services.platform,
        'active': {
          'root': activeRoot,
          'version': active.version,
          'managed': isManaged,
          'compiler': active.compiler.name,
          'detail': active.detail,
        },
        'managed': [
          for (final sdk in managed)
            {'version': sdk.version, 'path': sdk.path, 'state': sdk.state.name},
        ],
        'available': catalog?.versions ?? const <String>[],
        'catalogStale': catalog?.stale ?? false,
        'catalogError': catalogError,
        'suggested': suggestion?.version,
      };
      services.write('${jsonEncode(document)}\n');
      return;
    }
    final out = StringBuffer()
      ..writeln(
        'iOS builds use: Flutter ${active.version ?? '?'}'
        '${activeRoot == null ? '' : '  ($activeRoot)'}'
        '${isManaged ? '  [installed by xcross]' : ''}',
      )
      ..writeln(switch (active.compiler) {
        CompilerStatus.available => '✔ iOS release compiler available',
        CompilerStatus.missing => '✖ no iOS release compiler for this Flutter',
        CompilerStatus.unknown =>
          '? iOS release compiler not checked (${active.detail ?? 'offline'})',
      });
    final installed = [
      for (final sdk in managed)
        if (sdk.state == ManagedSdkState.ready)
          sdk.version
        else
          '${sdk.version} (not prepared)',
    ];
    out.writeln(
      'Installed by xcross: '
      '${installed.isEmpty ? 'none' : installed.join(', ')}',
    );
    if (catalog != null) {
      out.writeln(
        'With an iOS compiler for ${services.platform}: '
        '${catalog.versions.take(8).join(', ')}'
        '${catalog.versions.length > 8 ? ', …' : ''}'
        '${catalog.stale ? '  (saved list; offline)' : ''}',
      );
    } else {
      out.writeln('Could not read the published compiler list: $catalogError');
    }
    if (suggestion != null) {
      out.writeln(
        'Fix: xcross flutter sdk auto   (installs Flutter ${suggestion.version} '
        'for iOS builds)',
      );
    }
    services.write(out.toString());
  }
}

/// `xcross flutter sdk install <version> [--force]`.
@internal
final class FlutterSdkInstallCommand extends Command<void> {
  FlutterSdkInstallCommand(this.services) {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Install even when no iOS compiler is published for it.',
    );
  }

  final FlutterSdkServices services;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Download a Flutter version for iOS builds (does not select it).';

  @override
  String get invocation => 'xcross flutter sdk install <version> [--force]';

  @override
  Future<void> run() async {
    final args = argResults!;
    if (args.rest.length != 1) usageException('Pass one version, e.g. 3.47.6.');
    final path = await installVersion(
      services,
      args.rest.single,
      force: args.flag('force'),
    );
    services.log.logDone('Flutter ${args.rest.single} is ready', path);
  }
}

/// Installs [version] after checking the catalog (unless [force]).
@internal
Future<String> installVersion(
  FlutterSdkServices services,
  String version, {
  bool force = false,
}) async {
  if (!ManagedFlutterSdks.versionPattern.hasMatch(version)) {
    throw codedError(
      XcrossCodes.toolchainFlutterSdkVersionUnavailable,
      '"$version" is not a Flutter release version such as 3.47.6.',
    );
  }
  if (!force) {
    final catalog = await services.catalog();
    if (!catalog.versions.contains(version)) {
      throw codedError(
        XcrossCodes.toolchainFlutterSdkVersionUnavailable,
        'No iOS compiler is published for Flutter $version on '
        '${services.platform}.',
      );
    }
  }
  final git = await services.locateGit();
  if (git == null) {
    throw codedError(
      XcrossCodes.toolchainGitMissing,
      'Git is needed to download Flutter.',
    );
  }
  final root = await services.sdks.install(version, git: git);
  return root;
}

/// Points the xcross config at [sdkRoot]; returns the config path.
@internal
Future<String> useSdk(FlutterSdkServices services, String sdkRoot) async {
  final loaded = await services.loadConfig();
  final xcrun = loaded.config == null && services.xcrunForConfig != null
      ? await services.xcrunForConfig!()
      : null;
  final path = await services.saveConfig(
    services.sdks.withSdk(loaded.config, sdkRoot, xcrun: xcrun),
  );
  return path;
}

/// `xcross flutter sdk use <version|path>`.
@internal
final class FlutterSdkUseCommand extends Command<void> {
  FlutterSdkUseCommand(this.services);

  final FlutterSdkServices services;

  @override
  String get name => 'use';

  @override
  String get description =>
      'Build iOS apps with an installed Flutter version or a Flutter folder.';

  @override
  String get invocation => 'xcross flutter sdk use <version|path>';

  @override
  Future<void> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      usageException('Pass one version (e.g. 3.47.6) or a Flutter folder.');
    }
    final value = args.rest.single;
    final sdks = services.sdks;
    final String root;
    if (ManagedFlutterSdks.versionPattern.hasMatch(value)) {
      root = sdks.directory(value);
      if (sdks.stateOf(root) != ManagedSdkState.ready) {
        throw codedError(
          XcrossCodes.toolchainFlutterSdkVersionUnavailable,
          'Flutter $value is not installed by xcross.',
          hint: 'Run `xcross flutter sdk install $value` first.',
        );
      }
    } else {
      root = value;
      if (sdks.stateOf(root) == ManagedSdkState.missing) {
        throw codedError(
          XcrossCodes.toolchainFlutterSdkVersionUnavailable,
          '$value is not a Flutter folder (no bin/flutter).',
          hint: 'Pass the folder that contains bin/flutter.',
        );
      }
    }
    final path = await useSdk(services, root);
    services.log.logDone('iOS builds now use Flutter from $root', path);
  }
}

/// `xcross flutter sdk auto [--yes]`.
@internal
final class FlutterSdkAutoCommand extends Command<void> {
  FlutterSdkAutoCommand(this.services) {
    argParser.addFlag(
      'yes',
      abbr: 'y',
      negatable: false,
      help: 'Download without asking (about 1 GB).',
    );
  }

  final FlutterSdkServices services;

  @override
  String get name => 'auto';

  @override
  String get description =>
      'If your Flutter has no iOS compiler for this computer, install and use '
      'the newest one that has, for iOS builds only.';

  @override
  Future<void> run() async {
    final args = argResults!;
    final log = services.log;
    final active = await log.logStep(
      'Checking the Flutter used for iOS builds',
      services.activeFlutter,
    );
    if (active.compiler == CompilerStatus.available) {
      log.logDone(
        'Flutter ${active.version ?? ''} already has an iOS compiler for '
        '${services.platform}; nothing to change',
      );
      return;
    }
    final catalog = await log.logStep(
      'Reading the published iOS compilers',
      services.catalog,
    );
    final current = active.version;
    final suggestion = current == null
        ? suggestFlutterSdk('0.0.0', catalog.versions)
        : suggestFlutterSdk(current, catalog.versions);
    if (suggestion == null) {
      if (current != null && catalog.versions.contains(current)) {
        log.logDone(
          'Flutter $current has a published iOS compiler; it is downloaded '
          'on the first release build',
        );
        return;
      }
      throw codedError(
        XcrossCodes.toolchainFlutterSdkVersionUnavailable,
        'No Flutter version has a published iOS compiler for '
        '${services.platform}.',
      );
    }
    final version = suggestion.version;
    final directory = services.sdks.directory(version);
    log.logInfo(
      'Plan',
      'Flutter ${current ?? '?'} → $version for iOS builds'
          '${suggestion.sameLine ? '' : ' (newest available; not the same '
                    'major.minor as yours)'}',
    );
    services.write(
      '${flutterSdkExplanation(current: current, suggested: version, platform: services.platform, directory: directory)}\n',
    );
    final ready = services.sdks.stateOf(directory) == ManagedSdkState.ready;
    if (!ready && !args.flag('yes')) {
      final confirm = services.confirm;
      if (confirm == null) {
        throw UsageException(
          'This downloads Flutter $version (about 1 GB). Run again with '
          '--yes to continue.',
          usage,
        );
      }
      if (!await confirm('Download Flutter $version (about 1 GB) now?')) {
        log.logWarn('Nothing was changed.');
        return;
      }
    }
    final root = ready
        ? directory
        : await installVersion(services, version, force: true);
    final path = await log.logStep(
      'Selecting Flutter $version for iOS builds',
      () => useSdk(services, root),
    );
    log.logDone('iOS builds now use Flutter $version', path);
  }
}

/// `xcross flutter sdk reset`.
@internal
final class FlutterSdkResetCommand extends Command<void> {
  FlutterSdkResetCommand(this.services);

  final FlutterSdkServices services;

  @override
  String get name => 'reset';

  @override
  String get description =>
      'Build iOS apps with your own Flutter again (installed versions stay on '
      'disk).';

  @override
  Future<void> run() async {
    final loaded = await services.loadConfig();
    final config = loaded.config;
    final path = loaded.path;
    if (config == null ||
        path == null ||
        (config.roots.flutterSdk == null && config.tool('flutter') == null)) {
      services.log.logDone('iOS builds already use your own Flutter');
      return;
    }
    final cleared = ManagedFlutterSdks.withoutSdk(config);
    if (cleared == null) {
      await services.deleteConfig(path);
      services.log.logDone(
        'iOS builds use your own Flutter again (removed the xcross config '
        'that only selected the Flutter SDK)',
        path,
      );
    } else {
      await services.saveConfig(cleared);
      services.log.logDone('iOS builds use your own Flutter again', path);
    }
  }
}
