import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

@internal
final class PlistStoryboardPolicy {
  PlistStoryboardPolicy(this.fileSystem, this.paths);

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// [onRemoved] (studio: 002) is told about every storyboard reference
  /// that is removed, as `(Info.plist key, storyboard name)`.
  String stripUnsatisfiableStoryboards(
    String xml,
    String bundleDir, {
    void Function(String key, String name)? onRemoved,
  }) {
    bool hasCompiled(String name) => fileSystem
        .directory(paths.join(bundleDir, '$name.storyboardc'))
        .existsSync();

    // Named local reused by Main and Scene patterns (identical predicate).
    String Function(Match) keepIfCompiled(String key) => (m) {
      if (hasCompiled(m.group(1)!)) return m.group(0)!;
      onRemoved?.call(key, m.group(1)!);
      return '';
    };

    var result = xml.replaceAllMapped(
      _uiMainStoryboardPattern,
      keepIfCompiled('UIMainStoryboardFile'),
    );

    result = result.replaceAllMapped(_uiLaunchStoryboardPattern, (m) {
      if (hasCompiled(m.group(1)!)) {
        return m.group(0)!;
      }
      onRemoved?.call('UILaunchStoryboardName', m.group(1)!);
      // Replace with UILaunchScreen programmatic launch screen if absent.
      // Reads the pre-launch-strip snapshot of `result` on purpose: hoisting
      // this check or chaining the replaceAllMapped calls changes which
      // snapshot is inspected and can emit a duplicate UILaunchScreen.
      if (!result.contains('UILaunchScreen')) {
        return '<key>UILaunchScreen</key>\n\t<dict/>';
      }
      return '';
    });

    result = result.replaceAllMapped(
      _uiSceneStoryboardPattern,
      keepIfCompiled('UISceneStoryboardFile'),
    );

    return result;
  }

  static final _uiMainStoryboardPattern = RegExp(
    r'<key>UIMainStoryboardFile</key>\s*<string>([^<]*)</string>',
  );

  static final _uiLaunchStoryboardPattern = RegExp(
    r'<key>UILaunchStoryboardName</key>\s*<string>([^<]*)</string>',
  );

  static final _uiSceneStoryboardPattern = RegExp(
    r'<key>UISceneStoryboardFile</key>\s*<string>([^<]*)</string>',
  );
}
