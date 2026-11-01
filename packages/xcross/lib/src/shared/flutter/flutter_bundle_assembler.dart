import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/artifact/plist_mutations.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart'; // studio: 002
import 'package:xcross/src/shared/flutter/build/app_extension_builder.dart';
import 'package:xcross/src/shared/flutter/build/flutter_app_entitlements.dart'; // studio: 003
import 'package:xcross/src/shared/flutter/build/flutter_asset_catalogs.dart'; // studio: 004
import 'package:xcross/src/shared/flutter/build/info_plist.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_resources.dart'; // studio: 002
import 'package:xcross/src/shared/flutter/build/ios_bundle_versions.dart';
import 'package:xcross/src/shared/flutter/build/ios_deployment_target.dart';
import 'package:xcross/src/shared/flutter/constants.dart';
import 'package:xcross/src/shared/flutter/extensions/app_extension_plist.dart';
import 'package:xcross/src/shared/flutter/flutter_build_runtime.dart';
import 'package:xcross/src/shared/flutter/flutter_build_steps.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_mode.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_options.dart';

@internal
final class FlutterBundleAssembler<T extends PlatformHostInterface>
    implements FlutterAssembleStep<T> {
  FlutterBundleAssembler(this.context);
  final FlutterBuildContext<T> context;
  FlutterBuildRuntime<T> get runtime => context.runtime;
  String get projectRoot => context.projectRoot;
  String get bundleId => context.bundleId;
  String get appName => context.appName;
  FlutterBuildOptions get options => context.options;
  IosBundleVersions get _versions => context.versions;
  String get outputDirectory => runtime.policy.outputDirectory(projectRoot);
  @override
  Future<String> assemble(FlutterLinkedArtifacts linked) =>
      _assembleAndPersistBundle(
        appFramework: linked.compiled.appFramework,
        xcframework: linked.runner.xcframework,
        runnerBinary: linked.runner.runnerBinary,
        sdkName: linked.runner.sdkName,
        pluginLibraries: linked.compiled.plugins?.dylibPaths ?? const [],
        pluginFrameworks: linked.compiled.plugins?.frameworkPaths ?? const [],
        nativeAssetFrameworks: linked.compiled.nativeAssets.frameworks,
        deploymentTarget: context.deploymentTarget,
        extensions: linked.extensions,
      );

  Future<String> _assembleAndPersistBundle({
    required String appFramework,
    required String xcframework,
    required String runnerBinary,
    required String sdkName,
    required List<String> pluginLibraries,
    required List<String> pluginFrameworks,
    required List<String> nativeAssetFrameworks,
    required IosDeploymentTarget deploymentTarget,
    required List<BuiltAppExtension> extensions,
  }) async {
    // Stage in a temp dir so the destination is only touched once everything
    // is in place.
    final tmp = await runtime.host.fileSystem
        .directory(runtime.host.paths.temporaryRoot)
        .createTemp('${appName}_app_bundle-');

    await _stageBundle(
      bundleDir: tmp.path,
      appFramework: appFramework,
      flutterFramework: runtime.host.paths.context.join(
        runtime.policy.selectEngineSlice(xcframework),
        'Flutter.framework',
      ),
      runnerBinary: runnerBinary,
      sdkName: sdkName,
      pluginLibraries: pluginLibraries,
      pluginFrameworks: pluginFrameworks,
      nativeAssetFrameworks: nativeAssetFrameworks,
      deploymentTarget: deploymentTarget,
      extensions: extensions,
    );

    final dest = runtime.host.paths.context.join(
      outputDirectory,
      '$appName.app',
    );
    final destDir = runtime.host.fileSystem.directory(dest);
    if (destDir.existsSync()) {
      await destDir.delete(recursive: true);
    }
    await runtime.host.fileSystem
        .directory(runtime.host.paths.context.dirname(dest))
        .create(recursive: true);
    await runtime.directoryCopier.copy(tmp.path, dest);
    await tmp.delete(recursive: true);
    await _publishDebugSymbols(
      appFramework: appFramework,
      engineSlice: runtime.policy.selectEngineSlice(xcframework),
      nativeAssetFrameworks: nativeAssetFrameworks,
    );

    return dest;
  }

  /// Replaces the dSYMs beside the `.app` with those of this build, as
  /// `flutter build ios` leaves them: `App.framework.dSYM`, the engine's
  /// `Flutter.framework.dSYM`, and one per native asset framework. Debug
  /// builds have none, so they only remove stale ones.
  Future<void> _publishDebugSymbols({
    required String appFramework,
    required String engineSlice,
    required List<String> nativeAssetFrameworks,
  }) async {
    final paths = runtime.host.paths.context;
    final output = runtime.host.fileSystem.directory(outputDirectory);
    await for (final entity in output.list(followLinks: false)) {
      if (entity.path.endsWith('.framework.dSYM')) {
        await entity.delete(recursive: true);
      }
    }
    if (!options.buildMode.isPrecompiled) return;
    for (final dsym in [
      '$appFramework.dSYM',
      paths.join(engineSlice, 'dSYMs', 'Flutter.framework.dSYM'),
      for (final framework in nativeAssetFrameworks) '$framework.dSYM',
    ]) {
      if (!runtime.host.fileSystem.directory(dsym).existsSync()) continue;
      await runtime.directoryCopier.copy(
        dsym,
        paths.join(outputDirectory, paths.basename(dsym)),
      );
    }
  }

  /// Lay out the `.app` contents under [bundleDir]: the Runner executable,
  /// the embedded frameworks and plugin dylibs, storyboards, and `Info.plist`.
  Future<void> _stageBundle({
    required String bundleDir,
    required String appFramework,
    required String flutterFramework,
    required String runnerBinary,
    required String sdkName,
    required List<String> pluginLibraries,
    required List<String> pluginFrameworks,
    required List<String> nativeAssetFrameworks,
    required IosDeploymentTarget deploymentTarget,
    required List<BuiltAppExtension> extensions,
  }) async {
    final frameworksDir = runtime.host.paths.context.join(
      bundleDir,
      'Frameworks',
    );
    await runtime.host.fileSystem
        .directory(frameworksDir)
        .create(recursive: true);

    final runnerDest = runtime.host.paths.context.join(bundleDir, 'Runner');
    await runtime.host.fileSystem
        .file(runnerBinary)
        .copy(runtime.host.fileSystem.file(runnerDest).path);
    runtime.runner.makeExecutable(runnerDest);

    await runtime.directoryCopier.copy(
      flutterFramework,
      runtime.host.paths.context.join(frameworksDir, 'Flutter.framework'),
    );
    await runtime.directoryCopier.copy(
      appFramework,
      runtime.host.paths.context.join(frameworksDir, 'App.framework'),
    );
    await runtime.frameworks.copyPluginLibraries(
      pluginLibraries,
      frameworksDir,
    );
    await runtime.frameworks.copyNativeAssetFrameworks(
      nativeAssetFrameworks,
      frameworksDir,
    );
    final embedded = await runtime.frameworks.copyMissingFrameworks(
      pluginFrameworks,
      frameworksDir,
    );
    await runtime.nativeAssetFrameworks.thinEmbedded(
      embedded,
      lipo: () => runtime.nativeTools.locateLlvmTool('llvm-lipo'),
    );

    await _embedAppExtensions(bundleDir, extensions);
    final skipped = await runtime.resources.stage(
      projectRoot: projectRoot,
      bundleDir: bundleDir,
    );
    // studio: 004 — compile catalogs + launch storyboard before reporting.
    final assets = await _compileAssetCatalogs(
      bundleDir,
      skipped,
      deploymentTarget,
    );
    _reportSkippedResources([
      for (final resource in skipped)
        if (!assets.handled.contains(resource.path)) resource,
    ]);
    await _writeInfoPlist(
      bundleDir,
      deploymentTarget: deploymentTarget,
      sdkName: sdkName,
      assets: assets,
    );
    for (final binary in await runtime.signatures.refresh(bundleDir)) {
      runtime.runner.log.logTrace('refreshed ad-hoc signature of $binary');
    }
  }

  // studio: 004 — Assets.car, loose icons and the UILaunchScreen (#149).
  Future<FlutterAssetCatalogResult> _compileAssetCatalogs(
    String bundleDir,
    List<SkippedResource> skipped,
    IosDeploymentTarget deploymentTarget,
  ) async =>
      FlutterAssetCatalogs(
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
        warn: (code, {required subject, required message}) =>
            runtime.warnings.warn(code, subject: subject, message: message),
        trace: runtime.runner.log.logTrace,
      ).compile(
        bundleDir: bundleDir,
        skipped: skipped,
        deploymentTarget: deploymentTarget.version,
        launchStoryboardName: FlutterAssetCatalogs.launchStoryboardName(
          await _loadPlistTemplate(),
        ),
        display: _shownPath,
      );

  String _shownPath(String path) {
    final context = runtime.host.paths.context;
    return context.isWithin(projectRoot, path)
        ? context.relative(path, from: projectRoot)
        : path;
  }

  // studio: 002 — every skipped project resource gets a coded warning.
  void _reportSkippedResources(List<SkippedResource> skipped) {
    final context = runtime.host.paths.context;
    for (final resource in skipped) {
      final shown = _shownPath(resource.path);
      switch (resource.reason) {
        case SkippedResourceReason.assetCatalog:
          runtime.warnings.warn(
            XcrossCodes.buildAssetCatalogSkipped,
            subject: shown,
            message:
                '$shown was not compiled; the icons and images in it are not '
                'in the app.',
          );
        case SkippedResourceReason.uncompiledStoryboard:
          final name = context.basenameWithoutExtension(resource.path);
          runtime.warnings.warn(
            XcrossCodes.buildStoryboardSkipped,
            subject: name,
            message:
                'Storyboard "$name" ($shown) is not compiled and was left '
                'out; Info.plist references to it are removed.',
          );
        case SkippedResourceReason.missing:
          runtime.warnings.warn(
            XcrossCodes.buildResourceMissing,
            subject: shown,
            message:
                '$shown is listed in the Xcode project but does not exist.',
          );
      }
    }
  }

  /// Copy each built `.appex` into the app's `PlugIns` directory, the only
  /// location iOS looks for embedded app extensions.
  Future<void> _embedAppExtensions(
    String bundleDir,
    List<BuiltAppExtension> extensions,
  ) async {
    if (extensions.isEmpty) return;
    final plugInsDir = runtime.host.paths.context.join(bundleDir, 'PlugIns');
    await runtime.host.fileSystem.directory(plugInsDir).create(recursive: true);
    for (final extension in extensions) {
      await runtime.directoryCopier.copy(
        extension.bundlePath,
        runtime.host.paths.context.join(
          plugInsDir,
          extension.extension.bundleName,
        ),
      );
    }
  }

  /// Generate and write `Info.plist` into [bundleDir] with `$(VAR)`
  /// substitution, mandatory iOS keys, storyboard stripping, and ObjC class
  /// name normalization.
  Future<void> _writeInfoPlist(
    String bundleDir, {
    required IosDeploymentTarget deploymentTarget,
    required String sdkName,
    FlutterAssetCatalogResult assets = FlutterAssetCatalogResult.none,
  }) async {
    var plistXml = await _loadPlistTemplate();

    // ORDER MATTERS: vars must be expanded before forcing keys so that forced
    // keys see already-substituted values from the template, and before
    // storyboard stripping so $(VAR)-valued storyboard names are resolved
    // before the .storyboardc filesystem probe.
    plistXml = InfoPlist.expandXmlVars(
      plistXml,
      await buildSubstitutionMap(sdkName: sdkName),
    );
    if (options.buildName != null ||
        !plistXml.contains('<key>CFBundleShortVersionString</key>')) {
      plistXml = PlistMutations.setPlistString(
        plistXml,
        'CFBundleShortVersionString',
        _versions.shortVersion,
      );
    }
    if (options.buildNumber != null ||
        !plistXml.contains('<key>CFBundleVersion</key>')) {
      plistXml = PlistMutations.setPlistString(
        plistXml,
        'CFBundleVersion',
        _versions.bundleVersion,
      );
    }
    plistXml = InfoPlist.applyIosRequiredKeys(
      plistXml,
      bundleId: bundleId,
      deploymentTarget: deploymentTarget,
    );
    plistXml = runtime.policy.transformPlist(plistXml, sdkName: sdkName);
    if (options.buildMode != FlutterBuildMode.release) {
      plistXml = InfoPlist.applyDebugVmServiceDiscovery(plistXml);
    }
    plistXml = runtime.storyboards.stripUnsatisfiableStoryboards(
      plistXml,
      bundleDir,
      // studio: 002 — a removed storyboard reference is reported, not silent.
      onRemoved: (key, name) {
        // studio: 004 — the launch storyboard became a UILaunchScreen.
        if (key == 'UILaunchStoryboardName' &&
            name == assets.launchStoryboardName) {
          return;
        }
        runtime.warnings.warn(
          XcrossCodes.buildStoryboardSkipped,
          subject: name,
          message:
              'Info.plist $key "$name" has no compiled storyboard and was '
              'removed.',
        );
      },
    );
    plistXml = InfoPlist.applySceneLifecycle(plistXml);
    plistXml = InfoPlist.normalizeObjCClassNames(plistXml);
    // Carry the app's own App Groups forward so the sign/install stage can
    // provision them alongside its extensions'.
    plistXml = AppExtensionPlist.setAppGroups(plistXml, _hostAppGroups());
    plistXml = _withDeclaredEntitlements(plistXml); // studio: 003
    plistXml = _withAssetCatalogKeys(plistXml, assets); // studio: 004

    await runtime.host.fileSystem
        .file(runtime.host.paths.context.join(bundleDir, 'Info.plist'))
        .writeAsString(plistXml);
  }

  // studio: 004 — icon keys and UILaunchScreen from the compiled catalog.
  String _withAssetCatalogKeys(
    String plistXml,
    FlutterAssetCatalogResult assets,
  ) {
    try {
      return FlutterAssetCatalogs.mergeInfoPlist(plistXml, assets);
    } on FormatException catch (error) {
      runtime.warnings.warn(
        XcrossCodes.buildAssetCatalogSkipped,
        subject: 'Info.plist',
        message:
            'The app icon and launch screen keys were not added: '
            '${error.message}.',
      );
      return plistXml;
    }
  }

  // studio: 003 — push, associated domains, … reach the signer (#149).
  String _withDeclaredEntitlements(String plistXml) {
    final entitlements = FlutterAppEntitlements(
      runtime.host.fileSystem,
      runtime.host.paths.context,
    );
    final path = entitlements.locate(
      projectRoot,
      fromProject: runtime.extensions.applicationEntitlements(projectRoot),
    );
    if (path == null) return plistXml;
    try {
      return FlutterAppEntitlements.withSigningKeys(
        plistXml,
        entitlements.read(path),
      );
    } on FormatException catch (error) {
      runtime.warnings.warn(
        XcrossCodes.buildEntitlementsUnreadable,
        subject: path,
        message:
            '${runtime.host.paths.context.basename(path)} is ignored: '
            '${error.message}.',
      );
      return plistXml;
    }
  }

  /// App Groups declared by the application target's entitlements file.
  List<String> _hostAppGroups() {
    final extensionGroups = runtime.extensions.applicationEntitlements(
      projectRoot,
    );
    return runtime.extensions.readAppGroups(extensionGroups);
  }

  /// Read `ios/Runner/Info.plist`, falling back to [InfoPlist.fallback].
  Future<String> _loadPlistTemplate() async {
    final plistFile = runtime.host.fileSystem.file(
      runtime.host.paths.context.join(
        projectRoot,
        'ios',
        'Runner',
        'Info.plist',
      ),
    );
    if (plistFile.existsSync()) {
      final plistSource = await plistFile.readAsString();
      return plistSource;
    }
    return InfoPlist.fallback;
  }

  /// Build the `$(VAR)` substitution map.
  ///
  /// Precedence (lowest → highest):
  ///   1. Hard-coded defaults (`1.0.0` / `1`).
  ///   2. `Debug.xcconfig` and its includes in textual order, falling back
  ///      to `Generated.xcconfig` only when no Debug file exists.
  ///   3. The decided bundle versions (studio: 002 — flag > pubspec >
  ///      xcconfig > project file > default), pinned for the four version
  ///      variables so every template spelling expands to the same pair.
  @visibleForTesting
  Future<Map<String, String>> buildSubstitutionMap({String? sdkName}) async {
    final selectedSdk = sdkName ?? runtime.target.buildPlatform.sdkName;
    final subs = <String, String>{
      'EXECUTABLE_NAME': PlistDefaults.executable,
      'PRODUCT_NAME': PlistDefaults.executable,
      'PRODUCT_MODULE_NAME': PlistDefaults.executable,
      'PRODUCT_BUNDLE_IDENTIFIER': bundleId,
      'DEVELOPMENT_LANGUAGE': 'en',
      'FLUTTER_BUILD_NAME': PlistDefaults.shortVersion,
      'FLUTTER_BUILD_NUMBER': PlistDefaults.bundleVersion,
      // Xcode expands these from the application target's build settings.
      // Without them, `ios/Runner/Info.plist` (which references them by
      // default) ships a literal "$(MARKETING_VERSION)" as the app version.
      'MARKETING_VERSION': _versions.shortVersion,
      'CURRENT_PROJECT_VERSION': _versions.bundleVersion,
    };

    // `receive_sharing_intent` and friends point the app's `AppGroupId` key
    // at `$(CUSTOM_GROUP_ID)`, which Xcode expands from the target's build
    // settings. The extension build already substitutes it; doing the same
    // here keeps both sides naming one container, instead of the app reading
    // back the literal `$(CUSTOM_GROUP_ID)` and finding nothing shared.
    final hostGroups = _hostAppGroups();
    if (hostGroups.isNotEmpty) {
      subs['CUSTOM_GROUP_ID'] = hostGroups.first;
    }

    final flutterConfigDirectory = runtime.host.paths.context.join(
      projectRoot,
      'ios',
      'Flutter',
    );
    final overrides = _buildVersionOverrides();
    subs.addAll(
      await runtime.xcconfigs.readDebugConfiguration(
        debugPath: runtime.host.paths.context.join(
          flutterConfigDirectory,
          'Debug.xcconfig',
        ),
        generatedPath: runtime.host.paths.context.join(
          flutterConfigDirectory,
          'Generated.xcconfig',
        ),
        sdk: selectedSdk,
        defaults: subs,
        overrides: overrides,
      ),
    );
    subs.addAll(overrides);

    return subs;
  }

  // studio: 002 — pin the decided versions (not only explicit flags).
  /// The bundle version variables, pinned to the decided [_versions].
  Map<String, String> _buildVersionOverrides() => {
    'FLUTTER_BUILD_NAME': _versions.shortVersion,
    'MARKETING_VERSION': _versions.shortVersion,
    'FLUTTER_BUILD_NUMBER': _versions.bundleVersion,
    'CURRENT_PROJECT_VERSION': _versions.bundleVersion,
  };
}
