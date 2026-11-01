import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';

/// An in-memory `.app` bundle for unit tests that do not need the disk.
final class MemorySource extends InspectSource {
  MemorySource(this.contents, {this.name = 'Memory.app'})
    : files = List.unmodifiable(contents.keys.toList()..sort());

  final Map<String, Uint8List> contents;

  @override
  final String name;

  @override
  final List<String> files;

  @override
  InputKind get kind => InputKind.app;

  @override
  int? get sizeBytes => null;

  @override
  String? get sha256Hex => null;

  @override
  String get bundlePath => '.';

  @override
  List<String> get skippedSymlinks => const [];

  @override
  bool hasFile(String path) => contents.containsKey(path);

  @override
  bool hasDirectory(String path) =>
      contents.keys.any((file) => file.startsWith('$path/'));

  @override
  int? sizeOf(String path) => contents[path]?.length;

  @override
  Uint8List? read(String path) => contents[path];

  @override
  void close() {}
}
