import 'package:apple_developer_kit/host/shared/apple_host_services.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/shared/grandslam/grandslam_session_store.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:cli_kit/shared/process/process.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:dart_mobile_device/shared/diagnostics/device_probe.dart';
import 'package:darwin_sdk_kit/shared/sdk/darwin_sdk.dart';
import 'package:darwin_sdk_kit/shared/sdk/darwin_sdk_repository.dart';
import 'package:darwin_sdk_kit/shared/toolchain/darwin_toolchain_resolver.dart';
import 'package:darwin_sdk_kit/target/shared/ios_build_platform.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:xcross/src/shared/cli/basic/auth_command.dart'; // studio: 015
import 'package:xcross/src/shared/cli/basic/doctor_models.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart'; // studio: 002
import 'package:xcross/src/shared/sdk/xcode_swift_requirement.dart';
import 'package:xcross/src/shared/toolchain/path_linker_guard.dart'; // studio: 002

@internal
final class DoctorEnvironmentChecks<T extends PlatformHostInterface> {
  DoctorEnvironmentChecks({
    required this.hostPlatform,
    required this.buildPlatform,
    required this.appleHostServices,
    required this.runner,
    required this.repository,
    required this.toolchain,
    required this.deviceDiagnostics,
    required this.sdkMismatch,
    required this.sdkToolchainIdentity,
    required this.createAppleHttpClient,
    this.minimumSwift,
    this.swiftInstallGuidance,
    this.swiftEnvironmentChecks,
    // studio: 002 — host device service reachability (Device service check).
    this.deviceServiceProblem,
    // studio: 002 — configured environment.PATH entries (PATH guard).
    this.configuredPath = const [],
  });
  final http.Client Function() createAppleHttpClient;
  final T hostPlatform;
  final IosBuildPlatformInterface buildPlatform;
  final AppleHostServices appleHostServices;
  final ProcessRunner<T> runner;
  final DarwinSdkRepository<T> repository;
  final DarwinToolchainResolver<T> toolchain;
  final DeviceDiagnostics deviceDiagnostics;
  final Future<String?> Function(String bundle) sdkMismatch;
  final Future<Map<String, String>> Function() sdkToolchainIdentity;
  final Future<List<DoctorCheck>> Function()? swiftEnvironmentChecks;
  final (int, int)? minimumSwift;
  final String? swiftInstallGuidance;
  final Future<String?> Function()? deviceServiceProblem;
  final List<String> configuredPath;

  static const _requiredTools = ['swift', 'clang++', 'llvm-ar'];

  DoctorCheck hostSupport() =>
      DoctorCheck.success('Host', '${hostPlatform.name} is supported.');

  /// Everything a Flutter build runs on the host: the Swift toolchain that
  /// drives SwiftPM, its host environment, and the iOS compiler, linker and
  /// SDK it builds against.
  Future<List<DoctorCheck>> flutterToolchain() async {
    final checks = <DoctorCheck>[hostSupport()];
    for (final tool in _requiredTools) {
      checks.add(await _tool(tool));
    }
    if (await swiftBelowHostMinimum() case final problem?) {
      checks.add(DoctorCheck.failure('Swift version', problem));
    }
    checks.addAll(await _swiftEnvironment());
    checks.add(await _iosClang());
    checks.add(await iosLinker());
    checks.addAll(await configuredPathLinkers()); // studio: 002
    checks.add(await darwinSdk());
    return checks;
  }

  Future<List<DoctorCheck>> _swiftEnvironment() async {
    final run = swiftEnvironmentChecks;
    if (run == null) return const [];
    try {
      return await run();
    } on Object catch (error) {
      return [DoctorCheck.failure('Swift environment', '$error')];
    }
  }

  Future<DoctorCheck> _tool(String name) async {
    final path = await runner.which(
      name,
      extraDirectories: toolchain.llvmToolDirs(),
    );
    return path == null
        ? DoctorCheck.failure(
            name,
            'Not found. Run `xcross setup` after installing Swift.',
          )
        : DoctorCheck.success(name, 'Found', path: path);
  }

  Future<DoctorCheck> _iosClang() async {
    try {
      return DoctorCheck.success(
        'iOS clang',
        'Ready',
        path: await _resolveIosClang(),
      );
    } on Object catch (error) {
      return DoctorCheck.failure('iOS clang', error.toString());
    }
  }

  // studio: 002 — a configured PATH entry whose ld64.lld cannot link iOS
  // (typically a Swift toolchain `bin`) broke native-asset linking (#148).
  Future<List<DoctorCheck>> configuredPathLinkers() async => [
    for (final (entry, problem) in await PathLinkerGuard(
      toolchain,
    ).configuredProblems(configuredPath))
      DoctorCheck.warning(
        'Configured PATH',
        codedWarning(
          XcrossCodes.toolchainPathLinkerUnusable,
          '$entry: ld64.lld $problem',
        ),
        path: entry,
      ),
  ];

  Future<DoctorCheck> iosLinker() async {
    final String path;
    try {
      path = await _resolveIosLinker();
    } on Object catch (error) {
      return DoctorCheck.failure('iOS linker', error.toString());
    }
    final problem = await toolchain.selectorStubDefect(path);
    if (problem != null) {
      return DoctorCheck.warning('iOS linker', problem, path: path);
    }
    final extra = await _ld64LldDetail(path);
    return DoctorCheck.success(
      'iOS linker',
      extra == null ? 'Ready' : 'Ready ($extra)',
      path: path,
    );
  }

  /// `LLD <major>.<minor>`, so a healthy linker still reports which one it
  /// is: the selector-stub warning names a bad version, but without this a
  /// good one is indistinguishable from an unknown one.
  Future<String?> _ld64LldDetail(String path) async {
    final version = await toolchain.ld64LldVersion(path);
    return version == null ? null : 'LLD ${version.$1}.${version.$2}';
  }

  Future<String> _resolveIosClang() {
    final sdk = repository.current();
    if (sdk == null) throw StateError('Darwin SDK is not installed.');
    return toolchain.resolveDarwinClang(
      repository.iosSdk(sdk, target: buildPlatform),
    );
  }

  Future<String> _resolveIosLinker() {
    final sdk = repository.current();
    if (sdk == null) throw StateError('Darwin SDK is not installed.');
    return toolchain.resolveLd64Lld();
  }

  Future<DoctorCheck> darwinSdk() async {
    final path = repository.installBundle;
    if (!repository.isValidBundle(path)) {
      return const DoctorCheck.failure(
        'Darwin SDK',
        'Missing or incomplete. Run `xcross sdk install <Xcode.xip>`.',
      );
    }
    final mismatch = await sdkMismatch(path);
    if (mismatch != null) {
      return DoctorCheck.failure(
        'Darwin SDK',
        '$mismatch Reinstall it with `xcross sdk install <Xcode.xip>`.',
      );
    }
    final tooOld = await swiftTooOldForSdk(path);
    if (tooOld != null) return DoctorCheck.failure('Darwin SDK', tooOld);
    // Repairs a bundle installed before xcross rewrote text stubs, so
    // `doctor` reports the SDK the build will actually get rather than the
    // one on disk a moment ago.
    final patched = repository.patch.ensureApplied(path);
    return DoctorCheck.success(
      'Darwin SDK',
      patched == 0
          ? 'Installed'
          : 'Installed (rewrote $patched text stubs for this linker)',
      path: path,
    );
  }

  /// Why the installed SDK's Xcode generation outruns the host Swift, or null
  /// when the pair is fine or cannot be judged.
  ///
  /// Reported separately from [SdkInstall.hostToolchainMismatch]: that one
  /// asks whether Swift *changed* since the install, while this asks whether
  /// the Swift now on PATH is new enough for this SDK at all. A host that
  /// downgraded Swift, or installed an Xcode 27 SDK with an older `xcross`
  /// that did not yet check, only hears about it here.
  Future<String?> swiftTooOldForSdk(String bundle) async {
    final int? xcodeMajor;
    try {
      xcodeMajor = XcodeSwiftRequirement.xcodeMajorFromSdkPath(
        repository.iosSdk(DarwinSdk(bundle), target: buildPlatform),
      );
    } on Object catch (error) {
      runner.log.logTrace(
        'Could not read the installed iPhoneOS SDK version: $error',
      );
      return null;
    }
    if (xcodeMajor == null) return null;
    if (XcodeSwiftRequirement.minimumSwift(xcodeMajor) == null) return null;
    final Map<String, String> identity;
    try {
      identity = await sdkToolchainIdentity();
    } on Object catch (error) {
      runner.log.logTrace(
        'Could not identify the host Swift toolchain: $error',
      );
      return null;
    }
    return XcodeSwiftRequirement.mismatchWithHint(
      xcodeMajor: xcodeMajor,
      swiftVersionOutput: identity['version'] ?? '',
      swiftPath: identity['swift'],
    );
  }

  /// Why the Swift on PATH is older than this host supports, or null when it
  /// is new enough, the host sets no floor, or the version cannot be read.
  Future<String?> swiftBelowHostMinimum() async {
    if (minimumSwift == null) return null;
    final Map<String, String> identity;
    try {
      identity = await sdkToolchainIdentity();
    } on Object catch (error) {
      runner.log.logTrace(
        'Could not identify the host Swift toolchain: $error',
      );
      return null;
    }
    return XcodeSwiftRequirement.hostFloorMismatch(
      minimum: minimumSwift,
      swiftVersionOutput: identity['version'] ?? '',
      swiftPath: identity['swift'],
      installHint: swiftInstallGuidance,
    );
  }

  /// Device tooling, signing credentials and connected devices: what `run`
  /// needs beyond a successful build, shared by every framework.
  Future<List<DoctorCheck>> deployment() async {
    final deviceTools = await _deviceTools();
    if (deviceTools.status == DoctorStatus.failure) return [deviceTools];

    final checks = <DoctorCheck>[
      deviceTools,
      ?await _deviceService(), // studio: 002
      await _authentication(),
    ];
    try {
      checks.addAll(await devices(await deviceDiagnostics.devices()));
    } on Object catch (error) {
      checks.add(DoctorCheck.warning('Device', 'Discovery failed: $error'));
    }
    return checks;
  }

  // studio: 002 — usbmuxd / Apple Mobile Device Service must accept
  // connections for any USB device work.
  Future<DoctorCheck?> _deviceService() async {
    final probe = deviceServiceProblem;
    if (probe == null) return null;
    final problem = await probe();
    return problem == null
        ? const DoctorCheck.success('Device service', 'Reachable')
        : DoctorCheck.failure(
            'Device service',
            '[device.host_service_unavailable] $problem',
          );
  }

  Future<DoctorCheck> _deviceTools() async {
    try {
      final executable = await deviceDiagnostics.resolveExecutable();
      return DoctorCheck.success('Device tools', 'Found', path: executable);
    } on Object catch (error) {
      return DoctorCheck.failure('Device tools', '$error');
    }
  }

  Future<List<DoctorCheck>> devices(List<Device> found) async {
    if (found.isEmpty) {
      return const [
        DoctorCheck.warning('Device', 'No connected iOS device found.'),
      ];
    }
    final checks = <DoctorCheck>[];
    for (final device in found) {
      checks.add(
        _deviceCheck(device, await deviceDiagnostics.osMajorVersion(device)),
      );
    }
    return checks;
  }

  static String _rejectedKeyHint(String keyId) =>
      'Apple rejected the key. In App Store Connect, open Users and Access → '
      'Integrations → App Store Connect API and check that $keyId is listed, '
      'active and has the Admin or App Manager role, and that the Issuer ID '
      'shown there is the one you saved. An individual key (Integrations → '
      'Individual Keys) is detected when you run xcross auth again; leave '
      'out --issuer-id for one. A push (APNs) or Sign in with Apple key from '
      'developer.apple.com is also a .p8 file but does not work here. Or '
      'sign in with your Apple ID: xcross auth --apple-id=<email>.';

  static DoctorCheck _deviceCheck(Device device, int? osMajor) {
    final label = '${device.name} (${device.udid})';
    if (osMajor == null) {
      return DoctorCheck.warning(
        'Device',
        '$label: could not read the iOS version.',
      );
    }
    // studio: 009 — iOS 15/16 are supported since feature 005 (install over
    // usbmux, open via the user's DDI or from the icon); only debug runs need
    // iOS 17. This check still said "iOS 17 or later is required" (found on
    // the iPhone X, 2026-11-02).
    if (osMajor < 15) {
      return DoctorCheck.failure(
        'Device',
        '$label runs iOS $osMajor; iOS 15 or later is required.',
      );
    }
    if (osMajor < 17) {
      return DoctorCheck.success(
        'Device',
        '$label runs iOS $osMajor: release and profile builds '
            '(debug needs iOS 17 or later).',
      );
    }
    return DoctorCheck.success('Device', '$label runs iOS $osMajor.');
  }

  Future<DoctorCheck> _authentication() async {
    final appleId = await _appleIdAuthentication();
    if (appleId != null) return appleId;
    final appStoreConnect = await _appStoreConnectAuthentication();
    return appStoreConnect;
  }

  Future<DoctorCheck?> _appleIdAuthentication() async {
    try {
      final session = await GrandSlamSessionStore(
        hostServices: appleHostServices,
      ).load();
      if (session == null || session.isExpired) return null;
      return const DoctorCheck.success(
        'Authentication',
        'Apple ID session is available.',
      );
    } on Object catch (error) {
      return DoctorCheck.failure(
        'Authentication',
        'Apple ID session is unusable: $error',
      );
    }
  }

  Future<DoctorCheck> _appStoreConnectAuthentication() async {
    final path = AscCredentials.defaultConfigPath(
      hostServices: appleHostServices,
    );
    if (!appleHostServices.host.fileSystem.file(path).existsSync()) {
      return const DoctorCheck.failure(
        'Authentication',
        'No credentials found. Run `xcross auth`.',
      );
    }
    String? keyId;
    var individual = false;
    try {
      final credentials = await AscCredentialsLoader(
        hostServices: appleHostServices,
      ).load(path: path);
      keyId = credentials.keyId;
      individual = credentials.keyType == AscKeyType.individual;
      final client = AscClient(
        credentials,
        httpClient: createAppleHttpClient(),
      );
      try {
        await client.listDevices();
      } finally {
        client.close();
      }
      return DoctorCheck.success(
        'Authentication',
        individual
            ? 'App Store Connect individual API key is valid.'
            : 'App Store Connect credentials are valid.',
      );
    } on Object catch (error) {
      // studio: 009/015 — a 401 means Apple refuses the request; for an
      // individual key that is the provisioning limit, for a team key the
      // key itself (seen 2026-11-02).
      final refused = '$error'.contains('HTTP 401');
      if (refused && individual) {
        return const DoctorCheck.failure(
          'Authentication',
          individualKeyProvisioningNote,
        );
      }
      final hint = refused ? '\n${_rejectedKeyHint(keyId ?? 'this key')}' : '';
      return DoctorCheck.failure(
        'Authentication',
        'App Store Connect credentials are unusable: $error$hint',
      );
    }
  }
}
