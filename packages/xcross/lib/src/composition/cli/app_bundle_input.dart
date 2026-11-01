// studio: 005/011 — a private, signable copy of a user's `.ipa` or `.app`
// (shared by `xcross install` and `xcross sign`).
@internal
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';

/// Prepares the input of `xcross install` / `xcross sign`: the user's file is
/// never modified; the signer works on a copy under a work folder.
@internal
final class AppBundleInput {
  const AppBundleInput({required this.fileSystem, required this.paths});

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// A private copy of the app bundle under [work]: an `.ipa` is extracted
  /// (exactly one `Payload/*.app`), an `.app` is copied. [forSigning]
  /// rewrites binary Info.plists (app and extensions) as XML, which the
  /// signer edits; without it the copy stays byte-identical, so an existing
  /// signature still holds.
  String prepare(String input, String work, {bool forSigning = true}) {
    final trimmed = input.replaceAll(RegExp(r'[\\/]+$'), '');
    final lower = trimmed.toLowerCase();
    final String appPath;
    if (fileSystem.directory(input).existsSync() && lower.endsWith('.app')) {
      appPath = paths.join(work, paths.basename(trimmed));
      _copyDirectory(fileSystem.directory(input), appPath);
    } else if (fileSystem.file(input).existsSync() && lower.endsWith('.ipa')) {
      appPath = _extractIpa(input, work);
    } else {
      throw codedError(
        XcrossCodes.installUnsupportedInput,
        '${paths.basename(input)} is not an existing .ipa file or .app '
        'directory.',
      );
    }
    if (forSigning) _xmlInfoPlists(appPath);
    return appPath;
  }

  /// `CFBundleIdentifier` from the bundle's Info.plist (binary or XML).
  String bundleId(String appPath) {
    final id = _infoPlist(appPath)['CFBundleIdentifier'];
    if (id is! String || id.isEmpty) {
      throw codedError(
        XcrossCodes.installNoApp,
        '${paths.basename(appPath)} has no CFBundleIdentifier.',
      );
    }
    return id;
  }

  /// Replaces `CFBundleIdentifier` (studio: 011, `xcross sign --bundle-id`).
  /// Extensions keep their suffix under the new id.
  void setBundleId(String appPath, String bundleId) {
    final old = this.bundleId(appPath);
    _rewrite(appPath, (plist) => plist['CFBundleIdentifier'] = bundleId);
    final plugIns = fileSystem.directory(paths.join(appPath, 'PlugIns'));
    if (!plugIns.existsSync()) return;
    for (final entity in plugIns.listSync()) {
      if (entity is! Directory || !entity.path.endsWith('.appex')) continue;
      if (!fileSystem
          .file(paths.join(entity.path, 'Info.plist'))
          .existsSync()) {
        continue;
      }
      _rewrite(entity.path, (plist) {
        final id = plist['CFBundleIdentifier'];
        if (id is String && id.startsWith('$old.')) {
          plist['CFBundleIdentifier'] = '$bundleId${id.substring(old.length)}';
        }
      });
    }
  }

  /// Whether the main executable may be App Store encrypted (`SC_Info`):
  /// such apps install but do not start after re-signing.
  bool looksEncrypted(String appPath) =>
      fileSystem.directory(paths.join(appPath, 'SC_Info')).existsSync();

  void _xmlInfoPlists(String appPath) {
    final bundles = [
      appPath,
      if (fileSystem.directory(paths.join(appPath, 'PlugIns')).existsSync())
        for (final entity
            in fileSystem.directory(paths.join(appPath, 'PlugIns')).listSync())
          if (entity is Directory && entity.path.endsWith('.appex'))
            entity.path,
    ];
    for (final bundle in bundles) {
      final file = fileSystem.file(paths.join(bundle, 'Info.plist'));
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      if (!_isBinary(bytes)) continue;
      file.writeAsStringSync(
        PropertyListSerialization.stringWithPropertyList(
          _decode(bytes, bundle),
        ),
      );
    }
  }

  void _rewrite(String bundle, void Function(Map<String, Object> plist) edit) {
    final plist = _infoPlist(bundle);
    edit(plist);
    fileSystem
        .file(paths.join(bundle, 'Info.plist'))
        .writeAsStringSync(
          PropertyListSerialization.stringWithPropertyList(plist),
        );
  }

  Map<String, Object> _infoPlist(String bundle) {
    final file = fileSystem.file(paths.join(bundle, 'Info.plist'));
    if (!file.existsSync()) {
      throw codedError(
        XcrossCodes.installNoApp,
        '${paths.basename(bundle)} has no Info.plist.',
      );
    }
    return _decode(file.readAsBytesSync(), bundle);
  }

  Map<String, Object> _decode(Uint8List bytes, String bundle) {
    final Object root;
    try {
      root = _isBinary(bytes)
          ? PropertyListSerialization.propertyListWithData(
              ByteData.sublistView(bytes),
            )
          : PropertyListSerialization.propertyListWithString(
              utf8.decode(bytes),
            );
      // The parser reports malformed input with assorted error types.
    } on Object {
      throw codedError(
        XcrossCodes.installNoApp,
        '${paths.basename(bundle)}/Info.plist is not a valid property list.',
      );
    }
    if (root is! Map) {
      throw codedError(
        XcrossCodes.installNoApp,
        '${paths.basename(bundle)}/Info.plist is not a dictionary.',
      );
    }
    return {
      for (final MapEntry(:key, :value) in root.entries)
        if (value != null) '$key': value as Object,
    };
  }

  static bool _isBinary(Uint8List bytes) =>
      bytes.length >= 8 &&
      ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == 'bplist00';

  String _extractIpa(String ipa, String work) {
    final stream = InputFileStream(fileSystem.file(ipa).path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(stream);
        // archive reports damaged zips with assorted exception types.
      } on Object {
        throw codedError(
          XcrossCodes.installUnsupportedInput,
          '${paths.basename(ipa)} is not a readable zip archive.',
        );
      }
      final apps = <String>{
        for (final entry in archive.files)
          if (entry.name.replaceAll(r'\', '/').split('/') case [
            'Payload',
            final app,
            ...,
          ] when app.endsWith('.app'))
            app,
      };
      if (apps.length != 1) {
        throw codedError(
          XcrossCodes.installNoApp,
          '${paths.basename(ipa)} has ${apps.length} app bundles under '
          'Payload/.',
        );
      }
      final prefix = 'Payload/${apps.single}/';
      final root = paths.join(work, apps.single);
      for (final entry in archive.files) {
        final name = entry.name.replaceAll(r'\', '/');
        if (!entry.isFile || !name.startsWith(prefix)) continue;
        final relative = name.substring(prefix.length);
        if (relative.isEmpty || relative.split('/').contains('..')) continue;
        final target = fileSystem.file(
          paths.joinAll([root, ...relative.split('/')]),
        );
        target.parent.createSync(recursive: true);
        final output = OutputMemoryStream();
        entry.decompress(output);
        target.writeAsBytesSync(output.getBytes());
        if (entry.mode & 0x49 != 0) fileSystem.makeExecutable(target.path);
      }
      fileSystem.directory(root).createSync(recursive: true);
      return root;
    } finally {
      stream.closeSync();
    }
  }

  void _copyDirectory(Directory source, String target) {
    final root = source.path.replaceAll(RegExp(r'[\\/]+$'), '');
    fileSystem.directory(target).createSync(recursive: true);
    for (final entity in source.listSync(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(root.length + 1);
      final destination = paths.join(target, relative);
      if (entity is Directory) {
        fileSystem.directory(destination).createSync(recursive: true);
      } else if (entity is File) {
        fileSystem.file(destination).parent.createSync(recursive: true);
        entity.copySync(fileSystem.file(destination).path);
      }
    }
  }
}
