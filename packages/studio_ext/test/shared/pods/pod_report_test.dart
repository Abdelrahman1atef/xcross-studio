import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/pods/pod_report.dart';
import 'package:studio_ext/shared/pods/pods_command.dart';
import 'package:test/test.dart';

void main() {
  group('AC-046-24 AC-046-33 PodReport warning text', () {
    test('formats four-part warning for no_slice', () {
      const report = PodReport(
        code: 'pod.no_slice',
        reason: 'no_slice',
        plugin: 'google_mlkit_text_recognition',
        pod: 'MLKitVision',
        podVersion: '10.0.0',
        buildTarget: 'iOS simulator',
        detail: 'has ios-arm64, ios-x86_64-simulator',
      );

      final text = report.formatWarning();
      expect(
        text,
        '⚠ Plugin "google_mlkit_text_recognition" is left out of this build: its features will not work in the app.\n'
        '  Why: pod "MLKitVision 10.0.0" has no slice for the iOS simulator (has ios-arm64, ios-x86_64-simulator).\n'
        '  You can: build for a real iPhone instead (device builds include it).\n'
        '  Report: send this to the xcross developers so they can fix it: xcross pods report MLKitVision',
      );
    });

    test('formats four-part warning for resolve_conflict', () {
      const report = PodReport(
        code: 'pod.resolve_conflict',
        reason: 'resolve_conflict',
        plugin: 'my_plugin',
        pod: 'PromisesObjC',
        requiredBy: ['plugin_a', 'plugin_b'],
      );

      final text = report.formatWarning();
      expect(
        text,
        '⚠ Plugin "my_plugin" is left out of this build: its features will not work in the app.\n'
        '  Why: no version of pod "PromisesObjC" fits the requirements of plugin_a, plugin_b.\n'
        '  You can: run "pod update" or adjust plugin versions to align requirements.\n'
        '  Report: send this to the xcross developers so they can fix it: xcross pods report PromisesObjC',
      );
    });

    test('formats four-part warning for download_failed', () {
      const report = PodReport(
        code: 'pod.download_failed',
        reason: 'download_failed',
        plugin: 'vlc_player',
        pod: 'MobileVLCKit',
        podVersion: '3.6.1b1',
        detail: 'HTTP 404',
      );

      final text = report.formatWarning();
      expect(
        text,
        '⚠ Plugin "vlc_player" is left out of this build: its features will not work in the app.\n'
        '  Why: failed to download source for pod "MobileVLCKit 3.6.1b1": HTTP 404.\n'
        '  You can: check your network connection, proxy settings, or install Git if missing.\n'
        '  Report: send this to the xcross developers so they can fix it: xcross pods report MobileVLCKit',
      );
    });

    test('formats four-part warning for converter_off', () {
      const report = PodReport(
        code: 'pod.converter_off',
        reason: 'converter_off',
        plugin: 'webrtc',
        pod: 'WebRTC-SDK',
      );

      final text = report.formatWarning();
      expect(
        text,
        '⚠ Plugin "webrtc" is left out of this build: its features will not work in the app.\n'
        '  Why: pod "WebRTC-SDK" requires the pod converter, but XCROSS_POD_CONVERTER is off.\n'
        '  You can: enable the converter by setting XCROSS_POD_CONVERTER=on.\n'
        '  Report: send this to the xcross developers so they can fix it: xcross pods report WebRTC-SDK',
      );
    });

    test('formats four-part warning for swift_binary_incompatible', () {
      const report = PodReport(
        code: 'pod.swift_binary_incompatible',
        reason: 'swift_binary_incompatible',
        plugin: 'my_sdk',
        pod: 'VendorSDK',
        podVersion: '1.2.0',
      );

      final text = report.formatWarning();
      expect(
        text,
        '⚠ Plugin "my_sdk" is left out of this build: its features will not work in the app.\n'
        '  Why: pod "VendorSDK 1.2.0" was built without Swift library evolution (.swiftinterface missing).\n'
        '  You can: ask the pod author for a build with BUILD_LIBRARY_FOR_DISTRIBUTION=YES.\n'
        '  Report: send this to the xcross developers so they can fix it: xcross pods report VendorSDK',
      );
    });
  });

  group('AC-046-24 Redaction', () {
    test('redacts home paths, project paths, and sensitive tokens', () {
      const report = PodReport(
        code: 'pod.compile_failed',
        reason: 'compile_failed',
        plugin: 'scanner',
        pod: 'BarcodeScanner',
        detail:
            r'Error in C:\Users\johndoe\.pub-cache\hosted\git/repo: failed with Bearer secret_token_123456789 and ghp_abc1234567890abcdef123456789'
            '\n'
            r'at D:\MyProjects\SecretApp\ios\Runner.swift',
      );

      final redacted = report.redact(
        homeDir: r'C:\Users\johndoe',
        projectDir: r'D:\MyProjects\SecretApp',
      );

      expect(redacted.detail, isNot(contains(r'C:\Users\johndoe')));
      expect(redacted.detail, isNot(contains(r'D:\MyProjects\SecretApp')));
      expect(redacted.detail, contains(r'~\.pub-cache'));
      expect(redacted.detail, contains(r'<project>\ios\Runner.swift'));
      expect(redacted.detail, contains('Bearer [REDACTED]'));
      expect(redacted.detail, contains('[REDACTED]'));
      expect(redacted.detail, isNot(contains('secret_token_123456789')));
    });

    test('caps detail lines at 20 lines', () {
      final longDetail = List.generate(
        30,
        (i) => 'Line $i: compilation error',
      ).join('\n');
      final report = PodReport(
        code: 'pod.compile_failed',
        reason: 'compile_failed',
        plugin: 'scanner',
        pod: 'BarcodeScanner',
        detail: longDetail,
      );

      final redacted = report.redact();
      final lines = redacted.detail!.split('\n');
      expect(lines.first, 'Line 0: compilation error');
      expect(lines[19], 'Line 19: compilation error');
      expect(lines[20], '... (truncated)');
      expect(lines.length, 21);
    });
  });

  group('AC-046-24 AC-046-34 PodsCommand CLI', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pods-report-cli-');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('prints formatted reports and filters by pod name', () {
      final reportFile = File(p.join(tempDir.path, 'pods-report.json'));
      const handler = PodsReportFile();
      handler.save(reportFile, const [
        PodReport(
          code: 'pod.no_slice',
          reason: 'no_slice',
          plugin: 'plugin_one',
          pod: 'PodOne',
          podVersion: '1.0.0',
        ),
        PodReport(
          code: 'pod.download_failed',
          reason: 'download_failed',
          plugin: 'plugin_two',
          pod: 'PodTwo',
          podVersion: '2.0.0',
        ),
      ]);

      final output = <String>[];
      final fs = MemoryHostFileSystem();
      final runner = CommandRunner<void>('xcross', 'test')
        ..addCommand(
          PodsCommand(
            fileSystem: fs,
            paths: p.posix,
            write: output.add,
            projectDirectory: tempDir.path,
          ),
        );

      // 1. Report all
      runner.run(['pods', 'report', '--file', reportFile.path]);
      expect(output.join('\n'), contains('Plugin "plugin_one"'));
      expect(output.join('\n'), contains('Plugin "plugin_two"'));

      // 2. Filter by PodOne
      output.clear();
      runner.run(['pods', 'report', 'PodOne', '--file', reportFile.path]);
      expect(output.join('\n'), contains('Plugin "plugin_one"'));
      expect(output.join('\n'), isNot(contains('Plugin "plugin_two"')));

      // 3. JSON mode
      output.clear();
      runner.run([
        'pods',
        'report',
        'PodOne',
        '--json',
        '--file',
        reportFile.path,
      ]);
      final jsonOutput = jsonDecode(output.first) as List<dynamic>;
      expect(jsonOutput.length, 1);
      expect((jsonOutput.first as Map)['pod'], 'PodOne');
    });
  });
}

@internal
class MemoryHostFileSystem implements HostFileSystemInterface {
  @override
  File file(String path) => File(path);

  @override
  Directory directory(String path) => Directory(path);

  @override
  Link link(String path) => Link(path);

  @override
  void makeExecutable(String path) {}

  @override
  void setPermissions(String path, int mode) {}

  @override
  Future<void> createArchiveLink(String destination, String target) async {}
}
