// studio: 027 — the two property lists of a Flutter project's iOS side that a
// developer edits for permissions and capabilities: `ios/Runner/Info.plist`
// and the entitlements file. Edits go through [PlistText] and always leave a
// backup of what was there.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/inspect/plist_reader.dart';
import 'package:studio_ext/src/shared/permissions/plist_text.dart';

/// A property list of the project, read as text.
@internal
@immutable
final class ProjectPlist {
  const ProjectPlist(this.path, this.relativePath, this.text);

  /// Absolute path; [text] is null when the file does not exist.
  final String path;

  /// Path from the project root, with `/`.
  final String relativePath;
  final String? text;

  bool get exists => text != null;

  /// The editor for [text]; throws [PlistEditException] for a binary or
  /// broken file.
  PlistText get editable => PlistText(text ?? emptyEntitlements);

  /// The top-level values, parsed (a missing DOCTYPE is tolerated, like in
  /// the build). Empty when the file is missing or unreadable.
  Map<String, Object?> get values {
    final source = text;
    if (source == null) return const {};
    final withDoctype = source.contains('<!DOCTYPE')
        ? source
        : source.replaceFirst('<plist', '$_doctype\n<plist');
    return readPlist(
          Uint8List.fromList(utf8.encode(withDoctype)),
        )?.dictionary ??
        const {};
  }

  static const _doctype =
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">';

  /// An entitlements file with nothing in it.
  static const emptyEntitlements =
      '<?xml version="1.0" encoding="UTF-8"?>\n$_doctype\n'
      '<plist version="1.0">\n<dict>\n</dict>\n</plist>\n';
}

/// The project's iOS property lists and how to write them.
@internal
final class ProjectPlists {
  ProjectPlists({
    required this.fileSystem,
    required this.paths,
    required this.root,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String root;
  final DateTime Function() _now;

  /// The project folder has the iOS side of a Flutter app.
  bool get hasIos =>
      fileSystem.file(_join(['ios', 'Runner', 'Info.plist'])).existsSync();

  String _join(List<String> parts) => paths.joinAll([root, ...parts]);

  ProjectPlist info() => _read(['ios', 'Runner', 'Info.plist']);

  /// The entitlements file the project declares (`CODE_SIGN_ENTITLEMENTS` of
  /// the Xcode project), else the conventional `ios/Runner/Runner.entitlements`.
  ProjectPlist entitlements() {
    final declared = _declaredEntitlements();
    return _read(declared ?? ['ios', 'Runner', 'Runner.entitlements']);
  }

  /// Whether the Xcode project points at an entitlements file. xcross finds
  /// `Runner.entitlements` by its path, but Xcode only honours the file when
  /// the project names it.
  bool get xcodeKnowsEntitlements => _declaredEntitlements() != null;

  List<String>? _declaredEntitlements() {
    final pbxproj = fileSystem.file(
      _join(['ios', 'Runner.xcodeproj', 'project.pbxproj']),
    );
    if (!pbxproj.existsSync()) return null;
    final match = RegExp(
      r'''CODE_SIGN_ENTITLEMENTS\s*=\s*"?([^";\s]+)"?\s*;''',
    ).firstMatch(pbxproj.readAsStringSync());
    final value = match?.group(1);
    if (value == null || value.contains(r'$')) return null;
    return ['ios', ...value.split('/')];
  }

  ProjectPlist _read(List<String> parts) {
    final file = fileSystem.file(_join(parts));
    return ProjectPlist(
      file.path,
      parts.join('/'),
      file.existsSync() ? file.readAsStringSync() : null,
    );
  }

  /// Writes [text] as [target], after copying what is there to
  /// `.xcross/permission-backups/<stamp>/<relative path>`. Returns the backup
  /// path, or null when nothing was there to keep or nothing changed.
  String? write(ProjectPlist target, String text) {
    if (target.text == text) return null;
    String? backup;
    if (target.exists) {
      final stamp = _stamp(_now());
      backup = paths.joinAll([
        root,
        '.xcross',
        'permission-backups',
        stamp,
        ...target.relativePath.split('/'),
      ]);
      fileSystem.file(backup)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(target.text!);
    }
    fileSystem.file(target.path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    return backup;
  }

  static String _stamp(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
