// studio: 025 — podspec-only plugins get a Package.swift draft when a build
// starts, so problem plugins show in seconds, not after minutes of compiling.
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/plugins/plugin_command.dart';
import 'package:xcross/src/shared/diagnostics/build_warnings.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/build/ios_plugins.dart';
import 'package:xcross/src/shared/flutter/build/plugin_overrides.dart';

/// Writes `xcross_overrides/<plugin>/<version>/` for plugins that only ship a
/// podspec, the same files `xcross plugin shim` writes.
@internal
final class PluginAutoDraft {
  PluginAutoDraft({
    required this.fileSystem,
    required this.paths,
    required this.projectRoot,
    required this.locator,
    required this.warnings,
    required this.environment,
  });

  /// Set to `off` to leave podspec-only plugins out instead.
  static const switchName = 'XCROSS_PLUGIN_DRAFTS';

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String projectRoot;
  final PluginOverrideLocator locator;
  final BuildWarnings warnings;
  final Map<String, String> environment;

  /// Drafts what it can of [plugins]. Returns the names of plugins it could
  /// not draft, which it has already warned about.
  Set<String> draftMissing(List<IosPlugin> plugins) {
    if (environment[switchName] == 'off') return const {};
    final writer = PluginDraftWriter(ProjectPlugins(fileSystem, paths));
    final undraftable = <String>{};
    for (final plugin in plugins) {
      if (plugin.usesSwiftPackageManager || !plugin.usesCocoaPods) continue;
      final version = PluginOverrides.versionOf(plugin, paths);
      // The developer's own folder decides, even one that does not apply.
      final lookup = locator.find(plugin.name, version);
      if (lookup.override != null || lookup.problems.isNotEmpty) continue;
      final target = ProjectPlugin(
        name: plugin.name,
        root: plugin.packageRoot,
        platformDirectory: paths.join(
          plugin.packageRoot,
          plugin.platformDirectoryName,
        ),
        version: version,
      );
      final unknown = writer.unknownPods(target);
      if (unknown.isNotEmpty) {
        undraftable.add(plugin.name);
        warnings.warn(
          XcrossCodes.buildPluginUnknownPods,
          subject: plugin.name,
          message:
              'Plugin "${plugin.name}" only ships a podspec and needs '
              '${unknown.join(', ')}, with no known Swift package; its native '
              'iOS code will not be included.',
        );
        continue;
      }
      final written = writer.write(
        target,
        base: paths.join(projectRoot, 'xcross_overrides'),
      );
      warnings.warn(
        XcrossCodes.buildPluginDrafted,
        subject: plugin.name,
        message:
            'Plugin "${plugin.name}" only ships a podspec; xcross drafted '
            '${written.path}. ${written.notes.join(' ')}',
      );
    }
    return undraftable;
  }
}
