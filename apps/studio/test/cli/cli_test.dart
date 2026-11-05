import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xcross_studio/src/cli/output_line.dart';
import 'package:xcross_studio/src/cli/xcross_commands.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';
import 'package:xcross_studio/src/host/host_platform.dart';
import 'package:xcross_studio/src/state/settings.dart';

void main() {
  group('AC-008-4 command lines', () {
    test('build, run and install', () {
      expect(
        XcrossCommands.build(
          mode: BuildMode.release,
          buildName: ' 1.2.0 ',
          buildNumber: '7',
        ),
        [
          'flutter',
          'build',
          '--release',
          '--ipa',
          '--build-name',
          '1.2.0',
          '--build-number',
          '7',
        ],
      );
      expect(
        XcrossCommands.build(mode: BuildMode.debug, ipa: false, buildName: ''),
        ['flutter', 'build', '--debug'],
      );
      expect(XcrossCommands.run(mode: BuildMode.profile, udid: 'U1'), [
        'flutter',
        'run',
        '--profile',
        '--udid',
        'U1',
      ]);
      expect(
        XcrossCommands.install('/a b/app.ipa', ddi: '/ddi', launch: false),
        ['install', '/a b/app.ipa', '--ddi', '/ddi', '--no-launch'],
      );
    });

    test('AC-011-1 sign writes an IPA without installing', () {
      expect(XcrossCommands.sign('/a/app.ipa'), ['sign', '/a/app.ipa']);
      expect(
        XcrossCommands.sign('/a/app.ipa', output: '/o/x.ipa', udid: 'U1'),
        ['sign', '/a/app.ipa', '-o', '/o/x.ipa', '--udid', 'U1'],
      );
    });

    test('doctor is the flutter doctor (no top-level doctor exists)', () {
      expect(XcrossCommands.doctor(), ['flutter', 'doctor']);
    });

    test('device commands always ask for JSON', () {
      expect(XcrossCommands.devices(), ['devices', '--json']);
      expect(XcrossCommands.appList(udid: 'U1'), [
        'app',
        'list',
        '--json',
        '--udid',
        'U1',
      ]);
      expect(XcrossCommands.appInfo('com.example.app'), [
        'app',
        'info',
        'com.example.app',
        '--json',
      ]);
      expect(
        XcrossCommands.logs(
          app: 'com.example.app',
          preset: LogPreset.push,
          processes: ['apsd', ' '],
          level: LogLevel.error,
        ),
        [
          'logs',
          '--json',
          '--app',
          'com.example.app',
          '--preset',
          'push',
          '--process',
          'apsd',
          '--level',
          'error',
        ],
      );
      expect(XcrossCommands.crashesList(), ['crashes', 'list', '--json']);
      expect(XcrossCommands.crashesPull('Runner-1.ips', outDirectory: '/o'), [
        'crashes',
        'pull',
        'Runner-1.ips',
        '--out',
        '/o',
      ]);
    });

    test('plugin commands', () {
      expect(XcrossCommands.pluginList('/p'), [
        'plugin',
        'list',
        '--project',
        '/p',
      ]);
      expect(XcrossCommands.pluginShim('maps', project: '/p', force: true), [
        'plugin',
        'shim',
        'maps',
        '--project',
        '/p',
        '--force',
      ]);
    });

    test('features 027 and 028: the commands and what they print', () {
      expect(XcrossCommands.pluginStatus(), ['plugin', 'status', '--json']);
      expect(XcrossCommands.pluginRegenerate('fluttertoast'), [
        'plugin',
        'shim',
        'fluttertoast',
        '--force',
      ]);
      expect(
        XcrossCommands.permissionSet('NSCameraUsageDescription', 'Scan.'),
        ['permissions', 'set', 'NSCameraUsageDescription', 'Scan.', '--json'],
      );
      expect(XcrossCommands.capabilityAdd('push', ['production']), [
        'capabilities',
        'add',
        'push',
        '--value',
        'production',
        '--json',
      ]);
      final status = XcrossEvent.tryParse(
        '{"v":1,"type":"plugin_status","project":"/p","plugins":['
        '{"name":"fluttertoast","version":"8.2.14","kind":"draft",'
        '"overridePath":"xcross_overrides/fluttertoast/8.2.14","edited":false,'
        '"problems":[{"code":"manifest_missing","message":"no manifest"}],'
        '"action":"regenerate","canRegenerate":true,'
        '"command":["plugin","shim","fluttertoast","--force"]}]}',
      );
      final plugin = (status! as PluginStatusReport).plugins.single;
      expect(plugin.name, 'fluttertoast');
      expect(plugin.needsAction, isTrue);
      expect(plugin.problems.single.code, 'manifest_missing');
      expect(plugin.canRegenerate, isTrue);
      expect(plugin.command, ['plugin', 'shim', 'fluttertoast', '--force']);

      final permissions = XcrossEvent.tryParse(
        '{"v":1,"type":"permissions","permissions":['
        '{"key":"NSMicrophoneUsageDescription","name":"Microphone",'
        '"value":"TODO","status":"placeholder","neededBy":["record"]}],'
        '"missing":[{"resource":"camera","keys":["NSCameraUsageDescription"],'
        '"plugins":["image_picker_ios"]}],'
        '"catalog":[{"key":"NSCameraUsageDescription","name":"Camera",'
        '"description":"d","suggestion":"Scan codes."}]}',
      );
      final report = permissions! as PermissionsReport;
      expect(report.permissions.single.isPlaceholder, isTrue);
      expect(report.missing.single.keys.first, 'NSCameraUsageDescription');
      expect(
        report.catalogOf('NSCameraUsageDescription')?.suggestion,
        'Scan codes.',
      );

      final change = XcrossEvent.tryParse(
        '{"v":1,"type":"capabilities_change","action":"add","id":"push",'
        '"changed":true,"backup":null,"notes":["n"]}',
      );
      expect((change! as ProjectChange).target, 'push');
    });

    test('passwords never appear in the shown command', () {
      final command = XcrossCommands.authAppleId(
        'me@example.com',
        password: 'hunter2',
      );
      expect(command, contains('hunter2'));
      final shown = XcrossCommands.display(command);
      expect(shown, isNot(contains('hunter2')));
      expect(shown, 'xcross auth --apple-id=me@example.com --password ••••');
    });

    test('AC-015-7 a team key passes the Issuer ID, an individual key '
        'leaves it out', () {
      expect(
        XcrossCommands.authApiKey(
          issuerId: ' issuer ',
          keyId: 'K1',
          privateKeyPath: 'k.p8',
        ),
        [
          'auth',
          '--issuer-id',
          'issuer',
          '--key-id',
          'K1',
          '--private-key',
          'k.p8',
        ],
      );
      expect(XcrossCommands.authApiKey(keyId: 'K1', privateKeyPath: 'k.p8'), [
        'auth',
        '--key-id',
        'K1',
        '--private-key',
        'k.p8',
      ]);
    });

    test('FR-001 a bundled xcross next to the GUI is found', () {
      expect(
        XcrossInvocation.bundledNextTo(
          r'C:\Apps\XCross Studio\xcross_studio.exe',
          windows: true,
          exists: (path) =>
              path == r'C:\Apps\XCross Studio\xcross\bin\xcross.exe',
        ),
        r'C:\Apps\XCross Studio\xcross\bin\xcross.exe',
      );
      expect(
        XcrossInvocation.bundledNextTo(
          '/opt/xcross-studio/xcross_studio',
          windows: false,
          exists: (path) => path == '/opt/xcross-studio/xcross/bin/xcross',
        ),
        '/opt/xcross-studio/xcross/bin/xcross',
      );
      expect(
        XcrossInvocation.bundledNextTo('/opt/x/gui', windows: false),
        isNull,
      );
      expect(const XcrossInvocation.binary().isDefault, isTrue);
      expect(const XcrossInvocation.binary('/x/xcross').isDefault, isFalse);
    });

    test('FR-001 the bundled CLI is resolved per copy of the app, never '
        'saved as a path', () {
      final settings = Settings();
      expect(settings.effectiveInvocation.executable, 'xcross');
      settings.bundledXcross = r'D:\new\xcross\bin\xcross.exe';
      expect(
        settings.effectiveInvocation.executable,
        r'D:\new\xcross\bin\xcross.exe',
      );
      expect(settings.toJson()['invocation'], {
        'executable': 'xcross',
        'prefixArguments': <String>[],
      });
      // A CLI the user picked wins over the bundled one.
      settings.invocation = const XcrossInvocation.binary(
        r'C:\tools\xcross.exe',
      );
      expect(settings.effectiveInvocation.executable, r'C:\tools\xcross.exe');
    });

    test('FR-001 a bundle path saved by an older version is recognised', () {
      bool studio(String path) =>
          path == r'D:\old\xcross-studio-windows-x64\xcross_studio.exe';
      expect(
        XcrossInvocation.isStudioBundled(
          r'D:\old\xcross-studio-windows-x64\xcross\bin\xcross.exe',
          windows: true,
          exists: studio,
        ),
        isTrue,
      );
      // An xcross the user installed elsewhere is their choice.
      expect(
        XcrossInvocation.isStudioBundled(
          r'C:\Users\me\AppData\Local\xcross\bin\xcross.exe',
          windows: true,
          exists: studio,
        ),
        isFalse,
      );
      expect(
        XcrossInvocation.isStudioBundled(
          '/opt/xcross-studio/xcross/bin/xcross',
          windows: false,
          exists: (path) => path == '/opt/xcross-studio/xcross_studio',
        ),
        isTrue,
      );
    });

    test('invocations: binary and from source', () {
      const binary = XcrossInvocation.binary();
      expect(binary.argumentsFor(['doctor']), ['doctor']);
      final source = XcrossInvocation.fromSource('/repo', context: p.posix);
      expect(source.executable, 'dart');
      expect(source.argumentsFor(['doctor']), [
        'run',
        '/repo/packages/xcross/bin/xcross.dart',
        'doctor',
      ]);
      final round = XcrossInvocation.fromJson(source.toJson());
      expect(round.toString(), source.toString());
      expect(XcrossInvocation.fromJson(null).executable, 'xcross');
    });
  });

  group('AC-008-3 NDJSON events', () {
    test('every v1 event type parses', () {
      final log = XcrossEvent.tryParse(
        '{"v":1,"type":"devicelog","time":"2026-11-01T16:55:51.0186",'
        '"process":"Runner","pid":12,"subsystem":null,"category":null,'
        '"level":"error","message":"boom","highlight":"error"}',
      );
      expect(log, isA<DeviceLogLine>());
      log as DeviceLogLine;
      expect(log.clock, '16:55:51.018');
      expect(log.toText(), '★ 16:55:51.018 Runner[12] E boom');

      final device = XcrossEvent.tryParse(
        '{"v":1,"type":"device","udid":"U1","name":"Phone",'
        '"osVersion":"16.7.16","connection":"usb"}',
      );
      expect(device, isA<ConnectedDevice>());
      expect((device! as ConnectedDevice).legacy, isTrue);

      final info = XcrossEvent.tryParse(
        '{"v":1,"type":"appinfo","bundleId":"com.example.app","name":"A",'
        '"version":"1","build":"2","executable":"Runner",'
        '"signer":"development","teamId":"TEAM",'
        '"entitlements":{"aps-environment":"development"},'
        '"push":"development","associatedDomains":["applinks:x.com"]}',
      );
      expect(info, isA<AppInfo>());
      info as AppInfo;
      expect(info.push, 'development');
      expect(info.associatedDomains, ['applinks:x.com']);

      expect(
        XcrossEvent.tryParse(
          '{"v":1,"type":"app","bundleId":"b","name":null,"version":"1",'
          '"build":"1","executable":"Runner"}',
        ),
        isA<InstalledApp>(),
      );
      expect(
        XcrossEvent.tryParse(
          '{"v":1,"type":"crash","name":"Runner-2026.ips","process":"Runner",'
          '"time":"2026-11-01T10:00:00","exceptionType":"EXC_CRASH"}',
        ),
        isA<CrashReport>(),
      );
      final diagnosis = XcrossEvent.tryParse(
        '{"v":1,"type":"diagnosis","bundleId":"b","entitlement":null,'
        '"appSeen":true,"registrationSeen":false,"deliverySeen":false,'
        '"permissionDenied":false,"verdict":"missing_entitlement",'
        '"hint":"Add aps-environment."}',
      );
      expect(diagnosis, isA<PushDiagnosis>());
      expect((diagnosis! as PushDiagnosis).verdict, 'missing_entitlement');
      expect(
        XcrossEvent.tryParse('{"v":1,"type":"notice","message":"waiting"}'),
        isA<Notice>(),
      );
    });

    test('text, other JSON and newer versions are not events', () {
      expect(XcrossEvent.tryParse('Building Runner.app…'), isNull);
      expect(XcrossEvent.tryParse('{not json'), isNull);
      expect(XcrossEvent.tryParse('{"v":2,"type":"devicelog"}'), isNull);
      expect(XcrossEvent.tryParse('{"v":1,"type":"future"}'), isNull);
      expect(XcrossEvent.tryParse('[1,2]'), isNull);
    });
  });

  group('AC-008-5 output lines', () {
    test('errors, warnings, hints and checks are classified', () {
      final error = OutputLine.classify(
        'error: [device.not_found] No iPhone is connected by USB.',
      );
      expect(error.kind, LineKind.error);
      expect(error.code, 'device.not_found');
      expect(error.isIssue, isTrue);
      final warning = OutputLine.classify(
        '\x1B[33mwarning: [build.asset_catalog_skipped] Assets.xcassets\x1B[0m',
      );
      expect(warning.kind, LineKind.warning);
      expect(warning.code, 'build.asset_catalog_skipped');
      expect(warning.text, startsWith('warning:'));
      expect(OutputLine.classify('hint: run xcross auth').kind, LineKind.hint);
      expect(OutputLine.classify('  ✔ Device service').kind, LineKind.success);
      expect(OutputLine.classify('✖ push').kind, LineKind.failure);
      expect(
        OutputLine.classify('progress', fromStderr: true).kind,
        LineKind.stderr,
      );
    });

    test('kill-tree, folder and settings locations per host', () {
      const windows = WindowsHost();
      expect(windows.killTreeCommand(12), [
        'taskkill',
        '/PID',
        '12',
        '/T',
        '/F',
      ]);
      expect(windows.openFolderCommand(r'C:\x'), ['explorer', r'C:\x']);
      final (winCommand, winArgs) = windows.groupLeader('xcross', ['doctor']);
      expect(winCommand, 'xcross');
      expect(winArgs, ['doctor']);
      expect(
        windows.configDirectory({'APPDATA': r'C:\Users\u\AppData\Roaming'}),
        r'C:\Users\u\AppData\Roaming\XCross Studio',
      );
      const linux = LinuxHost();
      expect(linux.killTreeCommand(12), ['kill', '-TERM', '--', '-12']);
      expect(linux.openFolderCommand('/x'), ['xdg-open', '/x']);
      final (linuxCommand, linuxArgs) = linux.groupLeader('xcross', ['doctor']);
      expect(linuxCommand, 'setsid');
      expect(linuxArgs, ['xcross', 'doctor']);
      expect(
        linux.configDirectory({'HOME': '/home/u'}),
        '/home/u/.config/xcross-studio',
      );
      expect(
        linux.configDirectory({'HOME': '/home/u', 'XDG_CONFIG_HOME': '/cfg'}),
        '/cfg/xcross-studio',
      );
    });
  });
}
