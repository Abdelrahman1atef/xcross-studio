// studio: 011 — the IPA writer and the post-sign check of `xcross sign`.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/inspect/signed_bundle_check.dart';
import 'package:studio_ext/shared/ipa/ipa_writer.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/test_file_system.dart';

void main() {
  late Directory temp;
  const fileSystem = IoFileSystem();
  final writer = IpaWriter(fileSystem: fileSystem, paths: p.context);

  setUp(() => temp = Directory.systemTemp.createTempSync('studio_sign_'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// `profileAppex` without the xcross hand-off keys: what a correct
  /// `xcross sign` output looks like.
  FixtureBundle signedBundle() {
    final bundle = profileAppex();
    return FixtureBundle(bundle.appName, {
      ...bundle.files,
      'Info.plist': xmlPlist(baseInfoPlist(bundleId: 'com.example.profile')),
    });
  }

  /// Central-directory "version made by" host byte of every entry.
  List<int> madeByHosts(Uint8List zip) {
    final data = ByteData.sublistView(zip);
    final hosts = <int>[];
    for (var i = 0; i + 46 <= zip.length; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014B50) hosts.add(zip[i + 5]);
    }
    return hosts;
  }

  test('AC-011-3 the IPA is Payload/<App>.app, sorted, with Unix modes', () {
    final app = signedBundle().writeApp(temp);
    final ipa = writer.write(app, p.join(temp.path, 'out', 'Signed.ipa'));
    final bytes = File(ipa).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = [for (final f in archive.files) f.name];
    expect(names.take(2), ['Payload/', 'Payload/Runner.app/']);
    expect(names.skip(2).toList(), [...names.skip(2)]..sort());
    expect(names, contains('Payload/Runner.app/_CodeSignature/'));
    expect(names, contains('Payload/Runner.app/embedded.mobileprovision'));
    ArchiveFile entry(String name) =>
        archive.files.singleWhere((f) => f.name == 'Payload/Runner.app/$name');
    expect(entry('Runner').mode & 0x1FF, 0x1ED, reason: 'Mach-O is 0755');
    expect(entry('Info.plist').mode & 0x1FF, 0x1A4, reason: 'data is 0644');
    expect(madeByHosts(bytes).toSet(), {3}, reason: 'made on Unix');
    expect(File('$ipa.part').existsSync(), isFalse);
  });

  test('AC-011-3 the same bundle gives the same bytes', () {
    final app = signedBundle().writeApp(temp);
    final a = writer.write(app, p.join(temp.path, 'a.ipa'));
    sleep(const Duration(milliseconds: 1100));
    File(p.join(app, 'Info.plist')).setLastModifiedSync(DateTime.now());
    final b = writer.write(app, p.join(temp.path, 'b.ipa'));
    expect(File(a).readAsBytesSync(), File(b).readAsBytesSync());
  });

  test('AC-011-4 a certificate-signed bundle with a profile passes', () {
    final app = signedBundle().writeApp(temp);
    final ipa = writer.write(app, p.join(temp.path, 'Signed.ipa'));
    final check = SignedBundleCheck.run(fileSystem, ipa);
    expect(check.problems, isEmpty);
    expect(check.ok, isTrue);
    expect(check.bundleId, 'com.example.profile');
    expect(check.teamId, 'TEAMID1234');
    expect(check.profileKind, 'development');
    expect(check.entitlementKeys, contains('aps-environment'));
    final summary = check.summaryLines().join('\n');
    expect(summary, contains('development · expires'));
    expect(summary, contains('team TEAMID1234'));
    expect(summary, isNot(contains('00008')), reason: 'no device ids');
  });

  test('AC-011-4 unsigned, leftover keys and unreadable inputs fail', () {
    final unsigned = SignedBundleCheck.run(
      fileSystem,
      unsignedV209().writeIpa(temp, 'unsigned.ipa'),
    );
    expect(unsigned.ok, isFalse);
    expect(
      unsigned.problems.join('\n'),
      contains('no embedded.mobileprovision'),
    );
    expect(
      unsigned.problems.join('\n'),
      contains('not signed with a certificate'),
    );

    final leftover = SignedBundleCheck.run(
      fileSystem,
      profileAppex().writeIpa(temp, 'leftover.ipa'),
    );
    expect(leftover.problems.join('\n'), contains('XCrossEntitlements'));

    final broken = File(p.join(temp.path, 'broken.ipa'))
      ..writeAsStringSync('not a zip');
    final unreadable = SignedBundleCheck.run(fileSystem, broken.path);
    expect(unreadable.ok, isFalse);
    expect(unreadable.problems.single, startsWith('[inspect.'));
  });

  test('isMachO knows thin and fat magics', () {
    expect(IpaWriter.isMachO([0xCF, 0xFA, 0xED, 0xFE]), isTrue);
    expect(IpaWriter.isMachO([0xCA, 0xFE, 0xBA, 0xBE]), isTrue);
    expect(IpaWriter.isMachO([0x3C, 0x3F, 0x78, 0x6D]), isFalse);
    expect(IpaWriter.isMachO([0xCF]), isFalse);
  });
}
