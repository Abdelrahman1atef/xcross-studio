@internal
library;

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart'; // studio: 019
import 'package:build_cli_annotations/build_cli_annotations.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/appstore/build_numbers.dart'; // studio: 019
import 'package:xcross/src/composition/cli/asc_commands.dart'; // studio: 019
import 'package:xcross/src/composition/ios_target.dart';
import 'package:xcross/src/shared/cli/internal/parsed_command.dart';
import 'package:xcross/src/shared/cli/shared/ipa_packager.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart'; // studio: 018
import 'package:xcross/src/shared/flutter/build/flutter_pack_operation.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_mode.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';
import 'package:xcross/src/target/iphone/device/app_store_export.dart'; // studio: 018

part 'flutter_build_command.g.dart';

/// Shared `flutter build`/`flutter run` options: entry-point target, flavor,
/// dart-defines, and `--pub`.
@internal
class CommonFlutterArgs {
  @CliOption(
    abbr: 't',
    defaultsTo: 'lib/main.dart',
    help: 'The main entry-point file of the application.',
  )
  late String target;

  @CliOption(help: 'Build a custom app flavor (sets FLUTTER_APP_FLAVOR).')
  late String? flavor;

  @CliOption(abbr: 'D', help: 'Pass a KEY=VALUE define to the Dart compiler.')
  late List<String> dartDefine;

  @CliOption(help: 'Load dart-defines from a .json or .env file.')
  late List<String> dartDefineFromFile;

  @CliOption(help: 'Run "flutter pub get" before building.', defaultsTo: true)
  late bool pub;
}

/// The single build mode selected by `--debug`/`--profile`/`--release`.
@internal
FlutterBuildMode flutterBuildModeOf({
  required bool debug,
  required bool profile,
  required bool release,
  required Never Function(String message) usageException,
}) {
  final selected = [
    if (debug) FlutterBuildMode.debug,
    if (profile) FlutterBuildMode.profile,
    if (release) FlutterBuildMode.release,
  ];
  if (selected.length > 1) {
    usageException('Choose only one of --debug, --profile or --release.');
  }
  return selected.singleOrNull ?? FlutterBuildMode.debug;
}

/// Options for `xcross flutter build`.
@internal
@CliOptions()
final class FlutterBuildArgs extends CommonFlutterArgs {
  @CliOption(
    defaultsTo: 'iphone',
    help: 'Target platform: iphone or simulator.',
  )
  late String targetPlatform;

  @CliOption(negatable: false, help: 'Build a debug (JIT) app (default).')
  late bool debug;

  @CliOption(
    negatable: false,
    help: 'Build an ahead-of-time compiled profile app (devices only).',
  )
  late bool profile;

  @CliOption(
    negatable: false,
    help: 'Build an ahead-of-time compiled release app (devices only).',
  )
  late bool release;

  @CliOption(help: 'Version name (CFBundleShortVersionString).')
  late String? buildName;

  @CliOption(help: 'Version code (CFBundleVersion).')
  late String? buildNumber;

  @CliOption(
    defaultsTo: true,
    help:
        'Tree shake icon fonts so that only glyphs used by the application '
        'remain. Applies to profile and release builds.',
  )
  late bool treeShakeIcons;

  @CliOption(
    help:
        'Write Dart debug symbols to this directory instead of the app. '
        'Applies to profile and release builds.',
  )
  late String? splitDebugInfo;

  @CliOption(
    negatable: false,
    help:
        'Obfuscate Dart symbol names. Requires --split-debug-info; applies '
        'to profile and release builds.',
  )
  late bool obfuscate;

  @CliOption(
    abbr: 'i',
    negatable: false,
    help: 'Output a .ipa file instead of a .app.',
  )
  late bool ipa;
}

/// `xcross flutter build` — build a Flutter iOS `.app` (optionally ipa).
///
/// `build` produces an unsigned bundle; signing happens when `xcross flutter
/// run` installs it.
@internal
final class FlutterBuildCommand<T extends PlatformHostInterface>
    extends ParsedCommand<FlutterBuildArgs, void> {
  FlutterBuildCommand(this.runtime);
  @override
  ArgParser populateOptions(ArgParser parser) =>
      _$populateFlutterBuildArgsParser(parser)
        // studio: 018 — App Store distribution signing and the archive.
        ..addOption(
          exportMethodOption,
          allowed: const ['development', 'app-store'],
          defaultsTo: 'development',
          help:
              'app-store: sign for App Store distribution (team API key with '
              'the Admin or App Manager role) and write build/xcross-ios/ipa '
              'and build/xcross-ios/archive/Runner.xcarchive. Needs --release.',
        );

  // studio: 018
  static const exportMethodOption = 'export-method';
  @override
  FlutterBuildArgs parseOptions(ArgResults results) =>
      _$parseFlutterBuildArgsResult(results);

  final XcrossRuntime<T> runtime;
  @override
  String get name => 'build';

  @override
  String get description => 'Build a Flutter iOS .app without Xcode.';

  @override
  Future<void> run() async {
    // studio: 018
    final appStore = argResults?[exportMethodOption] == 'app-store';
    if (appStore && !options.release) {
      usageException('--export-method app-store needs --release.');
    }
    final mode = flutterBuildModeOf(
      debug: options.debug,
      profile: options.profile,
      release: options.release,
      usageException: usageException,
    );
    final features = composeBuildFeatures(
      options.targetPlatform,
      runtime,
      ipa: options.ipa,
    );
    final buildRuntime = features.flutterRuntime;
    final projectRoot = runtime.host.paths.context.current;
    // studio: 018 — a missing or individual key stops the build before it
    // compiles, not after.
    if (appStore) await _appStoreExport().credentials();
    // studio: 019 — `--build-number auto`: one past App Store Connect's newest.
    final buildNumber = options.buildNumber?.trim() == 'auto'
        ? await _autoBuildNumber(
            projectRoot,
            buildRuntime.bundleIds.resolve(projectRoot),
          )
        : options.buildNumber;
    final buildOptions = await buildRuntime.options.resolve(
      target: options.target,
      dartDefine: options.dartDefine,
      dartDefineFromFile: options.dartDefineFromFile,
      pub: options.pub,
      buildName: options.buildName,
      buildNumber: buildNumber,
      flavor: options.flavor,
      buildMode: mode,
      treeShakeIcons: options.treeShakeIcons,
      splitDebugInfo: options.splitDebugInfo,
      obfuscate: options.obfuscate,
      projectRoot: projectRoot,
    );

    final result = await FlutterPackOperation.pack(
      projectRoot: projectRoot,
      runtime: buildRuntime,
      options: buildOptions,
    );

    // studio: 018
    if (appStore) {
      await _exportForAppStore(result.appPath);
      return;
    }
    final finalPath = options.ipa
        ? await IpaPackager(host: runtime.host).package(result.appPath)
        : result.appPath;
    runtime.log.logDone('Wrote $finalPath');
    // studio: 012 — the .ipa for event consumers (FlutterPackOperation
    // reports the .app).
    if (options.ipa) {
      runtime.log.events?.event('artifact', {'kind': 'ipa', 'path': finalPath});
    }
  }

  // studio: 018
  AppStoreExport<T> _appStoreExport() => AppStoreExport(
    runner: runtime.runner,
    hostServices: runtime.appleHostServices,
    httpClients: runtime.signingHttpClients,
    environment: runtime.runner.effectiveEnvironment,
  );

  // studio: 018 — sign for distribution, write the IPA and the archive.
  Future<void> _exportForAppStore(String appPath) async {
    final paths = runtime.host.paths.context;
    final result = await _appStoreExport().export(
      appPath: appPath,
      outputRoot: paths.dirname(appPath),
    );
    if (result.missingDsyms.isNotEmpty) {
      runtime.log.logWarn(
        codedWarning(
          XcrossCodes.releaseDsymUnavailable,
          'No dSYM for ${result.missingDsyms.join(', ')}; crash reports from '
          'this build cannot be symbolicated for those binaries.',
        ),
      );
    }
    runtime.log.logDone('Wrote ${result.ipaPath}');
    runtime.log.logInfo('Archive', result.archivePath);
    runtime.log.events
      ?..event('artifact', {'kind': 'ipa', 'path': result.ipaPath})
      ..event('artifact', {'kind': 'xcarchive', 'path': result.archivePath});
  }

  // studio: 019 — max(pubspec build, newest App Store Connect build + 1);
  // the pubspec number when App Store Connect cannot be asked.
  Future<String> _autoBuildNumber(String projectRoot, String bundleId) async {
    final pubspec = runtime.host.fileSystem.file(
      runtime.host.paths.context.join(projectRoot, 'pubspec.yaml'),
    );
    final local =
        int.tryParse(
          RegExp(r'^version:\s*[^+\s]+\+(\d+)', multiLine: true)
                  .firstMatch(
                    pubspec.existsSync() ? pubspec.readAsStringSync() : '',
                  )
                  ?.group(1) ??
              '',
        ) ??
        1;
    try {
      final api = await openAscApi(runtime);
      try {
        final appId = runtime.runner.effectiveEnvironment['APP_STORE_APP_ID']
            ?.trim();
        final app = appId == null || appId.isEmpty
            ? await AscApps.findByBundleId(api, bundleId)
            : AscApi.data(await api.get('/v1/apps/$appId'));
        if (app == null) {
          runtime.log.logWarn(
            'Build number: App Store Connect has no app $bundleId yet; using '
            '$local from pubspec.yaml.',
          );
          return '$local';
        }
        final latest = await latestBuildNumber(api, app.id);
        final next = nextBuildNumber(local: local, latest: latest);
        runtime.log.logInfo(
          'Build number',
          '$next${latest == null ? '' : ' (App Store Connect has $latest)'}',
        );
        return '$next';
      } finally {
        api.close();
      }
    } on Object catch (error) {
      runtime.log.logWarn(
        'Build number: could not ask App Store Connect ($error); using '
        '$local from pubspec.yaml.',
      );
      return '$local';
    }
  }
}
