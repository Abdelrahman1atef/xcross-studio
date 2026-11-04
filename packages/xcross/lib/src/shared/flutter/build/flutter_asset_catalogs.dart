// studio: 004 — compile the app target's asset catalogs into Assets.car and
// turn the uncompilable launch storyboard into a UILaunchScreen (#149).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:studio_ext/shared/assets/launch_storyboard.dart';
import 'package:xcross/src/shared/diagnostics/xcross_diagnostics.dart';
import 'package:xcross/src/shared/flutter/build/ios_bundle_resources.dart';

/// Reports a coded build warning (see `BuildWarnings.warn`).
@internal
typedef AssetWarning =
    void Function(
      DiagnosticCode code, {
      required String subject,
      required String message,
    });

/// What the bundle got from the asset catalogs and the launch storyboard.
@internal
final class FlutterAssetCatalogResult {
  const FlutterAssetCatalogResult({
    this.infoPlistAdditions = const {},
    this.launchScreen,
    this.launchStoryboardName,
    this.handled = const {},
  });

  static const none = FlutterAssetCatalogResult();

  /// App icon keys for Info.plist.
  final Map<String, Object> infoPlistAdditions;

  /// The `UILaunchScreen` dictionary replacing the launch storyboard.
  final Map<String, Object>? launchScreen;

  /// The storyboard [launchScreen] was made from.
  final String? launchStoryboardName;

  /// Skipped resources (paths) this step dealt with and reported itself.
  final Set<String> handled;
}

/// Compiles the `.xcassets` the resource stager leaves out, writes
/// `Assets.car` and the loose icon PNGs into the bundle, and reads the
/// launch storyboard into a `UILaunchScreen` (background colour plus one
/// centred image, both from the compiled catalog).
@internal
final class FlutterAssetCatalogs {
  FlutterAssetCatalogs({
    required this.fileSystem,
    required this.paths,
    required this.warn,
    required this.trace,
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final AssetWarning warn;
  final void Function(String message) trace;

  /// The colour set holding the launch screen background.
  static const launchColorName = 'XCrossLaunchBackground';

  static final _launchStoryboardPattern = RegExp(
    r'<key>UILaunchStoryboardName</key>\s*<string>([^<$]*)</string>',
  );

  /// `UILaunchStoryboardName` of an Info.plist template, if literal.
  static String? launchStoryboardName(String plistXml) {
    final name = _launchStoryboardPattern.firstMatch(plistXml)?.group(1);
    return name == null || name.trim().isEmpty ? null : name.trim();
  }

  FlutterAssetCatalogResult compile({
    required String bundleDir,
    required List<SkippedResource> skipped,
    required String deploymentTarget,
    String? launchStoryboardName,
    String Function(String path)? display,
  }) {
    final show = display ?? paths.basename;
    final catalogs = [
      for (final resource in skipped)
        if (resource.reason == SkippedResourceReason.assetCatalog)
          resource.path,
    ];
    final storyboard = launchStoryboardName == null
        ? null
        : [
            for (final resource in skipped)
              if (resource.reason ==
                      SkippedResourceReason.uncompiledStoryboard &&
                  paths.basenameWithoutExtension(resource.path) ==
                      launchStoryboardName &&
                  fileSystem.file(resource.path).existsSync())
                resource.path,
          ].firstOrNull;
    if (catalogs.isEmpty && storyboard == null) {
      return FlutterAssetCatalogResult.none;
    }

    final compiler = AssetCatalogCompiler(fileSystem: fileSystem, paths: paths);
    final spec = storyboard == null ? null : _readStoryboard(storyboard, show);
    final approximations = [...?spec?.approximations];
    CatalogColor? launchColor;
    CatalogColor? backgroundImageColor;
    if (spec != null) {
      final backgroundImage = spec.backgroundImageName;
      if (backgroundImage != null) {
        backgroundImageColor = compiler.uniformImageColor(
          catalogs,
          backgroundImage,
        );
        if (backgroundImageColor == null) {
          approximations.add(
            'full-screen image "$backgroundImage" (only a single-colour '
            'background image can be used)',
          );
        }
      }
      launchColor =
          backgroundImageColor ?? spec.background ?? LaunchStoryboard.white;
    }

    final launchImage = spec?.imageName;
    final CompiledAssetCatalog compiled;
    try {
      compiled = compiler.compile(
        catalogs,
        deploymentTarget: deploymentTarget,
        extraColors: {launchColorName: ?launchColor},
        launch: launchImage == null || launchColor == null
            ? null
            : LaunchBackdrop(
                imageName: launchImage,
                colorName: backgroundImageColor == null
                    ? spec?.backgroundColorName
                    : null,
                color: launchColor,
              ),
      );
      // A compiler fault must never fail the build: it falls back to
      // today's behaviour with a coded warning.
    } on Object catch (error) {
      for (final catalog in catalogs) {
        warn(
          XcrossCodes.buildAssetCatalogSkipped,
          subject: show(catalog),
          message:
              '${show(catalog)} could not be compiled ($error); the icons and '
              'images in it are not in the app.',
        );
      }
      return FlutterAssetCatalogResult(handled: {...catalogs});
    }

    for (final issue in compiled.issues) {
      warn(
        issue.kind == AssetCatalogIssueKind.unsupported
            ? XcrossCodes.buildAssetUnsupported
            : XcrossCodes.buildAssetInvalid,
        subject: issue.subject,
        message: issue.message,
      );
    }
    if (compiled.renditionCount > 0) {
      fileSystem
          .file(paths.join(bundleDir, 'Assets.car'))
          .writeAsBytesSync(compiled.car);
    }
    for (final loose in compiled.looseFiles) {
      fileSystem
          .file(paths.join(bundleDir, loose.name))
          .writeAsBytesSync(loose.bytes);
    }
    trace(
      'Assets.car: ${compiled.renditionCount} renditions from '
      '${catalogs.map(show).join(', ')}'
      '${compiled.appIconName == null ? '' : ', app icon '
                '"${compiled.appIconName}" '
                '(${compiled.looseFiles.length} loose PNGs)'}',
    );

    Map<String, Object>? launchScreen;
    if (spec != null && storyboard != null) {
      final named = spec.backgroundColorName;
      final useNamed =
          backgroundImageColor == null &&
          named != null &&
          compiled.colorNames.contains(named);
      if (named != null && !useNamed && backgroundImageColor == null) {
        approximations.add(
          'colour "$named" (not a colour set in the asset catalog)',
        );
      }
      final image = spec.imageName;
      final hasImage = image != null && compiled.imageNames.contains(image);
      if (image != null && !hasImage) {
        approximations.add('image "$image" (not in the asset catalog)');
      }
      launchScreen = {
        'UIColorName': useNamed ? named : launchColorName,
        'UIImageName': ?(hasImage ? image : null),
      };
      final name = paths.basenameWithoutExtension(storyboard);
      if (approximations.isNotEmpty) {
        warn(
          XcrossCodes.buildLaunchScreenApproximated,
          subject: name,
          message:
              '${show(storyboard)} is shown as a UILaunchScreen; left out: '
              '${approximations.join(', ')}.',
        );
      }
      trace('$name.storyboard → UILaunchScreen $launchScreen');
    }

    return FlutterAssetCatalogResult(
      infoPlistAdditions: compiled.infoPlistAdditions,
      launchScreen: launchScreen,
      launchStoryboardName: launchScreen == null ? null : launchStoryboardName,
      handled: {...catalogs, ?(launchScreen == null ? null : storyboard)},
    );
  }

  LaunchScreenSpec? _readStoryboard(
    String storyboard,
    String Function(String path) show,
  ) {
    try {
      return LaunchStoryboard.parse(
        fileSystem.file(storyboard).readAsStringSync(),
      );
    } on FormatException catch (error) {
      warn(
        XcrossCodes.buildLaunchScreenUnreadable,
        subject: paths.basenameWithoutExtension(storyboard),
        message: '${show(storyboard)} cannot be read (${error.message}).',
      );
      return null;
    }
  }

  /// [plistXml] with the icon keys and the launch screen of [result].
  ///
  /// An existing non-empty `UILaunchScreen` (written by the developer) is
  /// kept. Throws [FormatException] when [plistXml] is not a dictionary.
  static String mergeInfoPlist(
    String plistXml,
    FlutterAssetCatalogResult result,
  ) {
    final launch = result.launchScreen;
    if (result.infoPlistAdditions.isEmpty && launch == null) return plistXml;
    final root = _dictionary(plistXml);
    final existing = root['UILaunchScreen'];
    final updated = <String, Object>{
      ...root,
      ...result.infoPlistAdditions,
      if (launch != null && (existing is! Map || existing.isEmpty))
        'UILaunchScreen': launch,
    };
    return PropertyListSerialization.stringWithPropertyList(updated);
  }

  static const _doctype =
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">';

  static Map<String, Object> _dictionary(String xml) {
    var source = xml;
    if (!source.contains('<!DOCTYPE')) {
      final start = source.indexOf('<plist');
      if (start >= 0) {
        source = [
          source.substring(0, start),
          _doctype,
          source.substring(start),
        ].join('\n');
      }
    }
    final Object root;
    try {
      root = PropertyListSerialization.propertyListWithString(source);
      // The parser reports malformed input with assorted error types.
    } on Object catch (error) {
      throw FormatException('Info.plist is not a valid property list ($error)');
    }
    if (root is! Map) throw const FormatException('Info.plist is not a dict');
    return {
      for (final MapEntry(:key, :value) in root.entries)
        if (value != null) '$key': value as Object,
    };
  }
}
