import 'dart:convert'; // studio: 008
import 'dart:io';

import 'package:apple_developer_kit/shared/http/apple_http_client.dart';
import 'package:cli_kit/composition/native_host.dart';
import 'package:cli_kit/shared/download/download.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:dart_mobile_device/host/shared/console/native_device_console.dart';
import 'package:dart_mobile_device/host/shared/network/native_device_sockets.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:studio_ext/shared/events/ndjson_events.dart'; // studio: 012
import 'package:xcross/src/composition/xcross_host_context.dart';
import 'package:xcross/src/composition/xcross_runtime.dart';
import 'package:xcross/src/host/shared/cli/native_command_prompt.dart';
import 'package:xcross/src/shared/flutter/hot_reload/vm_service_output.dart';
import 'package:xcross/src/shared/setup/setup_requirements.dart';
import 'package:xcross/src/shared/update/release_lookup.dart';
import 'package:xcross/src/target/iphone/device/signing_http_client_factory.dart';

@internal
XcrossHostContext<PlatformHostInterface> createNativeXcrossContext() {
  // studio: 008 — the XCross Studio GUI reads output through a pipe, where
  // Windows would otherwise encode it in the ANSI code page (✔, ✖ and
  // non-Latin app names become `?`).
  if (Platform.environment['XCROSS_OUTPUT_ENCODING']?.toLowerCase() ==
      'utf-8') {
    stdout.encoding = utf8;
    stderr.encoding = utf8;
  }
  final snapshot = detectPlatformHostSnapshot();
  // studio: 012 — XCROSS_EVENTS=ndjson: one JSON event per line on stdout
  // for the XCross Studio GUI (specs/012-build-events).
  final events = NdjsonEvents.fromEnvironment(Platform.environment, stdout.add);
  final log = Log(
    output:
        events?.logOutput ??
        StreamLogOutput(
          stdout: stdout,
          stderr: stderr,
          supportsAnsi: stdout.hasTerminal && stdout.supportsAnsiEscapes,
          terminalColumns: () =>
              stdout.hasTerminal ? stdout.terminalColumns : 80,
        ),
    events: events,
  );
  return composeXcrossHost(
    snapshot.host,
    commandPrompt: NativeCommandPrompt(input: stdin, output: stdout),
    setupConsole: SetupConsole(
      hasTerminal: stdin.hasTerminal,
      readLine: stdin.readLineSync,
      output: stdout,
    ),
    releaseLookup: const ReleaseLookup(createClient: HttpClient.new),
    outputHasTerminal: stdout.hasTerminal,
    createHttpClient: http.Client.new,
    abi: snapshot.abi,
    processorCount: snapshot.processorCount,
    log: log,
    stdinStream: stdin,
    stdoutSink: stdout,
    stderrSink: stderr,
    deviceConsole: NativeDeviceConsole(input: stdin, output: stdout),
    deviceSockets: const NativeDeviceSockets(),
    downloader: Downloader(createClient: HttpClient.new, log: log),
    signingHttpClients: const HttpSigningClientFactory(),
    createAppleHttpClient: AppleHttpClientFactory(
      createSecurityContext: () => SecurityContext(withTrustedRoots: true),
      createHttpClient: (context) => HttpClient(context: context),
    ).createClient,
    createLocalHttpClient: HttpClient.new,
    vmOutput: VmServiceOutput(output: stdout, errors: stderr),
    executable: snapshot.resolvedExecutable,
    hostname: snapshot.localHostname,
    localeName: snapshot.localeName,
  );
}
