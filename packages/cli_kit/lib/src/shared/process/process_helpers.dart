import 'dart:async';
import 'dart:convert';

import 'package:cli_kit/shared/process/process_models.dart';
import 'package:meta/meta.dart';
import 'package:pure/pure.dart';

@internal
abstract final class ProcessHelpers {
  static String failureMessage(
    String executable,
    List<String> arguments,
    int exitCode, {
    required ProcessExitDiagnostic diagnostic,
    String output = '',
    bool captured = true,
  }) {
    final detail = diagnostic.description;
    final message = StringBuffer('command failed ($exitCode')
      ..write(detail == null ? '' : ': $detail')
      ..write('): ${commandLine(executable, arguments)}');
    if (output.trim().isNotEmpty) {
      message.write('\n$output');
    } else if (captured && diagnostic.crashed) {
      message.write(
        '\nIt wrote nothing before dying. Re-run with --verbose: that hands '
        'the tool this terminal instead of a pipe, which is the only way its '
        'crash message survives.',
      );
    }
    return message.toString();
  }

  static final _plainArgument = RegExp(r'^[a-zA-Z0-9_./:=+,\\-]+$');
  static final _needsEscape = RegExp(r'["\x00-\x1f\x7f]');

  /// The command as it is launched: Windows extended-length paths are shown
  /// the way [plainPath] and [plainArgument] hand them to the process.
  static String commandLine(String executable, List<String> arguments) => [
    plainPath(executable),
    ...arguments.map(plainArgument),
  ].map(_displayToken).join(' ');

  /// Longest path, in characters, passed without the `\\?\` prefix; longer
  /// ones keep it, since only the prefix lifts Windows' MAX_PATH limit.
  static const maxPlainPathLength = 248;

  /// [path] without a Windows extended-length prefix (`\\?\C:\…` becomes
  /// `C:\…`, `\\?\UNC\host\…` becomes `\\host\…`).
  static String plainPath(String path) {
    if (path.startsWith(r'\\?\UNC\')) return '\\\\${path.substring(8)}';
    if (path.startsWith(r'\\?\')) return path.substring(4);
    return path;
  }

  /// [path] as [plainPath] when that is shorter than [maxPlainPathLength],
  /// else unchanged.
  static String shortPlainPath(String path) {
    final plain = plainPath(path);
    return plain.length < maxPlainPathLength ? plain : path;
  }

  static final _optionValue = RegExp(r'^(--?[^=\s]+=)(.*)$');

  /// One process argument as Windows launches it: a short extended-length
  /// path, alone or as an `--option=` value, loses its `\\?\` prefix.
  static String plainArgument(String argument) {
    final option = _optionValue.firstMatch(argument);
    if (option != null) return '${option[1]}${shortPlainPath(option[2]!)}';
    return shortPlainPath(argument);
  }

  static String _displayToken(String value) {
    if (_plainArgument.hasMatch(value)) return value;
    if (_needsEscape.hasMatch(value)) return jsonEncode(value);
    return '"$value"';
  }

  static Stream<T> pausingBroadcast<T>(Stream<T> source) =>
      source.asBroadcastStream(
        onListen: (sub) => callIf(sub.isPaused, sub.resume),
        onCancel: (sub) => sub.pause(),
      );

  static String bracketHost(String addr) =>
      addr.contains(':') ? '[$addr]' : addr;

  static String unbracketHost(String host) =>
      host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;

  static Future<T?> pollUntil<T>({
    required Future<T?> Function() attempt,
    required Duration timeout,
    required Duration interval,
    bool Function()? cancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (cancelled?.call() ?? false) return null;
      try {
        final result = await attempt();
        if (result != null) return result;
      } on Object catch (_) {}
      await Future<void>.delayed(interval);
    }
    return null;
  }
}
