import 'package:meta/meta.dart';

/// How an installed app was signed, from its `SignerIdentity`.
@internal
enum SignerType {
  appStore('app-store'),
  testflight('testflight'),
  development('development'),
  distribution('distribution'),
  other('other');

  const SignerType(this.wire);

  final String wire;

  static SignerType of(String? identity) {
    final value = identity ?? '';
    if (value == 'Apple iPhone OS Application Signing') return appStore;
    if (value.contains('TestFlight')) return testflight;
    if (value.startsWith('Apple Development') ||
        value.startsWith('iPhone Developer')) {
      return development;
    }
    if (value.startsWith('Apple Distribution') ||
        value.startsWith('iPhone Distribution')) {
      return distribution;
    }
    return other;
  }
}

/// An installed app as reported by `apps list` (data-model
/// "InstalledAppInfo").
@internal
final class InstalledAppInfo {
  const InstalledAppInfo({
    required this.bundleId,
    required this.name,
    required this.version,
    required this.build,
    required this.executable,
    required this.entitlements,
    required this.signer,
    required this.signerIdentity,
  });

  factory InstalledAppInfo.fromAppsList(
    String bundleId,
    Map<String, Object?> app,
  ) {
    final entitlements = app['Entitlements'];
    final identity = app['SignerIdentity'];
    return InstalledAppInfo(
      bundleId: bundleId,
      name: _string(app['CFBundleDisplayName']) ?? _string(app['CFBundleName']),
      version: _string(app['CFBundleShortVersionString']),
      build: _string(app['CFBundleVersion']),
      executable: _string(app['CFBundleExecutable']),
      entitlements: entitlements is Map
          ? {
              for (final key
                  in entitlements.keys.map((k) => '$k').toList()..sort())
                key: entitlements[key],
            }
          : const {},
      signer: SignerType.of(_string(identity)),
      signerIdentity: _string(identity),
    );
  }

  final String bundleId;
  final String? name;
  final String? version;
  final String? build;
  final String? executable;

  /// Entitlements as installed, keys sorted.
  final Map<String, Object?> entitlements;
  final SignerType signer;

  /// Raw certificate name; may contain a person's name (shown only with
  /// `--show-sensitive`).
  final String? signerIdentity;

  /// `aps-environment`, or null when the app cannot receive push.
  String? get push => _string(entitlements['aps-environment']);

  List<String> get associatedDomains =>
      switch (entitlements['com.apple.developer.associated-domains']) {
        final List<Object?> domains => [for (final d in domains) '$d'],
        _ => const [],
      };

  String? get teamId =>
      _string(entitlements['com.apple.developer.team-identifier']) ??
      switch (_string(entitlements['application-identifier'])) {
        final String id when id.contains('.') => id.substring(
          0,
          id.indexOf('.'),
        ),
        _ => null,
      };

  /// NDJSON `appinfo` event (contracts/devicelog.schema.json).
  Map<String, Object?> toJson() => {
    'v': 1,
    'type': 'appinfo',
    'bundleId': bundleId,
    'name': name,
    'version': version,
    'build': build,
    'executable': executable,
    'signer': signer.wire,
    'teamId': teamId,
    'entitlements': entitlements,
    'push': push,
    'associatedDomains': associatedDomains,
  };

  /// Human summary (contracts/cli.md).
  String toHuman({required bool showSensitive}) {
    final signerLine =
        'signer: ${signer.wire}${teamId == null ? '' : ' · team $teamId'}'
        '${showSensitive && signerIdentity != null ? ' · $signerIdentity' : ''}';
    final lines = <String>[
      '${name ?? bundleId} ($bundleId) ${version ?? '?'} (${build ?? '?'})',
      signerLine,
      _check(
        push != null,
        'push entitlement',
        push == null
            ? 'missing (no aps-environment)'
            : 'aps-environment = $push',
      ),
      _check(
        associatedDomains.isNotEmpty,
        'associated domains',
        associatedDomains.isEmpty ? 'none' : associatedDomains.join(', '),
      ),
      'entitlements:',
      for (final MapEntry(:key, :value) in entitlements.entries)
        '  $key: $value',
    ];
    return '${lines.join('\n')}\n';
  }

  static String _check(bool ok, String label, String detail) =>
      '${ok ? '✔' : '✖'} ${label.padRight(21)}$detail';

  static String? _string(Object? value) => value is String ? value : null;
}
