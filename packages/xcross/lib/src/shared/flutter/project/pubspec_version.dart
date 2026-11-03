// studio: 022 — the pubspec `version:` line, read, bumped and rewritten in
// place for `xcross project version` (specs/022-studio-release-flow).
import 'package:meta/meta.dart';

/// The part of a version [PubspecVersion.bump] raises.
@internal
enum VersionPart { major, minor, patch, build }

/// `version: <name>+<build>` of a pubspec: the iOS
/// `CFBundleShortVersionString` and `CFBundleVersion`.
@internal
@immutable
final class PubspecVersion {
  const PubspecVersion(this.name, this.build);

  /// `1.2.3`.
  final String name;

  /// `7`; null when the pubspec has no `+<build>`.
  final int? build;

  static final _name = RegExp(r'^\d+(\.\d+){0,2}$');
  static final _line = RegExp(
    r'''^version:([ \t]*)(['"]?)([^'"#\s]*)\2([ \t]*(#.*)?)$''',
  );

  /// Up to three dot-separated numbers, as App Store Connect accepts.
  static bool isValidName(String text) => _name.hasMatch(text);

  /// `1.2.3+7` or `1.2.3`; null when malformed.
  static PubspecVersion? parse(String text) {
    final parts = text.trim().split('+');
    if (parts.length > 2 || !isValidName(parts.first)) return null;
    if (parts.length == 1) return PubspecVersion(parts.first, null);
    final build = int.tryParse(parts[1]);
    if (build == null || build < 0) return null;
    return PubspecVersion(parts.first, build);
  }

  /// The top-level `version:` of [pubspec], or null.
  static PubspecVersion? read(String pubspec) {
    for (final line in pubspec.split('\n')) {
      final match = _line.firstMatch(line.trimRight());
      if (match != null) return parse(match.group(3)!);
    }
    return null;
  }

  /// [pubspec] with its top-level `version:` set to [version]; quotes,
  /// comments and every other line are kept. Without a `version:` line one
  /// is added after `name:`.
  static String write(String pubspec, PubspecVersion version) {
    final newline = pubspec.contains('\r\n') ? '\r\n' : '\n';
    final lines = pubspec.split(newline);
    for (var i = 0; i < lines.length; i++) {
      final match = _line.firstMatch(lines[i]);
      if (match == null) continue;
      final quote = match.group(2)!;
      lines[i] =
          'version:${match.group(1)!.isEmpty ? ' ' : match.group(1)}'
          '$quote${version.text}$quote${match.group(4)}';
      return lines.join(newline);
    }
    final name = lines.indexWhere((line) => line.startsWith('name:'));
    lines.insert(name + 1, 'version: ${version.text}');
    return lines.join(newline);
  }

  /// `1.2.3+7`.
  String get text => build == null ? name : '$name+$build';

  /// [part] raised by one. A new version also raises the build number:
  /// Flutter uses it as Android's `versionCode` too, which must always grow.
  PubspecVersion bump(VersionPart part) {
    final nextBuild = (build ?? 0) + 1;
    if (part == VersionPart.build) return PubspecVersion(name, nextBuild);
    final numbers = [...name.split('.').map(int.parse), 0, 0].take(3).toList();
    switch (part) {
      case VersionPart.major:
        numbers
          ..[0] += 1
          ..[1] = 0
          ..[2] = 0;
      case VersionPart.minor:
        numbers
          ..[1] += 1
          ..[2] = 0;
      case VersionPart.patch:
        numbers[2] += 1;
      case VersionPart.build:
        break;
    }
    return PubspecVersion(numbers.join('.'), nextBuild);
  }

  @override
  String toString() => '$name (${build ?? '-'})';
}
