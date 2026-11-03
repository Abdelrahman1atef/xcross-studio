// studio: 019 — a command failure with its own exit code.
import 'package:meta/meta.dart';

/// Stops a command with [message] and [exitCode] (the runner prints the
/// message as an error and exits with the code).
@immutable
final class CommandExit implements Exception {
  const CommandExit(this.message, {this.exitCode = 1});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}
