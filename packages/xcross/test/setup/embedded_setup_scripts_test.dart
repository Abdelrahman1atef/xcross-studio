import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/host/shared/setup/posix_setup_script.dart';
import 'package:xcross/src/host/windows/setup/windows_setup_script.dart';
import 'package:xcross/src/host/windows/setup/windows_setup_scripts.g.dart';
import 'package:xcross/src/shared/setup/setup_script.dart';

import '../../tool/generate_setup_scripts.dart';
import '../host_operations_fixtures.dart';

void main() {
  // Tests run from packages/xcross.
  final package = Directory.current.path;
  final scripts = readSetupScripts(setupScriptsDirectory(package));

  test('the compiled-in scripts match setup/*.ps1', () {
    final generated = File(
      p.join(package, generatedSetupScriptsPath),
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      generated,
      renderSetupScripts(scripts),
      reason:
          'A setup script changed without its embedded copy. Run '
          '`dart run tool/generate_setup_scripts.dart` in packages/xcross.',
    );
    expect(windowsSetupScripts, scripts);
  });

  test('every built-in manager has its script compiled in', () {
    final host = nativeFixtureHost();
    final windows = WindowsSetupScript(
      host,
      fixtureRunner(host, log: fixtureLog()),
    );
    for (final manager in windows.supportedManagers) {
      final script = WindowsSetupScript.script(manager);
      expect(script.embedded, scripts[manager], reason: manager);
      expect(script.source, endsWith('/setup/$manager.ps1'));
    }
  });

  test(
    'an embedded script is cached by content and never downloaded',
    () async {
      final temporary = Directory.systemTemp.createTempSync('xcross-embed-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final host = nativeFixtureHost(
        environment: {
          'LOCALAPPDATA': temporary.path,
          'XDG_CACHE_HOME': temporary.path,
          'HOME': temporary.path,
        },
      );
      final text = scripts['direct']!;
      final manager = SetupScriptManager(
        createHttpClient: () => throw StateError('unexpected HTTP client'),
        source: WindowsSetupScript.script('direct').source,
        embedded: text,
        host: host,
        runner: fixtureRunner(host, log: fixtureLog()),
        policy: PosixSetupScript(host),
        download: (_) => throw StateError('unexpected download'),
        execute: (_, _, _) async {},
      );
      expect(manager.isRemote, isFalse);

      SetupScriptApproval? shown;
      await manager.run(
        refreshFirst: true,
        approve: (script) {
          shown = script;
          return true;
        },
      );

      final digest = sha256.convert(utf8.encode(text)).toString();
      expect(shown!.name, 'direct.ps1');
      expect(shown!.source, SetupScriptManager.builtInSource);
      expect(shown!.sha256, digest);
      expect(p.basename(shown!.path), '$digest.sh');
      expect(File(shown!.path).readAsStringSync(), text);
      expect((await manager.refresh())!.path, shown!.path);
    },
  );
}
