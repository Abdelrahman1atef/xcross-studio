import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// Synthesizes a Clang module map for a framework that does not ship one.
@internal
final class PodFrameworkModuleMap {
  const PodFrameworkModuleMap({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  /// Generates the module.modulemap text for [name] using [headerFiles].
  String generate({required String name, required List<String> headerFiles}) {
    final hasUmbrella = headerFiles.contains('$name.h');
    final buffer = StringBuffer();
    buffer.writeln('framework module $name {');
    if (hasUmbrella) {
      buffer.writeln('  umbrella header "$name.h"');
    } else {
      for (final header in headerFiles) {
        if (header.endsWith('.h')) {
          buffer.writeln('  header "$header"');
        }
      }
    }
    buffer.writeln('  export *');
    buffer.writeln('  module * { export * }');
    buffer.writeln('}');
    return buffer.toString();
  }

  /// Ensures `Modules/module.modulemap` exists inside [framework].
  ///
  /// If it already exists, returns null without modifying it.
  /// If missing, inspects `Headers/` and writes a synthesized module map.
  File? ensureModuleMap(Directory framework) {
    final modulesDir = directoryFactory(path.join(framework.path, 'Modules'));
    final moduleMapFile = fileFactory(
      path.join(modulesDir.path, 'module.modulemap'),
    );
    if (moduleMapFile.existsSync()) return null;

    final name = path.basenameWithoutExtension(framework.path);
    final headersDir = directoryFactory(path.join(framework.path, 'Headers'));
    final headers = <String>[];
    if (headersDir.existsSync()) {
      for (final entity in headersDir.listSync(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.h')) {
          headers.add(path.basename(entity.path));
        }
      }
    }
    headers.sort();

    final content = generate(name: name, headerFiles: headers);
    modulesDir.createSync(recursive: true);
    moduleMapFile.writeAsStringSync(content);
    return moduleMapFile;
  }
}
