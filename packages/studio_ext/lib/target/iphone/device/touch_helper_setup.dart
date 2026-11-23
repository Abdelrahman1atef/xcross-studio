// studio: 048 — one-click setup of the touch helper (WebDriverAgent) on an
// iPhone: download Appium's prebuilt runner, sign it with the user's Apple
// account, install it. `xcross screen touch-setup --udid <udid> [--json]`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/target/iphone/device/log_output.dart';
import 'package:studio_ext/src/target/iphone/device/touch_runner_source.dart';

/// The touch helper the engine installs: Appium's WebDriverAgent runner for
/// real devices (BSD-3-Clause), pinned by version and SHA-256.
abstract final class TouchHelperRelease {
  static const version = '16.15.3';
  static const url =
      'https://github.com/appium/WebDriverAgent/releases/download/'
      'v$version/WebDriverAgentRunner-Runner.zip';
  static const sha256 =
      '2176793538d902f6b1e61291e9997f68d306541f222ea715d256a7c6ce9d4fc5';
  static const appName = 'WebDriverAgentRunner-Runner.app';

  /// The App ID asked for; the signer may qualify it for the account.
  static const bundleId = 'com.xcross.touchhelper.xctrunner';
}

/// What the setup needs from the engine (built in the composition root).
abstract interface class TouchHelperServices {
  /// Downloads [url] to [path].
  Future<void> download(String url, String path);

  /// Signs the `.app` in place with the user's Apple account (the iPhone is
  /// registered on the team); returns the bundle id it was signed as.
  Future<String> sign(
    String appPath, {
    required String bundleId,
    required String udid,
  });

  /// Installs the signed `.app` on the iPhone.
  Future<void> install(String appPath, {required String udid});

  /// Compiles the xcross touch runner ([sourcePath], Objective-C) into an
  /// iPhone XCTest bundle binary at [binaryPath], with the installed iOS SDK.
  /// Throws (with the reason) when this PC cannot build it.
  Future<void> buildRunner(String sourcePath, String binaryPath);
}

/// Unpacks and prepares the runner (file work only).
final class TouchHelperPackage {
  TouchHelperPackage({
    required this.workRoot,
    this.expectedSha256 = TouchHelperRelease.sha256,
  });

  /// Where the download is kept and the `.app` is prepared.
  final String workRoot;

  /// The SHA-256 the download must have.
  final String expectedSha256;

  String get zipPath => p.join(
    workRoot,
    'WebDriverAgentRunner-Runner-${TouchHelperRelease.version}.zip',
  );

  /// Whether [bytes] are the pinned release.
  bool verified(List<int> bytes) =>
      sha256.convert(bytes).toString() == expectedSha256;

  /// Unpacks [zipBytes] into a fresh `app/` folder; returns the `.app` path.
  String unpack(List<int> zipBytes) {
    final out = Directory(p.join(workRoot, 'app'));
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    // normalize, not canonicalize: canonicalize lower-cases on Windows, and an
    // iPhone bundle needs its exact names (PlugIns/, the executable).
    final root = p.normalize(p.absolute(out.path));
    for (final entry in ZipDecoder().decodeBytes(zipBytes)) {
      final target = p.normalize(p.join(root, entry.name));
      // Never write outside the folder (a hostile archive path).
      if (!p.isWithin(root, target)) continue;
      if (entry.isFile) {
        File(target)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(entry.content);
      } else {
        Directory(target).createSync(recursive: true);
      }
    }
    final app = p.join(root, TouchHelperRelease.appName);
    if (!Directory(app).existsSync()) {
      throw CliError(
        '[touch_setup.package] The download has no ${TouchHelperRelease.appName}.',
      );
    }
    return app;
  }

  /// The test bundle XCTest runs inside the runner app.
  static String testBundle(String appPath) =>
      p.join(appPath, 'PlugIns', 'WebDriverAgentRunner.xctest');

  /// Puts the xcross touch runner [binary] in place of WebDriverAgent's test
  /// bundle (same name, so the runner app finds it); WebDriverAgent's library
  /// is no longer needed.
  void useFastRunner(String appPath, String binary) {
    final bundle = testBundle(appPath);
    File(binary).copySync(p.join(bundle, 'WebDriverAgentRunner'));
    final frameworks = Directory(p.join(bundle, 'Frameworks'));
    if (frameworks.existsSync()) frameworks.deleteSync(recursive: true);
  }

  /// Leaves out the debug symbols and keeps only the plain arm64 slice of
  /// each FAT Mach-O file (the signer takes single-architecture files).
  void prepare(String appPath) {
    final dir = Directory(appPath);
    for (final symbols
        in dir
            .listSync(recursive: true)
            .whereType<Directory>()
            .where((d) => d.path.endsWith('.dSYM'))
            .toList()) {
      if (symbols.existsSync()) symbols.deleteSync(recursive: true);
    }
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final data = file.readAsBytesSync();
      final slice = arm64Slice(data);
      if (slice != null) file.writeAsBytesSync(slice);
    }
  }

  static const _fatMagic = 0xCAFEBABE;
  static const _fatMagic64 = 0xCAFEBABF;
  static const _cpuArm64 = 0x0100000C;

  /// The plain arm64 slice of a FAT Mach-O file; null when [data] is not FAT
  /// or has no such slice.
  static Uint8List? arm64Slice(Uint8List data) {
    if (data.length < 8) return null;
    final view = ByteData.sublistView(data);
    final magic = view.getUint32(0);
    if (magic != _fatMagic && magic != _fatMagic64) return null;
    final count = view.getUint32(4);
    // Java class files share 0xCAFEBABE; a real FAT header has few slices.
    if (count == 0 || count > 16) return null;
    var pos = 8;
    for (var i = 0; i < count; i++) {
      final int cpu;
      final int sub;
      final int offset;
      final int size;
      if (magic == _fatMagic) {
        if (pos + 20 > data.length) return null;
        cpu = view.getUint32(pos);
        sub = view.getUint32(pos + 4) & 0x00FFFFFF;
        offset = view.getUint32(pos + 8);
        size = view.getUint32(pos + 12);
        pos += 20;
      } else {
        if (pos + 32 > data.length) return null;
        cpu = view.getUint32(pos);
        sub = view.getUint32(pos + 4) & 0x00FFFFFF;
        offset = view.getUint64(pos + 8);
        size = view.getUint64(pos + 16);
        pos += 32;
      }
      if (cpu == _cpuArm64 && sub == 0 && offset + size <= data.length) {
        return Uint8List.sublistView(data, offset, offset + size);
      }
    }
    return null;
  }
}

/// `xcross screen touch-setup --udid <udid> [--bundle-id <id>] [--json]`.
final class ScreenTouchSetupCommand extends Command<void> {
  ScreenTouchSetupCommand({
    required TouchHelperServices services,
    required String workRoot,
    required void Function(List<int>) writeBytes,
    String expectedSha256 = TouchHelperRelease.sha256,
  }) : _services = services,
       _workRoot = workRoot,
       _expectedSha256 = expectedSha256,
       _writeBytes = writeBytes {
    argParser
      ..addOption('udid', help: 'The iPhone.', mandatory: true)
      ..addOption(
        'bundle-id',
        help: 'App ID for the touch helper.',
        defaultsTo: TouchHelperRelease.bundleId,
      )
      ..addFlag(
        'wda',
        negatable: false,
        help:
            'Install WebDriverAgent as it is instead of building the faster '
            'xcross touch runner.',
      )
      ..addFlag('json', negatable: false, help: 'One JSON event per line.');
  }

  final TouchHelperServices _services;
  final String _workRoot;
  final String _expectedSha256;
  final void Function(List<int>) _writeBytes;

  @override
  String get name => 'touch-setup';

  @override
  String get description =>
      'Install the touch helper on the iPhone, signed with your Apple '
      'account, so the live screen takes taps and swipes. It is built on this '
      'PC from the xcross touch runner (faster); WebDriverAgent is the '
      'fallback.';

  @override
  String get invocation =>
      'xcross screen touch-setup --udid <udid> [--bundle-id <id>] [--wda] '
      '[--json]';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    final udid = argResults!.option('udid')!;
    final bundleId = argResults!.option('bundle-id')!;
    final wantFast = !argResults!.flag('wda');
    void step(String step, String detail) => _write({
      'v': 1,
      'type': 'touch_setup',
      'step': step,
      'detail': detail,
    }, json: json);
    String? failedStep;
    try {
      final package = TouchHelperPackage(
        workRoot: _workRoot,
        expectedSha256: _expectedSha256,
      );
      failedStep = 'download';
      final zip = File(package.zipPath);
      var bytes = zip.existsSync() ? zip.readAsBytesSync() : Uint8List(0);
      if (!package.verified(bytes)) {
        step(
          'download',
          'Downloading the runner app (WebDriverAgent ${TouchHelperRelease.version})',
        );
        zip.parent.createSync(recursive: true);
        await _services.download(TouchHelperRelease.url, zip.path);
        bytes = zip.readAsBytesSync();
        if (!package.verified(bytes)) {
          zip.deleteSync();
          throw CliError(
            '[touch_setup.download] The touch helper download is not the '
            'expected file (SHA-256 check failed).',
          );
        }
      }
      failedStep = 'prepare';
      step('prepare', 'Preparing the touch helper');
      final app = package.unpack(bytes);
      package.prepare(app);
      var fast = false;
      if (wantFast) {
        failedStep = 'build';
        step('build', 'Building the fast touch helper on this PC');
        final dir = Directory(p.join(_workRoot, 'runner'))
          ..createSync(recursive: true);
        final source = File(p.join(dir.path, touchRunnerSourceName))
          ..writeAsStringSync(touchRunnerSource);
        final binary = p.join(dir.path, 'XcrossTouchRunner');
        try {
          await _services.buildRunner(source.path, binary);
          package.useFastRunner(app, binary);
          fast = true;
        } on Object catch (e) {
          final why = e is CliError ? e.message : '$e';
          step(
            'build',
            'The fast touch helper could not be built on this PC ($why). '
                'Installing WebDriverAgent instead (slower touch).',
          );
        }
      }
      failedStep = 'sign';
      step('sign', 'Signing it with your Apple account');
      final signedAs = await _services.sign(
        app,
        bundleId: bundleId,
        udid: udid,
      );
      failedStep = 'install';
      step('install', 'Installing it on the iPhone');
      await _services.install(app, udid: udid);
      _write({
        'v': 1,
        'type': 'touch_setup_done',
        'ok': true,
        'bundleId': signedAs,
        'fast': fast,
        'message': fast
            ? 'The fast touch helper is on the iPhone.'
            : 'The touch helper (WebDriverAgent) is on the iPhone.',
      }, json: json);
    } on Object catch (e) {
      final message = e is CliError ? e.message : '$e';
      _write({
        'v': 1,
        'type': 'touch_setup_done',
        'ok': false,
        'step': failedStep,
        'message': message,
      }, json: json);
      if (e is CliError) rethrow;
      throw CliError('[touch_setup.${failedStep ?? 'error'}] $message');
    }
  }

  void _write(Map<String, Object?> event, {required bool json}) {
    if (json) {
      _writeBytes(utf8.encode(ndjsonLine(event)));
      return;
    }
    final text = switch (event['type']) {
      'touch_setup' => '… ${event['detail']}',
      'touch_setup_done' when event['ok'] == true =>
        'Done: ${event['message']} (${event['bundleId']})',
      _ => 'Touch helper not installed: ${event['message']}',
    };
    _writeBytes(utf8.encode('$text\n'));
  }
}
