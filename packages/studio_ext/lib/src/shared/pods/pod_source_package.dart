import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/pods/pod_settings_converter.dart';

/// Generates Package.swift for C, Objective-C, and Objective-C++ source pods (§8.3, §8.4, T305).
@internal
final class PodSourcePackage {
  const PodSourcePackage({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  /// Generates the `Package.swift` content for an Objective-C / Objective-C++ source pod.
  String generateManifest({
    required String pod,
    required String module,
    required String iosDeploymentTarget,
    PodTargetSettings settings = const PodTargetSettings(),
    List<String> dependencies = const [],
    Map<String, String> dependencyModules = const {},
    String publicHeadersPath = 'include',
    bool isStaticFramework = false,
    bool hasCxx = false,
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
        final prodName = dependencyModules[dep] ?? dep;
        manifestBuffer.writeln(
          '                .product(name: "$prodName", package: "pod-$dep"),',
        );
      }
      manifestBuffer.writeln('            ],');
    }
    manifestBuffer.writeln('            path: "Sources/$module",');
    manifestBuffer.writeln(
      '            publicHeadersPath: "$publicHeadersPath",',
    );

    // cSettings
    final cSettingsLines = <String>[];
    cSettingsLines.add('.define("COCOAPODS")');
    cSettingsLines.add('.unsafeFlags(["-USWIFT_PACKAGE"])');
    for (final def in settings.defines.entries) {
      if (def.key == 'COCOAPODS') continue;
      if (def.value != null && def.value!.isNotEmpty) {
        cSettingsLines.add('.define("${def.key}", to: "${def.value}")');
      } else {
        cSettingsLines.add('.define("${def.key}")');
      }
    }
    for (final hsp in settings.headerSearchPaths) {
      cSettingsLines.add('.headerSearchPath("$hsp")');
    }
    for (final flag in settings.cFlags) {
      cSettingsLines.add('.unsafeFlags(["$flag"])');
    }

    manifestBuffer.writeln('            cSettings: [');
    for (final line in cSettingsLines) {
      manifestBuffer.writeln('                $line,');
    }
    manifestBuffer.writeln('            ],');

    // cxxSettings
    if (settings.cxxFlags.isNotEmpty || hasCxx) {
      manifestBuffer.writeln('            cxxSettings: [');
      for (final flag in settings.cxxFlags) {
        manifestBuffer.writeln('                .unsafeFlags(["$flag"]),');
      }
      manifestBuffer.writeln('            ],');
    }

    // linkerSettings
    final linkerLines = <String>[];
    for (final fw in settings.linkedFrameworks) {
      linkerLines.add('.linkedFramework("$fw")');
    }
    for (final lib in settings.linkedLibraries) {
      linkerLines.add('.linkedLibrary("$lib")');
    }
    for (final flag in settings.linkerFlags) {
      linkerLines.add('.unsafeFlags(["$flag"])');
    }
    if (linkerLines.isNotEmpty) {
      manifestBuffer.writeln('            linkerSettings: [');
      for (final line in linkerLines) {
        manifestBuffer.writeln('                $line,');
      }
      manifestBuffer.writeln('            ],');
    }

    manifestBuffer.writeln('        ),');
    manifestBuffer.writeln('    ],');

    if (settings.cLanguageStandard != null) {
      manifestBuffer.writeln(
        '    cLanguageStandard: .${settings.cLanguageStandard},',
      );
    }
    if (settings.cxxLanguageStandard != null || hasCxx) {
      final cxx = settings.cxxLanguageStandard ?? 'cxx17';
      manifestBuffer.writeln('    cxxLanguageStandard: .$cxx,');
    }

    manifestBuffer.writeln(')');
    return manifestBuffer.toString();
  }

  /// Writes `Package.swift` for the source pod.
  File generate({
    required Directory packageDir,
    required String pod,
    required String module,
    required String iosDeploymentTarget,
    PodTargetSettings settings = const PodTargetSettings(),
    List<String> dependencies = const [],
    Map<String, String> dependencyModules = const {},
    String publicHeadersPath = 'include',
    bool isStaticFramework = false,
    bool hasCxx = false,
  }) {
    final manifestText = generateManifest(
      pod: pod,
      module: module,
      iosDeploymentTarget: iosDeploymentTarget,
      settings: settings,
      dependencies: dependencies,
      dependencyModules: dependencyModules,
      publicHeadersPath: publicHeadersPath,
      isStaticFramework: isStaticFramework,
      hasCxx: hasCxx,
    );

    final manifestFile = fileFactory(p.join(packageDir.path, 'Package.swift'));
    manifestFile.parent.createSync(recursive: true);
    manifestFile.writeAsStringSync(manifestText);
    return manifestFile;
  }
}
