// studio: 021 — what the project says about its App Store app
// (specs/021-app-store-submission, AC-021-1).
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';

/// The bundle ID, a display name and a SKU suggestion for the New App form.
@internal
@immutable
final class AppStoreProject {
  const AppStoreProject({this.bundleId, this.name});

  /// Reads the Flutter project at [root]; every field is null when it is not
  /// one.
  factory AppStoreProject.read({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String root,
  }) {
    final bundleId = ReleaseProject(
      fileSystem: fileSystem,
      paths: paths,
      root: root,
    ).bundleId;
    String? name;
    final info = fileSystem.file(
      paths.join(root, 'ios', 'Runner', 'Info.plist'),
    );
    if (info.existsSync()) {
      try {
        final plist = PropertyListSerialization.propertyListWithString(
          info.readAsStringSync(),
        );
        if (plist is Map) {
          for (final key in const ['CFBundleDisplayName', 'CFBundleName']) {
            final value = plist[key];
            if (value is String && value.isNotEmpty && !value.contains(r'$')) {
              name = value;
              break;
            }
          }
        }
      } on Object {
        // A template plist with variables or no DOCTYPE: fall back below.
      }
    }
    if (name == null) {
      final pubspec = fileSystem.file(paths.join(root, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        name = RegExp(
          r'^name:\s*["\x27]?([A-Za-z0-9_]+)',
          multiLine: true,
        ).firstMatch(pubspec.readAsStringSync())?.group(1);
      }
    }
    return AppStoreProject(bundleId: bundleId, name: name);
  }

  final String? bundleId;
  final String? name;

  /// A SKU to suggest: the bundle ID's last component, upper-cased, with the
  /// characters App Store Connect allows.
  String? get sku {
    final id = bundleId;
    if (id == null) return null;
    final last = id.split('.').last;
    final cleaned = last.toUpperCase().replaceAll(RegExp('[^A-Z0-9_]'), '_');
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Apple's New App page (the public API cannot create apps).
  static const newAppUrl = 'https://appstoreconnect.apple.com/apps';
}
