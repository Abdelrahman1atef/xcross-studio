import 'package:cli_kit/shared/platform/platform_host.dart';

import 'package:studio_ext/src/shared/inspect/inspect_failure.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/inspector.dart';

/// What `xcross sign` (feature 011) checks in the bundle it wrote, read with
/// the feature 001 inspector: every executable certificate-signed, a
/// provisioning profile embedded, no xcross hand-off keys left behind.
final class SignedBundleCheck {
  const SignedBundleCheck({
    required this.bundleId,
    required this.teamId,
    required this.profileKind,
    required this.profileExpires,
    required this.deviceCount,
    required this.provisionsAllDevices,
    required this.entitlementKeys,
    required this.problems,
  });

  /// Inspects the `.ipa` or `.app` at [path]. Never throws: an unreadable
  /// input is reported as a problem.
  factory SignedBundleCheck.run(
    HostFileSystemInterface fileSystem,
    String path,
  ) {
    InspectSource? source;
    try {
      source = InspectSource.open(fileSystem, path);
      return SignedBundleCheck.fromReport(inspectBundle(source));
    } on InspectFailure catch (failure) {
      return SignedBundleCheck(
        bundleId: null,
        teamId: null,
        profileKind: null,
        profileExpires: null,
        deviceCount: null,
        provisionsAllDevices: false,
        entitlementKeys: const [],
        problems: ['[${failure.code}] ${failure.message}'],
      );
    } finally {
      source?.close();
    }
  }

  /// The check for an inspector [report].
  factory SignedBundleCheck.fromReport(InspectReport report) {
    final problems = <String>[];
    if (!report.signature.present) {
      problems.add('the app has no _CodeSignature/CodeResources');
    }
    ExecutableInfo? main;
    for (final executable in report.executables) {
      if (executable.role == ExecutableRole.main) main = executable;
      if (executable.signature.kind != SignatureKind.certificate) {
        problems.add(
          '${executable.path} is ${executable.signature.kind.wire}-signed, '
          'not signed with a certificate',
        );
      }
    }
    if (main == null) problems.add('the main executable is missing');
    final profile = report.profile;
    if (profile == null) problems.add('no embedded.mobileprovision');
    for (final extension in report.extensions) {
      if (extension.profile == null) {
        problems.add('${extension.path} has no embedded.mobileprovision');
      }
    }
    if (report.bundle.xcrossPrivateKeys.entries.any(
      (entry) => entry.key != 'XCrossAppGroups' && entry.value,
    )) {
      problems.add('Info.plist still carries XCrossEntitlements/Capabilities');
    }
    for (final issue in report.issues) {
      if (issue.severity == IssueSeverity.error) {
        problems.add('[${issue.code}] ${issue.message}');
      }
    }
    final entitlements = main?.entitlements ?? const <String, Object?>{};
    return SignedBundleCheck(
      bundleId: report.bundle.bundleId,
      teamId: main?.signature.teamId ?? report.signature.teamId,
      profileKind: profile?.kind.wire,
      profileExpires: profile?.expirationDate,
      deviceCount: profile?.deviceCount,
      provisionsAllDevices: profile?.provisionsAllDevices ?? false,
      entitlementKeys: entitlements.keys.toList()..sort(),
      problems: problems,
    );
  }

  final String? bundleId;
  final String? teamId;

  /// `development`, `ad-hoc`, `app-store` or `enterprise`.
  final String? profileKind;

  /// ISO-8601 expiry of the embedded profile.
  final String? profileExpires;
  final int? deviceCount;
  final bool provisionsAllDevices;

  /// Entitlement keys of the main executable's signature.
  final List<String> entitlementKeys;

  /// Why the bundle would not install; empty when it looks right.
  final List<String> problems;

  bool get ok => problems.isEmpty;

  /// `✔`-style summary lines (no device ids, no certificate names).
  List<String> summaryLines() {
    final devices = provisionsAllDevices
        ? 'all devices'
        : switch (deviceCount) {
            null => 'devices unknown',
            1 => '1 device',
            final count => '$count devices',
          };
    final expires = switch (profileExpires) {
      final String date when date.length >= 10 => date.substring(0, 10),
      final other => other ?? '?',
    };
    final keys = entitlementKeys.isEmpty ? 'none' : entitlementKeys.join(', ');
    return [
      '✔ bundle id     ${bundleId ?? '?'}',
      '✔ signature     certificate · team ${teamId ?? '?'}',
      '✔ profile       ${profileKind ?? '?'} · expires $expires · $devices',
      '✔ entitlements  $keys',
    ];
  }
}
