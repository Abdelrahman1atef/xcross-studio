import 'dart:async';
import 'dart:io';

import 'package:studio_ext/shared/pods/pod_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late PodCache cache;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pod-cache-test-');
    cache = PodCache(
      root: root,
      fileFactory: File.new,
      directoryFactory: Directory.new,
      processAlive: (pid) => pid == 42,
      processId: 42,
    );
  });
  tearDown(() => root.delete(recursive: true));

  test('AC-046-28 makes stable short keys and safe paths', () {
    final key = cache.key12('pod@1.0');
    expect(key, hasLength(12));
    expect(cache.key12('pod@1.0'), key);
    expect(cache.source(key).path, contains('sources'));
    expect(cache.package('Pod', '1.0', key).path, contains('1.0-$key'));
    expect(() => cache.package('../bad', '1.0', key), throwsArgumentError);
  });

  test('AC-046-28 serializes two cache users', () async {
    final key = cache.key12('same');
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = cache.withLock(key, () async {
      entered.complete();
      await release.future;
      return 'first';
    });
    await entered.future;
    var secondEntered = false;
    final second = cache.withLock(key, () async {
      secondEntered = true;
      return 'second';
    });
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(secondEntered, isFalse);
    release.complete();
    expect(await first, 'first');
    expect(await second, 'second');
    expect(cache.lockFile(key).existsSync(), isFalse);
  });

  test('AC-046-28 takes over a stale lock', () async {
    final key = cache.key12('stale');
    final lock = cache.lockFile(key);
    await lock.parent.create(recursive: true);
    await lock.writeAsString('999999:old');
    expect(await cache.withLock(key, () async => 7), 7);
    expect(lock.existsSync(), isFalse);
  });

  test('AC-046-28 serializes two OS processes', () async {
    final key = cache.key12('processes');
    final helper =
        File('test/fixtures/pods/cache_lock_helper.dart').existsSync()
        ? 'test/fixtures/pods/cache_lock_helper.dart'
        : 'packages/studio_ext/test/fixtures/pods/cache_lock_helper.dart';
    Future<Process> start(String label) => Process.start(
      Platform.resolvedExecutable,
      ['run', helper, root.path, key, label],
      mode: ProcessStartMode.inheritStdio,
    );
    Future<void> until(File marker) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!marker.existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Timed out waiting for ${marker.path}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    final first = await start('first');
    await until(File('${root.path}/entered-first'));
    final second = await start('second');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(File('${root.path}/entered-second').existsSync(), isFalse);
    File('${root.path}/release-first').writeAsStringSync('yes');
    expect(await first.exitCode, 0);
    await until(File('${root.path}/entered-second'));
    File('${root.path}/release-second').writeAsStringSync('yes');
    expect(await second.exitCode, 0);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('AC-046-28 lists and clears pod entries after confirmation', () async {
    final key = cache.key12('entry');
    await cache.source(key).create(recursive: true);
    await cache.package('A', '1.0', key).create(recursive: true);
    expect(cache.listEntries(), hasLength(2));
    await expectLater(cache.clear(confirmed: false), throwsStateError);
    await cache.clear(confirmed: true);
    expect(cache.listEntries(), isEmpty);
  });

  test('AC-046-28 explains a hard-link failure', () async {
    final linking = PodCache(
      root: root,
      fileFactory: File.new,
      directoryFactory: Directory.new,
      processAlive: (_) => true,
      processId: 42,
      createHardLink: (_, _) async =>
          throw const FileSystemException('no links'),
    );
    await expectLater(
      linking.link(File('${root.path}/source'), File('${root.path}/dest')),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('one volume'),
        ),
      ),
    );
  });

  test('AC-046-28 seals every file in a cache entry', () async {
    final paths = <String>[];
    final sealing = PodCache(
      root: root,
      fileFactory: File.new,
      directoryFactory: Directory.new,
      processAlive: (_) => true,
      processId: 42,
      makeReadOnly: (path) async => paths.add(path),
    );
    final source = cache.source(cache.key12('seal'));
    await source.create(recursive: true);
    await File('${source.path}/A.h').writeAsString('header');
    await sealing.seal(source);
    expect(paths.single, endsWith('A.h'));
  });
}
