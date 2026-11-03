// studio: 019 — `xcross publish` (specs/019-upload-processing).
import 'dart:io';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/appstore/publish_command.dart';
import 'package:xcross/src/composition/cli/asc_commands.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';

/// The commands feature 019 adds.
@internal
List<Command<void>> publishCommands<T extends PlatformHostInterface>(
  XcrossRuntime<T> runtime,
) => [
  PublishCommand(
    openApi: () => openAscApi(runtime),
    loadCredentials: () =>
        AscCredentialsLoader(hostServices: runtime.appleHostServices).load(),
    fileSystem: runtime.host.fileSystem,
    currentDirectory: () => runtime.host.paths.context.current,
    write: runtime.log.output.write,
    runProcess: (executable, arguments, {workingDirectory}) async {
      final result = await runtime.runner.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      return ProcessResult(0, result.exitCode, result.stdout, result.stderr);
    },
    temporaryRoot: runtime.host.paths.temporaryRoot,
    environment: runtime.runner.effectiveEnvironment,
  ),
];
