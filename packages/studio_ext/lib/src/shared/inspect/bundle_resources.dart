import 'package:meta/meta.dart';

import 'package:studio_ext/src/shared/inspect/inspect_codes.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';

/// Reads icons, `Assets.car`, the launch screen and compiled storyboards of
/// the bundle in [source] (data-model "Resources").
///
/// [info] is the root Info.plist, or null when it is missing or unreadable;
/// then declaration-based issues are skipped because nothing is known about
/// what the bundle declares.
@internal
Resources readResources(
  InspectSource source,
  Map<String, Object?>? info,
  List<Issue> issues,
) {
  final assetsCar = AssetsCar(
    present: source.hasFile('Assets.car'),
    sizeBytes: source.sizeOf('Assets.car'),
  );
  final rootFiles = [
    for (final file in source.files)
      if (!file.contains('/')) file,
  ];
  final storyboards = compiledStoryboards(source.files);

  String? iconName;
  final declared = <DeclaredIcon>[];
  void addIconSet(String set, Object? icons) {
    if (icons is! Map) return;
    final primary = icons['CFBundlePrimaryIcon'];
    if (primary is! Map) return;
    final name = primary['CFBundleIconName'];
    if (set == 'CFBundleIcons' && name is String) iconName = name;
    final files = primary['CFBundleIconFiles'];
    if (files is! List) return;
    for (final file in files.whereType<String>()) {
      declared.add(
        DeclaredIcon(
          set: set,
          name: file,
          files: matchImageFiles(rootFiles, file),
        ),
      );
    }
  }

  addIconSet('CFBundleIcons', info?['CFBundleIcons']);
  addIconSet('CFBundleIcons~ipad', info?['CFBundleIcons~ipad']);
  final legacyIcon = info?['CFBundleIconFile'];
  if (legacyIcon is String) {
    declared.add(
      DeclaredIcon(
        set: 'CFBundleIconFile',
        name: legacyIcon,
        files: matchImageFiles(rootFiles, legacyIcon),
      ),
    );
  }
  declared.sort((a, b) {
    final bySet = a.set.compareTo(b.set);
    return bySet != 0 ? bySet : a.name.compareTo(b.name);
  });

  final launchScreen = _launchScreen(info, rootFiles, storyboards, assetsCar);

  if (info != null) {
    if (declared.isEmpty && (iconName == null || !assetsCar.present)) {
      issues.add(
        Issue.of(
          InspectCodes.noIcon,
          severity: IssueSeverity.warning,
          message: 'The app declares no icon files and has no Assets.car.',
        ),
      );
    }
    for (final icon in declared.where((icon) => !icon.resolved)) {
      issues.add(
        Issue.of(
          InspectCodes.iconFileMissing,
          severity: IssueSeverity.warning,
          message:
              'Icon "${icon.name}" (${icon.set}) matches no file in the '
              'bundle root.',
        ),
      );
    }
    _launchIssues(launchScreen, rootFiles, issues);
  }

  return Resources(
    icons: Icons(iconName: iconName, declared: declared),
    assetsCar: assetsCar,
    launchScreen: launchScreen,
    storyboards: storyboards,
  );
}

LaunchScreen _launchScreen(
  Map<String, Object?>? info,
  List<String> rootFiles,
  List<String> storyboards,
  AssetsCar assetsCar,
) {
  final dictionary = info?['UILaunchScreen'];
  final storyboardName = info?['UILaunchStoryboardName'];
  final storyboard = storyboardName is String
      ? LaunchStoryboard(
          name: storyboardName,
          compiledPresent: storyboards.any(
            (path) =>
                path == '$storyboardName.storyboardc' ||
                path.endsWith('.lproj/$storyboardName.storyboardc'),
          ),
        )
      : null;
  if (dictionary is Map) {
    final imageName = dictionary['UIImageName'];
    final image = imageName is String
        ? LaunchImage(
            name: imageName,
            source: matchImageFiles(rootFiles, imageName).isNotEmpty
                ? LaunchImageSource.looseFile
                : assetsCar.present
                ? LaunchImageSource.assetCatalog
                : LaunchImageSource.missing,
          )
        : null;
    return LaunchScreen(
      kind: LaunchScreenKind.uiLaunchScreen,
      keys: [for (final key in dictionary.keys) '$key']..sort(),
      image: image,
      storyboard: storyboard,
    );
  }
  return LaunchScreen(
    kind: storyboard == null
        ? LaunchScreenKind.none
        : LaunchScreenKind.storyboard,
    keys: const [],
    image: null,
    storyboard: storyboard,
  );
}

void _launchIssues(
  LaunchScreen launchScreen,
  List<String> rootFiles,
  List<Issue> issues,
) {
  if (launchScreen.kind == LaunchScreenKind.none) {
    issues.add(
      Issue.of(
        InspectCodes.noLaunchScreen,
        severity: IssueSeverity.warning,
        message: 'Neither UILaunchScreen nor UILaunchStoryboardName is set.',
      ),
    );
  }
  if (launchScreen.kind == LaunchScreenKind.uiLaunchScreen &&
      launchScreen.keys.isEmpty) {
    issues.add(
      Issue.of(
        InspectCodes.launchScreenEmpty,
        severity: IssueSeverity.warning,
        message: 'UILaunchScreen is an empty dictionary.',
      ),
    );
  }
  final image = launchScreen.image;
  if (image?.source == LaunchImageSource.missing) {
    issues.add(
      Issue.of(
        InspectCodes.launchImageMissing,
        severity: IssueSeverity.warning,
        message:
            'Launch image "${image!.name}" is neither a bundle file nor in an '
            'Assets.car.',
      ),
    );
  }
  if (image?.source == LaunchImageSource.looseFile) {
    issues.add(
      Issue.of(
        InspectCodes.launchImageNotInCatalog,
        severity: IssueSeverity.warning,
        path: matchImageFiles(rootFiles, image!.name).first,
        message:
            'Launch image "${image.name}" is a loose PNG, which iOS does not '
            'show as a launch image.',
      ),
    );
  }
  final storyboard = launchScreen.storyboard;
  if (storyboard != null && !storyboard.compiledPresent) {
    issues.add(
      Issue.of(
        InspectCodes.launchStoryboardMissing,
        severity: IssueSeverity.warning,
        message:
            'UILaunchStoryboardName "${storyboard.name}" has no compiled '
            '${storyboard.name}.storyboardc.',
      ),
    );
  }
}

/// Root-level files that iOS would load for image [name]:
/// `<name>[@2x|@3x][~ipad|~iphone].png`, where [name] may already end in
/// `.png`. Sorted.
@internal
List<String> matchImageFiles(List<String> rootFiles, String name) {
  final base = name.toLowerCase().endsWith('.png')
      ? name.substring(0, name.length - 4)
      : name;
  final pattern = RegExp(
    '^${RegExp.escape(base)}(@[23]x)?(~ipad|~iphone)?\\.png\$',
  );
  return [
    for (final file in rootFiles)
      if (pattern.hasMatch(file)) file,
  ]..sort();
}

/// Paths of compiled storyboard directories (`*.storyboardc`), sorted.
@internal
List<String> compiledStoryboards(List<String> files) {
  final result = <String>{};
  for (final file in files) {
    final segments = file.split('/');
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].endsWith('.storyboardc')) {
        result.add(segments.sublist(0, i + 1).join('/'));
        break;
      }
    }
  }
  return result.toList()..sort();
}
