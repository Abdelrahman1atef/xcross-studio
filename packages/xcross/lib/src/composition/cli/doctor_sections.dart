import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/composition/flutter/flutter_sdk_services.dart'; // studio: 014
import 'package:xcross/src/composition/flutter/ios_gen_snapshot.dart';
import 'package:xcross/src/composition/ios_target.dart';
import 'package:xcross/src/shared/cli/basic/doctor_environment_checks.dart';
import 'package:xcross/src/shared/cli/basic/doctor_models.dart';
import 'package:xcross/src/shared/compose/kmp_project_detector.dart';
import 'package:xcross/src/shared/compose/toolchain/compose_toolchain_resolver.dart';
import 'package:xcross/src/shared/flutter/gen_snapshot/ios_gen_snapshot_mode.dart';
import 'package:xcross/src/shared/flutter/gen_snapshot/ios_gen_snapshot_resolver.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_mode.dart';
import 'package:xcross/src/shared/flutter/project/push_readiness.dart'; // studio: 016
import 'package:xcross/src/shared/flutter/sdk/ios_compiler_catalog.dart'; // studio: 014
import 'package:xcross/src/shared/packages/package_config_resolver.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';
import 'package:xcross/src/target/shared/runtime/build_features.dart';

/// The read-only checks behind `xcross flutter doctor` and
/// `xcross compose doctor`, grouped so each framework examines only what its
/// own build and run actually need.
@internal
final class DoctorSections<T extends PlatformHostInterface> {
  DoctorSections(this.runtime, {required this.environment, String? projectRoot})
    : projectRoot = projectRoot ?? runtime.host.paths.context.current,
      features = composePhysicalFeatures(runtime),
      packageConfigs = PackageConfigResolver(
        fileSystem: runtime.host.fileSystem,
        paths: runtime.host.paths.context,
      );

  final XcrossRuntime<T> runtime;
  final DoctorEnvironmentChecks<T> environment;
  final String projectRoot;
  final XcrossBuildFeatures<T> features;
  final PackageConfigResolver packageConfigs;

  List<DoctorSection> get flutter => [
    DoctorSection('Flutter project', flutterProject),
    // studio: 016 — only for a project that wants push.
    if (_push case final push when push.applies)
      DoctorSection(PushReadiness.section, () async => push.checks()),
    DoctorSection('iOS toolchain', environment.flutterToolchain),
    DoctorSection('Deployment', environment.deployment),
  ];

  // studio: 016
  late final PushReadiness _push = PushReadiness(
    fileSystem: runtime.host.fileSystem,
    paths: runtime.host.paths.context,
    projectRoot: projectRoot,
    environment: runtime.runner.effectiveEnvironment,
  );

  List<DoctorSection> get compose => [
    DoctorSection('Compose project', composeProject),
    DoctorSection('Compose toolchain', composeToolchain),
    DoctorSection('Deployment', environment.deployment),
  ];

  bool _exists(String name) => runtime.host.fileSystem
      .file(runtime.host.paths.context.join(projectRoot, name))
      .existsSync();

  /// The Flutter SDK is checked even outside a project: it is the one
  /// project-level requirement that does not depend on having one.
  Future<List<DoctorCheck>> flutterProject() async {
    if (!_exists('pubspec.yaml')) {
      return [
        const DoctorCheck.warning(
          'Project',
          'No pubspec.yaml in the current directory.',
        ),
        await _flutterSdk(),
        // studio: 014 — the compiler depends on the Flutter, not the project.
        ...await _aotCompilers(),
      ];
    }
    final project = _flutterPubspec();
    if (project.status == DoctorStatus.failure) {
      return [project, await _flutterSdk()];
    }
    return [
      project,
      _flutterEntrypoint(),
      await _flutterSdk(),
      await _flutterPackages(),
      _flutterIosProject(), // studio: 032
      ...await _aotCompilers(),
    ];
  }

  /// Whether release and profile builds will find an iOS AOT compiler.
  ///
  /// Debug builds never need one, so a missing compiler is a warning, and a
  /// failed network check is reported without failing the doctor.
  Future<List<DoctorCheck>> _aotCompilers() async {
    final String flutterRoot;
    try {
      flutterRoot = await features.flutterRuntime.resolveFlutterRoot(
        projectRoot: projectRoot,
      );
    } on Object {
      return const [];
    }
    final resolver = composeIosGenSnapshotResolver(
      runner: runtime.runner,
      downloader: runtime.downloader,
      createHttpClient: runtime.createHttpClient,
      config: runtime.config,
    );
    final checks = <DoctorCheck>[];
    for (final mode in IosGenSnapshotMode.values) {
      final label = 'AOT compiler (${mode.name})';
      final IosGenSnapshotAvailability found;
      try {
        found = await resolver.availability(
          flutterRoot: flutterRoot,
          engineDirectory: features.flutterRuntime
              .engineCache(flutterRoot, mode: FlutterBuildMode.of(mode))
              .engineDirectory,
          mode: mode,
        );
      } on Object catch (error) {
        checks.add(DoctorCheck.warning(label, '$error'));
        continue;
      }
      checks.add(switch (found.source) {
        IosGenSnapshotSource.flutterSdk => DoctorCheck.success(
          label,
          'Shipped with the Flutter engine',
          path: found.path,
        ),
        IosGenSnapshotSource.cache => DoctorCheck.success(
          label,
          'Cached',
          path: found.path,
        ),
        IosGenSnapshotSource.pinned => DoctorCheck.success(
          label,
          'Pinned in xcross config',
          path: found.path,
        ),
        IosGenSnapshotSource.download => DoctorCheck.success(
          label,
          'Published; downloaded on the first build '
          '(`xcross flutter precache` fetches it now)',
        ),
        null when found.unknown => DoctorCheck.warning(
          label,
          found.detail ?? 'Unavailable',
        ),
        // studio: 014 — a confirmed missing release compiler blocks iPhone
        // release builds (the only kind iOS 15/16 run): ✗ with the fix.
        null => _missingCompiler(
          label,
          mode,
          found,
          await _suggestion(found.release?.version),
        ),
      });
    }
    return checks;
  }

  // studio: 014
  DoctorCheck _missingCompiler(
    String label,
    IosGenSnapshotMode mode,
    IosGenSnapshotAvailability found,
    String? suggestion,
  ) {
    final version = found.release?.version;
    final message =
        '${version == null ? 'This Flutter' : 'Flutter $version'} has no '
        'published iOS ${mode.name} compiler for this computer'
        '${suggestion == null ? '' : '; newest with one: $suggestion'}. '
        'Fix: `xcross flutter sdk auto` (your own Flutter is not changed).';
    return mode == IosGenSnapshotMode.release
        ? DoctorCheck.failure(label, message)
        : DoctorCheck.warning(label, message);
  }

  // studio: 014
  Future<String?> _suggestion(String? current) async {
    if (current == null) return null;
    try {
      final catalog = await composeIosCompilerCatalog(
        runner: runtime.runner,
        createHttpClient: runtime.createHttpClient,
        platform: composeIosGenSnapshotHost(runtime.host).prebuiltPlatform,
      ).load();
      return suggestFlutterSdk(current, catalog.versions)?.version;
    } on Object {
      return null;
    }
  }

  DoctorCheck _flutterPubspec() {
    try {
      return DoctorCheck.success(
        'Project',
        features.flutterRuntime.pubspecs.loadSync(projectRoot).name,
      );
    } on Object catch (error) {
      return DoctorCheck.failure('Project', '$error');
    }
  }

  DoctorCheck _flutterEntrypoint() {
    final entrypoint = runtime.host.fileSystem.file(
      runtime.host.paths.context.join(projectRoot, 'lib', 'main.dart'),
    );
    return entrypoint.existsSync()
        ? DoctorCheck.success('Entrypoint', 'Found', path: entrypoint.path)
        : const DoctorCheck.failure(
            'Entrypoint',
            'lib/main.dart does not exist.',
          );
  }

  Future<DoctorCheck> _flutterSdk() async {
    try {
      final flutterRoot = await features.flutterRuntime.resolveFlutterRoot(
        projectRoot: projectRoot,
      );
      return DoctorCheck.success('Flutter SDK', 'Found', path: flutterRoot);
    } on Object catch (error) {
      return DoctorCheck.failure('Flutter SDK', '$error');
    }
  }

  /// studio: 032 - whether the project has what an iOS build starts from; the
  /// fix for either gap is `xcross ios prepare`, not a Mac.
  DoctorCheck _flutterIosProject() {
    final paths = runtime.host.paths.context;
    final ios = paths.join(projectRoot, 'ios');
    final hasProject =
        runtime.host.fileSystem
            .file(paths.join(ios, 'Runner.xcodeproj', 'project.pbxproj'))
            .existsSync() ||
        runtime.host.fileSystem
            .file(paths.join(ios, 'Runner', 'Info.plist'))
            .existsSync();
    if (!hasProject) {
      return const DoctorCheck.warning(
        'iOS project',
        'No ios/ Runner project. Run: flutter create --platforms=ios .',
      );
    }
    if (!_exists('.flutter-plugins-dependencies')) {
      return const DoctorCheck.warning(
        'iOS project',
        'No plugin list yet. Run: xcross ios prepare',
      );
    }
    return const DoctorCheck.success(
      'iOS project',
      'Ready. No pod install needed; xcross ios prepare lists each plugin.',
    );
  }

  Future<DoctorCheck> _flutterPackages() async {
    final packageConfig = await packageConfigs.find(projectRoot);
    return packageConfig == null
        ? const DoctorCheck.warning(
            'Packages',
            'No package_config.json; `flutter pub get` will be required.',
          )
        : DoctorCheck.success('Packages', 'Resolved', path: packageConfig);
  }

  Future<List<DoctorCheck>> composeProject() async {
    if (!_exists('settings.gradle.kts') && !_exists('settings.gradle')) {
      return const [
        DoctorCheck.warning(
          'Project',
          'No settings.gradle.kts or settings.gradle in the current '
              'directory.',
        ),
      ];
    }
    try {
      final project = KmpProjectDetector(
        files: runtime.host.fileSystem,
        log: runtime.log,
        root: projectRoot,
      ).detect();
      return [DoctorCheck.success('Project', project.moduleName)];
    } on Object catch (error) {
      return [DoctorCheck.failure('Project', '$error')];
    }
  }

  /// One row per tool the Compose build resolves. The Darwin SDK and linker
  /// rows reuse the shared iOS checks once resolved, so a stale SDK or a
  /// defective `ld64.lld` reads the same as it does for Flutter.
  Future<List<DoctorCheck>> composeToolchain() async {
    final requirements = await features.composeResolver.requirements(
      environment: runtime.runner.effectiveEnvironment,
      projectRoot: projectRoot,
    );
    return [
      environment.hostSupport(),
      for (final requirement in requirements)
        await _composeRequirement(requirement),
    ];
  }

  Future<DoctorCheck> _composeRequirement(ComposeRequirement requirement) {
    final name = requirement.name;
    if (requirement.problem case final problem?) {
      // `compose build` downloads Kotlin/Native on demand, so its absence
      // only costs time on the first build.
      return Future.value(
        name == ComposeRequirement.kotlinNative
            ? DoctorCheck.warning(
                name,
                'Not installed. The first build downloads it, or run '
                '`xcross compose setup`.',
              )
            : DoctorCheck.failure(name, problem),
      );
    }
    return switch (name) {
      ComposeRequirement.darwinSdk => environment.darwinSdk(),
      ComposeRequirement.ld64Lld => environment.iosLinker(),
      _ => Future.value(
        DoctorCheck.success(name, 'Found', path: requirement.path),
      ),
    };
  }
}
