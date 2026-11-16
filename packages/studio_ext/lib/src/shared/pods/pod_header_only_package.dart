import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Generates Package.swift and placeholder.c for header-only pods like GoogleMLKit (§8.3).
@internal
final class PodHeaderOnlyPackage {
  const PodHeaderOnlyPackage({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  /// Writes `Package.swift` and `Sources/<Module>/placeholder.c` for a header-only pod.
  File generate({
    required Directory packageDir,
    required String pod,
    required String module,
    required String iosDeploymentTarget,
    List<String> dependencies = const [],
    String? customModuleMap,
  }) {
    // 1. Create Sources/<Module>/placeholder.c
    final sourcesDir = directoryFactory(
      p.join(packageDir.path, 'Sources', module),
    );
    sourcesDir.createSync(recursive: true);
    final placeholder = fileFactory(p.join(sourcesDir.path, 'placeholder.c'));
    placeholder.writeAsStringSync(
      '// Placeholder for header-only pod $module\n',
    );

    // 2. Build Package.swift
    final manifestBuffer = StringBuffer();
    manifestBuffer.writeln('// swift-tools-version: 5.9');
    manifestBuffer.writeln('// xcross: pod-converter v1');
    manifestBuffer.writeln('import PackageDescription');
    manifestBuffer.writeln();

    final pkgName = 'pod-$pod';
    manifestBuffer.writeln('let package = Package(');
    manifestBuffer.writeln('    name: "$pkgName",');
    manifestBuffer.writeln('    platforms: [.iOS("$iosDeploymentTarget")],');
    manifestBuffer.writeln('    products: [');
    manifestBuffer.writeln(
      '        .library(name: "$pkgName", targets: ["$module"]),',
    );
    manifestBuffer.writeln('    ],');

    if (dependencies.isNotEmpty) {
      manifestBuffer.writeln('    dependencies: [');
      for (final dep in dependencies) {
        manifestBuffer.writeln(
          '        .package(name: "pod-$dep", path: "../pod-$dep"),',
        );
      }
      manifestBuffer.writeln('    ],');
    }

    manifestBuffer.writeln('    targets: [');
    manifestBuffer.writeln('        .target(');
    manifestBuffer.writeln('            name: "$module",');
    if (dependencies.isNotEmpty) {
      manifestBuffer.writeln('            dependencies: [');
      for (final dep in dependencies) {
        manifestBuffer.writeln(
          '                .product(name: "pod-$dep", package: "pod-$dep"),',
        );
      }
      manifestBuffer.writeln('            ],');
    }
    manifestBuffer.writeln('            path: ".",');
    manifestBuffer.writeln(
      '            sources: ["Sources/$module/placeholder.c"],',
    );
    manifestBuffer.writeln('            publicHeadersPath: "Headers/Public"');
    manifestBuffer.writeln('        ),');
    manifestBuffer.writeln('    ]');
    manifestBuffer.writeln(')');

    final manifestFile = fileFactory(p.join(packageDir.path, 'Package.swift'));
    manifestFile.writeAsStringSync(manifestBuffer.toString());
    return manifestFile;
  }
}
