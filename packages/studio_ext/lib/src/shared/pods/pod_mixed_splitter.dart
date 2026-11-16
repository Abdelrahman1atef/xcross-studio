import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/plugins/package_swift_draft.dart';

/// The direction of code dependencies in a mixed Swift/ObjC pod (§8.8).
@internal
enum PodMixedDirection {
  /// ObjC uses Swift: ObjC target `<Module>` depends on Swift target `<Module>_swift`.
  /// ObjC imports of `<Module>-Swift.h` are patched to `@import <Module>_swift;`.
  objcUsesSwift,

  /// Swift uses ObjC only: ObjC target `<Module>ObjC`, Swift target `<Module>`
  /// with generated `@_exported import <Module>ObjC`.
  swiftUsesObjc,

  /// Both directions depend on each other cyclically; cannot be split in SwiftPM.
  cyclic,
}

/// The result of splitting a mixed pod into targets.
@internal
final class PodMixedSplitResult {
  const PodMixedSplitResult({
    required this.direction,
    required this.objcTarget,
    required this.swiftTarget,
    this.bridgingHeader,
    this.exportedImportFile,
    this.reason,
  });

  final PodMixedDirection direction;
  final String objcTarget;
  final String swiftTarget;
  final String? bridgingHeader;
  final String? exportedImportFile;
  final String? reason;

  bool get isSupported => direction != PodMixedDirection.cyclic;
}

/// Splits mixed Objective-C and Swift pods into acyclic SwiftPM targets (§8.8, T302).
@internal
final class PodMixedSplitter {
  const PodMixedSplitter({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  /// Detects the target dependency direction for a mixed pod.
  static PodMixedDirection detectDirection({
    required String module,
    required List<String> objcSources,
    required List<String> swiftSources,
    required Map<String, String> filesContent,
  }) {
    final swiftHeaderRegex = RegExp(
      '^[ \\t]*#import\\s+[<"](?:$module/)?[^>"]*-Swift\\.h[>"]',
      multiLine: true,
    );

    var objcUsesSwift = false;
    for (final src in objcSources) {
      final content = filesContent[src] ?? '';
      if (swiftHeaderRegex.hasMatch(content)) {
        objcUsesSwift = true;
        break;
      }
    }

    // Check if Swift uses ObjC classes
    final objcClassRegex = RegExp(r'@(?:interface|protocol)\s+(\w+)\b');
    final declaredObjcClasses = <String>{};
    for (final file in filesContent.keys) {
      if (file.endsWith('.h')) {
        final content = filesContent[file] ?? '';
        for (final m in objcClassRegex.allMatches(content)) {
          if (m.group(1) case final cls?) declaredObjcClasses.add(cls);
        }
      }
    }

    var swiftUsesObjc = false;
    if (declaredObjcClasses.isNotEmpty) {
      for (final src in swiftSources) {
        final content = filesContent[src] ?? '';
        for (final cls in declaredObjcClasses) {
          if (RegExp('\\b$cls\\b').hasMatch(content)) {
            swiftUsesObjc = true;
            break;
          }
        }
        if (swiftUsesObjc) break;
      }
    }

    // Two-way circular dependency check
    if (objcUsesSwift && swiftUsesObjc) {
      // Check if Swift calls into ObjC which also calls into Swift in a closed loop
      // If ObjC has cyclic dependence that cannot be broken by a bridging header
      var hasCircularTypeDependency = false;
      for (final src in objcSources) {
        final content = filesContent[src] ?? '';
        if (swiftHeaderRegex.hasMatch(content)) {
          // Check if this same ObjC file declares classes used by Swift
          for (final cls in declaredObjcClasses) {
            if (content.contains('@interface $cls') &&
                swiftSources.any(
                  (s) => (filesContent[s] ?? '').contains(cls),
                )) {
              hasCircularTypeDependency = true;
              break;
            }
          }
        }
      }
      if (hasCircularTypeDependency) {
        return PodMixedDirection.cyclic;
      }
      return PodMixedDirection.objcUsesSwift;
    }

    if (objcUsesSwift) {
      return PodMixedDirection.objcUsesSwift;
    }

    // Swift uses ObjC (e.g. Try 2.1.1) or default independent
    return PodMixedDirection.swiftUsesObjc;
  }

  /// Splits the mixed pod and writes target structures.
  PodMixedSplitResult split({
    required Directory packageDir,
    required String pod,
    required String module,
    required List<String> objcSources,
    required List<String> swiftSources,
    required Map<String, String> filesContent,
  }) {
    final direction = detectDirection(
      module: module,
      objcSources: objcSources,
      swiftSources: swiftSources,
      filesContent: filesContent,
    );

    if (direction == PodMixedDirection.cyclic) {
      return PodMixedSplitResult(
        direction: direction,
        objcTarget: module,
        swiftTarget: '${module}_swift',
        reason: 'pod.objc_uses_own_swift',
      );
    }

    if (direction == PodMixedDirection.objcUsesSwift) {
      // ObjC -> Swift: ObjC target is `<Module>`, Swift target is `<Module>_swift`
      final swiftTarget = '${module}_swift';
      final objcTarget = module;

      // Patch ObjC sources that import -Swift.h to @import <swiftTarget>;
      for (final relative in objcSources) {
        final content = filesContent[relative];
        if (content == null) continue;
        final patched = patchSwiftHeaderImports(
          content,
          pod,
          targetModuleName: swiftTarget,
        );
        if (patched != null) {
          final file = fileFactory(p.join(packageDir.path, relative));
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(patched);
        }
      }

      // Synthesize bridging header if Swift code reaches ObjC headers
      final bridgingHeaderName = '$swiftTarget-Bridging.h';
      final headerImports = filesContent.keys
          .where((k) => k.endsWith('.h') && !k.endsWith('-Swift.h'))
          .map((h) => '#import "${p.basename(h)}"')
          .join('\n');
      if (headerImports.isNotEmpty) {
        final bridgingFile = fileFactory(
          p.join(packageDir.path, 'Sources', swiftTarget, bridgingHeaderName),
        );
        bridgingFile.parent.createSync(recursive: true);
        bridgingFile.writeAsStringSync(
          '// Generated bridging header for $swiftTarget\n$headerImports\n',
        );
      }

      return PodMixedSplitResult(
        direction: direction,
        objcTarget: objcTarget,
        swiftTarget: swiftTarget,
        bridgingHeader: headerImports.isNotEmpty ? bridgingHeaderName : null,
      );
    } else {
      // Swift uses ObjC only: ObjC target is `<Module>ObjC`, Swift target is `<Module>`
      final objcTarget = '${module}ObjC';
      final swiftTarget = module;

      // Write @_exported import <objcTarget> in Swift target
      final exportedPath = p.join(
        'Sources',
        swiftTarget,
        '${module}_Exported.swift',
      );
      final exportedFile = fileFactory(p.join(packageDir.path, exportedPath));
      exportedFile.parent.createSync(recursive: true);
      exportedFile.writeAsStringSync(
        '// Generated re-export of $objcTarget\n@_exported import $objcTarget\n',
      );

      return PodMixedSplitResult(
        direction: direction,
        objcTarget: objcTarget,
        swiftTarget: swiftTarget,
        exportedImportFile: exportedPath,
      );
    }
  }

  /// Patches `@import <Module>;` in Objective-C consumer sources to also include
  /// `@import <Module>ObjC;` when the mixed module was split with a separate ObjC target (§8.8, §8.9).
  static String? patchObjcConsumerImports(
    String source,
    Set<String> mixedModules,
  ) {
    var patched = source;
    for (final module in mixedModules) {
      final pattern = RegExp(
        '^[ \\t]*@import\\s+$module\\s*;[^\n]*',
        multiLine: true,
      );
      patched = patched.replaceAllMapped(pattern, (match) {
        final line = match.group(0)!;
        if (patched.contains('@import ${module}ObjC;')) return line;
        return '$line\n@import ${module}ObjC;';
      });
    }
    return patched == source ? null : patched;
  }
}
