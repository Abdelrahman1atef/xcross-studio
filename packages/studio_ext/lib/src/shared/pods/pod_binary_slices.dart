import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:propertylistserialization/propertylistserialization.dart';

@internal
final class PodNoSlice implements Exception {
  const PodNoSlice(this.pod, this.available, this.needed);
  final String pod;
  final List<String> available;
  final String needed;

  @override
  String toString() =>
      'pod.no_slice: $pod has ${available.join(', ')}; this build needs $needed';
}

/// Reads the xcframework's declared iOS architectures for a build target.
@internal
final class PodBinarySlices {
  const PodBinarySlices(this.fileFactory);
  final File Function(String) fileFactory;

  List<String> inspect(Directory framework) {
    final info = fileFactory(path.join(framework.path, 'Info.plist'));
    final bytes = info.readAsBytesSync();
    final binary =
        bytes.length >= 8 && ascii.decode(bytes.sublist(0, 8)) == 'bplist00';
    final value = binary
        ? PropertyListSerialization.propertyListWithData(
            ByteData.sublistView(Uint8List.fromList(bytes)),
          )
        : PropertyListSerialization.propertyListWithString(utf8.decode(bytes));
    if (value is! Map || value['AvailableLibraries'] is! List) {
      throw const FormatException('Invalid xcframework Info.plist');
    }
    return [
      for (final library in value['AvailableLibraries'] as List<Object?>)
        if (library is Map && library['SupportedPlatform'] == 'ios')
          '${library['LibraryIdentifier']} (${(library['SupportedArchitectures'] as List?)?.join(',') ?? ''})',
    ];
  }

  String requireArm64({
    required String pod,
    required Directory framework,
    required String? variant,
    required String needed,
  }) {
    final info = fileFactory(path.join(framework.path, 'Info.plist'));
    final bytes = info.readAsBytesSync();
    final binary =
        bytes.length >= 8 && ascii.decode(bytes.sublist(0, 8)) == 'bplist00';
    final value = binary
        ? PropertyListSerialization.propertyListWithData(
            ByteData.sublistView(Uint8List.fromList(bytes)),
          )
        : PropertyListSerialization.propertyListWithString(utf8.decode(bytes));
    if (value is! Map || value['AvailableLibraries'] is! List) {
      throw const FormatException('Invalid xcframework Info.plist');
    }
    for (final library in value['AvailableLibraries'] as List<Object?>) {
      if (library is Map &&
          library['SupportedPlatform'] == 'ios' &&
          library['SupportedPlatformVariant'] == variant &&
          library['SupportedArchitectures'] is List &&
          (library['SupportedArchitectures'] as List<Object?>).contains(
            'arm64',
          ) &&
          library['LibraryIdentifier'] is String) {
        return library['LibraryIdentifier'] as String;
      }
    }
    throw PodNoSlice(pod, inspect(framework), needed);
  }
}
