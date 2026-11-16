import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// Thrown when a resource name collides with another resource or bundle.
@internal
final class PodResourceClash implements Exception {
  const PodResourceClash(this.pod, this.resourceName);
  final String pod;
  final String resourceName;

  @override
  String toString() =>
      'pod.resource_clash: Resource "$resourceName" in pod "$pod" collides with an existing file or bundle.';
}

/// Thrown when a resource requires an Apple compiler unavailable on this host (§8.7, T304).
@internal
final class PodUncompiledResource implements Exception {
  const PodUncompiledResource(this.pod, this.file, this.extension);
  final String pod;
  final String file;
  final String extension;

  @override
  String toString() =>
      'pod.uncompiled_resource: Resource "$file" in pod "$pod" requires an Apple compiler ($extension) and cannot be compiled on this host.';
}

/// Validates whether a resource file can be packaged or needs an Apple compiler (§8.7).
@internal
final class PodResourceCompilerCheck {
  static const uncompiledExtensions = {
    '.xcdatamodeld',
    '.metal',
    '.xib',
    '.storyboard',
  };

  /// Checks whether [relativePath] needs an Apple compiler that is unavailable.
  static String? checkUncompiled(String relativePath) {
    final lower = relativePath.toLowerCase();
    for (final ext in uncompiledExtensions) {
      if (lower.endsWith(ext) || lower.contains('$ext/')) {
        return ext;
      }
    }
    return null;
  }
}

/// Stages resource bundles and plain resources according to CocoaPods conventions.
@internal
final class PodResources {
  const PodResources({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  /// Stages [resourceBundles] and [plainResources] into [destination].
  ///
  /// Returns the set of staged file paths relative to [destination].
  Set<String> stageResources({
    required String pod,
    required Directory destination,
    Map<String, List<File>> resourceBundles = const {},
    List<File> plainResources = const [],
    Set<String> existingPaths = const {},
  }) {
    final claimed = Set<String>.from(existingPaths);

    // 1. Process resource bundles: <Key>.bundle
    for (final entry in resourceBundles.entries) {
      final key = entry.key;
      final bundleDirName = '$key.bundle';
      if (claimed.contains(bundleDirName)) {
        throw PodResourceClash(pod, bundleDirName);
      }
      claimed.add(bundleDirName);

      final bundleDir = directoryFactory(
        path.join(destination.path, bundleDirName),
      )..createSync(recursive: true);

      // Write org.cocoapods.<Key> Info.plist
      final infoPlist = fileFactory(path.join(bundleDir.path, 'Info.plist'));
      infoPlist.writeAsStringSync(_bundleInfoPlist(key));
      claimed.add(path.join(bundleDirName, 'Info.plist'));

      // Copy files into bundle
      for (final file in entry.value) {
        final fileName = path.basename(file.path);
        if (PodResourceCompilerCheck.checkUncompiled(file.path)
            case final ext?) {
          throw PodUncompiledResource(pod, fileName, ext);
        }
        final targetRelative = path.join(bundleDirName, fileName);
        if (claimed.contains(targetRelative)) {
          throw PodResourceClash(pod, targetRelative);
        }
        claimed.add(targetRelative);
        file.copySync(path.join(bundleDir.path, fileName));
      }
    }

    // 2. Process plain resources
    for (final file in plainResources) {
      final fileName = path.basename(file.path);
      if (PodResourceCompilerCheck.checkUncompiled(file.path) case final ext?) {
        throw PodUncompiledResource(pod, fileName, ext);
      }
      // Info.plist or PrivacyInfo.xcprivacy never go to app root
      if (fileName.toLowerCase() == 'info.plist' ||
          fileName.toLowerCase() == 'privacyinfo.xcprivacy') {
        final syntheticBundle = '${pod}Resources.bundle';
        final bundleDir = directoryFactory(
          path.join(destination.path, syntheticBundle),
        )..createSync(recursive: true);
        final targetRelative = path.join(syntheticBundle, fileName);
        if (claimed.contains(targetRelative)) {
          throw PodResourceClash(pod, targetRelative);
        }
        claimed.add(targetRelative);
        file.copySync(path.join(bundleDir.path, fileName));
      } else {
        if (claimed.contains(fileName)) {
          throw PodResourceClash(pod, fileName);
        }
        claimed.add(fileName);
        file.copySync(path.join(destination.path, fileName));
      }
    }

    return claimed;
  }

  String _bundleInfoPlist(String bundleKey) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>org.cocoapods.$bundleKey</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
''';
}
