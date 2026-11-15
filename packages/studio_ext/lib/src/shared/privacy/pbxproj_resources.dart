// studio: privacy — adds a file of the Runner folder to the Runner target's
// "Copy Bundle Resources", the way Xcode's "Add Files to Runner" does. The
// edit is made on the text of project.pbxproj, so every other byte stays as
// Xcode wrote it.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// What [addRunnerResource] found or did.
@internal
enum PbxResourceState {
  /// The app target already copies the file.
  listed,

  /// The app target uses Xcode 16 folder sync for Runner: every file in the
  /// folder is copied, so nothing has to change.
  synchronized,

  /// The file was added; [PbxResourceResult.text] is the new project.
  added,
}

/// The result of [addRunnerResource].
@internal
@immutable
final class PbxResourceResult {
  const PbxResourceResult(this.state, this.text);

  final PbxResourceState state;

  /// The project text to write; the same text unless [state] is `added`.
  final String text;
}

/// Thrown when the project is not one this editor can change safely.
@internal
final class PbxEditException implements Exception {
  const PbxEditException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Adds [fileName] (a file in the `Runner` folder next to `Info.plist`) to
/// the application target's resources in [text], a project.pbxproj.
///
/// Throws [PbxEditException] when the project has no application target, no
/// resources phase or no `Runner` group: the developer then adds the file in
/// Xcode.
@internal
PbxResourceResult addRunnerResource(String text, String fileName) {
  final objects = PbxObjects.scan(text);
  final target = objects
      .byIsa('PBXNativeTarget')
      .where(
        (object) =>
            object.field('productType') == 'com.apple.product-type.application',
      );
  if (target.isEmpty) {
    throw const PbxEditException(
      'The Xcode project has no application target.',
    );
  }
  final app = target.firstWhere(
    (object) => object.field('name') == 'Runner',
    orElse: () => target.first,
  );

  // Already copied by the app target?
  final phase = [
    for (final id in app.list('buildPhases'))
      if (objects[id] case final object?
          when object.isa == 'PBXResourcesBuildPhase')
        object,
  ].firstOrNull;
  if (phase != null) {
    for (final buildFileId in phase.list('files')) {
      final reference = objects[objects[buildFileId]?.field('fileRef')];
      final path = reference?.field('path');
      if (path != null && path.split('/').last == fileName) {
        return PbxResourceResult(PbxResourceState.listed, text);
      }
    }
  }

  // Xcode 16 folder sync: the folder's files are the target's resources.
  for (final id in app.list('fileSystemSynchronizedGroups')) {
    if (objects[id]?.field('path') == 'Runner') {
      return PbxResourceResult(PbxResourceState.synchronized, text);
    }
  }

  if (phase == null) {
    throw const PbxEditException(
      'The Runner target has no "Copy Bundle Resources" build phase.',
    );
  }
  final group = objects
      .byIsa('PBXGroup')
      .where((object) => object.field('path') == 'Runner')
      .firstOrNull;
  if (group == null) {
    throw const PbxEditException(
      'The Xcode project has no Runner group (folder) to add the file to.',
    );
  }

  final newline = text.contains('\r\n') ? '\r\n' : '\n';
  final edits = <PbxInsert>[];
  // A reference already in the Runner group is reused (the file was added
  // to the project but not to the target).
  var referenceId = [
    for (final id in group.list('children'))
      if (objects[id] case final child?
          when child.isa == 'PBXFileReference' &&
              child.field('path') == fileName)
        id,
  ].firstOrNull;
  if (referenceId == null) {
    referenceId = _newId(text, '$fileName.fileRef');
    edits
      ..add(
        _sectionInsert(
          text,
          'PBXFileReference',
          '\t\t$referenceId /* $fileName */ = {isa = PBXFileReference; '
              'lastKnownFileType = ${_fileType(fileName)}; path = $fileName; '
              'sourceTree = "<group>"; };$newline',
        ),
      )
      ..add(
        _listInsert(
          text,
          group.listClose('children'),
          '$referenceId /* $fileName */',
          newline,
        ),
      );
  }
  final buildFileId = _newId(text, '$fileName.buildFile');
  edits
    ..add(
      _sectionInsert(
        text,
        'PBXBuildFile',
        '\t\t$buildFileId /* $fileName in Resources */ = {isa = PBXBuildFile; '
            'fileRef = $referenceId /* $fileName */; };$newline',
      ),
    )
    ..add(
      _listInsert(
        text,
        phase.listClose('files'),
        '$buildFileId /* $fileName in Resources */',
        newline,
      ),
    );

  // From the end, so earlier offsets stay right.
  edits.sort((a, b) => b.offset.compareTo(a.offset));
  var result = text;
  for (final edit in edits) {
    result = result.replaceRange(edit.offset, edit.offset, edit.text);
  }
  return PbxResourceResult(PbxResourceState.added, result);
}

String _fileType(String fileName) => switch (fileName.split('.').last) {
  'xcprivacy' => 'text.xml',
  'plist' => 'text.plist.xml',
  'json' => 'text.json',
  _ => 'file',
};

/// A 24-digit object id that is not in [text], stable for the same input.
String _newId(String text, String seed) {
  for (var n = 0; ; n++) {
    final id = md5
        .convert(utf8.encode('xcross:$seed:$n'))
        .toString()
        .substring(0, 24)
        .toUpperCase();
    if (!text.contains(id)) return id;
  }
}

@internal
final class PbxInsert {
  const PbxInsert(this.offset, this.text);

  final int offset;
  final String text;
}

/// [line] at the end of the `/* Begin <isa> section */` block, or a new
/// block at the top of `objects` when the project has none.
PbxInsert _sectionInsert(String text, String isa, String line) {
  final end = text.indexOf('/* End $isa section */');
  if (end >= 0) return PbxInsert(text.lastIndexOf('\n', end) + 1, line);
  final objects = RegExp(r'\bobjects\s*=\s*\{[^\n]*\n').firstMatch(text);
  if (objects == null) {
    throw const PbxEditException('The Xcode project has no objects list.');
  }
  final newline = line.endsWith('\r\n') ? '\r\n' : '\n';
  return PbxInsert(
    objects.end,
    '$newline/* Begin $isa section */$newline$line'
    '/* End $isa section */$newline',
  );
}

/// [entry] as the last element of the list whose `)` is at [close].
PbxInsert _listInsert(String text, int close, String entry, String newline) {
  final lineStart = text.lastIndexOf('\n', close) + 1;
  final before = text.substring(lineStart, close);
  if (before.trim().isEmpty) {
    // `\t\t\t);` on a line of its own: one more element line above it.
    return PbxInsert(lineStart, '$before\t$entry,$newline');
  }
  final open = text.lastIndexOf('(', close);
  final empty = text.substring(open + 1, close).trim().isEmpty;
  return PbxInsert(close, empty ? '$entry, ' : ' $entry, ');
}

/// The objects of a project.pbxproj: each id with the text of its `{…}`.
@internal
final class PbxObjects {
  PbxObjects(this._text, this._spans);

  /// Reads the `objects = { … }` dictionary of [text].
  factory PbxObjects.scan(String text) {
    final start = RegExp(r'\bobjects\s*=\s*\{').firstMatch(text);
    if (start == null) {
      throw const PbxEditException('The Xcode project has no objects list.');
    }
    final spans = <String, (int, int)>{};
    final scanner = PbxScanner(text, start.end);
    while (true) {
      scanner.skipBlank();
      if (scanner.done || scanner.peek == '}') break;
      final id = scanner.token();
      scanner
        ..skipBlank()
        ..expect('=')
        ..skipBlank();
      if (scanner.peek != '{') {
        // Not an object (never in Xcode's output): skip the value.
        scanner.skipValue();
      } else {
        final open = scanner.offset;
        scanner.skipValue();
        spans[id] = (open, scanner.offset);
      }
      scanner.skipBlank();
      if (scanner.peek == ';') scanner.offset++;
    }
    return PbxObjects(text, spans);
  }

  final String _text;
  final Map<String, (int, int)> _spans;

  PbxObjectText? operator [](String? id) {
    final span = id == null ? null : _spans[id];
    return span == null ? null : PbxObjectText(_text, span.$1, span.$2);
  }

  Iterable<PbxObjectText> byIsa(String isa) => _spans.values
      .map((span) => PbxObjectText(_text, span.$1, span.$2))
      .where((object) => object.isa == isa);
}

/// One object: its text from `{` to just after `}`.
@internal
final class PbxObjectText {
  PbxObjectText(this._text, this._start, this._end);

  final String _text;
  final int _start;
  final int _end;

  String get _body => _text.substring(_start, _end);

  String? get isa => field('isa');

  /// A top-level scalar field, without quotes.
  String? field(String key) {
    final body = _body.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');
    final match = RegExp(
      '[{;\\s]${RegExp.escape(key)}\\s*=\\s*("((?:[^"\\\\]|\\\\.)*)"|[^;\\s{(]+)\\s*;',
    ).firstMatch(body);
    if (match == null) return null;
    return match.group(2) ?? match.group(1);
  }

  /// The ids in a list field such as `children = ( … );`.
  List<String> list(String key) {
    final open = _listOpen(key);
    if (open == null) return const [];
    final close = _closeOf(open);
    final inside = _text
        .substring(open + 1, close)
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    return [
      for (final part in inside.split(','))
        if (part.trim().isNotEmpty) part.trim().replaceAll('"', ''),
    ];
  }

  /// The offset of the `)` that ends the list field [key].
  int listClose(String key) {
    final open = _listOpen(key);
    if (open == null) {
      throw PbxEditException('An Xcode project object has no $key list.');
    }
    return _closeOf(open);
  }

  int? _listOpen(String key) {
    final match = RegExp(
      '[{;\\s]${RegExp.escape(key)}\\s*=\\s*\\(',
    ).firstMatch(_body);
    return match == null ? null : _start + match.end - 1;
  }

  int _closeOf(int open) {
    final scanner = PbxScanner(_text, open)..skipValue();
    return scanner.offset - 1;
  }
}

/// Walks the old-style property list text of a project.pbxproj.
@internal
final class PbxScanner {
  PbxScanner(this._text, this.offset);

  final String _text;
  int offset;

  bool get done => offset >= _text.length;
  String get peek => done ? '' : _text[offset];

  /// Skips spaces and comments.
  void skipBlank() {
    while (!done) {
      final char = _text[offset];
      if (char.trim().isEmpty) {
        offset++;
      } else if (_text.startsWith('/*', offset)) {
        final end = _text.indexOf('*/', offset + 2);
        offset = end < 0 ? _text.length : end + 2;
      } else if (_text.startsWith('//', offset)) {
        final end = _text.indexOf('\n', offset);
        offset = end < 0 ? _text.length : end + 1;
      } else {
        return;
      }
    }
  }

  void expect(String char) {
    if (peek != char) {
      throw PbxEditException(
        'The Xcode project could not be read (expected "$char" at $offset).',
      );
    }
    offset++;
  }

  /// A bare or quoted word.
  String token() {
    if (peek == '"') return _quoted();
    final start = offset;
    while (!done && !'{}()=,;" \t\r\n'.contains(_text[offset])) {
      if (_text.startsWith('/*', offset) || _text.startsWith('//', offset)) {
        break;
      }
      offset++;
    }
    if (start == offset) {
      throw PbxEditException(
        'The Xcode project could not be read (unexpected text at $offset).',
      );
    }
    return _text.substring(start, offset);
  }

  String _quoted() {
    final buffer = StringBuffer();
    offset++;
    while (!done) {
      final char = _text[offset++];
      if (char == '"') return buffer.toString();
      if (char == r'\' && !done) {
        buffer.write(_text[offset++]);
      } else {
        buffer.write(char);
      }
    }
    throw const PbxEditException(
      'The Xcode project could not be read (a string never ends).',
    );
  }

  /// Skips one value: a word, a string, `{…}` or `(…)`.
  void skipValue() {
    skipBlank();
    final open = peek;
    if (open != '{' && open != '(') {
      token();
      return;
    }
    final close = open == '{' ? '}' : ')';
    offset++;
    while (true) {
      skipBlank();
      if (done) {
        throw const PbxEditException(
          'The Xcode project could not be read (a list never ends).',
        );
      }
      final char = peek;
      if (char == close) {
        offset++;
        return;
      }
      if (char == '{' || char == '(') {
        skipValue();
      } else if ('=,;'.contains(char)) {
        offset++;
      } else {
        token();
      }
    }
  }
}
