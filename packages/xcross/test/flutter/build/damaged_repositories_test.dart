// studio: 025 — unusable repositories in SwiftPM's shared cache.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/host/windows/flutter/swiftpm/damaged_repositories.dart';

import 'plugin_overrides_test.dart' as overrides;

void main() {
  late Directory temp;
  late String folder;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xcross_damaged_');
    folder = temp.path;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  SwiftPmDamagedRepositories repositories({DateTime? now}) =>
      SwiftPmDamagedRepositories(
        const overrides.OverrideTestFileSystem(),
        clock: now == null ? null : () => now,
      );

  String repository(String name, List<String> paths) {
    final root = p.join(folder, name);
    Directory(root).createSync();
    for (final path in paths) {
      if (path.endsWith('/')) {
        Directory(p.join(root, path)).createSync(recursive: true);
      } else {
        File(p.join(root, path))
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
    }
    return root;
  }

  test('AC-025-9 the shapes found in the cache cannot be read', () {
    final tool = repositories();
    expect(tool.isUsable(repository('only-objects', ['objects/'])), isFalse);
    expect(
      tool.isUsable(
        repository('no-tags', ['FETCH_HEAD', 'HEAD', 'objects/', 'refs/']),
      ),
      isFalse,
    );
    expect(
      tool.isUsable(
        repository('no-refs-folder', ['HEAD', 'objects/', 'packed-refs']),
      ),
      isFalse,
    );
  });

  test('AC-025-9 a repository with packed refs or tags can', () {
    final tool = repositories();
    expect(
      tool.isUsable(
        repository('packed', [
          'config',
          'HEAD',
          'objects/',
          'refs/',
          'packed-refs',
        ]),
      ),
      isTrue,
    );
    expect(
      tool.isUsable(
        repository('loose', ['config', 'HEAD', 'objects/', 'refs/tags/1.0']),
      ),
      isTrue,
    );
  });

  test('a repository without its config lost files to Windows cleanup, even '
      'with tags (app-check, 2026-11-12)', () {
    expect(
      repositories().isUsable(
        repository('app-check', [
          'FETCH_HEAD',
          'HEAD',
          'objects/',
          'refs/',
          'packed-refs',
        ]),
      ),
      isFalse,
    );
  });

  test('missing git objects are taken as a damaged cache', () {
    expect(
      SwiftPmDamagedRepositories.explains(
        r"error: the package at '\' cannot be accessed (Couldn't read "
        "'11.3.2':\n    fatal: not a tree object)",
      ),
      isTrue,
    );
    expect(
      SwiftPmDamagedRepositories.explains('fatal: bad object 1a2b3c'),
      isTrue,
    );
  });

  test('AC-025-9 only unusable repositories are removed', () async {
    final good = repository('good', [
      'config',
      'HEAD',
      'objects/',
      'refs/',
      'packed-refs',
    ]);
    final bad = repository('bad', ['objects/pack/a.pack']);
    // Git's pack files are read-only.
    Process.runSync('attrib', [
      '+R',
      p.join(bad, 'objects', 'pack', 'a.pack'),
    ], runInShell: Platform.isWindows);

    expect(await repositories().removeFrom(folder), ['bad']);
    expect(Directory(good).existsSync(), isTrue);
    expect(Directory(bad).existsSync(), isFalse);
  }, testOn: 'windows');

  test(
    'AC-025-9 a new entry may be a clone in progress, so it stays',
    () async {
      final bad = repository('bad', ['objects/']);
      final tool = repositories(now: DateTime.now());
      expect(
        await tool.removeFrom(
          folder,
          minimumAge: SwiftPmDamagedRepositories.sharedCacheMinimumAge,
        ),
        isEmpty,
      );
      expect(Directory(bad).existsSync(), isTrue);

      final later = repositories(
        now: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(
        await later.removeFrom(
          folder,
          minimumAge: SwiftPmDamagedRepositories.sharedCacheMinimumAge,
        ),
        ['bad'],
      );
    },
  );

  test('AC-025-9 a missing folder is nothing to do', () async {
    expect(
      await repositories().removeFrom(p.join(folder, 'not-there')),
      isEmpty,
    );
  });

  test('AC-025-9 only the no-versions failure is taken as a damaged cache', () {
    expect(
      SwiftPmDamagedRepositories.explains(
        "error: Dependencies could not be resolved because no versions of 'x' "
        'match the requirement 1.0.0..<2.0.0',
      ),
      isTrue,
    );
    expect(SwiftPmDamagedRepositories.explains('network down'), isFalse);
  });

  test('the no-versions failure at the end of a dependency chain is a '
      'damaged cache too (2026-11-12, gtm-session-fetcher)', () {
    expect(
      SwiftPmDamagedRepositories.explains(
        "error: Dependencies could not be resolved because 'firebase_messaging' "
        "depends on 'firebase-ios-sdk' 13.0.0.\n'firebase-ios-sdk' 13.0.0 "
        "cannot be used because 'firebase-ios-sdk' 13.0.0 depends on "
        "'gtm-session-fetcher' 4.0.0..<6.0.0 and no versions of "
        "'gtm-session-fetcher' match the requirement 4.0.0..<6.0.0.",
      ),
      isTrue,
    );
    expect(
      SwiftPmDamagedRepositories.explains(
        "error: Dependencies could not be resolved because 'a' depends on "
        "'b' 2.0.0 and root depends on 'b' 1.0.0.",
      ),
      isFalse,
      reason: 'a real version conflict is not a damaged cache',
    );
  });

  test("the shared caches: the home folder and Swift 6's Temp folder", () {
    expect(SwiftPmDamagedRepositories.sharedCaches(home: 'home'), [
      p.join('home', '.swiftpm', 'cache', 'repositories'),
    ]);
    final temp = p.join('U', 'AppData', 'Local', 'Temp');
    expect(
      SwiftPmDamagedRepositories.sharedCaches(
        home: 'U',
        temp: temp,
        localAppData: p.join('U', 'AppData', 'Local'),
      ),
      [
        p.join('U', '.swiftpm', 'cache', 'repositories'),
        p.join(temp, 'org.swift.swiftpm', 'repositories'),
      ],
      reason: r'TEMP and LOCALAPPDATA\Temp are the same folder: listed once',
    );
    expect(SwiftPmDamagedRepositories.sharedCaches(), isEmpty);
  });
}
