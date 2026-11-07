/// Removes credential values before subprocess output is parsed or retained.
///
/// Exact values supplied in command arguments are removed even when the CLI
/// repeats them without a label. The generic patterns cover common diagnostics
/// from older binaries, which may print credentials without an argument echo.
class SecretRedactor {
  SecretRedactor(Iterable<String> knownSecrets)
    : _knownSecrets = [...knownSecrets.where((value) => value.isNotEmpty)]
        ..sort((a, b) => b.length.compareTo(a.length));

  final List<String> _knownSecrets;
  bool _insidePrivateKey = false;

  void addSecret(String value) {
    if (value.isEmpty || _knownSecrets.contains(value)) return;
    _knownSecrets.add(value);
    _knownSecrets.sort((a, b) => b.length.compareTo(a.length));
  }

  static SecretRedactor forCommand(List<String> command) {
    final secrets = <String>[];
    for (var i = 0; i < command.length; i++) {
      final part = command[i];
      final equals = part.indexOf('=');
      if (equals > 0 &&
          const {
            '--password',
            '--token',
            '--secret',
            '--api-key',
          }.contains(part.substring(0, equals))) {
        secrets.add(part.substring(equals + 1));
        continue;
      }
      if (const {
            '--password',
            '--token',
            '--secret',
            '--api-key',
          }.contains(part) &&
          i + 1 < command.length) {
        secrets.add(command[++i]);
      }
    }
    return SecretRedactor(secrets);
  }

  static final _labelled = RegExp(
    r'(password|token|secret|api[_-]?key|authorization)\s*[:=]\s*([^\s,;]+)',
    caseSensitive: false,
  );
  static final _jsonLabelled = RegExp(
    r'("(?:password|token|secret|api[_-]?key|authorization)"\s*:\s*")([^"\\]*(?:\\.[^"\\]*)*)(")',
    caseSensitive: false,
  );

  String redact(String text) {
    var result = text;
    for (final secret in _knownSecrets) {
      result = result.replaceAll(secret, '[redacted]');
    }
    result = result.replaceAllMapped(
      _jsonLabelled,
      (match) => '${match.group(1)}[redacted]${match.group(3)}',
    );
    return result.replaceAllMapped(
      _labelled,
      (match) => '${match.group(1)}=[redacted]',
    );
  }

  /// Redacts PEM key bodies one output line at a time before they are parsed.
  String redactLine(String line) {
    if (_insidePrivateKey) {
      if (line.contains('-----END ') && line.contains('PRIVATE KEY-----')) {
        _insidePrivateKey = false;
      }
      return '[redacted private key]';
    }
    if (line.contains('-----BEGIN ') && line.contains('PRIVATE KEY-----')) {
      _insidePrivateKey = !line.contains('-----END ');
      return '[redacted private key]';
    }
    return redact(line);
  }
}
