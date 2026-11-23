// studio: 048 — touch helper setup (specs: 048-iphone-screen).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/target/iphone/device/touch_helper_setup.dart';
import 'package:test/test.dart';

/// A FAT Mach-O with an x86_64 slice and an arm64 slice.
Uint8List _fat({required List<int> x86, required List<int> arm}) {
  const header = 8 + 2 * 20;
  final out = BytesBuilder()
    ..add(_u32(0xCAFEBABE))
    ..add(_u32(2))
    ..add(_arch(0x01000007, 3, header, x86.length))
    ..add(_arch(0x0100000C, 0, header + x86.length, arm.length))
    ..add(x86)
    ..add(arm);
  return out.toBytes();
}

List<int> _u32(int v) =>
    (ByteData(4)..setUint32(0, v)).buffer.asUint8List().toList();

List<int> _arch(int cpu, int sub, int offset, int size) => [
  ..._u32(cpu),
  ..._u32(sub),
  ..._u32(offset),
  ..._u32(size),
  ..._u32(14),
];

/// A small stand-in for Appium's runner zip.
Uint8List _runnerZip() {
  const app = 'WebDriverAgentRunner-Runner.app';
  final archive = Archive()
    ..add(ArchiveFile.bytes('$app/Info.plist', utf8.encode('<plist/>')))
    ..add(
      ArchiveFile.bytes(
        '$app/WebDriverAgentRunner-Runner',
        _fat(x86: [1, 1, 1], arm: [7, 7, 7, 7]),
      ),
    )
    ..add(
      ArchiveFile.bytes(
        '$app/PlugIns/WebDriverAgentRunner.xctest.dSYM/Contents/Info.plist',
        utf8.encode('<plist/>'),
      ),
    )
    ..add(
      ArchiveFile.bytes(
        '$app/PlugIns/WebDriverAgentRunner.xctest/Info.plist',
        utf8.encode('<plist/>'),
      ),
    )
    ..add(
      ArchiveFile.bytes(
        '$app/PlugIns/WebDriverAgentRunner.xctest/WebDriverAgentRunner',
        [5, 5, 5],
      ),
    )
    ..add(
      ArchiveFile.bytes(
        '$app/PlugIns/WebDriverAgentRunner.xctest/Frameworks/WebDriverAgentLib.framework/WebDriverAgentLib',
        [6, 6, 6],
      ),
    )
    ..add(ArchiveFile.bytes('../escape.txt', utf8.encode('no')));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

@internal
final class FakeServices implements TouchHelperServices {
  FakeServices(this.zip, {this.signFails = false, this.buildFails = false});

  final Uint8List zip;
  final bool signFails;
  final bool buildFails;
  String? builtFrom;
  Uint8List? testBundleAtSign;
  bool frameworksAtSign = false;
  int downloads = 0;
  String? signedApp;
  String? installedApp;
  List<String>? appFilesAtSign;
  Uint8List? runnerAtSign;

  @override
  Future<void> download(String url, String path) async {
    downloads++;
    expect(url, TouchHelperRelease.url);
    File(path).writeAsBytesSync(zip);
  }

  @override
  Future<String> sign(
    String appPath, {
    required String bundleId,
    required String udid,
  }) async {
    if (signFails) throw CliError('[signing] Sign in to your Apple account.');
    signedApp = appPath;
    appFilesAtSign = [
      for (final f in Directory(appPath).listSync(recursive: true))
        p.relative(f.path, from: appPath).replaceAll(r'\', '/'),
    ];
    runnerAtSign = File(
      p.join(appPath, 'WebDriverAgentRunner-Runner'),
    ).readAsBytesSync();
    final bundle = p.join(appPath, 'PlugIns', 'WebDriverAgentRunner.xctest');
    final binary = File(p.join(bundle, 'WebDriverAgentRunner'));
    testBundleAtSign = binary.existsSync() ? binary.readAsBytesSync() : null;
    frameworksAtSign = Directory(p.join(bundle, 'Frameworks')).existsSync();
    return 'XCR-TEAM.$bundleId';
  }

  @override
  Future<void> install(String appPath, {required String udid}) async =>
      installedApp = appPath;

  static final builtBinary = Uint8List.fromList([0xCF, 0xFA, 0xED, 0xFE, 1]);

  @override
  Future<void> buildRunner(String sourcePath, String binaryPath) async {
    builtFrom = File(sourcePath).readAsStringSync();
    if (buildFails) {
      throw CliError('[touch_setup.build] No iOS SDK on this PC.');
    }
    File(binaryPath).writeAsBytesSync(builtBinary);
  }
}

void main() {
  late Directory work;
  late List<int> out;

  setUp(() {
    work = Directory.systemTemp.createTempSync('touch_setup_test');
    out = [];
  });
  tearDown(() => work.deleteSync(recursive: true));

  List<Map<String, Object?>> events() => [
    for (final line in const LineSplitter().convert(utf8.decode(out)))
      (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  Future<void> run(
    FakeServices services, {
    String? sha,
    List<String> extra = const [],
  }) => CommandRunner<void>('xcross', 'test')
      .addCommandAnd(
        ScreenTouchSetupCommand(
          services: services,
          workRoot: work.path,
          writeBytes: out.addAll,
          expectedSha256: sha ?? sha256.convert(services.zip).toString(),
        ),
      )
      .run(['touch-setup', '--udid', 'UDID1', '--json', ...extra]);

  test('AC-048-T5 a FAT file keeps only its plain arm64 slice', () {
    final fat = _fat(x86: [1, 2], arm: [9, 8, 7]);
    expect(TouchHelperPackage.arm64Slice(fat), [9, 8, 7]);
    expect(
      TouchHelperPackage.arm64Slice(Uint8List.fromList([1, 2, 3])),
      isNull,
    );
    expect(
      TouchHelperPackage.arm64Slice(
        Uint8List.fromList([0xFE, 0xED, 0xFA, 0xCF, 0, 0, 0, 0]),
      ),
      isNull,
      reason: 'a thin Mach-O stays as it is',
    );
  });

  test(
    'AC-048-T6 setup downloads, prepares, signs and installs; the download is reused',
    () async {
      final services = FakeServices(_runnerZip());
      await run(services);
      expect(events().map((e) => e['step'] ?? e['type']), [
        'download',
        'prepare',
        'build',
        'sign',
        'install',
        'touch_setup_done',
      ]);
      final done = events().last;
      expect(done['ok'], true);
      expect(done['fast'], true);
      expect(services.builtFrom, contains('@interface XcrossTouchRunner'));
      expect(
        services.testBundleAtSign,
        FakeServices.builtBinary,
        reason: 'our runner in place of WebDriverAgent',
      );
      expect(services.frameworksAtSign, isFalse);
      expect(done['bundleId'], 'XCR-TEAM.${TouchHelperRelease.bundleId}');
      expect(services.installedApp, services.signedApp);
      expect(
        services.appFilesAtSign!.where((f) => f.contains('.dSYM')),
        isEmpty,
      );
      expect(services.runnerAtSign, [7, 7, 7, 7], reason: 'arm64 slice only');
      // iOS is case-sensitive: names on disk must keep their exact case
      // (Windows would open them either way, so check the listing itself).
      expect(p.basename(services.signedApp!), TouchHelperRelease.appName);
      expect(
        services.appFilesAtSign,
        containsAll([
          'PlugIns',
          'PlugIns/WebDriverAgentRunner.xctest',
          'WebDriverAgentRunner-Runner',
        ]),
      );
      expect(
        File(p.join(work.path, 'escape.txt')).existsSync() ||
            File(p.join(work.parent.path, 'escape.txt')).existsSync(),
        isFalse,
        reason: 'archive paths never leave the folder',
      );

      out.clear();
      await run(services);
      expect(services.downloads, 1, reason: 'the checked download is kept');
      expect(events().first['step'], 'prepare');
    },
  );

  test(
    'AC-048-T7 a download with the wrong SHA-256 is refused and removed',
    () async {
      final services = FakeServices(_runnerZip());
      await expectLater(run(services, sha: '0' * 64), throwsA(isA<CliError>()));
      final done = events().last;
      expect(done['ok'], false);
      expect(done['step'], 'download');
      expect(done['message'], contains('SHA-256'));
      expect(services.signedApp, isNull);
      expect(
        work.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')),
        isEmpty,
      );
    },
  );

  test(
    'AC-048-T8 a signing problem stops the setup with its message',
    () async {
      final services = FakeServices(_runnerZip(), signFails: true);
      await expectLater(run(services), throwsA(isA<CliError>()));
      final done = events().last;
      expect(done['ok'], false);
      expect(done['step'], 'sign');
      expect(done['message'], contains('Sign in to your Apple account'));
      expect(services.installedApp, isNull);
    },
  );

  test(
    'AC-048-T11 the fast helper cannot be built here (or --wda): WebDriverAgent is installed instead',
    () async {
      final services = FakeServices(_runnerZip(), buildFails: true);
      await run(services);
      final done = events().last;
      expect(done['ok'], true);
      expect(done['fast'], false);
      expect(
        events().where((e) => e['step'] == 'build').last['detail'],
        allOf(contains('No iOS SDK'), contains('WebDriverAgent')),
      );
      expect(services.testBundleAtSign, [5, 5, 5]);
      expect(services.frameworksAtSign, isTrue);

      out.clear();
      final wda = FakeServices(_runnerZip());
      await run(wda, extra: ['--wda']);
      expect(wda.builtFrom, isNull, reason: '--wda skips the build');
      expect(events().last['fast'], false);
    },
  );
}

extension on CommandRunner<void> {
  CommandRunner<void> addCommandAnd(Command<void> command) {
    addCommand(command);
    return this;
  }
}
