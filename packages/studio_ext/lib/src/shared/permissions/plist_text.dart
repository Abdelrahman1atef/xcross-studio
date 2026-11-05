// studio: 027 — one top-level key of an XML property list, read, set and
// removed as text, so a developer's comments, key order, indentation, line
// endings and `$(VARIABLE)` values stay exactly as they were. (A parser that
// writes the whole file back drops all of that.)
import 'package:meta/meta.dart';

/// A plist that cannot be edited safely, with a stable [code].
@internal
final class PlistEditException implements Exception {
  const PlistEditException(this.code, this.message);

  /// `permissions.binary_plist`, `permissions.bad_plist`.
  final String code;
  final String message;

  @override
  String toString() => '[$code] $message';
}

/// Where one top-level `<key>` and its value sit in the text.
@internal
@immutable
final class PlistEntry {
  const PlistEntry(this.key, this.keyStart, this.valueStart, this.valueEnd);

  final String key;

  /// Offset of `<key>`.
  final int keyStart;

  /// Offset of the value's first tag and one past its last.
  final int valueStart;
  final int valueEnd;
}

/// The text of an XML property list whose root is a dictionary.
@internal
final class PlistText {
  PlistText(this.source) {
    if (source.startsWith('bplist00')) {
      throw const PlistEditException(
        'permissions.binary_plist',
        'The file is a binary property list; it can only be edited as XML.',
      );
    }
    _parse();
  }

  final String source;

  late final List<PlistEntry> _entries;
  late final int _rootClose;

  /// `\r\n` when the file uses it, else `\n`.
  String get newline => source.contains('\r\n') ? '\r\n' : '\n';

  /// The top-level keys, in file order.
  List<String> get keys => [for (final entry in _entries) entry.key];

  bool has(String key) => _entries.any((entry) => entry.key == key);

  /// The leading whitespace of the first top-level key's line (a tab in files
  /// Xcode writes); a tab when there is none yet.
  String get indent {
    for (final entry in _entries) {
      final lineStart = source.lastIndexOf('\n', entry.keyStart) + 1;
      final lead = source.substring(lineStart, entry.keyStart);
      if (lead.trim().isEmpty && lead.isNotEmpty) return lead;
    }
    return '\t';
  }

  /// [source] with [key] set to [value] (String, bool, int, double, List or
  /// Map of those): the value is replaced in place, or the pair is added
  /// before the closing `</dict>`.
  String set(String key, Object value) {
    final unit = indent;
    final fragment = _fragment(value, unit, unit);
    for (final entry in _entries) {
      if (entry.key != key) continue;
      return source.replaceRange(entry.valueStart, entry.valueEnd, fragment);
    }
    final nl = newline;
    final lineStart = source.lastIndexOf('\n', _rootClose) + 1;
    final onOwnLine = source.substring(lineStart, _rootClose).trim().isEmpty;
    final at = onOwnLine ? lineStart : _rootClose;
    final pair =
        '$unit<key>${_escape(key)}</key>$nl$unit$fragment$nl'
        '${onOwnLine ? '' : nl}';
    return source.replaceRange(at, at, pair);
  }

  /// [source] without [key]; unchanged when it is not there.
  String remove(String key) {
    for (final entry in _entries) {
      if (entry.key != key) continue;
      var start = source.lastIndexOf('\n', entry.keyStart) + 1;
      if (source.substring(start, entry.keyStart).trim().isNotEmpty) {
        start = entry.keyStart;
      }
      var end = entry.valueEnd;
      final rest = source.indexOf('\n', end);
      if (rest != -1 && source.substring(end, rest).trim().isEmpty) {
        end = rest + 1;
      }
      return source.replaceRange(start, end, '');
    }
    return source;
  }

  // --- parsing -------------------------------------------------------------

  static final _token = RegExp(
    r'<!--[\s\S]*?-->'
    r'|<\?[\s\S]*?\?>'
    '|<!DOCTYPE[^>]*>'
    r'|<key>([\s\S]*?)</key>'
    r'|<(string|integer|real|date|data)>[\s\S]*?</\2>'
    r'|<(true|false|string|dict|array|integer|real|date|data)\s*/>'
    r'|<(/?)(dict|array|plist)(?:\s[^>]*)?>',
  );

  void _parse() {
    final entries = <PlistEntry>[];
    var depth = -1; // -1: before the root dict
    var seenPlist = false;
    String? pendingKey;
    int? pendingKeyStart;
    int? valueStart;
    var valueDepth = 0;
    var rootClose = -1;

    void finish(int end) {
      entries.add(PlistEntry(pendingKey!, pendingKeyStart!, valueStart!, end));
      pendingKey = null;
      valueStart = null;
    }

    for (final match in _token.allMatches(source)) {
      final text = match.group(0)!;
      if (text.startsWith('<!--') ||
          text.startsWith('<?') ||
          text.startsWith('<!DOCTYPE')) {
        continue;
      }
      final keyText = match.group(1);
      final scalar = match.group(2);
      final selfClosing = match.group(3);
      final closing = match.group(4) == '/';
      final tag = match.group(5);

      if (tag == 'plist') {
        seenPlist = !closing;
        continue;
      }
      if (!seenPlist) continue;

      if (depth == -1) {
        if (tag == 'dict' && !closing) {
          depth = 0;
        } else if (tag == 'array' || scalar != null || selfClosing != null) {
          throw const PlistEditException(
            'permissions.bad_plist',
            'The root of the property list is not a dictionary.',
          );
        }
        continue;
      }

      if (valueStart == null) {
        // Expecting a key, or the end of the root dictionary.
        if (keyText != null && depth == 0) {
          pendingKey = _unescape(keyText);
          pendingKeyStart = match.start;
          continue;
        }
        if (tag == 'dict' && closing && depth == 0) {
          rootClose = match.start;
          break;
        }
        if (pendingKey == null) {
          throw const PlistEditException(
            'permissions.bad_plist',
            'A value without a key in the property list.',
          );
        }
        // The value of pendingKey starts here.
        valueStart = match.start;
        if (scalar != null || selfClosing != null) {
          finish(match.end);
        } else if (tag != null && !closing) {
          valueDepth = 1;
        } else {
          throw const PlistEditException(
            'permissions.bad_plist',
            'Unbalanced tags in the property list.',
          );
        }
        continue;
      }

      // Inside a container value.
      if (tag != null) {
        if (!closing) {
          valueDepth++;
        } else {
          valueDepth--;
          if (valueDepth == 0) finish(match.end);
        }
      }
    }
    if (depth == -1 || rootClose == -1 || valueStart != null) {
      throw const PlistEditException(
        'permissions.bad_plist',
        'The property list is not a complete dictionary.',
      );
    }
    _entries = entries;
    _rootClose = rootClose;
  }

  // --- writing -------------------------------------------------------------

  /// The XML of [value], its lines after the first indented from [indent].
  String _fragment(Object? value, String indent, String unit) {
    final nl = newline;
    switch (value) {
      case final String text:
        return '<string>${_escape(text)}</string>';
      case final bool flag:
        return flag ? '<true/>' : '<false/>';
      case final int number:
        return '<integer>$number</integer>';
      case final double number:
        return '<real>$number</real>';
      case final List<Object?> items:
        if (items.isEmpty) return '<array/>';
        final inner = '$indent$unit';
        return '<array>$nl'
            '${[for (final item in items) '$inner${_fragment(item, inner, unit)}$nl'].join()}'
            '$indent</array>';
      case final Map<Object?, Object?> map:
        if (map.isEmpty) return '<dict/>';
        final inner = '$indent$unit';
        return '<dict>$nl'
            '${[for (final MapEntry(:key, :value) in map.entries) '$inner<key>${_escape('$key')}</key>$nl$inner${_fragment(value, inner, unit)}$nl'].join()}'
            '$indent</dict>';
    }
    throw ArgumentError('Cannot write a ${value.runtimeType} to a plist.');
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _unescape(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
