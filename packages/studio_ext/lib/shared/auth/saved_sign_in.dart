// studio: 026 — what `xcross auth status` reports
// (specs/026-all-screens-preview, User Story 1).
import 'package:apple_developer_kit/host/shared/apple_host_services.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:apple_developer_kit/shared/grandslam/grandslam_session_store.dart';
import 'package:apple_developer_kit/shared/secure/local_cipher.dart';
import 'package:meta/meta.dart';

/// What is saved about signing in: how the user signed in and with which
/// identifiers. Never holds a password, token or key contents.
@immutable
final class SavedSignIn {
  const SavedSignIn({
    this.session,
    this.sessionProblem,
    this.sessionBlocksKey = false,
    this.key,
    this.keyProblem,
    this.keyFileFound = false,
  });

  final GrandSlamSession? session;

  /// Why a saved Apple ID session could not be read.
  final String? sessionProblem;

  /// The session is broken in a way that may hide its team, so signing stops
  /// instead of using a key that may belong to another team.
  final bool sessionBlocksKey;

  final AscCredentials? key;

  /// Why a saved App Store Connect key could not be read.
  final String? keyProblem;

  /// Whether the `.p8` file [key] points at is still there.
  final bool keyFileFound;

  /// Only reads files: Apple is not asked whether any of it still works.
  static Future<SavedSignIn> read(AppleHostServices hostServices) async {
    GrandSlamSession? session;
    String? sessionProblem;
    var sessionBlocksKey = false;
    try {
      session = await GrandSlamSessionStore(hostServices: hostServices).load();
    } on LocalCipherError {
      sessionProblem = 'The saved session cannot be read on this computer.';
    } on Object catch (error) {
      sessionProblem = '$error';
      sessionBlocksKey = true;
    }

    final keyPath = AscCredentials.defaultConfigPath(
      hostServices: hostServices,
    );
    final files = hostServices.host.fileSystem;
    AscCredentials? key;
    String? keyProblem;
    if (files.file(keyPath).existsSync()) {
      try {
        key = await AscCredentialsLoader(
          hostServices: hostServices,
        ).load(path: keyPath);
      } on Object catch (error) {
        keyProblem = '$error';
      }
    }

    return SavedSignIn(
      session: session,
      sessionProblem: sessionProblem,
      sessionBlocksKey: sessionBlocksKey,
      key: key,
      keyProblem: keyProblem,
      keyFileFound: key != null && files.file(key.privateKeyPath).existsSync(),
    );
  }

  /// What device builds sign with: `apple-id`, `api-key` or null. The order of
  /// `SigningSessionResolver.resolve`.
  String? get deviceBuilds {
    if (session != null) return 'apple-id';
    return sessionBlocksKey || key == null ? null : 'api-key';
  }

  /// What App Store builds sign with: a team key, or null.
  String? get appStoreBuilds =>
      key?.keyType == AscKeyType.team ? 'api-key' : null;

  Map<String, Object?> toJson() {
    final session = this.session;
    final key = this.key;
    return {
      'v': 1,
      'type': 'auth_status',
      'deviceBuilds': deviceBuilds,
      'appStoreBuilds': appStoreBuilds,
      'appleId': session == null
          ? sessionProblem == null
                ? null
                : {'problem': sessionProblem}
          : {
              'email': session.username,
              'teamId': session.teamId,
              'anisetteUrl': session.anisetteUrl,
              'expires': session.token.expiry.toUtc().toIso8601String(),
              'expired': session.isExpired,
            },
      'apiKey': key == null
          ? keyProblem == null
                ? null
                : {'problem': keyProblem}
          : {
              'keyType': key.keyType.name,
              'issuerId': key.issuerId.isEmpty ? null : key.issuerId,
              'keyId': key.keyId,
              'privateKeyPath': key.privateKeyPath,
              'privateKeyFound': keyFileFound,
            },
    };
  }

  String render() {
    final out = StringBuffer();
    final session = this.session;
    final key = this.key;
    if (session != null) {
      out
        ..writeln('Apple ID: ${session.username}')
        ..writeln('  Team ID: ${session.teamId}')
        ..writeln('  Anisette server: ${session.anisetteUrl ?? 'local'}')
        ..writeln(
          '  Session ${session.isExpired ? 'expired' : 'expires'}: '
          '${session.token.expiry.toUtc().toIso8601String()}',
        );
    } else if (sessionProblem != null) {
      out.writeln('Apple ID: $sessionProblem');
    }
    if (key != null) {
      out.writeln(
        'App Store Connect API key (${key.keyType.name}): ${key.keyId}',
      );
      if (key.issuerId.isNotEmpty) out.writeln('  Issuer ID: ${key.issuerId}');
      out.writeln(
        '  Private key: ${key.privateKeyPath}'
        '${keyFileFound ? '' : ' (file not found)'}',
      );
    } else if (keyProblem != null) {
      out.writeln('App Store Connect API key: $keyProblem');
    }
    if (out.isEmpty) {
      return 'Not signed in. Run xcross auth to sign in.\n';
    }
    String label(String? value) => switch (value) {
      'apple-id' => 'Apple ID',
      'api-key' => 'App Store Connect API key',
      _ => 'nothing yet',
    };
    out
      ..writeln('Device builds use: ${label(deviceBuilds)}')
      ..writeln('App Store builds use: ${label(appStoreBuilds)}');
    return out.toString();
  }
}
