import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/cli/ide/subcommands/vscode_json_merge.dart';
import 'package:xcross/src/shared/cli/ide/xcross_executable.dart';

/// `xcross ide idea` — write a shared LSP4IJ DAP run configuration that
/// drives `xcross flutter dap` (stdio).
@internal
final class IdeaCommand extends Command<void> {
  IdeaCommand(this.launcher);

  final XcrossIdeLauncher launcher;
  @override
  String get name => 'idea';

  @override
  String get description =>
      'Set up a JetBrains DAP run config so Debug runs on an iOS device.';

  @override
  Future<void> run() async {
    final exe = launcher.resolve(subcommand: 'idea', brokenFeature: 'Debug');

    final dir = launcher.host.fileSystem.directory(
      launcher.host.paths.context.join(
        launcher.host.paths.context.current,
        '.run',
      ),
    );
    await dir.create(recursive: true);

    // studio: 009 — a debug entry (iOS 17+) and a release entry (what
    // iOS 15/16 can run), so the iPhone shows up in the run dropdown either
    // way; xcross-generated files are updated instead of left stale.
    await _writeOrUpdate(
      launcher.host.paths.context.join(dir.path, 'xcross_ios_device.run.xml'),
      buildIdeaRunXml(exe, environment: launcher.generatedEnvironment),
    );
    await _writeOrUpdate(
      launcher.host.paths.context.join(dir.path, 'xcross_ios_release.run.xml'),
      buildIdeaRunXml(
        exe,
        environment: launcher.generatedEnvironment,
        name: xcrossReleaseLaunchName,
        args: const ['--release'],
      ),
    );

    launcher.log.logInfo(
      'Next',
      launcher.log.dim(
        'install LSP4IJ (plugins.jetbrains.com/plugin/23257-lsp4ij), then '
        'pick "$xcrossLaunchName" (iOS 17+) or "$xcrossReleaseLaunchName" '
        "in the run dropdown and press Debug (not Flutter's Run button)",
      ),
    );
  }

  /// Writes [content]; an existing file is updated only when xcross wrote
  /// it (a `.bak` copy is kept). A run config the user made themselves is
  /// never clobbered: it is printed instead.
  Future<void> _writeOrUpdate(String path, String content) async {
    final file = launcher.host.fileSystem.file(path);
    final shown = launcher.host.paths.context.relative(path);
    if (file.existsSync()) {
      final current = await file.readAsString();
      if (current == content) {
        launcher.log.logDone('Unchanged $shown');
        return;
      }
      if (!isXcrossRunXml(current)) {
        launcher.log.logWarn(
          '$shown already exists and was not written by xcross — merge '
          'this in yourself:\n$content',
        );
        return;
      }
      await launcher.host.fileSystem.file('$path.bak').writeAsString(current);
      await file.writeAsString(content);
      launcher.log.logDone('Updated $shown (previous version: $shown.bak)');
      return;
    }
    await file.writeAsString(content);
    launcher.log.logDone('Wrote $shown');
  }

  /// Whether [xml] is a run configuration `xcross ide idea` generated.
  static bool isXcrossRunXml(String xml) =>
      xml.contains('type="DAPConfiguration"') &&
      xml.contains('<option name="serverName" value="xcross" />') &&
      xml.contains('flutter dap');

  /// Shared `.run/*.run.xml` body for LSP4IJ's `DAPConfiguration` type.
  static String buildIdeaRunXml(
    String xcrossExe, {
    Map<String, String> environment = const {},
    String name = xcrossLaunchName,
    List<String> args = const [],
  }) {
    final command = '${_quoteCmd(xcrossExe)} flutter dap';
    final launch = jsonEncode({
      'type': 'dart',
      'name': name,
      'request': 'launch',
      'program': 'lib/main.dart',
      'cwd': r'${workspaceFolder}',
      'env': {...environment, xcrossEnvKey: xcrossEnvValue},
      'args': args,
    });

    return '''
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="${_xmlAttr(name)}" type="DAPConfiguration" factoryName="DAPConfiguration">
    <option name="command" value="${_xmlAttr(command)}" />
    <option name="connectTimeout" value="0" />
    <option name="debugMode" value="LAUNCH" />
    <option name="debugServerWaitStrategy" value="TIMEOUT" />
    <option name="file" value="\$PROJECT_DIR\$/lib/main.dart" />
    <option name="workingDirectory" value="\$PROJECT_DIR\$" />
    <option name="serverId" value="" />
    <option name="serverName" value="xcross" />
    <option name="launchConfiguration" value="${_xmlAttr(launch)}" />
    <option name="serverMappings">
      <list>
        <ServerMappingSettings>
          <option name="fileNamePatterns">
            <list>
              <option value="*.dart" />
            </list>
          </option>
          <fileType>
            <FileTypeSettings>
              <option name="patterns">
                <option value="*.dart" />
              </option>
            </FileTypeSettings>
          </fileType>
        </ServerMappingSettings>
      </list>
    </option>
    <method v="2" />
  </configuration>
</component>
''';
  }

  /// LSP4IJ splits `command` on whitespace, so a path containing any must be
  /// quoted before it is embedded.
  static String _quoteCmd(String path) => path.contains(RegExp(r'[\s"]'))
      ? '"${path.replaceAll('"', r'\"')}"'
      : path;

  static String _xmlAttr(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('"', '&quot;');
}
