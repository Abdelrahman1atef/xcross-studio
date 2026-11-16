import 'dart:io';

import 'package:archive/archive.dart';
import 'package:studio_ext/src/shared/pods/pod_archive.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late PodArchive extractor;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pod-archive-test-');
    extractor = const PodArchive(
      directoryFactory: Directory.new,
      fileFactory: File.new,
    );
  });
  tearDown(() => root.delete(recursive: true));

  test('AC-046-6 extracts a zip atomically and flattens one root', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('repo/Sources/A.m', 'content'))
      ..addFile(ArchiveFile.string('repo/LICENSE', 'MIT'));
    final destination = Directory('${root.path}/source');
    await extractor.extract(
      ZipEncoder().encode(archive),
      'zip',
      destination,
      flatten: true,
    );
    expect(
      File('${destination.path}/Sources/A.m').readAsStringSync(),
      'content',
    );
    expect(File('${destination.path}/LICENSE').existsSync(), isTrue);
    expect(
      root.listSync().where((entry) => entry.path.contains('.tmp-')),
      isEmpty,
    );
  });

  test('AC-046-6 extracts each supported tar compression', () async {
    final tar = TarEncoder().encode(
      Archive()..addFile(ArchiveFile.string('Sources/A.m', 'source')),
    );
    final archives = <String, List<int>>{
      'tar': tar,
      'tgz': const GZipEncoder().encode(tar),
      'tbz': BZip2Encoder().encode(tar),
      'txz': XZEncoder().encode(tar),
    };
    for (final entry in archives.entries) {
      final destination = Directory('${root.path}/${entry.key}');
      await extractor.extract(entry.value, entry.key, destination);
      expect(
        File('${destination.path}/Sources/A.m').readAsStringSync(),
        'source',
        reason: entry.key,
      );
    }
  });

  test('AC-046-6 rejects traversal, absolute, and drive-letter entries', () {
    for (final name in [
      '../outside',
      '/absolute',
      r'C:\outside',
      'a/.. /outside',
    ]) {
      expect(
        () => extractor.validateName(name),
        throwsA(isA<UnsafePodArchive>()),
        reason: name,
      );
    }
  });

  test('AC-046-6 converts an internal symlink to a copy', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('repo/original.h', 'header'))
      ..addFile(ArchiveFile.symlink('repo/alias.h', 'original.h'));
    final destination = Directory('${root.path}/source');
    await extractor.extract(
      TarEncoder().encode(archive),
      'tar',
      destination,
      flatten: true,
    );
    expect(File('${destination.path}/alias.h').readAsStringSync(), 'header');
  });

  test('AC-046-6 rejects an outside symlink', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.symlink('alias.h', '../outside'));
    final destination = Directory('${root.path}/source');
    await expectLater(
      extractor.extract(TarEncoder().encode(archive), 'tar', destination),
      throwsA(isA<UnsafePodArchive>()),
    );
    expect(destination.existsSync(), isFalse);
  });

  test('AC-046-6 skips non-iOS xcframework slices', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('SDK.xcframework/ios-arm64/SDK', 'ios'))
      ..addFile(ArchiveFile.string('SDK.xcframework/macos-arm64/SDK', 'mac'));
    final destination = Directory('${root.path}/source');
    await extractor.extract(ZipEncoder().encode(archive), 'zip', destination);
    expect(
      File('${destination.path}/SDK.xcframework/ios-arm64/SDK').existsSync(),
      isTrue,
    );
    expect(
      File('${destination.path}/SDK.xcframework/macos-arm64/SDK').existsSync(),
      isFalse,
    );
  });

  test('AC-046-6 flags an LFS pointer for git fallback', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'SDK.xcframework/ios-arm64/SDK',
          'version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 5\n',
        ),
      );
    final destination = Directory('${root.path}/source');
    await expectLater(
      extractor.extract(ZipEncoder().encode(archive), 'zip', destination),
      throwsA(isA<PodLfsPointer>()),
    );
    expect(destination.existsSync(), isFalse);
  });
}
