import 'dart:convert';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:darwin_sdk_kit/shared/sdk/darwin_sdk.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/flutter/swiftpm/filesystem.dart';
import 'package:xcross/src/shared/flutter/swiftpm/host_build_services.dart';
import 'package:xcross/src/shared/flutter/swiftpm/librarian_resolver.dart';

@internal
final class SwiftPmToolchain<T extends PlatformHostInterface> {
  SwiftPmToolchain({
    required this.filesystem,
    required this.hostBuildServices,
    required this.librarianResolver,
  });
  final SwiftPmFilesystem<T> filesystem;
  final SwiftPmHostBuildServices<T> hostBuildServices;
  final SwiftPmLibrarianResolver<T> librarianResolver;
  static const libtool = SwiftPmLibrarianResolver.libtool;

  // studio: Xcode's clang warns when Objective-C passes `nil` to an enum
  // parameter; upstream clang (15 and later) makes -Wint-conversion an
  // error, so videosdk_webrtc (`initWithAudioDeviceModuleType:nil`, through
  // 0.0.19) built in Xcode but stopped here (a client app, 2026-11-17).
  static const appleClangDiagnostics = ['-Wno-error=int-conversion'];

  static const librarians = SwiftPmLibrarianResolver.librarians;
  Future<Map<String, Object>> resolveBuildToolchainIdentity(DarwinSdk? sdk) =>
      hostBuildServices.buildToolchainIdentity(sdk);
  Future<String> writeToolset({
    required String outputDir,
    required String linkerPath,
    String? cCompilerPath,
    String? cxxCompilerPath,
    String? librarianPath,
  }) async {
    final output = filesystem.artifactFileSystem.directory(outputDir);
    await output.create(recursive: true);
    final toolset = <String, Object>{
      'schemaVersion': '1.0',
      'rootPath': SwiftPmFilesystem.jsonPath(output.resolveSymbolicLinksSync()),
      'librarian': {
        'path': librarianPath ?? await librarianResolver.resolveLibrarian(),
      },
    };
    await hostBuildServices.configureToolset(
      toolset,
      linkerPath,
      cCompilerPath,
      cxxCompilerPath,
    );
    final cCompiler = {...?(toolset['cCompiler'] as Map<String, Object>?)};
    cCompiler['extraCLIOptions'] = [
      ...?(cCompiler['extraCLIOptions'] as List<Object?>?),
      ...appleClangDiagnostics,
    ];
    toolset['cCompiler'] = cCompiler;
    final path = p.join(outputDir, 'xcross-toolset.json');
    await filesystem.writeStable(
      path,
      '${const JsonEncoder.withIndent('  ').convert(toolset)}\n',
    );
    return path;
  }
}
