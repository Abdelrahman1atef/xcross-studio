import 'package:meta/meta.dart';

/// CocoaPods version and requirement rules inherited from RubyGems.
@internal
final class PodVersion implements Comparable<PodVersion> {
  PodVersion(String value) : source = value, segments = _segments(value) {
    if (segments.isEmpty || segments.first is! int) {
      throw FormatException('Invalid pod version: $value');
    }
  }

  final String source;
  final List<Object> segments;

  bool get isPrerelease => segments.any((segment) => segment is String);

  PodVersion get release {
    final numbers = segments.takeWhile((segment) => segment is int).join('.');
    return PodVersion(numbers);
  }

  PodVersion get bump {
    final numbers = release.segments.cast<int>().toList();
    if (numbers.length > 1) numbers.removeLast();
    numbers[numbers.length - 1]++;
    return PodVersion(numbers.join('.'));
  }

  @override
  int compareTo(PodVersion other) {
    final length = segments.length > other.segments.length
        ? segments.length
        : other.segments.length;
    for (var i = 0; i < length; i++) {
      final left = i < segments.length ? segments[i] : 0;
      final right = i < other.segments.length ? other.segments[i] : 0;
      if (left == right) continue;
      if (left is int && right is String) return 1;
      if (left is String && right is int) return -1;
      final comparison = left is int
          ? left.compareTo(right as int)
          : (left as String).compareTo(right as String);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static List<Object> _segments(String value) {
    if (!RegExp(r'^\d+(?:[.\-]?[a-zA-Z0-9]+)*$').hasMatch(value)) {
      throw FormatException('Invalid pod version: $value');
    }
    return RegExp(r'\d+|[a-zA-Z]+').allMatches(value.toLowerCase()).map((
      match,
    ) {
      final part = match.group(0)!;
      return int.tryParse(part) ?? part;
    }).toList();
  }

  @override
  String toString() => source;
}

@internal
final class PodRequirement {
  PodRequirement(String expression)
    : _clauses = expression.trim().isEmpty
          ? []
          : expression.split(',').map(PodClause.parse).toList();

  final List<PodClause> _clauses;

  bool allows(PodVersion version, {bool pinned = false}) {
    if (version.isPrerelease &&
        !pinned &&
        !_clauses.any((clause) => clause.version.isPrerelease)) {
      return false;
    }
    return _clauses.every((clause) => clause.allows(version));
  }
}

@internal
final class PodClause {
  PodClause(this.operator, this.version);

  PodClause.parse(String raw)
    : operator = _parseOperator(raw),
      version = PodVersion(_parseVersion(raw));

  final String operator;
  final PodVersion version;

  static RegExpMatch _match(String raw) {
    final match = RegExp(
      r'^\s*(~>|>=|<=|!=|=|>|<)?\s*(\S+)\s*$',
    ).firstMatch(raw);
    if (match == null) throw FormatException('Invalid pod requirement: $raw');
    return match;
  }

  static String _parseOperator(String raw) => _match(raw).group(1) ?? '=';
  static String _parseVersion(String raw) => _match(raw).group(2)!;

  bool allows(PodVersion candidate) {
    final comparison = candidate.compareTo(version);
    return switch (operator) {
      '=' => comparison == 0,
      '!=' => comparison != 0,
      '>' => comparison > 0,
      '<' => comparison < 0,
      '>=' => comparison >= 0,
      '<=' => comparison <= 0,
      '~>' => comparison >= 0 && candidate.release.compareTo(version.bump) < 0,
      _ => false,
    };
  }
}
