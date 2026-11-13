// studio: `xcross engine info`: which engine this is, for XCross Studio.
// An engine without this command (upstream xcross, or an XCross Studio build
// older than it) is one the Studio refuses.
import 'dart:convert';

import 'package:args/command_runner.dart';

/// What `xcross engine info` reports.
abstract final class EngineIdentity {
  /// The engine's name in `engine_info`; upstream xcross has no such command.
  static const engine = 'xcross-studio';

  /// Raise this when XCross Studio must refuse older engines (for example a
  /// build fix it relies on, such as the App Store icon set records in
  /// Assets.car); the Studio has a matching minimum.
  ///
  /// 1: icon-set records in Assets.car, `--build-number keep`.
  static const protocol = 1;
}

/// `xcross engine …`: about this engine.
final class EngineCommand extends Command<void> {
  EngineCommand({
    required String version,
    required void Function(String) write,
  }) {
    addSubcommand(EngineInfoCommand(version: version, write: write));
  }

  @override
  String get name => 'engine';

  @override
  String get description =>
      'Show which xcross engine this is and its protocol version, for '
      'XCross Studio.';
}

/// `xcross engine info [--json]`.
final class EngineInfoCommand extends Command<void> {
  EngineInfoCommand({
    required String version,
    required void Function(String) write,
  }) : _version = version,
       _write = write {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print one engine_info JSON line.',
    );
  }

  final String _version;
  final void Function(String) _write;

  @override
  String get name => 'info';

  @override
  String get description =>
      'Show the engine name, its protocol version (what XCross Studio checks) '
      'and the xcross version.';

  @override
  String get invocation => 'xcross engine info [--json]';

  /// The one-line contract XCross Studio parses.
  static Map<String, Object> document(String version) => {
    'v': 1,
    'type': 'engine_info',
    'engine': EngineIdentity.engine,
    'protocol': EngineIdentity.protocol,
    'version': version,
  };

  @override
  Future<void> run() async {
    if (argResults!.rest.isNotEmpty) usageException('No arguments expected.');
    if (argResults!.flag('json')) {
      _write('${jsonEncode(document(_version))}\n');
      return;
    }
    _write(
      'Engine     ${EngineIdentity.engine}\n'
      'Protocol   ${EngineIdentity.protocol}\n'
      'Version    $_version\n',
    );
  }
}
