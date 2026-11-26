// studio: 051 — the fixes behind `xcross project inspect`: change the bundle
// ID everywhere in the iOS project, and import a Firebase plist so the
// plist, firebase_options.dart and firebase.json name the same iOS app.
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/flutter/build/flutter_app_entitlements.dart';
import 'package:xcross/src/shared/flutter/project/pbx_project_reader.dart';
import 'package:xcross/src/shared/flutter/project/project_inspection.dart';

/// One file a fix changed (or would change, on a dry run).
@internal
@immutable
final class FileChange {
  const FileChange(this.path, this.changes);

  /// Project-relative.
  final String path;

  /// How many values changed in it.
  final int changes;

  Map<String, Object?> toJson() => {'path': path, 'changes': changes};
}

/// A valid bundle ID: reverse-DNS, letters, digits, `-` and `.`.
@internal
bool isValidBundleId(String id) =>
    RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$').hasMatch(id);

/// Rewrites a project's files. Every method keeps the files' formatting and
/// line endings and touches only the values it names.
@internal
final class ProjectRewriter {
  ProjectRewriter({
    required this.fileSystem,
    required this.paths,
    required this.projectRoot,
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String projectRoot;

  String _rel(String path) =>
      paths.relative(path, from: projectRoot).replaceAll(r'\', '/');

  static final _bundleSetting = RegExp(
    r'(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)("?)([^";\s]+)("?)(\s*;)',
  );

  /// Sets the app's bundle ID to [bundleId] in every configuration, moves
  /// the other targets (tests, extensions) that sat under an old app ID
  /// under the new one, and replaces a hard-coded Info.plist ID. Firebase
  /// files are left alone: they belong to a Firebase app, see
  /// [importFirebasePlist].
  ({String? previous, List<FileChange> files}) setBundleId(
    String bundleId, {
    bool dryRun = false,
  }) {
    if (!isValidBundleId(bundleId)) {
      throw XcrossError(
        '"$bundleId" is not a bundle ID: use letters, digits, "-" and dots, '
        'like com.company.app.',
      );
    }
    final reader = PbxProjectReader(fileSystem, paths);
    final pbxPath = reader.findPbxproj(projectRoot);
    final project = pbxPath == null ? null : reader.parseFile(pbxPath);
    final app = project?.applicationTarget;
    if (pbxPath == null || project == null || app == null) {
      throw XcrossError('No iOS app target found under ios/.');
    }
    // Every ID the app target has, in any configuration.
    final list = project.object(app.string('buildConfigurationList'));
    final old = <String>{
      for (final id
          in list?.stringList('buildConfigurations') ?? const <String>[])
        if (project
                .object(id)
                ?.map('buildSettings')['PRODUCT_BUNDLE_IDENTIFIER']
            case final String value when value.trim().isNotEmpty)
          value.trim(),
    };
    final previous = project.buildSettings(
      app,
      preferredConfiguration: 'Release',
    )['PRODUCT_BUNDLE_IDENTIFIER'];

    final files = <FileChange>[];
    final pbxFile = fileSystem.file(pbxPath);
    final pbxText = pbxFile.readAsStringSync();
    var count = 0;
    final pbxNext = pbxText.replaceAllMapped(_bundleSetting, (m) {
      final value = m.group(3)!;
      String? next;
      if (old.contains(value)) {
        next = bundleId;
      } else {
        for (final o in old) {
          if (value.startsWith('$o.')) {
            next = '$bundleId${value.substring(o.length)}';
            break;
          }
        }
      }
      if (next == null || next == value) return m.group(0)!;
      count++;
      return '${m.group(1)}${m.group(2)}$next${m.group(4)}${m.group(5)}';
    });
    if (count > 0) {
      files.add(FileChange(_rel(pbxPath), count));
      if (!dryRun) pbxFile.writeAsStringSync(pbxNext);
    }

    final infoPath = paths.join(projectRoot, 'ios', 'Runner', 'Info.plist');
    final info = fileSystem.file(infoPath);
    if (info.existsSync()) {
      final text = info.readAsStringSync();
      var infoCount = 0;
      final next = text.replaceAllMapped(
        RegExp(r'(<key>CFBundleIdentifier</key>\s*<string>)([^<]*)(</string>)'),
        (m) {
          final value = m.group(2)!.trim();
          if (value.contains(r'$(') || !old.contains(value)) return m.group(0)!;
          infoCount++;
          return '${m.group(1)}\$(PRODUCT_BUNDLE_IDENTIFIER)${m.group(3)}';
        },
      );
      if (infoCount > 0) {
        files.add(FileChange(_rel(infoPath), infoCount));
        if (!dryRun) info.writeAsStringSync(next);
      }
    }
    return (previous: previous is String ? previous : null, files: files);
  }

  static const _plistToOptions = {
    'API_KEY': 'apiKey',
    'GOOGLE_APP_ID': 'appId',
    'GCM_SENDER_ID': 'messagingSenderId',
    'PROJECT_ID': 'projectId',
    'STORAGE_BUCKET': 'storageBucket',
    'BUNDLE_ID': 'iosBundleId',
  };

  /// Puts the GoogleService-Info.plist at [source] in `ios/Runner`, and
  /// points `lib/firebase_options.dart` and `firebase.json` at the same
  /// Firebase iOS app. Refuses a plist for another bundle ID or another
  /// Firebase project (that needs `flutterfire configure`).
  ({String bundleId, String appId, List<FileChange> files, List<String> notes})
  importFirebasePlist(String source, {bool dryRun = false}) {
    final file = fileSystem.file(source);
    if (!file.existsSync()) throw XcrossError('No file at $source.');
    final text = file.readAsStringSync();
    final Map<String, Object> plist;
    try {
      plist = FlutterAppEntitlements.parseDictionary(text);
    } on FormatException {
      throw XcrossError('$source is not a property list.');
    }
    String need(String key) => switch (plist[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => throw XcrossError(
        '$source has no $key: it is not a GoogleService-Info.plist.',
      ),
    };
    final bundleId = need('BUNDLE_ID');
    final appId = need('GOOGLE_APP_ID');
    final projectId = need('PROJECT_ID');

    final current = ProjectInspector(
      fileSystem: fileSystem,
      paths: paths,
      projectRoot: projectRoot,
    ).inspect();
    if (current.bundleId != null && current.bundleId != bundleId) {
      throw XcrossError(
        'This plist is for $bundleId, but the app is ${current.bundleId}. '
        'In the Firebase console, download the plist of the iOS app '
        '${current.bundleId} (add that iOS app if there is none).',
      );
    }
    final currentProject = current.items
        .where((i) => i.id == 'firebase_project')
        .firstOrNull
        ?.value;
    if (currentProject != null && currentProject != projectId) {
      throw XcrossError(
        'This plist is from the Firebase project $projectId; the app uses '
        '$currentProject. Moving to another project changes Android too: run '
        '`flutterfire configure` for that.',
      );
    }

    final files = <FileChange>[];
    final notes = <String>[];
    final target = paths.join(
      projectRoot,
      'ios',
      'Runner',
      'GoogleService-Info.plist',
    );
    final targetFile = fileSystem.file(target);
    final old = targetFile.existsSync() ? targetFile.readAsStringSync() : null;
    if (old != text) {
      files.add(FileChange(_rel(target), 1));
      if (!dryRun) {
        targetFile.parent.createSync(recursive: true);
        targetFile.writeAsStringSync(text);
      }
    }
    final pbxPath = PbxProjectReader(
      fileSystem,
      paths,
    ).findPbxproj(projectRoot);
    if (pbxPath != null &&
        !fileSystem
            .file(pbxPath)
            .readAsStringSync()
            .contains('GoogleService-Info.plist')) {
      notes.add(
        'The Xcode project does not list GoogleService-Info.plist. Xcode on a '
        'Mac would leave it out of the app: add it to the Runner target there '
        'once.',
      );
    }

    // firebase_options.dart: the ios block's values.
    final optionsPath = paths.join(projectRoot, 'lib', 'firebase_options.dart');
    final options = fileSystem.file(optionsPath);
    String? oldAppId;
    if (options.existsSync()) {
      final source = options.readAsStringSync();
      final block = firebaseIosBlock(source);
      if (block == null) {
        notes.add(
          'lib/firebase_options.dart has no ios options; run '
          '`flutterfire configure` to add iOS there.',
        );
      } else {
        oldAppId = firebaseIosOptions(source)?['appId'];
        var count = 0;
        var body = source.substring(block.start, block.end);
        for (final MapEntry(:key, value: field) in _plistToOptions.entries) {
          final value = plist[key];
          if (value is! String) continue;
          body = body.replaceAllMapped(
            RegExp('($field\\s*:\\s*)([\'"])([^\'"]*)([\'"])'),
            (m) {
              if (m.group(3) == value) return m.group(0)!;
              count++;
              return '${m.group(1)}${m.group(2)}$value${m.group(4)}';
            },
          );
        }
        if (count > 0) {
          files.add(FileChange(_rel(optionsPath), count));
          if (!dryRun) {
            options.writeAsStringSync(
              source.replaceRange(block.start, block.end, body),
            );
          }
        }
      }
    }

    // firebase.json: the old iOS app ID wherever it is named.
    final jsonPath = paths.join(projectRoot, 'firebase.json');
    final json = fileSystem.file(jsonPath);
    if (json.existsSync()) {
      final source = json.readAsStringSync();
      final oldIds = {...firebaseJsonIosAppIds(source), ?oldAppId}
        ..remove(appId);
      var count = 0;
      var next = source;
      for (final id in oldIds) {
        next = next.replaceAllMapped(RegExp('"${RegExp.escape(id)}"'), (_) {
          count++;
          return '"$appId"';
        });
      }
      if (count > 0) {
        files.add(FileChange(_rel(jsonPath), count));
        if (!dryRun) json.writeAsStringSync(next);
      }
    }
    return (bundleId: bundleId, appId: appId, files: files, notes: notes);
  }
}
