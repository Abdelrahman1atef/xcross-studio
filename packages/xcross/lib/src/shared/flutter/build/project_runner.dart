// studio: 007 — link the project's own Runner sources (AppDelegate, …)
// instead of the generic runner shim, when XCROSS_RUNNER=project.
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:darwin_sdk_kit/shared/sdk/darwin_sdk.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/diagnostics/build_warnings.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/build/ios_deployment_target.dart';
import 'package:xcross/src/shared/flutter/build/project_runner_sources.dart';
import 'package:xcross/src/shared/flutter/constants.dart';
import 'package:xcross/src/shared/flutter/errors.dart';
import 'package:xcross/src/shared/flutter/flutter_build_runtime.dart';

/// Builds the Runner from [ProjectRunnerSources] and returns its path.
@internal
typedef ProjectRunnerCompile =
    Future<String> Function(ProjectRunnerSources sources);

/// Decides whether a build uses the project's Runner and never lets that
/// choice fail the build: any problem falls back to the generic runner with
/// a coded warning.
@internal
final class ProjectRunner {
  ProjectRunner({
    required this.environment,
    required this.discover,
    required this.compile,
    required this.warnings,
    required this.log,
  });

  /// The coordinator for a real build of the project at [projectRoot].
  static ProjectRunner forRuntime<T extends PlatformHostInterface>(
    FlutterBuildRuntime<T> runtime, {
    required String projectRoot,
    required ProjectRunnerCompile compile,
  }) => ProjectRunner(
    environment: runtime.host.environment.values,
    discover: () => ProjectRunnerSources.discover(
      projectRoot,
      fileSystem: runtime.host.fileSystem,
      paths: runtime.host.paths.context,
      projects: runtime.projects,
    ),
    compile: compile,
    warnings: runtime.warnings,
    log: runtime.runner.log,
  );

  final Map<String, String> environment;
  final ProjectRunnerSources Function() discover;
  final ProjectRunnerCompile compile;
  final BuildWarnings warnings;
  final Log log;

  static const _subject = 'Runner';

  /// The Runner linked from the project's sources, or null when the generic
  /// runner should be used (the default, or after a coded warning).
  Future<String?> build() async {
    if (RunnerMode.fromEnvironment(environment) != RunnerMode.project) {
      return null;
    }
    final ProjectRunnerSources sources;
    try {
      sources = discover();
    } on Exception catch (error) {
      _failed('its sources could not be read ($error)');
      return null;
    }
    if (sources.isEmpty) {
      _failed('the app target has no Swift or Objective-C sources');
      return null;
    }
    if (sources.registersPluginsAtLaunch && !sources.usesImplicitEngine) {
      warnings.warn(
        XcrossCodes.buildRunnerLegacyRegistration,
        subject: _subject,
        message:
            'AppDelegate registers plugins with `self` at launch, before any '
            'Flutter engine exists; xcross registers them on the window '
            "scene's engine instead.",
      );
    }
    if (sources.sceneDelegateHasCode) {
      warnings.warn(
        XcrossCodes.buildRunnerSceneDelegateReplaced,
        subject: _subject,
        message:
            "SceneDelegate has code, but xcross's scene delegate creates the "
            'Flutter window (Main.storyboard cannot be compiled), so that '
            'code does not run.',
      );
    }
    log.logStatus(
      'Runner: compiling the project sources '
      '(${sources.swift.length} Swift, ${sources.objc.length} Objective-C)',
    );
    try {
      return await compile(sources);
    } on Exception catch (error) {
      final errors = firstErrors('$error');
      _failed(
        'they did not build'
        '${errors.isEmpty ? '' : ':\n    ${errors.join('\n    ')}'}',
      );
      return null;
    }
  }

  void _failed(String reason) => warnings.warn(
    XcrossCodes.buildRunnerProjectFailed,
    subject: _subject,
    message:
        "The app's own Runner sources were not used: $reason. The app is "
        "built with xcross's generic runner, so code in AppDelegate does not "
        'run.',
  );

  /// The compiler's first error lines (or the first lines of [output] when
  /// none is marked `error:`), shortened for a warning.
  @visibleForTesting
  static List<String> firstErrors(String output, {int limit = 3}) {
    final lines = [
      for (final line in output.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final marked = lines.where((line) => line.contains('error:')).toList();
    final shown = marked.isEmpty ? lines : marked;
    return shown
        .take(limit)
        .map(
          (line) => line.length > 200 ? '${line.substring(0, 197)}...' : line,
        )
        .toList();
  }
}

/// Compiles and links the project's Runner sources for iOS:
///
/// - Objective-C sources (and xcross's support file) with clang;
/// - with Swift sources: `swiftc` compiles them and links everything, the
///   same toolchain the app-extension builder uses;
/// - Objective-C only: ld64.lld links, like the runner shim.
@internal
final class ProjectRunnerBuilder<T extends PlatformHostInterface> {
  ProjectRunnerBuilder(this.runtime);

  final FlutterBuildRuntime<T> runtime;

  /// `UISceneDelegateClassName` for an app with a project runner.
  static const sceneDelegateClass = 'XcrossSceneDelegate';

  Future<String> build({
    required ProjectRunnerSources sources,
    required DarwinSdk sdk,
    required String flutterXcframework,
    required String outputDir,
    required IosDeploymentTarget deploymentTarget,
    String? pluginsLibrary,
    String? pluginModulesDir,
    List<String> nativeAssetFrameworks = const [],
  }) async {
    final files = runtime.host.fileSystem;
    final iosSdk = runtime.sdkRepository.iosSdk(
      sdk,
      target: deploymentTarget.platform,
    );
    final flutterSlice = runtime.policy.selectEngineSlice(flutterXcframework);
    final subframeworks = p.join(iosSdk, 'System', 'Library', 'SubFrameworks');
    final sdkVersion = _sdkVersion(iosSdk) ?? '26.5';

    final out = files.directory(outputDir);
    if (out.existsSync()) await out.delete(recursive: true);
    final supportDir = p.join(outputDir, 'support');
    final objectDir = p.join(outputDir, 'obj');
    await files.directory(supportDir).create(recursive: true);
    await files.directory(objectDir).create(recursive: true);
    await files
        .file(p.join(supportDir, 'GeneratedPluginRegistrant.h'))
        .writeAsString(registrantHeader);
    final supportSourcePath = p.join(supportDir, 'XcrossRunnerSupport.m');
    await files
        .file(supportSourcePath)
        .writeAsString(supportSource(hasPlugins: pluginsLibrary != null));
    final includeDirectories = [...sources.headerDirectories, supportDir];

    final clang = await runtime.toolchain.resolveDarwinClang(iosSdk);
    final objects = <String>[];
    final objcSources = [...sources.objc, supportSourcePath];
    for (var i = 0; i < objcSources.length; i++) {
      final object = p.join(
        objectDir,
        '${i}_${p.basenameWithoutExtension(objcSources[i])}.o',
      );
      await _run(
        clang,
        objcCompileArguments(
          sourcePath: objcSources[i],
          objectPath: object,
          iosSdk: iosSdk,
          subframeworks: subframeworks,
          flutterSlice: flutterSlice,
          deploymentTarget: deploymentTarget,
          includeDirectories: includeDirectories,
        ),
        label: 'clang',
      );
      objects.add(object);
    }

    final outputPath = p.join(outputDir, 'Runner');
    final ld64lld = await runtime.toolchain.resolveLd64Lld();
    if (sources.swift.isNotEmpty) {
      final resourceDir = _swiftResourceDir(sdk);
      final moduleCache = p.join(outputDir, 'module-cache');
      await files.directory(moduleCache).create(recursive: true);
      await _run(
        await _swiftc(),
        swiftArguments(
          iosSdk: iosSdk,
          resourceDir: resourceDir,
          clangBuiltins: _existingDirectory(
            p.join(resourceDir, 'clang', 'include'),
            marker: 'stdarg.h',
          ),
          compilerRtIos: _compilerRtIos(sdk.bundle),
          sources: sources.swift,
          objects: objects,
          outputPath: outputPath,
          deploymentTarget: deploymentTarget,
          flutterSlice: flutterSlice,
          moduleCache: moduleCache,
          moduleName: sources.moduleName,
          ld64lld: ld64lld,
          sdkVersion: sdkVersion,
          includeDirectories: includeDirectories,
          bridgingHeader: sources.bridgingHeader,
          parseAsLibrary: !sources.hasMainFile,
          pluginsLibrary: pluginsLibrary,
          pluginModulesDir: pluginModulesDir,
          nativeAssetFrameworks: nativeAssetFrameworks,
        ),
        label: 'swiftc',
      );
    } else {
      if (!sources.hasMainFile) {
        throw FlutterBuildError(
          'error: the Objective-C Runner has no main.m (UIApplicationMain).',
        );
      }
      await _run(
        ld64lld,
        objcLinkArguments(
          objects: objects,
          outputPath: outputPath,
          iosSdk: iosSdk,
          flutterSlice: flutterSlice,
          subframeworks: subframeworks,
          sdkVersion: sdkVersion,
          deploymentTarget: deploymentTarget,
          pluginsLibrary: pluginsLibrary,
          nativeAssetFrameworks: nativeAssetFrameworks,
        ),
        label: 'ld64.lld',
      );
    }

    if (!files.file(outputPath).existsSync()) {
      throw FlutterBuildError('error: the linker did not produce $outputPath');
    }
    runtime.runner.makeExecutable(outputPath);
    return outputPath;
  }

  /// Captured (not streamed), so a failure's message carries the compiler
  /// errors that [ProjectRunner] puts in its warning.
  Future<void> _run(
    String executable,
    List<String> arguments, {
    required String label,
  }) => runtime.runner.runChecked(executable, arguments, label: label);

  Future<String> _swiftc() async {
    try {
      return await runtime.runner.locateTool('swiftc');
    } on Object {
      throw FlutterBuildError(
        'error: swiftc not found on PATH; the Swift toolchain is needed to '
        'compile AppDelegate.swift (run `xcross setup`).',
      );
    }
  }

  /// clang arguments for one Objective-C source of the Runner target.
  @visibleForTesting
  static List<String> objcCompileArguments({
    required String sourcePath,
    required String objectPath,
    required String iosSdk,
    required String subframeworks,
    required String flutterSlice,
    required IosDeploymentTarget deploymentTarget,
    required List<String> includeDirectories,
  }) => [
    '-target',
    deploymentTarget.buildTriple,
    '-isysroot',
    iosSdk,
    '-F',
    subframeworks,
    '-F',
    flutterSlice,
    '-I',
    p.join(flutterSlice, 'Flutter.framework', 'Headers'),
    for (final directory in includeDirectories) ...['-I', directory],
    '-fobjc-arc',
    deploymentTarget.minimumVersionFlag,
    '-c',
    sourcePath,
    '-o',
    objectPath,
  ];

  /// swiftc arguments that compile the Swift sources and link the Runner
  /// executable together with the Objective-C [objects].
  @visibleForTesting
  static List<String> swiftArguments({
    required String iosSdk,
    required String resourceDir,
    required List<String> sources,
    required List<String> objects,
    required String outputPath,
    required IosDeploymentTarget deploymentTarget,
    required String flutterSlice,
    required String moduleCache,
    required String moduleName,
    required String ld64lld,
    required String sdkVersion,
    required List<String> includeDirectories,
    String? bridgingHeader,
    bool parseAsLibrary = true,
    String? clangBuiltins,
    String? compilerRtIos,
    String? pluginsLibrary,
    String? pluginModulesDir,
    List<String> nativeAssetFrameworks = const [],
  }) => [
    '-sdk',
    iosSdk,
    '-target',
    deploymentTarget.buildTriple,
    // Classes are `Runner.AppDelegate` at runtime, as Xcode builds them.
    '-module-name',
    moduleName,
    // The Darwin SDK's own Swift resources (see AppExtensionBuilder).
    '-resource-dir',
    resourceDir,
    // `@main` / `@UIApplicationMain` provide the entry point; a main.swift
    // is top-level code instead.
    if (parseAsLibrary) '-parse-as-library',
    '-module-cache-path',
    moduleCache,
    '-use-ld=$ld64lld',
    '-Xfrontend',
    '-enable-cross-import-overlays',
    '-Xfrontend',
    '-disable-modules-validate-system-headers',
    '-F',
    flutterSlice,
    if (pluginModulesDir != null) ...['-I', pluginModulesDir],
    if (bridgingHeader != null) ...['-import-objc-header', bridgingHeader],
    '-Xcc',
    '-isysroot',
    '-Xcc',
    iosSdk,
    if (clangBuiltins != null) ...['-Xcc', '-isystem', '-Xcc', clangBuiltins],
    for (final directory in includeDirectories) ...['-Xcc', '-I$directory'],
    '-framework',
    'Flutter',
    '-framework',
    'Foundation',
    '-framework',
    'UIKit',
    '-Xlinker',
    '-arch',
    '-Xlinker',
    'arm64',
    '-Xlinker',
    '-platform_version',
    '-Xlinker',
    deploymentTarget.linkerPlatform,
    '-Xlinker',
    deploymentTarget.version,
    '-Xlinker',
    sdkVersion,
    '-Xlinker',
    '-rpath',
    '-Xlinker',
    '@executable_path/Frameworks',
    for (final framework in nativeAssetFrameworks) ...[
      '-Xlinker',
      '-F',
      '-Xlinker',
      p.dirname(framework),
      '-Xlinker',
      '-needed_framework',
      '-Xlinker',
      p.basenameWithoutExtension(framework),
    ],
    if (compilerRtIos != null) ...['-Xlinker', compilerRtIos],
    if (pluginsLibrary != null) ...['-Xlinker', pluginsLibrary],
    ...objects,
    ...sources,
    '-o',
    outputPath,
  ];

  /// ld64.lld arguments for an Objective-C-only Runner (as the shim links).
  @visibleForTesting
  static List<String> objcLinkArguments({
    required List<String> objects,
    required String outputPath,
    required String iosSdk,
    required String flutterSlice,
    required String subframeworks,
    required String sdkVersion,
    required IosDeploymentTarget deploymentTarget,
    String? pluginsLibrary,
    List<String> nativeAssetFrameworks = const [],
  }) => [
    '-arch',
    'arm64',
    '-platform_version',
    deploymentTarget.linkerPlatform,
    deploymentTarget.version,
    sdkVersion,
    '-syslibroot',
    iosSdk,
    '-o',
    outputPath,
    ...objects,
    ?pluginsLibrary,
    '-F',
    flutterSlice,
    '-F',
    p.join(iosSdk, 'System', 'Library', 'Frameworks'),
    '-F',
    subframeworks,
    '-framework',
    'Flutter',
    for (final framework in nativeAssetFrameworks) ...[
      '-F',
      p.dirname(framework),
      '-needed_framework',
      p.basenameWithoutExtension(framework),
    ],
    '-framework',
    'UIKit',
    '-framework',
    'Foundation',
    '-lobjc',
    '-lc',
    '-rpath',
    '@executable_path/Frameworks',
  ];

  /// Same interface as Flutter's generated header, for projects whose
  /// `ios/Runner/GeneratedPluginRegistrant.h` is missing.
  static const registrantHeader = '''
// Generated by xcross: same interface as Flutter's GeneratedPluginRegistrant.h.
#ifndef GeneratedPluginRegistrant_h
#define GeneratedPluginRegistrant_h

#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface GeneratedPluginRegistrant : NSObject
+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry;
@end

NS_ASSUME_NONNULL_END
#endif /* GeneratedPluginRegistrant_h */
''';

  /// xcross's half of the Runner:
  ///
  /// - `GeneratedPluginRegistrant` forwards to the registrant exported by the
  ///   plugins library (plugins are one Swift package here, not CocoaPods,
  ///   so Flutter's `GeneratedPluginRegistrant.m` cannot be compiled);
  /// - `XcrossSceneDelegate` creates the Flutter window, which the template
  ///   gets from `Main.storyboard` (storyboards cannot be compiled without
  ///   Xcode). Pre-UIScene app delegates get their plugins registered on the
  ///   scene's engine.
  @visibleForTesting
  static String supportSource({required bool hasPlugins}) =>
      '''
// Generated by xcross (XCROSS_RUNNER=project).
#import <UIKit/UIKit.h>
#import <Flutter/Flutter.h>
#import "GeneratedPluginRegistrant.h"

${hasPlugins ? 'extern void ${GeneratedPluginsConstants.registrantSymbol}(NSObject<FlutterPluginRegistry>* registry);\n' : ''}
@implementation GeneratedPluginRegistrant
+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
${hasPlugins ? '  ${GeneratedPluginsConstants.registrantSymbol}(registry);\n' : ''}}
@end

@interface $sceneDelegateClass : FlutterSceneDelegate
@end

@implementation $sceneDelegateClass
- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions {
  if (![scene isKindOfClass:[UIWindowScene class]]) return;
  UIWindowScene* windowScene = (UIWindowScene*)scene;
  FlutterViewController* flutterViewController = [[FlutterViewController alloc] initWithProject:nil nibName:nil bundle:nil];
  id<UIApplicationDelegate> appDelegate = UIApplication.sharedApplication.delegate;
  if (![appDelegate conformsToProtocol:@protocol(FlutterImplicitEngineDelegate)]) {
    [GeneratedPluginRegistrant registerWithRegistry:flutterViewController.engine];
  }
  UIWindow* window = [[UIWindow alloc] initWithWindowScene:windowScene];
  window.rootViewController = flutterViewController;
  self.window = window;
  [window makeKeyAndVisible];
  [super scene:scene willConnectToSession:session options:connectionOptions];
}
@end
''';

  /// [plistXml] with every `UISceneDelegateClassName` set to [className].
  static String withSceneDelegate(String plistXml, String className) =>
      plistXml.replaceAllMapped(
        RegExp(
          r'(<key>UISceneDelegateClassName</key>\s*<string>)[^<]*(</string>)',
        ),
        (match) => '${match.group(1)}$className${match.group(2)}',
      );

  static String _swiftResourceDir(DarwinSdk sdk) => p.join(
    sdk.bundle,
    'Developer',
    'Toolchains',
    'XcodeDefault.xctoolchain',
    'usr',
    'lib',
    'swift',
  );

  String? _existingDirectory(String directory, {required String marker}) =>
      runtime.host.fileSystem.file(p.join(directory, marker)).existsSync()
      ? directory
      : null;

  /// `libclang_rt.ios.a` (or the simulator variant) from the Darwin SDK.
  String? _compilerRtIos(String darwinSdkBundle) {
    final clang = runtime.host.fileSystem.directory(
      p.join(
        darwinSdkBundle,
        'Developer',
        'Toolchains',
        'XcodeDefault.xctoolchain',
        'usr',
        'lib',
        'clang',
      ),
    );
    if (!clang.existsSync()) return null;
    final versions = clang.listSync().map((entry) => entry.path).toList()
      ..sort((a, b) => b.compareTo(a));
    for (final version in versions) {
      final candidate = p.join(
        version,
        'lib',
        'darwin',
        runtime.policy.sanitizerRuntimeLibrary,
      );
      if (runtime.host.fileSystem.file(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static String? _sdkVersion(String sdkPath) {
    final name = p.basenameWithoutExtension(sdkPath);
    final match = RegExp(r'^iPhone(?:OS|Simulator)([0-9.]+)$').firstMatch(name);
    final version = match?.group(1) ?? '';
    return version.isEmpty ? null : version;
  }
}
