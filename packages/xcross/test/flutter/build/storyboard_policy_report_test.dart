// studio: 002 — removed storyboard references are reported.
import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/artifact/plist_storyboard_policy.dart';

void main() {
  late Directory bundle;

  setUp(() {
    bundle = Directory.systemTemp.createTempSync('xcross-storyboards-');
    Directory(p.join(bundle.path, 'Main.storyboardc')).createSync();
  });
  tearDown(() => bundle.deleteSync(recursive: true));

  test('AC-002-14 every removed storyboard reference is reported', () {
    final removed = <String>[];
    final result =
        PlistStoryboardPolicy(
          const NativeTestFileSystem(),
          p.context,
        ).stripUnsatisfiableStoryboards(
          '<key>UIMainStoryboardFile</key><string>Main</string>'
          '<key>UILaunchStoryboardName</key><string>LaunchScreen</string>'
          '<key>UISceneStoryboardFile</key><string>Scene</string>',
          bundle.path,
          onRemoved: (key, name) => removed.add('$key=$name'),
        );
    expect(removed, [
      'UILaunchStoryboardName=LaunchScreen',
      'UISceneStoryboardFile=Scene',
    ]);
    expect(result, contains('<string>Main</string>'), reason: 'compiled');
    expect(result, contains('UILaunchScreen'));
    expect(result, isNot(contains('LaunchScreen</string>')));
  });
}

/// dart:io-backed host file system for tests that need real paths.
@internal
final class NativeTestFileSystem implements HostFileSystemInterface {
  const NativeTestFileSystem();

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
  Future<void> createArchiveLink(String destination, String target) =>
      Link(destination).create(target);
}
