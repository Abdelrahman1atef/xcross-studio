import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// Wraps vendored static libraries (.a) and their public headers into a library
/// xcframework bundle conforming to Apple's xcframework layout.
@internal
final class PodLibraryXcframework {
  const PodLibraryXcframework({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  /// Wraps [libraryFile] and headers from [headersDir] into an xcframework at [destination].
  ///
  /// If [simulatorLibraryFile] is provided, an `ios-arm64-simulator` slice is also added.
  Directory build({
    required String name,
    required File libraryFile,
    required Directory destination,
    Directory? headersDir,
    File? simulatorLibraryFile,
  }) {
    final xcframeworkDir = directoryFactory(
      path.join(destination.path, '$name.xcframework'),
    );
    xcframeworkDir.createSync(recursive: true);

    final binaryName = path.basename(libraryFile.path);
    final libraries = <Map<String, Object?>>[];

    // 1. Device slice: ios-arm64
    final deviceSliceDir = directoryFactory(
      path.join(xcframeworkDir.path, 'ios-arm64'),
    )..createSync(recursive: true);
    libraryFile.copySync(path.join(deviceSliceDir.path, binaryName));

    if (headersDir != null && headersDir.existsSync()) {
      final sliceHeadersDir = directoryFactory(
        path.join(deviceSliceDir.path, 'Headers'),
      )..createSync(recursive: true);
      _copyDirectory(headersDir, sliceHeadersDir);
    }

    libraries.add({
      'BinaryPath': binaryName,
      'HeadersPath': 'Headers',
      'LibraryIdentifier': 'ios-arm64',
      'LibraryPath': binaryName,
      'SupportedArchitectures': ['arm64'],
      'SupportedPlatform': 'ios',
    });

    // 2. Simulator slice: ios-arm64-simulator (if provided)
    if (simulatorLibraryFile != null && simulatorLibraryFile.existsSync()) {
      final simBinaryName = path.basename(simulatorLibraryFile.path);
      final simSliceDir = directoryFactory(
        path.join(xcframeworkDir.path, 'ios-arm64-simulator'),
      )..createSync(recursive: true);
      simulatorLibraryFile.copySync(path.join(simSliceDir.path, simBinaryName));

      if (headersDir != null && headersDir.existsSync()) {
        final simHeadersDir = directoryFactory(
          path.join(simSliceDir.path, 'Headers'),
        )..createSync(recursive: true);
        _copyDirectory(headersDir, simHeadersDir);
      }

      libraries.add({
        'BinaryPath': simBinaryName,
        'HeadersPath': 'Headers',
        'LibraryIdentifier': 'ios-arm64-simulator',
        'LibraryPath': simBinaryName,
        'SupportedArchitectures': ['arm64'],
        'SupportedPlatform': 'ios',
        'SupportedPlatformVariant': 'simulator',
      });
    }

    // 3. Info.plist
    final infoPlist = fileFactory(path.join(xcframeworkDir.path, 'Info.plist'));
    infoPlist.writeAsStringSync(_buildInfoPlist(libraries));

    return xcframeworkDir;
  }

  void _copyDirectory(Directory source, Directory destination) {
    for (final entity in source.listSync(recursive: true, followLinks: false)) {
      final relative = path.relative(entity.path, from: source.path);
      final targetPath = path.join(destination.path, relative);
      if (entity is Directory) {
        directoryFactory(targetPath).createSync(recursive: true);
      } else if (entity is File) {
        fileFactory(targetPath).parent.createSync(recursive: true);
        entity.copySync(targetPath);
      }
    }
  }

  String _buildInfoPlist(List<Map<String, Object?>> libraries) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    );
    buffer.writeln('<plist version="1.0">');
    buffer.writeln('<dict>');
    buffer.writeln('  <key>AvailableLibraries</key>');
    buffer.writeln('  <array>');
    for (final lib in libraries) {
      buffer.writeln('    <dict>');
      buffer.writeln('      <key>BinaryPath</key>');
      buffer.writeln('      <string>${lib['BinaryPath']}</string>');
      buffer.writeln('      <key>HeadersPath</key>');
      buffer.writeln('      <string>${lib['HeadersPath']}</string>');
      buffer.writeln('      <key>LibraryIdentifier</key>');
      buffer.writeln('      <string>${lib['LibraryIdentifier']}</string>');
      buffer.writeln('      <key>LibraryPath</key>');
      buffer.writeln('      <string>${lib['LibraryPath']}</string>');
      buffer.writeln('      <key>SupportedArchitectures</key>');
      buffer.writeln('      <array>');
      for (final arch in lib['SupportedArchitectures']! as List<String>) {
        buffer.writeln('        <string>$arch</string>');
      }
      buffer.writeln('      </array>');
      buffer.writeln('      <key>SupportedPlatform</key>');
      buffer.writeln('      <string>${lib['SupportedPlatform']}</string>');
      if (lib.containsKey('SupportedPlatformVariant')) {
        buffer.writeln('      <key>SupportedPlatformVariant</key>');
        buffer.writeln(
          '      <string>${lib['SupportedPlatformVariant']}</string>',
        );
      }
      buffer.writeln('    </dict>');
    }
    buffer.writeln('  </array>');
    buffer.writeln('  <key>CFBundlePackageType</key>');
    buffer.writeln('  <string>XFWK</string>');
    buffer.writeln('  <key>XCFrameworkFormatVersion</key>');
    buffer.writeln('  <string>1.0</string>');
    buffer.writeln('</dict>');
    buffer.writeln('</plist>');
    return buffer.toString();
  }
}
