import 'dart:io';

import 'package:path/path.dart' as p;

/// A read-only summary of a Flutter project for the Project page. Only for
/// display: xcross itself decides everything at build time.
class ProjectInfo {
  const ProjectInfo({
    required this.path,
    required this.isFlutterProject,
    this.name,
    this.version,
    this.bundleId,
    this.entitlements = const [],
    this.hasAppIcon = false,
    this.hasLaunchScreen = false,
  });

  final String path;
  final bool isFlutterProject;
  final String? name;
  final String? version;
  final String? bundleId;

  /// Entitlement keys declared in `ios/Runner/*.entitlements`.
  final List<String> entitlements;
  final bool hasAppIcon;
  final bool hasLaunchScreen;

  /// `<project>/build/xcross-ios`, where xcross writes the `.app` and `.ipa`.
  String get outputDirectory => p.join(path, 'build', 'xcross-ios');

  static Future<ProjectInfo> read(String path) async {
    final pubspec = File(p.join(path, 'pubspec.yaml'));
    final ios = Directory(p.join(path, 'ios'));
    if (!pubspec.existsSync() || !ios.existsSync()) {
      return ProjectInfo(path: path, isFlutterProject: false);
    }
    final yaml = await pubspec.readAsString();
    String? field(String key) => RegExp(
      '^$key:\\s*["\']?([^"\'#\\n]+?)["\']?\\s*(#.*)?\$',
      multiLine: true,
    ).firstMatch(yaml)?.group(1)?.trim();

    String? bundleId;
    final pbxproj = File(
      p.join(path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    );
    if (pbxproj.existsSync()) {
      final ids = [
        for (final match in RegExp(
          r'PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;',
        ).allMatches(await pbxproj.readAsString()))
          match.group(1)!,
      ].where((id) => !id.endsWith('.RunnerTests')).toList();
      if (ids.isNotEmpty) {
        ids.sort((a, b) => a.length.compareTo(b.length));
        bundleId = ids.first;
      }
    }

    final entitlements = <String>{};
    final runner = Directory(p.join(path, 'ios', 'Runner'));
    if (runner.existsSync()) {
      for (final entity in runner.listSync()) {
        if (entity is File && entity.path.endsWith('.entitlements')) {
          for (final match in RegExp(
            r'<key>([^<]+)</key>',
          ).allMatches(await entity.readAsString())) {
            entitlements.add(match.group(1)!);
          }
        }
      }
    }

    return ProjectInfo(
      path: path,
      isFlutterProject: true,
      name: field('name'),
      version: field('version'),
      bundleId: bundleId,
      entitlements: entitlements.toList()..sort(),
      hasAppIcon: Directory(
        p.join(path, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'),
      ).existsSync(),
      hasLaunchScreen: File(
        p.join(path, 'ios', 'Runner', 'Base.lproj', 'LaunchScreen.storyboard'),
      ).existsSync(),
    );
  }
}
