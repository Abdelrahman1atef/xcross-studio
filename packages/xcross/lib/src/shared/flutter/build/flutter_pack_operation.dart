import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart'; // studio: 002
import 'package:xcross/src/shared/flutter/build/flutter_packer.dart';
import 'package:xcross/src/shared/flutter/build/internal/swiftpm_workspace.dart';
import 'package:xcross/src/shared/flutter/flutter_build_runtime.dart';
import 'package:xcross/src/shared/flutter/models/flutter/flutter_build_options.dart';
import 'package:xcross/src/shared/models/pack_result.dart';
import 'package:xcross/src/shared/toolchain/path_linker_guard.dart'; // studio: 002

@internal
abstract final class FlutterPackOperation {
  static Future<PackResult> pack<T extends PlatformHostInterface>({
    required FlutterBuildRuntime<T> runtime,
    required FlutterBuildOptions options,
    required String projectRoot,
  }) async {
    options.validate(
      supportsPrecompiledModes: runtime.policy.supportsPrecompiledModes,
    );
    final bundleId = runtime.bundleIds.resolve(projectRoot);
    final workspace = SwiftPmWorkspace.forProject(
      projectRoot,
      policy: runtime.policy,
      environment: runtime.runner.effectiveEnvironment,
    );
    final packer = FlutterPacker(
      runtime: runtime,
      projectRoot: projectRoot,
      bundleId: bundleId,
      options: options,
      artifactJunctionCapabilityResolver: () => runtime.plugins
          .resolveArtifactJunctionCapabilities(workspace: workspace),
    );
    // studio: 002 — say which version is built and where it came from, and
    // warn once about configured PATH entries whose linker cannot link iOS.
    runtime.runner.log.logInfo('Version', packer.request.versions.describe());
    for (final (entry, problem) in await PathLinkerGuard(
      runtime.toolchain,
    ).configuredProblems(runtime.configuredPath)) {
      runtime.warnings.warn(
        XcrossCodes.toolchainPathLinkerUnusable,
        subject: entry,
        message: '$entry: ld64.lld $problem',
      );
    }
    final bundleDir = runtime.host.fileSystem.directory(
      p.join(packer.outputDirectory, '${packer.appName}.app'),
    );
    if (bundleDir.existsSync()) await bundleDir.delete(recursive: true);
    final ({String appPath, List<String> dartDefines}) built;
    try {
      built = await packer.pack();
    } finally {
      // studio: 002 — one summary line for all coded warnings of this build.
      if (runtime.warnings.takeSummary() case final summary?) {
        runtime.runner.log.logWarn(summary);
      }
    }
    // studio: 012 — the built .app for event consumers (the GUI).
    runtime.runner.log.events?.event('artifact', {
      'kind': 'app',
      'path': built.appPath,
    });
    return PackResult(
      outputPath: built.appPath,
      bundleId: bundleId,
      projectRoot: projectRoot,
      dartDefines: built.dartDefines,
    );
  }
}
