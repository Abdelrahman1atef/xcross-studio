import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:studio_ext/src/shared/pods/pod_xcconfig.dart';

@internal
final class PodBinaryLinkSettings {
  const PodBinaryLinkSettings({
    this.frameworks = const [],
    this.weakFrameworks = const [],
    this.libraries = const [],
    this.ignoredFlags = const [],
  });

  factory PodBinaryLinkSettings.fromConsumer(
    Map<String, Object?> attributes, {
    required PodBuildContext context,
    required String pod,
    required String module,
  }) {
    List<String> strings(Object? value) => switch (value) {
      final List<Object?> value =>
        value.map((part) => part.toString()).toList(),
      final String value => [value],
      _ => [],
    };
    final frameworks = strings(attributes['frameworks']);
    final weak = strings(attributes['weak_frameworks']);
    final libraries = strings(attributes['libraries']);
    final ignored = <String>[];
    const parser = PodXcconfig();
    for (final key in ['pod_target_xcconfig', 'user_target_xcconfig']) {
      final value = attributes[key];
      if (value is! Map) continue;
      final parsed = parser.parse(
        value.map((key, value) => MapEntry(key.toString(), value)),
        context: context,
        pod: pod,
        podRoots: {pod: 'Sources/$module'},
        publicHeaders: 'Headers/Public',
      );
      ignored.addAll(parsed.ignored);
      for (final flags in parsed.values['OTHER_LDFLAGS'] ?? const <String>[]) {
        final tokens = flags
            .split(RegExp(r'\s+'))
            .where((token) => token.isNotEmpty)
            .toList();
        for (var index = 0; index < tokens.length; index++) {
          final flag = tokens[index];
          if ((flag == '-framework' || flag == '-weak_framework') &&
              index + 1 < tokens.length) {
            (flag == '-framework' ? frameworks : weak).add(tokens[++index]);
          } else if (flag.startsWith('-l') && flag.length > 2) {
            libraries.add(flag.substring(2));
          } else if (flag != '-ObjC') {
            ignored.add('pod.setting_ignored: OTHER_LDFLAGS $flag');
          }
        }
      }
    }
    return PodBinaryLinkSettings(
      frameworks: frameworks,
      weakFrameworks: weak,
      libraries: libraries,
      ignoredFlags: ignored,
    );
  }

  final List<String> frameworks;
  final List<String> weakFrameworks;
  final List<String> libraries;
  final List<String> ignoredFlags;
}

/// Writes the local Swift package around one or more vendored xcframeworks.
@internal
final class PodBinaryManifest {
  const PodBinaryManifest();

  String write({
    required String pod,
    required String module,
    required List<String> frameworks,
    PodBinaryLinkSettings linker = const PodBinaryLinkSettings(),
  }) {
    if (!RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(pod)) {
      throw ArgumentError.value(pod, 'pod', 'Invalid pod name');
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(module)) {
      throw ArgumentError.value(module, 'module', 'Invalid module name');
    }
    if (frameworks.isEmpty) throw ArgumentError.value(frameworks, 'frameworks');
    final binaryNames = <String>[];
    final targets = <String>[];
    for (final path in frameworks) {
      if (!RegExp(
        r'^Frameworks/[A-Za-z0-9_.+-]+\.xcframework$',
      ).hasMatch(path)) {
        throw ArgumentError.value(path, 'frameworks', 'Unsafe framework path');
      }
      final name = path.substring(
        'Frameworks/'.length,
        path.length - '.xcframework'.length,
      );
      if (binaryNames.contains(name)) continue;
      binaryNames.add(name);
      targets.add(
        '    .binaryTarget(name: ${jsonEncode(name)}, path: ${jsonEncode(path)})',
      );
    }
    final wrapper = '${module}_xcross';
    if (binaryNames.contains(wrapper)) {
      throw ArgumentError.value(wrapper, 'module', 'Duplicate target name');
    }
    final linkerSettings = <String>[
      for (final framework in linker.frameworks.toSet())
        '.linkedFramework(${jsonEncode(framework)})',
      for (final framework in linker.weakFrameworks.toSet())
        '.unsafeFlags(["-weak_framework", ${jsonEncode(framework)}])',
      for (final library in linker.libraries.toSet())
        '.linkedLibrary(${jsonEncode(library)})',
    ];
    targets.add(
      '    .target(name: ${jsonEncode(wrapper)}, path: "Sources/$wrapper"'
      '${linkerSettings.isEmpty ? '' : ', linkerSettings: [${linkerSettings.join(', ')}]'})',
    );
    final products = [...binaryNames, wrapper].map(jsonEncode).join(', ');
    return [
      '// swift-tools-version: 5.9',
      '// xcross: pod-converter v1',
      'import PackageDescription',
      '',
      'let package = Package(',
      '  name: ${jsonEncode('pod-$pod')},',
      '  products: [.library(name: ${jsonEncode(module)}, targets: [$products])],',
      '  targets: [',
      targets.join(',\n'),
      '  ]',
      ')',
      '',
    ].join('\n');
  }

  String placeholder(String module) =>
      'void ${_identifier(module)}_xcross_anchor(void) {}\n';

  String _identifier(String input) {
    final converted = input.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    return RegExp(r'^\d').hasMatch(converted) ? '_$converted' : converted;
  }
}
