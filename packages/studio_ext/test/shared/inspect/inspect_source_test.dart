import 'dart:io';
import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/inspect_failure.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/test_file_system.dart';

void main() {
  late Directory temp;
  const fs = IoFileSystem();

  setUp(() => temp = Directory.systemTemp.createTempSync('inspect_source_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Matcher failsWith(String code) =>
      throwsA(isA<InspectFailure>().having((f) => f.code, 'code', code));

  String writeFile(String name, List<int> bytes) {
    final file = File('${temp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  test('reads an IPA: bundle path, sorted entries, hash and size', () {
    for (final compress in [false, true]) {
      final path = unsignedV209().writeIpa(temp, 'app.ipa', compress: compress);
      final source = InspectSource.open(fs, path);
      try {
        expect(source.kind, InputKind.ipa);
        expect(source.name, 'app.ipa');
        expect(source.bundlePath, 'Payload/Runner.app');
        expect(source.files, contains('Frameworks/App.framework/App'));
        expect(source.files, [...source.files]..sort());
        expect(source.hasDirectory('Frameworks/App.framework'), isTrue);
        expect(source.hasFile('Info.plist'), isTrue);
        expect(source.sizeBytes, File(path).lengthSync());
        expect(source.sha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(source.read('Runner'), unsignedV209().files['Runner']);
        expect(source.read('missing'), isNull);
      } finally {
        source.close();
      }
    }
  });

  test(r'reads a .app directory, also through a \\?\ long path', () {
    final path = adhocPush().writeApp(temp, directoryName: 'My.app');
    for (final longPaths in [false, true]) {
      final source = InspectSource.open(
        IoFileSystem(longPathPrefix: longPaths),
        path,
      );
      expect(source.kind, InputKind.app);
      expect(source.name, 'My.app');
      expect(source.bundlePath, '.');
      expect(source.sizeBytes, isNull);
      expect(source.sha256Hex, isNull);
      expect(source.files, contains('_CodeSignature/CodeResources'));
      expect(source.hasDirectory('_CodeSignature'), isTrue);
      expect(source.sizeOf('LaunchImage.png'), fakePng.length);
      expect(source.read('LaunchImage.png'), fakePng);
      source.close();
    }
  });

  test('fatal errors use stable codes', () {
    expect(
      () => InspectSource.open(fs, '${temp.path}/missing.ipa'),
      failsWith('inspect.input_not_found'),
    );
    expect(
      () => InspectSource.open(fs, writeFile('notes.txt', [1, 2])),
      failsWith('inspect.unsupported_input'),
    );
    expect(
      () => InspectSource.open(fs, writeFile('bad.ipa', [1, 2, 3, 4])),
      failsWith('inspect.corrupt_archive'),
    );
    expect(
      () => InspectSource.open(
        fs,
        writeFile(
          'empty.ipa',
          encodeZip({
            'Payload/readme.txt': Uint8List.fromList([1]),
          }),
        ),
      ),
      failsWith('inspect.no_app'),
    );
    expect(
      () => InspectSource.open(
        fs,
        writeFile(
          'two.ipa',
          encodeZip({
            'Payload/A.app/Info.plist': Uint8List.fromList([1]),
            'Payload/B.app/Info.plist': Uint8List.fromList([1]),
          }),
        ),
      ),
      failsWith('inspect.multiple_apps'),
    );
    final directory = Directory('${temp.path}/folder')..createSync();
    expect(
      () => InspectSource.open(fs, directory.path),
      failsWith('inspect.unsupported_input'),
    );
  });

  test(
    'symlinks inside a .app directory are skipped and listed',
    () {
      final path = adhocPush().writeApp(temp, directoryName: 'Link.app');
      Link('$path/Alias.png').createSync('$path/LaunchImage.png');
      final source = InspectSource.open(fs, path);
      expect(source.skippedSymlinks, ['Alias.png']);
      expect(source.hasFile('Alias.png'), isFalse);
    },
    skip: Platform.isWindows
        ? 'creating symlinks on Windows needs Developer Mode or admin rights'
        : false,
  );

  test('basenameOf handles both separators and trailing separators', () {
    expect(basenameOf(r'C:\a\b\App.ipa'), 'App.ipa');
    expect(basenameOf('/a/b/Runner.app/'), 'Runner.app');
    expect(basenameOf('Runner.app'), 'Runner.app');
  });
}
