import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Generates `<Pod>-prefix.pch` and resolves `-include` compiler flags (§8.6).
@internal
final class PodPrefixHeader {
  const PodPrefixHeader({
    required this.directoryFactory,
    required this.fileFactory,
  });

  final Directory Function(String) directoryFactory;
  final File Function(String) fileFactory;

  static const defaultPchTemplate = '''
#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif
''';

  /// Resolves the prefix header for [pod] with [moduleName].
  ///
  /// - If [prefixHeaderFile] is `false` or `'false'`: no prefix header is generated, returns `[]`.
  /// - If [prefixHeaderFile] is a path: uses that file and returns `['-include', path]`.
  /// - Otherwise: generates `Sources/<Module>/xcross/<Pod>-prefix.pch` with the UIKit/FOUNDATION_EXPORT
  ///   template plus any [prefixHeaderContents], returning `['-include', generatedPath]`.
  List<String> resolveAndGenerate({
    required Directory packageDir,
    required String pod,
    required String moduleName,
    Object? prefixHeaderFile,
    String? prefixHeaderContents,
  }) {
    if (prefixHeaderFile == false || prefixHeaderFile == 'false') {
      return const [];
    }

    if (prefixHeaderFile is String &&
        prefixHeaderFile.isNotEmpty &&
        prefixHeaderFile != 'true') {
      final customPath = p.isAbsolute(prefixHeaderFile)
          ? prefixHeaderFile
          : p.join(packageDir.path, prefixHeaderFile);
      return ['-include', customPath.replaceAll(r'\', '/')];
    }

    final xcrossDir = directoryFactory(
      p.join(packageDir.path, 'Sources', moduleName, 'xcross'),
    );
    xcrossDir.createSync(recursive: true);

    final pchFile = fileFactory(p.join(xcrossDir.path, '$pod-prefix.pch'));
    final buffer = StringBuffer(defaultPchTemplate);
    if (prefixHeaderContents != null &&
        prefixHeaderContents.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('// prefix_header_contents:');
      buffer.writeln(prefixHeaderContents.trim());
    }

    pchFile.writeAsStringSync(buffer.toString());
    final relPath = p
        .relative(pchFile.path, from: packageDir.path)
        .replaceAll(r'\', '/');
    return ['-include', relPath];
  }
}
