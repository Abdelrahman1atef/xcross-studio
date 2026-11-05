// studio: 028 — which Package.swift overrides xcross wrote itself and whether
// the developer has looked at them. Kept in ONE file at the root of
// `xcross_overrides/` (not inside a plugin's folder, whose files are laid over
// the plugin at build time).
import 'dart:convert';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;

/// What the ledger knows about one written draft.
final class DraftRecord {
  const DraftRecord({required this.writtenAt, required this.reviewed});

  /// ISO-8601, UTC.
  final String writtenAt;

  /// The developer said they looked at it (`xcross plugin ack`).
  final bool reviewed;

  Map<String, Object?> toJson() => {
    'writtenAt': writtenAt,
    'reviewed': reviewed,
  };
}

/// `xcross_overrides/.xcross-drafts.json`: `{"<plugin>/<version>": record}`.
final class DraftLedger {
  DraftLedger(this.fileSystem, this.paths, this.base);

  /// The ledger of the override folder [base] (`<project>/xcross_overrides`).
  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String base;

  static const fileName = '.xcross-drafts.json';

  String get path => paths.join(base, fileName);

  static String key(String plugin, String? version) =>
      version == null ? plugin : '$plugin/$version';

  Map<String, DraftRecord> read() {
    final file = fileSystem.file(path);
    if (!file.existsSync()) return const {};
    try {
      final Object? json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return const {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value case {
            'writtenAt': final String at,
            'reviewed': final bool reviewed,
          })
            key: DraftRecord(writtenAt: at, reviewed: reviewed),
      };
    } on FormatException {
      return const {};
    }
  }

  /// A draft was just written: not reviewed yet.
  void record(String plugin, String? version, {DateTime? now}) => _write({
    ...read(),
    key(plugin, version): DraftRecord(
      writtenAt: (now ?? DateTime.now()).toUtc().toIso8601String(),
      reviewed: false,
    ),
  });

  /// Marks the draft of [plugin] reviewed; false when the ledger has none.
  bool acknowledge(String plugin, String? version) {
    final records = read();
    final id = key(plugin, version);
    final record = records[id];
    if (record == null) return false;
    _write({
      ...records,
      id: DraftRecord(writtenAt: record.writtenAt, reviewed: true),
    });
    return true;
  }

  void _write(Map<String, DraftRecord> records) {
    final sorted = Map.fromEntries(
      records.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    fileSystem.file(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({for (final e in sorted.entries) e.key: e.value.toJson()})}\n',
      );
  }
}
