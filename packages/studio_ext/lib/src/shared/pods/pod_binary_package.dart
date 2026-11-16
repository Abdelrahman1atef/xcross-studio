import 'dart:io';

import 'package:cli_kit/shared/logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:studio_ext/src/shared/pods/pod_binary_manifest.dart';
import 'package:studio_ext/src/shared/pods/pod_binary_slices.dart';
import 'package:studio_ext/src/shared/pods/pod_consumer.dart';
import 'package:studio_ext/src/shared/pods/pod_swift_binary_check.dart';
import 'package:studio_ext/src/shared/pods/pod_xcconfig.dart';

/// Stages unchanged vendor xcframework files beside a local Swift manifest.
@internal
final class PodBinaryPackage {
  const PodBinaryPackage({
    required this.manifest,
    required this.directoryFactory,
    required this.fileFactory,
    required this.slices,
    required this.swiftBinaryCheck,
    this.events,
  });

  final PodBinaryManifest manifest;
  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;
  final PodBinarySlices slices;
  final PodSwiftBinaryCheck swiftBinaryCheck;
  final LogEvents? events;

  void writeFromSpec({
    required String pod,
    required Map<String, Object?> spec,
    required PodBuildContext context,
    required Directory source,
    required Directory destination,
    List<String>? selectedSubspecs,
  }) {
    final consumer = const PodConsumer().build(
      spec,
      selected: selectedSubspecs,
    );
    final module =
        (consumer.attributes['module_name'] ?? spec['module_name'])
            ?.toString() ??
        _c99Identifier(pod);
    final raw = consumer.attributes['vendored_frameworks'];
    final vendored = switch (raw) {
      final String value => [value],
      final List<Object?> value =>
        value.map((part) => part.toString()).toList(),
      _ => <String>[],
    };
    final sources = <String, String>{};
    for (final original in vendored) {
      if (!original.endsWith('.xcframework')) {
        throw UnsupportedError(
          'Legacy framework conversion is required: $original',
        );
      }
      final relative = 'Frameworks/${path.basename(original)}';
      if (sources.containsKey(relative) && sources[relative] != original) {
        throw ArgumentError.value(
          original,
          'vendored_frameworks',
          'Name clash',
        );
      }
      sources[relative] = original;
    }
    for (final original in sources.values) {
      final framework = directoryFactory(path.join(source.path, original));
      final identifier = slices.requireArm64(
        pod: pod,
        framework: framework,
        variant: context.simulator ? 'simulator' : null,
        needed: context.simulator ? 'ios-arm64-simulator' : 'ios-arm64',
      );
      final slice = directoryFactory(path.join(framework.path, identifier));
      if (slice.existsSync()) {
        for (final entity
            in slice.listSync(followLinks: false).whereType<Directory>()) {
          if (entity.path.endsWith('.framework')) {
            swiftBinaryCheck.requireInterface(
              entity,
              simulator: context.simulator,
            );
          }
        }
      }
    }
    write(
      pod: pod,
      module: module,
      source: source,
      destination: destination,
      frameworks: sources.keys.toList(),
      sourceFrameworks: sources,
      linker: PodBinaryLinkSettings.fromConsumer(
        consumer.attributes,
        context: context,
        pod: pod,
        module: module,
      ),
    );
  }

  String _c99Identifier(String name) {
    final collapsed = name
        .replaceAll(RegExp('[^A-Za-z0-9_]'), '_')
        .replaceAll(RegExp('_+'), '_');
    return RegExp(r'^\d').hasMatch(collapsed) ? '_$collapsed' : collapsed;
  }

  void write({
    required String pod,
    required String module,
    required Directory source,
    required Directory destination,
    required List<String> frameworks,
    Map<String, String> sourceFrameworks = const {},
    PodBinaryLinkSettings linker = const PodBinaryLinkSettings(),
  }) {
    final text = manifest.write(
      pod: pod,
      module: module,
      frameworks: frameworks,
      linker: linker,
    );
    final copies = <(Directory, Directory, List<FileSystemEntity>)>[];
    var total = 0;
    for (final relative in frameworks.toSet()) {
      final sourceRelative = sourceFrameworks[relative] ?? relative;
      if (path.isAbsolute(sourceRelative) ||
          path.split(path.normalize(sourceRelative)).contains('..') ||
          RegExp('^[A-Za-z]:').hasMatch(sourceRelative)) {
        throw ArgumentError.value(sourceRelative, 'sourceFrameworks');
      }
      final from = directoryFactory(path.join(source.path, sourceRelative));
      if (!from.existsSync()) {
        throw FileSystemException('Missing vendored xcframework', from.path);
      }
      final to = directoryFactory(path.join(destination.path, relative));
      final entities = from.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) total += entity.lengthSync();
      }
      copies.add((from, to, entities));
    }
    var done = 0;
    events?.event('step', {
      'name': 'pod_convert',
      'status': 'start',
      'pod': pod,
      'bytesDone': done,
      'bytesTotal': total,
    });
    for (final (from, to, entities) in copies) {
      for (final entity in entities) {
        final remainder = path.relative(entity.path, from: from.path);
        final target = path.join(to.path, remainder);
        if (entity is Directory) {
          directoryFactory(target).createSync(recursive: true);
        } else if (entity is File) {
          fileFactory(target).parent.createSync(recursive: true);
          entity.copySync(target);
          done += entity.lengthSync();
          events?.event('step', {
            'name': 'pod_convert',
            'status': 'progress',
            'pod': pod,
            'bytesDone': done,
            'bytesTotal': total,
          });
        } else {
          throw FileSystemException(
            'Unsupported xcframework link',
            entity.path,
          );
        }
      }
    }
    final wrapper = '${module}_xcross';
    final anchor = fileFactory(
      path.join(destination.path, 'Sources', wrapper, 'anchor.c'),
    );
    anchor.createSync(recursive: true);
    anchor.writeAsStringSync(manifest.placeholder(module));
    fileFactory(
      path.join(destination.path, 'Package.swift'),
    ).writeAsStringSync(text);
    events?.event('step', {
      'name': 'pod_convert',
      'status': 'done',
      'pod': pod,
      'bytesDone': done,
      'bytesTotal': total,
    });
  }
}
