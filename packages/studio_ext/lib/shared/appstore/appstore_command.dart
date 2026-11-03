// studio: 021 — `xcross appstore …`: the App Store submission steps of
// US-IOS-001 AC-16 from Windows or Linux (specs/021-app-store-submission).
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:apple_developer_kit/shared/errors/errors.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/appstore/app_store_metadata.dart';
import 'package:studio_ext/src/shared/appstore/app_store_project.dart';
import 'package:studio_ext/src/shared/appstore/app_store_review.dart';
import 'package:studio_ext/src/shared/appstore/app_store_screenshots.dart';
import 'package:studio_ext/src/shared/appstore/app_store_versions.dart';
import 'package:studio_ext/src/shared/appstore/asc_session.dart';

/// What every `appstore` subcommand needs.
final class AppStoreCommandContext {
  AppStoreCommandContext({
    required this.openApi,
    required this.fileSystem,
    required this.paths,
    required this.currentDirectory,
    required this.write,
  });

  final OpenAscApi openApi;
  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String Function() currentDirectory;
  final WriteOut write;

  /// The Flutter project in the current folder.
  AppStoreProject project() => AppStoreProject.read(
    fileSystem: fileSystem,
    paths: paths,
    root: currentDirectory(),
  );

  /// [path] resolved against the current folder.
  String resolve(String path) =>
      paths.isAbsolute(path) ? path : paths.join(currentDirectory(), path);

  /// Runs [body] with an API session; Apple's refusals become messages that
  /// name the role needed.
  Future<T> withApi<T>(
    String action,
    Future<T> Function(AscApi api) body,
  ) async {
    final AscApi api;
    try {
      api = await openApi();
    } on AppleError catch (error) {
      throw CliError(
        '${error.message}\nhint: sign in with an App Store Connect API key: '
        '`xcross auth --issuer-id <id> --key-id <id> --private-key '
        '<AuthKey.p8>`.',
      );
    }
    try {
      return await body(api);
    } on AppleApiError catch (error) {
      throw ascFailure(error, action: action);
    } finally {
      api.close();
    }
  }
}

/// `xcross appstore`.
final class AppStoreCommand extends Command<void> {
  AppStoreCommand({
    required OpenAscApi openApi,
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String Function() currentDirectory,
    required WriteOut write,
  }) {
    final context = AppStoreCommandContext(
      openApi: openApi,
      fileSystem: fileSystem,
      paths: paths,
      currentDirectory: currentDirectory,
      write: write,
    );
    addSubcommand(AppStoreAppCommand(context));
    addSubcommand(AppStoreVersionCommand(context));
    addSubcommand(AppStoreMetadataCommand(context));
    addSubcommand(AppStoreScreenshotsCommand(context));
    addSubcommand(AppStoreAttachCommand(context));
    addSubcommand(AppStoreSubmitCommand(context));
    addSubcommand(AppStoreStatusCommand(context));
  }

  @override
  String get name => 'appstore';

  @override
  String get description =>
      'Prepare and submit the App Store version with the App Store Connect '
      'API: app record, version, product page, screenshots, build, review. '
      'App Privacy, pricing and agreements are not in the API; set them in '
      'App Store Connect.';
}

/// A subcommand that acts on one app (`--app-id`, else the project's bundle
/// ID).
abstract class AppStoreSubcommand extends Command<void> {
  AppStoreSubcommand(this.context) {
    argParser.addOption(
      'app-id',
      valueHelp: 'id',
      help:
          'Apple ID of the app (default: the app whose bundle ID is the '
          "project's).",
    );
  }

  final AppStoreCommandContext context;

  String? get appIdOption => argResults!.option('app-id');

  /// The app record.
  Future<AscResource> app(AscApi api) => resolveAscApp(
    api,
    appId: appIdOption,
    bundleId: context.project().bundleId,
  );

  /// The `--version` option, checked.
  String? versionOption() {
    final value = argResults!.option('version')?.trim();
    if (value == null || value.isEmpty) return null;
    if (!_versionPattern.hasMatch(value)) {
      usageException('A version is like 1.2.3, not "$value".');
    }
    return value;
  }

  void addVersionOption() => argParser.addOption(
    'version',
    valueHelp: 'x.y.z',
    help: 'The App Store version (default: the one that can be edited).',
  );

  static final _versionPattern = RegExp(r'^\d+(\.\d+){0,2}$');
}

/// `xcross appstore app [--json]` (AC-021-1).
final class AppStoreAppCommand extends AppStoreSubcommand {
  AppStoreAppCommand(super.context) {
    argParser.addFlag('json', negatable: false, help: 'Print one JSON object.');
  }

  @override
  String get name => 'app';

  @override
  String get description =>
      "Find the project's app record in App Store Connect, or say how to "
      'create it.';

  @override
  Future<void> run() async {
    final json = argResults!.flag('json');
    final project = context.project();
    final appId = appIdOption;
    if (appId == null && project.bundleId == null) {
      usageException('Pass --app-id, or run in the Flutter project folder.');
    }
    final found = await context.withApi('read the app record', (api) async {
      if (appId != null) return AscApi.data(await api.get('/v1/apps/$appId'));
      final match = await AscApps.findByBundleId(api, project.bundleId!);
      return match;
    });
    if (found != null) {
      if (json) {
        context.write(
          '${jsonEncode({'v': 1, 'type': 'appstore_app', 'found': true, 'id': found.id, 'name': found.string('name'), 'bundleId': found.string('bundleId'), 'sku': found.string('sku'), 'primaryLocale': found.string('primaryLocale')})}\n',
        );
      } else {
        context.write(
          'App Store Connect app  ${found.string('name') ?? '?'}\n'
          '  Apple ID        ${found.id}\n'
          '  Bundle ID       ${found.string('bundleId') ?? '?'}\n'
          '  SKU             ${found.string('sku') ?? '?'}\n'
          '  Primary locale  ${found.string('primaryLocale') ?? '?'}\n',
        );
      }
      return;
    }
    final bundleId = project.bundleId!;
    if (json) {
      context.write(
        '${jsonEncode({'v': 1, 'type': 'appstore_app', 'found': false, 'bundleId': bundleId, 'name': project.name, 'sku': project.sku, 'newAppUrl': AppStoreProject.newAppUrl})}\n',
      );
    } else {
      context.write(
        'App Store Connect has no app with the bundle ID $bundleId.\n'
        "Apple's API cannot create apps: open ${AppStoreProject.newAppUrl}, "
        'press +, New App, and enter:\n'
        '  Platform     iOS\n'
        '  Name         ${project.name ?? '(the name shown on the App Store)'}\n'
        '  Bundle ID    $bundleId\n'
        '  SKU          ${project.sku ?? '(any unique text)'}\n',
      );
    }
    throw CliError('No App Store Connect app for $bundleId yet.');
  }
}

/// `xcross appstore version [<x.y.z>] [--create] [--json]` (AC-021-2).
final class AppStoreVersionCommand extends AppStoreSubcommand {
  AppStoreVersionCommand(super.context) {
    argParser
      ..addFlag(
        'create',
        negatable: false,
        help: 'Create the version when the app has no editable one.',
      )
      ..addFlag('json', negatable: false, help: 'Print one JSON object.');
  }

  @override
  String get name => 'version';

  @override
  String get invocation =>
      'xcross appstore version [<x.y.z>] [--create] [--json]';

  @override
  String get description =>
      'Show the App Store version that can be edited, or create it.';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length > 1) usageException('Pass at most one version.');
    final wanted = rest.isEmpty ? null : rest.single.trim();
    if (wanted != null && !RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(wanted)) {
      usageException('A version is like 1.2.3, not "$wanted".');
    }
    final create = argResults!.flag('create');
    await context.withApi('read or create the App Store version', (api) async {
      final app = await this.app(api);
      var version = await AppStoreVersions.find(api, app.id, version: wanted);
      var created = false;
      if (version == null || (wanted == null && create)) {
        if (version == null && !create) {
          throw CliError(
            wanted == null
                ? 'The app has no App Store version that can be edited; '
                      'create one with `xcross appstore version <x.y.z> '
                      '--create`.'
                : 'The app has no App Store version $wanted; add --create.',
          );
        }
        if (version == null) {
          if (wanted == null) {
            usageException('Pass the version to create, such as 1.0.0.');
          }
          version = await AppStoreVersions.create(api, app.id, wanted);
          created = true;
        }
      }
      final state = AppStoreVersions.stateOf(version);
      if (argResults!.flag('json')) {
        context.write(
          '${jsonEncode({'v': 1, 'type': 'appstore_version', 'id': version.id, 'version': version.string('versionString'), 'state': state, 'created': created})}\n',
        );
      } else {
        context.write(
          '${created ? 'Created' : 'Version'} ${version.string('versionString')} '
          '($state)\n',
        );
      }
    });
  }
}

/// `xcross appstore metadata pull|push` (AC-021-3, AC-021-4).
final class AppStoreMetadataCommand extends Command<void> {
  AppStoreMetadataCommand(AppStoreCommandContext context) {
    addSubcommand(AppStoreMetadataSyncCommand(context, push: false));
    addSubcommand(AppStoreMetadataSyncCommand(context, push: true));
  }

  @override
  String get name => 'metadata';

  @override
  String get description =>
      'Sync the product page with a fastlane-style folder '
      '(appstore/metadata/<locale>/description.txt, …).';
}

/// `metadata pull` or `metadata push`.
final class AppStoreMetadataSyncCommand extends AppStoreSubcommand {
  AppStoreMetadataSyncCommand(super.context, {required this.push}) {
    argParser.addOption(
      'dir',
      defaultsTo: 'appstore/metadata',
      help: 'The metadata folder.',
    );
    addVersionOption();
  }

  final bool push;

  @override
  String get name => push ? 'push' : 'pull';

  @override
  String get description => push
      ? 'Send the folder to App Store Connect (only changed fields).'
      : "Write App Store Connect's product page into the folder.";

  @override
  Future<void> run() async {
    final dir = context.resolve(argResults!.option('dir')!);
    final version = versionOption();
    final folder = push
        ? MetadataFolder.read(context.fileSystem, context.paths, dir)
        : null;
    if (folder != null &&
        folder.locales.isEmpty &&
        folder.copyright == null &&
        folder.primaryCategory == null &&
        folder.ageRating == null) {
      throw CliError('Nothing to send: $dir has no metadata files.');
    }
    await context.withApi(
      push ? 'update the product page' : 'read the product page',
      (api) async {
        final app = await this.app(api);
        final target = await AppStoreVersions.require(
          api,
          app.id,
          version: version,
        );
        final sync = MetadataSync(api, appId: app.id, version: target);
        if (folder != null) {
          final changes = await sync.push(folder);
          context.write(
            changes.isEmpty
                ? 'Nothing to change.\n'
                : '${changes.map((c) => '$c\n').join()}'
                      '${changes.length} change${changes.length == 1 ? '' : 's'} '
                      'sent for ${target.string('versionString')}.\n',
          );
          return;
        }
        final pulled = await sync.pull();
        final written = await pulled.write(
          context.fileSystem,
          context.paths,
          dir,
        );
        for (final file in written) {
          context.write('Wrote $file\n');
        }
        context.write(
          '${written.length} files in ${context.paths.relative(dir, from: context.currentDirectory())}\n',
        );
      },
    );
  }
}

/// `xcross appstore screenshots push` (AC-021-5, AC-021-6).
final class AppStoreScreenshotsCommand extends Command<void> {
  AppStoreScreenshotsCommand(AppStoreCommandContext context) {
    addSubcommand(AppStoreScreenshotsPushCommand(context));
  }

  @override
  String get name => 'screenshots';

  @override
  String get description =>
      'Upload screenshots from appstore/screenshots/<locale>/<display type>/.';
}

/// `screenshots push [--dir] [--replace] [--version]`.
final class AppStoreScreenshotsPushCommand extends AppStoreSubcommand {
  AppStoreScreenshotsPushCommand(super.context) {
    argParser
      ..addOption(
        'dir',
        defaultsTo: 'appstore/screenshots',
        help: 'The screenshots folder.',
      )
      ..addFlag(
        'replace',
        negatable: false,
        help: 'Delete the screenshots already in each set first.',
      );
    addVersionOption();
  }

  @override
  String get name => 'push';

  @override
  String get description =>
      'Check every image size, then upload the screenshots (display types '
      'such as APP_IPHONE_67, APP_IPHONE_65, APP_IPAD_PRO_3GEN_129).';

  @override
  Future<void> run() async {
    final dir = context.resolve(argResults!.option('dir')!);
    final version = versionOption();
    // Sizes are checked before signing in, so a bad file costs nothing.
    final files = ScreenshotFolder.plan(context.fileSystem, context.paths, dir);
    if (files.isEmpty) throw CliError('No screenshots in $dir.');
    await context.withApi('upload the screenshots', (api) async {
      final app = await this.app(api);
      final target = await AppStoreVersions.require(
        api,
        app.id,
        version: version,
      );
      final count = await ScreenshotUpload(
        api,
        paths: context.paths,
        versionId: target.id,
        write: (line) => context.write('$line\n'),
      ).push(files, replace: argResults!.flag('replace'));
      context.write(
        '$count screenshot${count == 1 ? '' : 's'} uploaded to '
        '${target.string('versionString')}.\n',
      );
    });
  }
}

/// `xcross appstore attach --build <number> [--version]` (AC-021-7).
final class AppStoreAttachCommand extends AppStoreSubcommand {
  AppStoreAttachCommand(super.context) {
    argParser.addOption(
      'build',
      valueHelp: 'number',
      mandatory: true,
      help: 'The build number (CFBundleVersion) to attach.',
    );
    addVersionOption();
  }

  @override
  String get name => 'attach';

  @override
  String get description =>
      'Attach a processed build to the App Store version.';

  @override
  Future<void> run() async {
    final number = argResults!.option('build')!.trim();
    final version = versionOption();
    await context.withApi('attach the build', (api) async {
      final app = await this.app(api);
      final target = await AppStoreVersions.require(
        api,
        app.id,
        version: version,
      );
      await AppStoreReview(api, appId: app.id).attach(target, number);
      context.write(
        'Attached build $number to ${target.string('versionString')}.\n',
      );
    });
  }
}

/// `xcross appstore submit [--version] [--dry-run]` (AC-021-8, AC-021-10).
final class AppStoreSubmitCommand extends AppStoreSubcommand {
  AppStoreSubmitCommand(super.context) {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'List what blocks the submission and change nothing.',
    );
    addVersionOption();
  }

  @override
  String get name => 'submit';

  @override
  String get description => 'Submit the App Store version for review.';

  @override
  Future<void> run() async {
    final dryRun = argResults!.flag('dry-run');
    final version = versionOption();
    await context.withApi('submit for review', (api) async {
      final app = await this.app(api);
      final target = await AppStoreVersions.require(
        api,
        app.id,
        version: version,
      );
      final review = AppStoreReview(api, appId: app.id);
      final blockers = await review.blockers(target);
      final name = target.string('versionString');
      for (final blocker in blockers) {
        context.write('blocker: $blocker\n');
      }
      context.write('note: $apiGapPages\n');
      if (blockers.isNotEmpty) {
        if (dryRun) {
          context.write(
            '${blockers.length} blocker${blockers.length == 1 ? '' : 's'}; '
            'nothing was submitted.\n',
          );
          return;
        }
        throw CliError(
          '$name was not submitted: fix the blockers above first.',
        );
      }
      if (dryRun) {
        context.write('$name is ready to submit (dry run, nothing sent).\n');
        return;
      }
      final submission = await review.submit(target);
      context.write(
        'Submitted $name for review (${submission.string('state') ?? 'WAITING_FOR_REVIEW'}).\n',
      );
    });
  }
}

/// `xcross appstore status [--json]` (AC-021-9).
final class AppStoreStatusCommand extends AppStoreSubcommand {
  AppStoreStatusCommand(super.context) {
    argParser.addFlag('json', negatable: false, help: 'Print one JSON object.');
  }

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show the App Store version state, its build and the review '
      'submissions.';

  @override
  Future<void> run() async {
    await context.withApi('read the review status', (api) async {
      final app = await this.app(api);
      final status = await AppStoreReview(api, appId: app.id).status();
      if (argResults!.flag('json')) {
        context.write('${jsonEncode(status)}\n');
        return;
      }
      final submissions = status['submissions']! as List<Object?>;
      context.write(
        'Version      ${status['version'] ?? '(none)'} (${status['state'] ?? '-'})\n'
        'Build        ${status['build'] ?? '(none attached)'}\n'
        'Submissions  ${submissions.isEmpty ? '(none)' : ''}\n',
      );
      for (final submission in submissions) {
        if (submission is! Map) continue;
        context.write(
          '  ${submission['state']}'
          '${submission['submittedDate'] == null ? '' : '  ${submission['submittedDate']}'}\n',
        );
      }
    });
  }
}
