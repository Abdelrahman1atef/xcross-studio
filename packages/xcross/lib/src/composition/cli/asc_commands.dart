// studio: 019–021 — App Store Connect API sessions for `xcross publish`,
// `xcross testflight` and `xcross appstore` (specs/019…021).
import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';

/// An API session signed with the saved App Store Connect key (team or
/// individual); opened per command.
@internal
Future<AscApi> openAscApi<T extends PlatformHostInterface>(
  XcrossRuntime<T> runtime,
) async => AscApi.fromCredentials(
  await AscCredentialsLoader(hostServices: runtime.appleHostServices).load(),
  httpClient: runtime.createAppleHttpClient(),
);
