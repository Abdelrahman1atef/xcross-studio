// studio: 021 — `xcross appstore …`: App Store submission with the App Store
// Connect API (specs/021-app-store-submission).
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/appstore/appstore_command.dart';
import 'package:xcross/src/composition/cli/asc_commands.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';

/// The commands feature 021 adds.
@internal
List<Command<void>> appStoreCommands<T extends PlatformHostInterface>(
  XcrossRuntime<T> runtime,
) => [
  AppStoreCommand(
    openApi: () => openAscApi(runtime),
    fileSystem: runtime.host.fileSystem,
    paths: runtime.host.paths.context,
    currentDirectory: () => runtime.host.paths.context.current,
    write: runtime.log.output.write,
  ),
];
