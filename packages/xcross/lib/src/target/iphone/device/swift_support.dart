// studio: 018 — the Swift runtime libraries an App Store IPA carries in
// `SwiftSupport/iphoneos/` (App Store Connect error 90426 without it).
import 'dart:io';
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/release/swift_runtime.dart';
import 'package:xcross/src/shared/sdk/sdk_install_constants.dart';

/// The libraries a built app needs in SwiftSupport, taken from the installed
/// SDK the way Xcode takes them from its toolchain.
@internal
final class SwiftSupport {
  const SwiftSupport({this.files = const {}, this.missing = const []});

  /// Folder of the libraries, at the root of the IPA and of the archive.
  static const folder = 'SwiftSupport/iphoneos';

  /// IPA entry name (`SwiftSupport/iphoneos/libswiftCore.dylib`) to the file.
  final Map<String, String> files;

  /// Libraries the app loads through its rpath, not weakly, that the SDK does
  /// not have.
  final List<String> missing;

  bool get isEmpty => files.isEmpty;

  /// Reads every Mach-O file of [appPath], collects the Swift runtime
  /// libraries they load (and those libraries' own Swift dependencies), and
  /// finds each in [sdkBundle]. [sdkBundle] is null when no SDK is installed.
  static Future<SwiftSupport> collect({
    required HostFileSystemInterface fileSystem,
    required String appPath,
    required String? sdkBundle,
  }) async {
    final binaries = <Uint8List>[];
    await for (final entity
        in fileSystem.directory(appPath).list(recursive: true)) {
      if (entity is! File) continue;
      if (!await _isMachO(entity)) continue;
      binaries.add(await entity.readAsBytes());
    }
    final needed = swiftRuntimeLibraries(binaries);
    if (needed.isEmpty) return const SwiftSupport();

    final folders = [
      if (sdkBundle != null)
        for (final relative in sdkSwiftRuntimeRelativePaths)
          p.joinAll([sdkBundle, ...relative.split('/')]),
    ];
    final found = <String, String>{};
    final missing = <String>[];
    final queue = needed.values.toList();
    final seen = {for (final library in queue) library.fileName};
    while (queue.isNotEmpty) {
      final library = queue.removeLast();
      String? path;
      for (final directory in folders) {
        final candidate = p.join(directory, library.fileName);
        if (fileSystem.file(candidate).existsSync()) {
          path = candidate;
          break;
        }
      }
      if (path == null) {
        // Only the ones found through the app's own rpath are demanded.
        if (library.required) missing.add(library.fileName);
        continue;
      }
      found['$folder/${library.fileName}'] = path;
      final dependencies = swiftRuntimeLibraries([
        await fileSystem.file(path).readAsBytes(),
      ]);
      for (final dependency in dependencies.values) {
        if (seen.add(dependency.fileName)) {
          queue.add(SwiftRuntimeLibrary(dependency.fileName, viaRpath: false));
        }
      }
    }
    return SwiftSupport(
      files: Map.fromEntries(
        found.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      missing: missing..sort(),
    );
  }

  /// Copies every library of [files] into `<appPath>/Frameworks`, where Xcode
  /// also keeps them: App Store Connect refuses an IPA whose SwiftSupport
  /// holds a library the app does not embed (90429). Call before signing, so
  /// the copies get the app's signature.
  Future<void> embed({
    required HostFileSystemInterface fileSystem,
    required String appPath,
  }) async {
    if (files.isEmpty) return;
    final frameworks = p.join(appPath, 'Frameworks');
    await fileSystem.directory(frameworks).create(recursive: true);
    for (final entry in files.entries) {
      final target = p.join(frameworks, p.basename(entry.key));
      if (fileSystem.file(target).existsSync()) continue;
      await fileSystem.file(entry.value).copy(target);
    }
  }

  static Future<bool> _isMachO(File file) async {
    final handle = await file.open();
    try {
      final head = await handle.read(4);
      if (head.length < 4) return false;
      final magic =
          (head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3];
      return const {
        0xfeedface,
        0xfeedfacf,
        0xcefaedfe,
        0xcffaedfe,
        0xcafebabe,
        0xbebafeca,
        0xcafebabf,
        0xbfbafeca,
      }.contains(magic);
    } finally {
      await handle.close();
    }
  }
}
