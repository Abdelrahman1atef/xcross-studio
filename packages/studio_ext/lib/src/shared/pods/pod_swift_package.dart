import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Represents the Swift language mode for a SwiftPM package.
@internal
enum PodSwiftLanguageMode {
  v4('v4'),
  v4_2('v4_2'),
  v5('v5'),
  v6('version("6")');

  const PodSwiftLanguageMode(this.manifestSyntax);
  final String manifestSyntax;

  String get code => this == v6 ? '.version("6")' : '.$manifestSyntax';
}

/// Generates Package.swift and source layout for Swift-only pods (§8.8, T301).
@internal
final class PodSwiftPackage {
  const PodSwiftPackage({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  /// Resolves the Swift language mode from a list of allowed versions or single version.
  /// Swift 6.4 supports 4, 4.2, 5, and 6 modes; chooses the highest supported mode allowed by the pod.
  static PodSwiftLanguageMode resolveLanguageMode(
    List<String> podVersions, {
    String defaultVersion = '5',
  }) {
    if (podVersions.isEmpty) {
      return parseSingleMode(defaultVersion);
    }
    final modes = podVersions.map(parseSingleMode).toSet();
    if (modes.contains(PodSwiftLanguageMode.v6)) {
      return PodSwiftLanguageMode.v6;
    }
    if (modes.contains(PodSwiftLanguageMode.v5)) {
      return PodSwiftLanguageMode.v5;
    }
    if (modes.contains(PodSwiftLanguageMode.v4_2)) {
      return PodSwiftLanguageMode.v4_2;
    }
    if (modes.contains(PodSwiftLanguageMode.v4)) {
      return PodSwiftLanguageMode.v4;
    }
    return PodSwiftLanguageMode.v5;
  }

  /// Parses a version string like '5.0', '4.2', '4', '6' into a [PodSwiftLanguageMode].
  static PodSwiftLanguageMode parseSingleMode(String version) {
    final trimmed = version.trim();
    if (trimmed.startsWith('6')) return PodSwiftLanguageMode.v6;
    if (trimmed.startsWith('5')) return PodSwiftLanguageMode.v5;
    if (trimmed == '4.2') return PodSwiftLanguageMode.v4_2;
    if (trimmed.startsWith('4')) return PodSwiftLanguageMode.v4;
    return PodSwiftLanguageMode.v5;
  }

  /// Sanitizes a pod name into a valid C99 / Swift identifier.
  static String sanitizeIdentifier(String name) {
    final sanitized = name.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_');
    if (RegExp('^[0-9]').hasMatch(sanitized)) {
      return '_$sanitized';
    }
    return sanitized;
  }

  /// Generates the `Package.swift` content for a Swift-only pod.
  String generateManifest({
    required String pod,
    required String module,
    required String iosDeploymentTarget,
    PodSwiftLanguageMode languageMode = PodSwiftLanguageMode.v5,
    List<String> dependencies = const [],
    List<String> linkedFrameworks = const [],
    List<String> linkedLibraries = const [],
    List<String> defines = const [],
  }) {
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
          '                .product(name: "$dep", package: "pod-$dep"),',
        );
      }
      manifestBuffer.writeln('            ],');
    }
    manifestBuffer.writeln('            path: "Sources/$module",');

    final swiftDefines = <String>{'COCOAPODS', ...defines};
    manifestBuffer.writeln('            swiftSettings: [');
    for (final def in swiftDefines) {
      manifestBuffer.writeln('                .define("$def"),');
    }
    manifestBuffer.writeln('            ],');

    if (linkedFrameworks.isNotEmpty || linkedLibraries.isNotEmpty) {
      manifestBuffer.writeln('            linkerSettings: [');
      for (final fw in linkedFrameworks) {
        manifestBuffer.writeln('                .linkedFramework("$fw"),');
      }
      for (final lib in linkedLibraries) {
        manifestBuffer.writeln('                .linkedLibrary("$lib"),');
      }
      manifestBuffer.writeln('            ],');
    }

    manifestBuffer.writeln('        ),');
    manifestBuffer.writeln('    ],');
    manifestBuffer.writeln('    swiftLanguageVersions: [${languageMode.code}]');
    manifestBuffer.writeln(')');

    return manifestBuffer.toString();
  }

  /// Writes `Package.swift` and organizes Swift sources under `Sources/<Module>/`.
  File generate({
    required Directory packageDir,
    required String pod,
    required String module,
    required String iosDeploymentTarget,
    PodSwiftLanguageMode languageMode = PodSwiftLanguageMode.v5,
    List<String> dependencies = const [],
    List<String> linkedFrameworks = const [],
    List<String> linkedLibraries = const [],
    List<String> defines = const [],
  }) {
    final manifestText = generateManifest(
      pod: pod,
      module: module,
      iosDeploymentTarget: iosDeploymentTarget,
      languageMode: languageMode,
      dependencies: dependencies,
      linkedFrameworks: linkedFrameworks,
      linkedLibraries: linkedLibraries,
      defines: defines,
    );

    final manifestFile = fileFactory(p.join(packageDir.path, 'Package.swift'));
    manifestFile.parent.createSync(recursive: true);
    manifestFile.writeAsStringSync(manifestText);
    return manifestFile;
  }
}
