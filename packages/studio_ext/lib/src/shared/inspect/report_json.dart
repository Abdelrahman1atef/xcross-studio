import 'dart:convert';

import 'package:meta/meta.dart';

/// Encodes [json] deterministically (research R9).
///
/// Two-space indentation, LF only, exactly one trailing newline, and every
/// code unit above `0x7e` escaped as `\uXXXX`. The result is pure ASCII, so
/// the bytes written to stdout do not depend on the console or pipe encoding
/// (on Windows a piped stdout uses the ANSI code page).
@internal
String encodeReportJson(Object? json) {
  final text = const JsonEncoder.withIndent('  ').convert(json);
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit > 0x7e) {
      out.write(r'\u');
      out.write(unit.toRadixString(16).padLeft(4, '0'));
    } else {
      out.writeCharCode(unit);
    }
  }
  out.write('\n');
  return out.toString();
}
