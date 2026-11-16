import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

@internal
final class PodSwiftBinaryIncompatible implements Exception {
  const PodSwiftBinaryIncompatible(this.module, this.triple);
  final String module;
  final String triple;

  @override
  String toString() =>
      'pod.swift_binary_incompatible: $module has no $triple.swiftinterface';
}

/// A Swift module compiled for another toolchain needs a textual interface.
@internal
final class PodSwiftBinaryCheck {
  const PodSwiftBinaryCheck({
    required this.directoryFactory,
    required this.fileFactory,
  });
  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  void requireInterface(Directory framework, {required bool simulator}) {
    final modules = directoryFactory(path.join(framework.path, 'Modules'));
    if (!modules.existsSync()) return;
    final triple = simulator ? 'arm64-apple-ios-simulator' : 'arm64-apple-ios';
    for (final module
        in modules.listSync(followLinks: false).whereType<Directory>()) {
      if (!module.path.endsWith('.swiftmodule')) continue;
      final name = path.basenameWithoutExtension(module.path);
      final interface = fileFactory(
        path.join(module.path, '$triple.swiftinterface'),
      );
      if (!interface.existsSync()) {
        throw PodSwiftBinaryIncompatible(name, triple);
      }
    }
  }
}
