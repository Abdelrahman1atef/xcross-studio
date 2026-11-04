import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/host/windows/flutter/swiftpm/damaged_repositories.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugin_package.dart';
import 'package:xcross/src/shared/flutter/swiftpm/binary_recovery.dart';
import 'package:xcross/src/shared/flutter/swiftpm/checkout.dart';
import 'package:xcross/src/shared/flutter/swiftpm/dependency_preparation.dart';
import 'package:xcross/src/shared/flutter/swiftpm/extracted_artifact_recovery.dart';
import 'package:xcross/src/shared/flutter/swiftpm/network_retry.dart';
import 'package:xcross/src/shared/flutter/swiftpm/package_metadata.dart';
import 'package:xcross/src/shared/flutter/swiftpm/process_policy.dart';

@internal
final class WindowsSwiftPmDependencyPreparation<T extends PlatformHostInterface>
    implements SwiftPmDependencyPreparation<T> {
  WindowsSwiftPmDependencyPreparation({
    required this.runner,
    required this.checkout,
    required this.metadata,
    required this.processPolicy,
    required this.networkRetry,
    required this.binaryRecovery,
    required this.extractedArtifacts,
  });
  final ProcessRunner<T> runner;
  final SwiftPmCheckout<T> checkout;
  final SwiftPmPackageMetadata metadata;
  final SwiftPmProcessPolicy<T> processPolicy;
  final SwiftPmNetworkRetry<T> networkRetry;
  final SwiftPmBinaryRecovery<T> binaryRecovery;
  final SwiftPmExtractedArtifactRecovery<T> extractedArtifacts;
  @override
  Future<void> prepare(SwiftPmDependencyCommand command) async {
    Future<void> resolveOnce() => runner.runChecked(
      command.swift,
      processPolicy
          .swiftResolveArguments(
            pluginsDir: command.pluginsDir,
            scratchPath: command.scratchPath,
            swiftSdksPath: command.swiftSdksPath,
            toolsetPath: command.toolsetPath,
            swiftSdkTriple: command.swiftSdkTriple,
          )
          .toList(),
      environment: command.environment,
      inheritStdio: runner.log.isVerbose,
      label: 'swift package resolve',
    );
    Future<void> resolve() async {
      try {
        await resolveOnce();
      } on Object catch (error) {
        if (!SwiftPmDamagedRepositories.explains(error) ||
            !await _removeDamagedRepositories(command.scratchPath)) {
          rethrow;
        }
        await resolveOnce();
      }
    }

    Future<void> resolveWithRetries() =>
        networkRetry.retryingTransientNetworkFailure(
          resolve,
          label: 'swift package resolve',
          retryable: SwiftPmNetworkRetry.isTransientResolveFailure,
        );
    final attemptState = SwiftPmBinaryAttemptState();
    final packageIdentities = await metadata.packageIdentitiesByDirectory(
      command.pluginsDir,
    );
    Future<bool> recover() => extractedArtifacts.stageExtractedBinaryArtifacts(
      scratchPath: command.scratchPath,
      packageIdentities: packageIdentities,
      binaryArtifactStore: command.binaryArtifactStore,
      binaryArtifactFallback: command.binaryArtifactFallback,
      attemptState: attemptState,
      packageLocalArtifactJunctionCapability:
          command.packageLocalArtifactJunctionCapability,
    );
    await binaryRecovery.resolveWithFinalBinaryRecovery(
      resolve: resolveWithRetries,
      recover: recover,
    );
    if (await checkout.materializeCheckoutSymlinks(command.scratchPath)) {
      await binaryRecovery.resolveWithFinalBinaryRecovery(
        resolve: resolveWithRetries,
        recover: recover,
      );
    }
  }

  /// Removes what SwiftPM cannot read versions from, so it fetches them again.
  /// Returns whether there was anything to remove.
  Future<bool> _removeDamagedRepositories(String scratchPath) async {
    final repositories = SwiftPmDamagedRepositories(runner.host.fileSystem);
    final home = runner.environmentValue(
      runner.effectiveEnvironment,
      'USERPROFILE',
    );
    final removed = [
      ...await repositories.removeFrom(p.join(scratchPath, 'repositories')),
      if (home != null)
        ...await repositories.removeFrom(
          SwiftPmDamagedRepositories.sharedCache(home),
          minimumAge: SwiftPmDamagedRepositories.sharedCacheMinimumAge,
        ),
    ];
    runner.log.logTrace(
      '[swift package resolve] removed unusable repositories: '
      '${removed.join(', ')}',
    );
    return removed.isNotEmpty;
  }
}
