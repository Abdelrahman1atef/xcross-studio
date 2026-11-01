// studio: 007 — the app target's own Runner sources (AppDelegate, …).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/build/pbxproj.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';

/// Which executable a Flutter build ships as `Runner`.
@internal
enum RunnerMode {
  /// xcross's generic Objective-C runner (the default).
  shim,

  /// The project's own Runner target sources (`XCROSS_RUNNER=project`).
  project;

  /// Environment variable that opts into [project].
  static const environmentKey = 'XCROSS_RUNNER';

  static RunnerMode fromEnvironment(Map<String, String> environment) =>
      environment[environmentKey]?.trim().toLowerCase() == 'project'
      ? project
      : shim;
}

/// The application target's sources as Xcode would compile them, minus
/// `GeneratedPluginRegistrant.m` (xcross supplies its own implementation,
/// because plugins are built as one Swift package, not as CocoaPods).
@internal
@immutable
final class ProjectRunnerSources {
  const ProjectRunnerSources({
    required this.swift,
    required this.objc,
    required this.headerDirectories,
    required this.moduleName,
    required this.usesImplicitEngine,
    required this.registersPluginsAtLaunch,
    required this.sceneDelegateHasCode,
    this.bridgingHeader,
  });

  /// Reads the application target of `<projectRoot>/ios/*.xcodeproj`
  /// (Sources build phase plus Xcode 16 synchronized folders). Without a
  /// usable project file, every `.swift`/`.m`/`.mm` in `ios/Runner` is used.
  factory ProjectRunnerSources.discover(
    String projectRoot, {
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required PbxProjectReader projects,
  }) {
    final iosDir = paths.join(projectRoot, 'ios');
    final pbxprojPath = projects.findPbxproj(projectRoot);
    final project = pbxprojPath == null
        ? null
        : projects.parseFile(pbxprojPath);
    final target = project?.applicationTarget;

    var files = <String>[
      if (project != null && target != null) ...{
        ...project.buildPhaseFiles(target, 'PBXSourcesBuildPhase'),
        ...project
            .synchronizedFiles(target, fileSystem: fileSystem)
            .where(PbxProject.isTargetSource),
      },
    ];
    if (files.isEmpty) {
      final runner = fileSystem.directory(paths.join(iosDir, 'Runner'));
      if (runner.existsSync()) {
        files = [
          for (final entity in runner.listSync())
            if (PbxProject.isTargetSource(entity.path)) entity.path,
        ]..sort();
      }
    }
    files = [
      for (final file in files)
        if (fileSystem.file(file).existsSync() &&
            paths.basenameWithoutExtension(file) != _registrant)
          file,
    ];

    final swift = [
      for (final file in files)
        if (paths.extension(file) == '.swift') file,
    ];
    final objc = [
      for (final file in files)
        if (const {'.m', '.mm', '.c'}.contains(paths.extension(file))) file,
    ];

    final texts = {
      for (final file in [...swift, ...objc])
        file: fileSystem.file(file).readAsStringSync(),
    };
    bool anySource(RegExp pattern) =>
        texts.values.any((text) => pattern.hasMatch(text));

    return ProjectRunnerSources(
      swift: swift,
      objc: objc,
      headerDirectories: {
        for (final file in [...swift, ...objc]) paths.dirname(file),
      }.toList(),
      bridgingHeader: _bridgingHeader(
        iosDir,
        project == null || target == null
            ? null
            : project.buildSetting(target, 'SWIFT_OBJC_BRIDGING_HEADER'),
        fileSystem: fileSystem,
        paths: paths,
      ),
      moduleName: _moduleName(
        project == null || target == null
            ? null
            : switch (project.buildSetting(target, 'PRODUCT_MODULE_NAME')) {
                final String name when !name.contains(r'$') => name,
                _ => target.string('name'),
              },
      ),
      usesImplicitEngine: anySource(
        RegExp('didInitializeImplicitFlutterEngine'),
      ),
      registersPluginsAtLaunch: anySource(
        RegExp(
          r'GeneratedPluginRegistrant\.register\(\s*with:\s*self\s*\)|'
          r'\[\s*GeneratedPluginRegistrant\s+registerWithRegistry:\s*self\s*\]',
        ),
      ),
      sceneDelegateHasCode: texts.entries.any(
        (entry) =>
            paths.basenameWithoutExtension(entry.key) == 'SceneDelegate' &&
            !isEmptySceneDelegate(entry.value),
      ),
    );
  }

  /// `.swift` sources.
  final List<String> swift;

  /// `.m`, `.mm` and `.c` sources.
  final List<String> objc;

  /// Folders holding the sources (searched for their headers).
  final List<String> headerDirectories;

  /// `SWIFT_OBJC_BRIDGING_HEADER`, or `ios/Runner/Runner-Bridging-Header.h`.
  final String? bridgingHeader;

  /// Swift module name (`Runner`).
  final String moduleName;

  /// The app delegate registers plugins in `didInitializeImplicitFlutterEngine`
  /// (Flutter's UIScene template).
  final bool usesImplicitEngine;

  /// The app delegate registers plugins with `self` at launch (pre-UIScene
  /// template).
  final bool registersPluginsAtLaunch;

  /// The project's `SceneDelegate` has a non-empty body; xcross replaces it.
  final bool sceneDelegateHasCode;

  bool get isEmpty => swift.isEmpty && objc.isEmpty;

  /// A `main.swift` / `main.m` provides the entry point itself.
  bool get hasMainFile => [
    ...swift,
    ...objc,
  ].any((source) => p.basenameWithoutExtension(source) == 'main');

  static const _registrant = 'GeneratedPluginRegistrant';

  /// Whether [source] declares a `SceneDelegate` with nothing in it (the
  /// Flutter template), ignoring comments and imports.
  @visibleForTesting
  static bool isEmptySceneDelegate(String source) {
    final code = source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp('//[^\n]*'), '');
    return RegExp(
          r'class\s+SceneDelegate\s*:\s*FlutterSceneDelegate\s*\{\s*\}',
        ).hasMatch(code) ||
        RegExp(r'@implementation\s+SceneDelegate\s*@end').hasMatch(code);
  }

  static String? _bridgingHeader(
    String iosDir,
    String? setting, {
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
  }) {
    final candidates = <String>[
      if (setting != null)
        setting.replaceFirst(
          RegExp(r'^(\$\(SRCROOT\)|\$\{SRCROOT\}|\$\(PROJECT_DIR\))/'),
          '',
        ),
      'Runner/Runner-Bridging-Header.h',
    ];
    for (final candidate in candidates) {
      if (candidate.isEmpty || candidate.contains(r'$')) continue;
      final path = paths.isAbsolute(candidate)
          ? candidate
          : paths.normalize(paths.joinAll([iosDir, ...candidate.split('/')]));
      if (fileSystem.file(path).existsSync()) return path;
    }
    return null;
  }

  /// Xcode's module name for a target: non-identifier characters become `_`.
  static String _moduleName(String? name) {
    if (name == null || name.isEmpty || name.contains(r'$')) return 'Runner';
    final sanitized = name.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    return RegExp('^[0-9]').hasMatch(sanitized) ? '_$sanitized' : sanitized;
  }
}
