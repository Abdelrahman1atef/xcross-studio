import 'package:cli_kit/shared/logging/logging.dart';

enum ProgressUnit { bytes, items }

final class ProgressBar {
  ProgressBar(
    this.label, {
    required this.log,
    this.total = -1,
    this.unit = ProgressUnit.bytes,
    String? glyph,
  }) : _glyph = glyph ?? log.glyph.download,
       _stopwatch = Stopwatch()..start(),
       // studio: 012 — no bar drawing when events are reported.
       _isTty = log.ansi.useAnsi && !log.isVerbose && log.events == null {
    log.stopStep();
  }

  static const _barWidth = 24;
  static const _labelWidth = 26;
  static const _renderIntervalMs = 100;

  static const _amountColumns = 32;

  static const _wideColumns = 78;

  final Log log;
  final String label;
  final ProgressUnit unit;
  final String _glyph;
  final Stopwatch _stopwatch;
  final bool _isTty;

  int total;

  int _current = 0;
  String _note = '';
  int _lastRenderMs = -_renderIntervalMs;
  int _lastLoggedDecile = -1;
  bool _done = false;

  int get current => _current;

  String get note => _note;

  set note(String value) {
    if (value == _note) return;
    _note = value;
    _report();
  }

  void add(int amount) => update(_current + amount);

  void update(int amount) {
    _current = amount;
    _report();
  }

  void finish([String? detail]) {
    // studio: 012 — the bar ends at 100% for event consumers.
    if (!_done && log.events != null) _emitProgress(log.events!, done: true);
    _close(() => log.logDone(label, detail ?? _format(_current)));
  }

  void fail([String? message]) =>
      _close(() => log.logStatus('${log.glyph.bad}${message ?? label}'));

  void _close(void Function() line) {
    if (_done) return;
    _done = true;
    _stopwatch.stop();
    if (_isTty) log.output.write('\r\x1B[K');
    line();
  }

  void _report() {
    if (_done) return;
    if (log.events case final sink?) {
      _emitProgress(sink);
      return;
    }
    if (!_isTty) {
      _logNextDecile();
      return;
    }
    final elapsedMs = _stopwatch.elapsedMilliseconds;
    if (elapsedMs - _lastRenderMs < _renderIntervalMs) return;
    _lastRenderMs = elapsedMs;
    _render(elapsedMs);
  }

  // studio: 012 — `progress` events, at most one per whole percent (or per
  // 250 ms when the total is unknown).
  int _lastEventPercent = -1;
  int _lastEventMs = -250;

  void _emitProgress(LogEvents sink, {bool done = false}) {
    final known = total > 0;
    final percent = known ? (_current * 100 ~/ total).clamp(0, 100) : -1;
    final elapsedMs = _stopwatch.elapsedMilliseconds;
    if (!done) {
      if (known && percent == _lastEventPercent) return;
      if (!known && elapsedMs - _lastEventMs < 250) return;
    }
    _lastEventPercent = percent;
    _lastEventMs = elapsedMs;
    sink.event('progress', {
      'label': label,
      'fraction': done ? 1.0 : (known ? percent / 100 : null),
      'current': _current,
      'total': known ? total : null,
      'unit': unit.name,
    });
  }

  void _logNextDecile() {
    if (total <= 0) return;
    final percent = (_current * 100 ~/ total).clamp(0, 100);
    if (percent ~/ 10 <= _lastLoggedDecile) return;
    _lastLoggedDecile = percent ~/ 10;
    final detail =
        '$percent%  ${_format(_current)} / ${_format(total)}'
        '${_note.isEmpty ? '' : '  $_note'}';
    log.logStatus('$_glyph$label ${log.dim(detail)}');
  }

  void _render(int elapsedMs) {
    final columns = log.output.terminalColumns;
    final buf = StringBuffer();
    var width = 0;
    void write(String plain, [String? styled]) {
      buf.write(styled ?? plain);
      width += plain.length;
    }

    write('  ', _glyph);
    write(columns >= _wideColumns ? label.padRight(_labelWidth) : '$label ');
    if (total > 0) {
      final barWidth = (columns - width - _amountColumns).clamp(8, _barWidth);
      final fraction = (_current / total).clamp(0.0, 1.0);
      final filled = (fraction * barWidth).round();
      write(
        '━' * barWidth,
        '${log.ansi.cyan}${'━' * filled}${log.ansi.none}'
        '${log.dim('━' * (barWidth - filled))}',
      );
      write(' ${(fraction * 100).round()}%'.padLeft(5));
    }

    final rate = elapsedMs > 0 ? _current * 1000 ~/ elapsedMs : 0;
    final extras = [
      if (total > 0)
        '  ${_format(_current)} / ${_format(total)}'
      else
        '  ${_format(_current)}',
      if (_note.isNotEmpty) '  $_note',
      '  ${_format(rate)}/s',
    ];
    for (final extra in extras) {
      if (width + extra.length > columns - 1) break;
      write(extra, log.dim(extra));
    }
    log.output.write('\r$buf\x1B[K');
  }

  String _format(int amount) =>
      unit == ProgressUnit.bytes ? formatBytes(amount) : formatCount(amount);

  static String formatBytes(int n) {
    if (n < 1024) return '$n B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = n / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }

  static String formatCount(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}
