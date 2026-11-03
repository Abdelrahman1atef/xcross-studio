// studio: 018 — SwiftPM resource bundles are embedded with files, not links
// (specs/018-app-store-build).
import 'dart:io';

import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/swiftpm/resource_bundle_copy.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('resource-bundle-'));
  tearDown(() => root.deleteSync(recursive: true));

  String write(String relative, String text) {
    final file = File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    return file.path;
  }

  /// Creates a relative link, or returns false where links are not allowed.
  bool link(String relative, String target) {
    final path = p.join(root.path, relative);
    Directory(p.dirname(path)).createSync(recursive: true);
    try {
      Link(path).createSync(target);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  ResourceBundleCopier copier() => ResourceBundleCopier(
    fileSystem: detectPlatformHost().fileSystem,
    paths: p.context,
  );

  test('a link SwiftPM copied out of its package is replaced by the file it '
      'points at in the checkout', () async {
    // The package: `Resources/PrivacyInfo.xcprivacy` links to a file two
    // levels up, as in SDWebImage.
    write('checkouts/Pkg/WebImage/PrivacyInfo.xcprivacy', 'manifest');
    final made =
        link(
          'checkouts/Pkg/Pkg/Resources/PrivacyInfo.xcprivacy',
          p.join('..', '..', 'WebImage', 'PrivacyInfo.xcprivacy'),
        ) &&
        // SwiftPM's copy: the same link text, dangling in the bundle.
        link(
          'products/Pkg_Pkg.bundle/PrivacyInfo.xcprivacy',
          p.join('..', '..', 'WebImage', 'PrivacyInfo.xcprivacy'),
        );
    if (!made) {
      markTestSkipped('symbolic links cannot be created here');
      return;
    }
    write('products/Pkg_Pkg.bundle/en.lproj/Strings.strings', 'strings');

    final app = p.join(root.path, 'Runner.app', 'Pkg_Pkg.bundle');
    final skipped = await copier().copy(
      p.join(root.path, 'products', 'Pkg_Pkg.bundle'),
      app,
      packageRoots: [p.join(root.path, 'checkouts')],
    );

    expect(skipped, isEmpty);
    final manifest = p.join(app, 'PrivacyInfo.xcprivacy');
    expect(FileSystemEntity.isLinkSync(manifest), isFalse);
    expect(File(manifest).readAsStringSync(), 'manifest');
    expect(
      File(p.join(app, 'en.lproj', 'Strings.strings')).readAsStringSync(),
      'strings',
    );
  });

  test('a link that resolves is copied as its file; links to folders are '
      'copied as folders', () async {
    write('shared/Assets/a.png', 'png');
    write('shared/note.txt', 'note');
    final made =
        link(
          'products/P_T.bundle/note.txt',
          p.join('..', '..', 'shared', 'note.txt'),
        ) &&
        link(
          'products/P_T.bundle/Assets',
          p.join(root.path, 'shared', 'Assets'),
        );
    if (!made) {
      markTestSkipped('symbolic links cannot be created here');
      return;
    }
    final app = p.join(root.path, 'Runner.app', 'P_T.bundle');
    final skipped = await copier().copy(
      p.join(root.path, 'products', 'P_T.bundle'),
      app,
    );
    expect(skipped, isEmpty);
    expect(FileSystemEntity.isLinkSync(p.join(app, 'note.txt')), isFalse);
    expect(File(p.join(app, 'note.txt')).readAsStringSync(), 'note');
    expect(FileSystemEntity.isLinkSync(p.join(app, 'Assets')), isFalse);
    expect(File(p.join(app, 'Assets', 'a.png')).readAsStringSync(), 'png');
  });

  test('a link found nowhere is left out and reported', () async {
    write('products/P_T.bundle/keep.txt', 'keep');
    if (!link('products/P_T.bundle/gone.txt', p.join('..', 'missing.txt'))) {
      markTestSkipped('symbolic links cannot be created here');
      return;
    }
    final app = p.join(root.path, 'Runner.app', 'P_T.bundle');
    final skipped = await copier().copy(
      p.join(root.path, 'products', 'P_T.bundle'),
      app,
      packageRoots: [p.join(root.path, 'checkouts')],
    );
    expect(skipped, ['gone.txt']);
    expect(File(p.join(app, 'keep.txt')).existsSync(), isTrue);
    expect(
      FileSystemEntity.typeSync(p.join(app, 'gone.txt'), followLinks: false),
      FileSystemEntityType.notFound,
    );
  });
}
