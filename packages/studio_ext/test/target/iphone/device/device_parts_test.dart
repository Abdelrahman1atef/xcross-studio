import 'package:dart_mobile_device/target/iphone/device/pymd/syslog_entry.dart';
import 'package:studio_ext/src/target/iphone/device/crash_reports.dart';
import 'package:studio_ext/src/target/iphone/device/installed_app_info.dart';
import 'package:studio_ext/src/target/iphone/device/log_filter.dart';
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/src/target/iphone/device/push_diagnosis.dart';
import 'package:studio_ext/src/target/iphone/device/sensitive_masker.dart';
import 'package:test/test.dart';

import '../../../support/fake_device_backend.dart';

SyslogEntry _entry(
  String process,
  String message, {
  int pid = 100,
  String level = 'NOTICE',
}) => SyslogEntry.tryParse(
  syslogLine(process: process, message: message, pid: pid, level: level),
)!;

void main() {
  group('LogFilter', () {
    test('AC-010-1 app filter keeps only the app executable', () {
      final filter = LogFilter(appExecutable: 'Runner');
      expect(filter.apply(_entry('Runner', 'hi'), mask: true), isNotNull);
      expect(filter.apply(_entry('SpringBoard', 'hi'), mask: true), isNull);
    });

    test('AC-010-3 a relaunched app (new pid) still matches', () {
      final filter = LogFilter(appExecutable: 'Runner');
      expect(
        filter.apply(_entry('Runner', 'again', pid: 999), mask: true),
        isNotNull,
      );
    });

    test('AC-010-4 process, grep and level filters combine', () {
      final filter = LogFilter(
        processes: ['apsd', '42'],
        grep: RegExp('token', caseSensitive: false),
        minLevel: 'error',
      );
      expect(
        filter.apply(_entry('apsd', 'TOKEN x', level: 'ERROR'), mask: true),
        isNotNull,
      );
      expect(
        filter.apply(
          _entry('other', 'token', pid: 42, level: 'FAULT'),
          mask: true,
        ),
        isNotNull,
        reason: 'pid matches',
      );
      expect(
        filter.apply(_entry('apsd', 'token', level: 'INFO'), mask: true),
        isNull,
        reason: 'below level',
      );
      expect(
        filter.apply(_entry('apsd', 'nothing', level: 'ERROR'), mask: true),
        isNull,
        reason: 'grep',
      );
      expect(
        filter.apply(_entry('bluetoothd', 'token', level: 'ERROR'), mask: true),
        isNull,
        reason: 'process',
      );
    });

    test('AC-010-5 flutter preset shows only Dart output without prefix', () {
      final filter = LogFilter(
        appExecutable: 'Runner',
        preset: LogPreset.flutter,
      );
      expect(
        filter.apply(_entry('Runner', 'flutter: hello'), mask: true)!.message,
        'hello',
      );
      expect(filter.apply(_entry('Runner', 'native line'), mask: true), isNull);
    });

    test('AC-010-7 push preset keeps push lines and highlights them', () {
      final filter = LogFilter(
        appExecutable: 'Runner',
        bundleId: 'com.example.app',
        preset: LogPreset.push,
      );
      Highlight? highlight(String process, String message) =>
          filter.apply(_entry(process, message), mask: true)?.highlight;
      expect(
        highlight('Runner', 'APNS device token registered'),
        Highlight.registration,
      );
      expect(
        highlight('apsd', 'Received incoming message on topic com.example.app'),
        Highlight.delivery,
      );
      expect(
        highlight(
          'Runner',
          "no valid 'aps-environment' entitlement string found for application",
        ),
        Highlight.error,
      );
      expect(
        filter.apply(_entry('apsd', 'unrelated topic com.other'), mask: true),
        isNull,
      );
      expect(filter.apply(_entry('Runner', 'layout done'), mask: true), isNull);
    });

    test('crash preset keeps app faults and system crash lines about it', () {
      final filter = LogFilter(
        appExecutable: 'Runner',
        bundleId: 'com.example.app',
        preset: LogPreset.crash,
      );
      expect(
        filter.apply(_entry('Runner', 'oops', level: 'FAULT'), mask: true),
        isNotNull,
      );
      expect(
        filter.apply(
          _entry('SpringBoard', 'com.example.app exited abnormally (crash)'),
          mask: true,
        ),
        isNotNull,
      );
      expect(filter.apply(_entry('Runner', 'fine'), mask: true), isNull);
    });
  });

  test('SC-004 masks UDIDs, tokens and emails', () {
    final masked = SensitiveMasker.mask(
      'device 00008020-001A2B3C4D5E6F70 / 0123456789abcdef0123456789abcdef01234567 '
      'token ${'ab' * 32} fcm cXyZ_123abcd:APA91bH${'q' * 40} '
      'user me@example.com',
    );
    expect(masked, isNot(contains('00008020')));
    expect(masked, isNot(contains('0123456789abcdef')));
    expect(masked, isNot(contains('abab')));
    expect(masked, isNot(contains('APA91b')));
    expect(masked, isNot(contains('me@example.com')));
    expect(masked, contains('<udid>'));
    expect(masked, contains('<token>'));
    expect(masked, contains('<email>'));
  });

  test('human line and NDJSON event', () {
    final event = DeviceLogEvent(
      entry: _entry('Runner', 'مرحبا ✓', level: 'ERROR'),
      message: 'مرحبا ✓',
      highlight: Highlight.delivery,
    );
    expect(event.toHumanLine(), '★ 12:00:00.123 Runner[100] E مرحبا ✓');
    final line = ndjsonLine(event.toJson());
    expect(line.endsWith('}\n'), isTrue);
    expect(line.codeUnits.every((u) => u <= 0x7e || u == 0x0a), isTrue);
    expect(line, contains('"highlight":"delivery"'));
  });

  group('AC-010-6 installed app info', () {
    test('signer, team, push and domains from apps list', () {
      final info = InstalledAppInfo.fromAppsList(
        'com.example.app',
        appEntry(
          executable: 'Runner',
          entitlements: {
            'aps-environment': 'development',
            'application-identifier': 'TEAMID1234.com.example.app',
            'com.apple.developer.associated-domains': ['applinks:example.com'],
          },
        ),
      );
      expect(info.signer, SignerType.development);
      expect(info.teamId, 'TEAMID1234');
      expect(info.push, 'development');
      expect(info.associatedDomains, ['applinks:example.com']);
      final human = info.toHuman(showSensitive: false);
      expect(human, contains('✔ push entitlement'));
      expect(human, contains('✔ associated domains'));
      expect(human, isNot(contains('Planted Person')));
      expect(info.toHuman(showSensitive: true), contains('Planted Person'));
    });

    test('missing push and domains are ✖; signer types are classified', () {
      final info = InstalledAppInfo.fromAppsList(
        'a.b',
        appEntry(
          executable: 'X',
          signer: 'Apple iPhone OS Application Signing',
        ),
      );
      expect(info.push, isNull);
      expect(info.signer, SignerType.appStore);
      expect(info.toHuman(showSensitive: false), contains('✖ push'));
      expect(
        SignerType.of('TestFlight Beta Distribution'),
        SignerType.testflight,
      );
      expect(
        SignerType.of('iPhone Distribution: Co (X)'),
        SignerType.distribution,
      );
      expect(SignerType.of('iPhone Developer: P (X)'), SignerType.development);
      expect(SignerType.of(null), SignerType.other);
    });
  });

  group('AC-010-8 push diagnosis', () {
    DeviceLogEvent event(String message, Highlight? highlight) =>
        DeviceLogEvent(
          entry: _entry('Runner', message),
          message: message,
          highlight: highlight,
        );

    test('each verdict', () {
      expect(
        PushDiagnosis(bundleId: 'a', entitlement: null).verdict,
        PushVerdict.missingEntitlement,
      );
      final notRunning = PushDiagnosis(
        bundleId: 'a',
        entitlement: 'development',
      );
      expect(notRunning.verdict, PushVerdict.appNotRunning);
      final notRegistered = PushDiagnosis(
        bundleId: 'a',
        entitlement: 'development',
      )..sawApp();
      expect(notRegistered.verdict, PushVerdict.notRegistered);
      final registered = PushDiagnosis(
        bundleId: 'a',
        entitlement: 'development',
      )..observe(event('APNS token', Highlight.registration), fromApp: true);
      expect(registered.verdict, PushVerdict.registeredNoDelivery);
      final delivered = PushDiagnosis(bundleId: 'a', entitlement: 'development')
        ..observe(
          event('Received incoming push', Highlight.delivery),
          fromApp: true,
        );
      expect(delivered.verdict, PushVerdict.delivered);
      final denied = PushDiagnosis(bundleId: 'a', entitlement: 'development')
        ..observe(
          event('notifications not authorized', Highlight.error),
          fromApp: true,
        );
      expect(denied.verdict, PushVerdict.permissionDenied);
      final entitlementError =
          PushDiagnosis(bundleId: 'a', entitlement: 'production')..observe(
            event("no valid 'aps-environment' entitlement", Highlight.error),
            fromApp: true,
          );
      expect(entitlementError.verdict, PushVerdict.missingEntitlement);
      expect(entitlementError.hint, contains('feature 003'));
      expect(entitlementError.toJson()['verdict'], 'missing_entitlement');
    });
  });

  group('AC-010-9 crash reports', () {
    test('names parse; folders are ignored; newest first', () {
      final names =
          [
              '/DiagnosticLogs',
              '/Runner-2026-10-01-101500.ips',
              '/Runner-2026-11-01-090000.ips',
              '/LowBatteryLog-2026-10-30-003829.ips',
            ].map(CrashName.tryParse).whereType<CrashName>().toList()
            ..sort(CrashName.newestFirst);
      expect(names.map((n) => n.name), [
        'Runner-2026-11-01-090000.ips',
        'LowBatteryLog-2026-10-30-003829.ips',
        'Runner-2026-10-01-101500.ips',
      ]);
      expect(names.first.process, 'Runner');
      expect(names.first.time, '2026-11-01T09:00:00');
    });

    test('.ips summary: exception, signal and faulting frames', () {
      final summary = CrashReportSummary.fromIps(
        '{"app_name":"Runner","bug_type":"309"}\n'
        '{"exception":{"type":"EXC_CRASH","signal":"SIGABRT"},'
        '"faultingThread":1,'
        '"usedImages":[{"name":"libsystem_kernel.dylib"},{"name":"Runner"}],'
        '"threads":[{"frames":[]},{"frames":['
        '{"imageIndex":0,"symbol":"__pthread_kill","imageOffset":10},'
        '{"imageIndex":1,"imageOffset":4096}]}]}',
      );
      expect(summary.exceptionType, 'EXC_CRASH');
      expect(summary.signal, 'SIGABRT');
      expect(summary.frames, [
        'libsystem_kernel.dylib  __pthread_kill',
        'Runner  +4096',
      ]);
      expect(
        CrashReportSummary.fromIps('legacy text report').exceptionType,
        isNull,
      );
    });
  });
}
