import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/inspect_report.dart';

const _ok = '✔';
const _bad = '✖';
const _labelWidth = 21;

/// Short ✔/✖ summary for humans (research R14, contracts/cli.md).
///
/// Uses only allow-listed report values: never UDIDs, profile UUIDs,
/// certificate data or non-allow-listed Info.plist values. Its exact layout is
/// not a stable interface; scripts must use `--json`.
@internal
String renderHumanSummary(InspectReport report) {
  final bundle = report.bundle;
  final header =
      '${report.input.name}  ${bundle.bundleId ?? '?'} '
      '${bundle.shortVersion ?? '?'} (${bundle.buildNumber ?? '?'}), '
      'iOS ${bundle.minimumOSVersion ?? '?'}+';
  final lines = <String>[
    header,
    _signedLine(report),
    _profileLine(report.profile),
    _pushLine(report),
    _domainsLine(report),
    _iconLine(report.resources),
    _launchLine(report.resources.launchScreen),
    _frameworksLine(report.frameworks),
    switch (report.issues.length) {
      0 => 'no issues',
      1 => '1 issue — run with --json for details',
      final n => '$n issues — run with --json for details',
    },
  ];
  return '${lines.join('\n')}\n';
}

String _line(bool ok, String label, String detail) =>
    '${ok ? _ok : _bad} ${label.padRight(_labelWidth)}$detail';

String _signedLine(InspectReport report) {
  final signature = report.signature;
  if (!signature.present) {
    return _line(false, 'signed', 'not signed (no _CodeSignature)');
  }
  final team = signature.teamId == null ? '' : ' · team ${signature.teamId}';
  return _line(true, 'signed', '${signature.kind.wire}$team');
}

String _profileLine(ProfileSummary? profile) {
  if (profile == null) return _line(false, 'provisioning profile', 'none');
  final parts = [
    profile.kind.wire,
    if (profile.teamId != null) 'team ${profile.teamId}',
    if (profile.provisionsAllDevices)
      'all devices'
    else if (profile.deviceCount != null)
      '${profile.deviceCount} device${profile.deviceCount == 1 ? '' : 's'}',
  ];
  return _line(true, 'provisioning profile', parts.join(' · '));
}

String _pushLine(InspectReport report) {
  final value = report.mainExecutable?.entitlements?['aps-environment'];
  if (value is String) {
    return _line(true, 'push entitlement', 'aps-environment = $value');
  }
  final granted =
      report.profile?.entitlements.containsKey('aps-environment') ?? false;
  return _line(
    false,
    'push entitlement',
    granted ? 'missing (profile grants it)' : 'missing',
  );
}

String _domainsLine(InspectReport report) {
  final domains = report
      .mainExecutable
      ?.entitlements?['com.apple.developer.associated-domains'];
  if (domains is List && domains.isNotEmpty) {
    final n = domains.length;
    return _line(true, 'associated domains', '$n domain${n == 1 ? '' : 's'}');
  }
  return _line(false, 'associated domains', 'none');
}

String _iconLine(Resources resources) {
  final resolved = resources.icons.declared.where((i) => i.resolved).toList();
  if (resolved.isNotEmpty) {
    final first = resolved.first;
    final n = first.files.length;
    return _line(true, 'icon', '${first.name} ($n file${n == 1 ? '' : 's'})');
  }
  if (resources.icons.iconName != null && resources.assetsCar.present) {
    return _line(true, 'icon', '${resources.icons.iconName} in Assets.car');
  }
  return _line(
    false,
    'icon',
    resources.icons.declared.isEmpty ? 'none' : 'declared but files missing',
  );
}

String _launchLine(LaunchScreen launch) {
  switch (launch.kind) {
    case LaunchScreenKind.none:
      return _line(false, 'launch screen', 'none');
    case LaunchScreenKind.storyboard:
      final storyboard = launch.storyboard!;
      return storyboard.compiledPresent
          ? _line(true, 'launch screen', 'storyboard ${storyboard.name}')
          : _line(
              false,
              'launch screen',
              'storyboard ${storyboard.name} not compiled',
            );
    case LaunchScreenKind.uiLaunchScreen:
      if (launch.keys.isEmpty) {
        return _line(false, 'launch screen', 'UILaunchScreen is empty');
      }
      return switch (launch.image?.source) {
        LaunchImageSource.assetCatalog => _line(
          true,
          'launch screen',
          'UILaunchScreen · image in Assets.car',
        ),
        LaunchImageSource.looseFile => _line(
          false,
          'launch screen',
          'UILaunchScreen · loose PNG (not shown by iOS)',
        ),
        LaunchImageSource.missing => _line(
          false,
          'launch screen',
          'UILaunchScreen · image missing',
        ),
        null => _line(
          true,
          'launch screen',
          'UILaunchScreen · ${launch.keys.join(', ')}',
        ),
      };
  }
}

String _frameworksLine(List<FrameworkInfo> frameworks) {
  if (frameworks.isEmpty) return _line(false, 'frameworks', 'none');
  final names = [
    for (final framework in frameworks)
      framework.name.replaceFirst(RegExp(r'\.(framework|dylib)$'), ''),
  ];
  final shown = names.length > 5
      ? '${names.take(5).join(', ')}, …'
      : names.join(', ');
  return _line(true, 'frameworks', '${frameworks.length} ($shown)');
}
