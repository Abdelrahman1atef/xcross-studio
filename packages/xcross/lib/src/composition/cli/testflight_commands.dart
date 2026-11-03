// studio: 020 — `xcross testflight …` (specs/020-testflight).
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/appstore/testflight_command.dart';
import 'package:xcross/src/composition/cli/asc_commands.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';

/// The commands feature 020 adds.
@internal
List<Command<void>> testflightCommands<T extends PlatformHostInterface>(
  XcrossRuntime<T> runtime,
) => [
  TestFlightCommand(
    TestFlightContext(
      openApi: () => openAscApi(runtime),
      fileSystem: runtime.host.fileSystem,
      paths: runtime.host.paths.context,
      currentDirectory: () => runtime.host.paths.context.current,
      write: runtime.log.output.write,
    ),
  ),
];
