import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/build/ios_deployment_target.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';
import 'package:xcross/src/shared/flutter/swiftpm/artifact_filesystem.dart';
import 'package:xcross/src/shared/flutter/swiftpm/checkout.dart';
import 'package:xcross/src/shared/flutter/swiftpm/checkout_manifest_normalizer.dart';
import 'package:xcross/src/shared/flutter/swiftpm/dependency_preparation.dart';
import 'package:xcross/src/shared/flutter/swiftpm/filesystem.dart';
import 'package:xcross/src/shared/flutter/swiftpm/host_build_services.dart';
import 'package:xcross/src/shared/flutter/swiftpm/host_policy.dart';
import 'package:xcross/src/shared/flutter/swiftpm/host_source_normalizer.dart';
import 'package:xcross/src/shared/flutter/swiftpm/manifest.dart';
import 'package:xcross/src/shared/flutter/swiftpm/manifest_dependencies.dart';
import 'package:xcross/src/shared/flutter/swiftpm/manifest_lexer.dart';
import 'package:xcross/src/shared/flutter/swiftpm/module_warmup.dart';
import 'package:xcross/src/shared/flutter/swiftpm/pin_conflicts.dart';
import 'package:xcross/src/shared/flutter/swiftpm/plugin_overlay.dart';
import 'package:xcross/src/shared/flutter/swiftpm/source_fallback_state.dart';

@internal
const String flutterFrameworkPackageName = 'FlutterFramework';
@internal
const String pluginsProductName = 'FlutterPluginsGenerated';

@internal
final class SwiftPmWorkspaceStager<T extends PlatformHostInterface> {
  SwiftPmWorkspaceStager({
    required this.artifactFileSystem,
    required this.checkout,
    required this.dependencyPreparation,
    required this.filesystem,
    required this.hostPolicy,
    required this.hostBuildServices,
    required this.manifest,
    required this.pluginOverlay,
    required this.runner,
    required this.sourceNormalizer,
    required this.checkoutManifestNormalizer,
  });
  final SwiftPmCheckoutManifestNormalizer<T> checkoutManifestNormalizer;
  final SwiftPmArtifactFileSystem artifactFileSystem;

  final SwiftPmCheckout<T> checkout;
  final SwiftPmDependencyPreparation<T> dependencyPreparation;
  final SwiftPmFilesystem<T> filesystem;
  final SwiftPmHostPolicy hostPolicy;
  final SwiftPmHostBuildServices<T> hostBuildServices;
  final SwiftPmManifest<T> manifest;
  final SwiftPmPluginOverlay<T> pluginOverlay;
  final ProcessRunner<T> runner;
  final SwiftPmHostSourceNormalizer sourceNormalizer;

  /// Writes the `FlutterFramework` and `Plugins` wrapper packages (manifests,
  /// registrant source, and the `Flutter.xcframework` link/copy) under
  /// [outputDir], without invoking `swift build`. Split out from [build] so
  /// the file-synthesis logic is testable without a Swift toolchain.
  Future<void> writeGeneratedPackages({
    required String outputDir,
    required List<IosPlugin> plugins,
    required String flutterXcframework,
    required IosDeploymentTarget deploymentTarget,
    bool verbose = false,
    bool? copyFlutterXcframework,
    Set<String> copyPluginPackages = const {},
    String? scratchPath,
    String? binaryArtifactStore,
    String? binaryArtifactFallback,
    bool swiftPmArtifactJunctionCapability = false,
    bool packageLocalArtifactJunctionCapability = false,
    bool sourceFallback = false,
    Map<String, String> podPackages = const {}, // studio: 046
  }) async {
    final packagesDir = p.join(outputDir, 'Packages');
    final frameworkDir = p.join(packagesDir, flutterFrameworkPackageName);
    final pluginsDir = p.join(outputDir, 'Plugins');

    await artifactFileSystem.directory(packagesDir).create(recursive: true);
    await writeFlutterFrameworkPackage(
      frameworkDir: frameworkDir,
      flutterXcframework: flutterXcframework,
      copyFlutterXcframework: copyFlutterXcframework,
    );

    final pluginTargets = {
      for (final plugin in plugins) plugin.name: plugin.swiftPackageDir,
    };
    // studio: 046 — stage every converted pod as an alias Packages/pod-<Pod>
    for (final entry in podPackages.entries) {
      final podName = entry.key.startsWith('pod-')
          ? entry.key.substring(4)
          : entry.key;
      final podAlias = p.join(packagesDir, 'pod-$podName');
      await filesystem.createDirectoryAlias(podAlias, entry.value);
      pluginTargets['pod-$podName'] = podAlias;
      pluginTargets[podName] = podAlias;
    }
    final fallbackState = sourceFallback
        ? await SwiftPmSourceFallbackState.read(artifactFileSystem, outputDir)
        : const SwiftPmSourceFallbackState();
    final pluginPackageDirs = <String, String>{};
    for (final plugin in plugins) {
      final packageAlias = p.join(packagesDir, plugin.name);
      pluginPackageDirs[plugin.name] = await pluginOverlay.stagePluginPackage(
        alias: packageAlias,
        target: plugin.swiftPackageDir,
        platformDir: plugin.platformDirectoryName,
        packageTargets: pluginTargets,
        copySources: copyPluginPackages.contains(plugin.name),
        fallbackSwiftModules: fallbackState.swiftModules,
        scratchPath: scratchPath,
        binaryArtifactStore: binaryArtifactStore,
        binaryArtifactFallback: binaryArtifactFallback,
        swiftPmArtifactJunctionCapability: swiftPmArtifactJunctionCapability,
        packageLocalArtifactJunctionCapability:
            packageLocalArtifactJunctionCapability,
      );
    }
    await checkPinConflicts(plugins, pluginPackageDirs, outputDir: outputDir);
    final packagesByDirectoryName = {
      for (final package in pluginPackageDirs.values)
        p.basename(package): package,
      // studio: 046 — include pod aliases for transitive rewrites
      for (final entry in podPackages.entries)
        p.basename(
          entry.key.startsWith('pod-') ? entry.key : 'pod-${entry.key}',
        ): p.join(
          packagesDir,
          entry.key.startsWith('pod-') ? entry.key : 'pod-${entry.key}',
        ),
    };
    for (final plugin in plugins) {
      if (!copyPluginPackages.contains(plugin.name)) continue;
      final stagedPackage = pluginPackageDirs[plugin.name]!;
      final manifestFile = artifactFileSystem.file(
        p.join(stagedPackage, 'Package.swift'),
      );
      var manifest = await manifestFile.readAsString();
      final original = manifest;
      for (final call in SwiftPmManifestLexer.swiftCalls(
        manifest,
        '.package',
      ).reversed) {
        final dependencyPath = SwiftPmManifestLexer.namedString(
          call.text,
          'path',
        );
        if (dependencyPath == null) continue;
        final dependencyName =
            SwiftPmManifestLexer.namedString(call.text, 'name') ??
            p.basename(dependencyPath);
        final sharedPackage = packagesByDirectoryName[dependencyName];
        if (sharedPackage == null || p.equals(dependencyPath, sharedPackage)) {
          continue;
        }
        final rewritten = call.text.replaceFirst(
          RegExp(r'path\s*:\s*"[^"]+"'),
          'path: "${SwiftPmFilesystem.swiftPath(sharedPackage)}"',
        );
        manifest = manifest.replaceRange(call.start, call.end, rewritten);
      }
      if (manifest != original) {
        await filesystem.writeStable(manifestFile.path, manifest);
      }
    }
    await writePluginsPackage(
      pluginsDir: pluginsDir,
      frameworkDir: frameworkDir,
      plugins: plugins,
      pluginPackageDirs: pluginPackageDirs,
      deploymentTarget: deploymentTarget,
      verbose: verbose,
    );
  }

  /// Stops before `swift package resolve` when the staged plugin manifests
  /// pin versions of one Swift package that no version satisfies (the
  /// firebase_messaging 17.0.0 / firebase_core 5.1.0 case), with a coded
  /// error naming the plugins to upgrade instead of SwiftPM's resolver
  /// output. The pins are left as they are.
  @visibleForTesting
  Future<void> checkPinConflicts(
    List<IosPlugin> plugins,
    Map<String, String> pluginPackageDirs, {
    String? outputDir,
  }) async {
    final manifests = <SwiftPmPluginManifest>[];
    for (final plugin in plugins) {
      final staged = pluginPackageDirs[plugin.name];
      if (staged == null) continue;
      final manifest = artifactFileSystem.file(p.join(staged, 'Package.swift'));
      if (!manifest.existsSync()) continue;
      manifests.add((
        plugin: plugin.name,
        version: await _pubspecVersion(plugin.packageRoot),
        manifest: await manifest.readAsString(),
      ));
    }
    // Also include converted pods and extra packages in pluginPackageDirs
    for (final entry in pluginPackageDirs.entries) {
      if (plugins.any((p) => p.name == entry.key)) continue;
      final manifest = artifactFileSystem.file(
        p.join(entry.value, 'Package.swift'),
      );
      if (!manifest.existsSync()) continue;
      manifests.add((
        plugin: entry.key,
        version: null,
        manifest: await manifest.readAsString(),
      ));
    }
    if (outputDir != null) {
      final packagesDir = artifactFileSystem.directory(
        p.join(outputDir, 'Packages'),
      );
      if (packagesDir.existsSync()) {
        for (final entity in packagesDir.listSync(followLinks: false)) {
          if (entity is Directory) {
            final dirName = p.basename(entity.path);
            if (!manifests.any((m) => m.plugin == dirName)) {
              final manifest = artifactFileSystem.file(
                p.join(entity.path, 'Package.swift'),
              );
              if (manifest.existsSync()) {
                manifests.add((
                  plugin: dirName,
                  version: null,
                  manifest: await manifest.readAsString(),
                ));
              }
            }
          }
        }
      }
    }
    if (SwiftPmPinConflicts.find(manifests) case final conflict?) {
      throw codedError(XcrossCodes.buildPluginPinConflict, conflict.message);
    }
  }

  Future<String?> _pubspecVersion(String packageRoot) async {
    final pubspec = artifactFileSystem.file(
      p.join(packageRoot, 'pubspec.yaml'),
    );
    if (!pubspec.existsSync()) return null;
    return _pubspecVersionLine.firstMatch(await pubspec.readAsString())?[1];
  }

  static final _pubspecVersionLine = RegExp(
    r'''^version:\s*['"]?([^\s'"#]+)''',
    multiLine: true,
  );

  Future<Map<String, Set<String>>> consumedProducts(String outputDir) async {
    final manifests = <String>[];
    final packages = artifactFileSystem.directory(
      p.join(outputDir, 'Packages'),
    );
    if (packages.existsSync()) {
      for (final entity in packages.listSync(recursive: true)) {
        if (entity is File && p.basename(entity.path) == 'Package.swift') {
          manifests.add(await entity.readAsString());
        }
      }
    }
    final state = await SwiftPmSourceFallbackState.read(
      artifactFileSystem,
      outputDir,
    );
    return SwiftPmManifestDependencies.mergeConsumedProducts(
      SwiftPmManifestDependencies.consumedProductsByIdentity(manifests),
      state.consumedProducts,
    );
  }

  Future<({Map<String, Set<String>> consumedProducts, bool swiftModules})>
  reconcileCheckoutFallbacks({
    required String outputDir,
    required String scratchPath,
    required Map<String, Set<String>> consumedProducts,
  }) async {
    final fallbacks = await checkoutManifestNormalizer
        .synthesizeCheckoutFallbacks(
          scratchPath,
          consumedProducts: consumedProducts,
        );
    final state = await SwiftPmSourceFallbackState.read(
      artifactFileSystem,
      outputDir,
    );
    final next = SwiftPmSourceFallbackState(
      consumedProducts: SwiftPmManifestDependencies.mergeConsumedProducts(
        state.consumedProducts,
        fallbacks.consumedProducts,
      ),
      swiftModules: fallbacks.swiftModules,
    );
    if (next.encode() != state.encode()) {
      await next.write(filesystem, outputDir);
    }
    return (
      consumedProducts: SwiftPmManifestDependencies.mergeConsumedProducts(
        consumedProducts,
        fallbacks.consumedProducts,
      ),
      swiftModules:
          jsonEncode(state.swiftModules) != jsonEncode(next.swiftModules),
    );
  }

  /// Writes `FlutterFramework/Package.swift` and links or copies the real
  /// [flutterXcframework]. Windows copies because creating symlinks commonly
  /// requires Developer Mode or elevation.
  Future<void> writeFlutterFrameworkPackage({
    required String frameworkDir,
    required String flutterXcframework,
    required bool? copyFlutterXcframework,
  }) async {
    await artifactFileSystem.directory(frameworkDir).create(recursive: true);
    await filesystem.writeStable(
      p.join(frameworkDir, 'Package.swift'),
      SwiftPmManifest.flutterFrameworkManifest(),
    );

    final frameworkPath = p.join(frameworkDir, 'Flutter.xcframework');
    await hostBuildServices.stageFlutterFramework(
      flutterXcframework,
      frameworkPath,
      copy: copyFlutterXcframework,
    );
  }

  /// Writes `Plugins/Package.swift` and the generated registrant source.
  Future<void> writePluginsPackage({
    required String pluginsDir,
    required String frameworkDir,
    required List<IosPlugin> plugins,
    required Map<String, String> pluginPackageDirs,
    required IosDeploymentTarget deploymentTarget,
    required bool verbose,
  }) async {
    final sourcesDir = p.join(pluginsDir, 'Sources', pluginsProductName);
    await artifactFileSystem.directory(sourcesDir).create(recursive: true);

    final moduleWarmup = hostPolicy.warmsImplicitModules;
    if (moduleWarmup) {
      await artifactFileSystem
          .directory(SwiftPmModuleWarmup.sourcesDir(pluginsDir))
          .create(recursive: true);
      // The module list comes from the resolved checkouts, which do not
      // exist yet. Seed the target with the modules every plugin imports so
      // the manifest stays valid; the build driver widens it once the plugin
      // graph is resolved.
      final seed = SwiftPmModuleWarmup.sourceFile(pluginsDir);
      if (!artifactFileSystem.file(seed).existsSync()) {
        await filesystem.writeStable(
          seed,
          SwiftPmModuleWarmup.source(SwiftPmModuleWarmup.baselineModules),
        );
      }
    }

    await filesystem.writeStable(
      p.join(pluginsDir, 'Package.swift'),
      SwiftPmManifest.pluginsManifest(
        plugins,
        frameworkDir,
        pluginPackageDirs: pluginPackageDirs,
        deploymentTarget: deploymentTarget,
        moduleWarmup: moduleWarmup,
      ),
    );

    await filesystem.writeStable(
      p.join(sourcesDir, 'GeneratedPluginRegistrant.swift'),
      manifest.registrantSource(
        plugins,
        verbose: verbose,
        stagedPackageDirs: pluginPackageDirs,
      ),
    );
  }
}

@internal
typedef SwiftPmSourceTransform =
    String Function(String content)? Function(String path);
