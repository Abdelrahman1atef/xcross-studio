// studio: 020 — `xcross testflight …`: TestFlight from the CLI
// (specs/020-testflight).
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/appstore/asc_session.dart';
import 'package:studio_ext/src/shared/appstore/testflight_api.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';

/// What every `testflight` subcommand needs.
final class TestFlightContext {
  TestFlightContext({
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

  /// The project's bundle ID (the app target's), when run in a project.
  String? projectBundleId() => ReleaseProject(
    fileSystem: fileSystem,
    paths: paths,
    root: currentDirectory(),
  ).bundleId;

  /// Opens a session, resolves the app and runs [body]; Apple refusals become
  /// errors with the role hint.
  Future<T> run<T>(
    ArgResults args,
    String action,
    Future<T> Function(TestFlightApi api, AscResource app) body,
  ) async {
    final api = await openApi();
    try {
      final app = await resolveAscApp(
        api,
        appId: args['app-id'] as String?,
        bundleId: projectBundleId(),
      );
      return await body(TestFlightApi(api), app);
    } on AppleApiError catch (error) {
      throw ascFailure(error, action: action);
    } finally {
      api.close();
    }
  }

  void line(String text) => write('$text\n');

  void json(Map<String, Object?> event) => write('${jsonEncode(event)}\n');
}

/// `xcross testflight`.
final class TestFlightCommand extends Command<void> {
  TestFlightCommand(TestFlightContext context) {
    addSubcommand(TestFlightStatusCommand(context));
    addSubcommand(TestFlightGroupsCommand(context));
    addSubcommand(TestFlightGroupCommand(context));
    addSubcommand(TestFlightAddCommand(context));
    addSubcommand(TestFlightWhatToTestCommand(context));
    addSubcommand(TestFlightTestersCommand(context));
    addSubcommand(TestFlightComplianceCommand(context));
    addSubcommand(TestFlightAppInfoCommand(context));
    addSubcommand(TestFlightReviewInfoCommand(context));
    addSubcommand(TestFlightSubmitCommand(context));
    addSubcommand(TestFlightPublicLinkCommand(context));
  }

  @override
  String get name => 'testflight';

  @override
  String get description =>
      'Check builds and distribute them with TestFlight (App Store Connect '
      'team key with the Admin or App Manager role).';
}

/// A `testflight` subcommand: `--app-id`, and `--build` when [buildScoped].
abstract base class TestFlightSubcommand extends Command<void> {
  TestFlightSubcommand(this.context, {bool buildScoped = false}) {
    argParser.addOption(
      'app-id',
      valueHelp: 'id',
      help:
          'Apple ID of the app (default: the App Store Connect app with the '
          "project's bundle ID).",
    );
    if (buildScoped) {
      argParser.addOption(
        'build',
        valueHelp: 'number',
        help: 'Build number (default: the newest upload).',
      );
    }
  }

  final TestFlightContext context;

  ArgResults get args => argResults!;

  String? option(String name) {
    final value = args[name] as String?;
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  int? intOption(String name) {
    final raw = option(name);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) usageException('--$name takes a number.');
    return value;
  }

  String requiredOption(String name) =>
      option(name) ?? usageException('Pass --$name.');
}

/// `testflight status`.
final class TestFlightStatusCommand extends TestFlightSubcommand {
  TestFlightStatusCommand(super.context, {super.buildScoped = true}) {
    argParser
      ..addOption(
        'version',
        valueHelp: 'x.y.z',
        help: 'Only builds of this marketing version.',
      )
      ..addOption('limit', defaultsTo: '5', help: 'How many builds to show.')
      ..addFlag('json', negatable: false, help: 'Print one JSON object.');
  }

  @override
  String get name => 'status';

  @override
  String get description =>
      'Processing and TestFlight states of the newest builds (or one build).';

  @override
  Future<void> run() => context.run(args, 'read the builds', (api, app) async {
    final builds = await api.builds(
      app.id,
      buildNumber: option('build'),
      version: option('version'),
      limit: intOption('limit') ?? 5,
    );
    if (args.flag('json')) {
      context.json({
        'v': 1,
        'type': 'testflight_status',
        'appId': app.id,
        'bundleId': app.string('bundleId'),
        'builds': [for (final build in builds) build.toJson()],
      });
      return;
    }
    if (builds.isEmpty) {
      context.line(
        'No builds in App Store Connect yet (upload one with `xcross '
        'publish`).',
      );
      return;
    }
    for (final build in builds) {
      final encryption = switch (build.usesNonExemptEncryption) {
        true => 'uses encryption',
        false => 'no non-exempt encryption',
        null => 'export compliance not answered',
      };
      context
        ..line(
          '${build.version ?? '?'} (${build.buildNumber})  '
          '${build.processingState ?? '?'}'
          '${build.expired ? '  EXPIRED' : ''}  uploaded '
          '${build.uploadedDate ?? '?'}',
        )
        ..line(
          '  internal: ${build.internalBuildState ?? '?'}  external: '
          '${build.externalBuildState ?? '?'}  $encryption',
        );
      if (build.groups.isNotEmpty) {
        context.line('  groups: ${build.groups.join(', ')}');
      }
      context.line(
        build.iconTemplateUrl == null
            ? '  icon: none (App Store Connect found no app icon in this '
                  'build)'
            : '  icon: ${build.iconWidth ?? '?'}x${build.iconHeight ?? '?'}  '
                  '${build.iconUrl}',
      );
    }
  });
}

/// `testflight groups`.
final class TestFlightGroupsCommand extends TestFlightSubcommand {
  TestFlightGroupsCommand(super.context) {
    argParser.addFlag('json', negatable: false, help: 'Print one JSON object.');
  }

  @override
  String get name => 'groups';

  @override
  String get description => "The app's TestFlight groups.";

  @override
  Future<void> run() => context.run(args, 'read the beta groups', (
    api,
    app,
  ) async {
    final groups = await api.groups(app.id);
    if (args.flag('json')) {
      context.json({
        'v': 1,
        'type': 'testflight_groups',
        'groups': [for (final group in groups) group.toJson()],
      });
      return;
    }
    if (groups.isEmpty) context.line('No beta groups yet.');
    for (final group in groups) {
      context.line(
        '${group.name}  ${group.internal ? 'internal' : 'external'}'
        '${group.publicLinkEnabled && group.publicLink != null ? '  ${group.publicLink}' : ''}',
      );
    }
  });
}

/// `testflight group create`.
final class TestFlightGroupCommand extends Command<void> {
  TestFlightGroupCommand(TestFlightContext context) {
    addSubcommand(TestFlightGroupCreateCommand(context));
  }

  @override
  String get name => 'group';

  @override
  String get description => 'Manage one TestFlight group.';
}

/// `testflight group create <name>`.
final class TestFlightGroupCreateCommand extends TestFlightSubcommand {
  TestFlightGroupCreateCommand(super.context) {
    argParser
      ..addFlag(
        'external',
        negatable: false,
        help: 'A group for external testers (beta review needed).',
      )
      ..addFlag(
        'public-link',
        negatable: false,
        help: 'Turn on the public link (external groups).',
      )
      ..addOption(
        'public-link-limit',
        valueHelp: 'n',
        help: 'Maximum testers through the public link.',
      );
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a TestFlight group.';

  @override
  String get invocation => 'xcross testflight group create <name>';

  @override
  Future<void> run() async {
    final name = args.rest.join(' ').trim();
    if (name.isEmpty) usageException('Pass the group name.');
    final external = args.flag('external');
    if (!external &&
        (args.flag('public-link') || option('public-link-limit') != null)) {
      usageException('A public link needs --external.');
    }
    await context.run(args, 'create the beta group', (api, app) async {
      final group = await api.createGroup(
        app.id,
        name: name,
        external: external,
        publicLink: args.flag('public-link'),
        publicLinkLimit: intOption('public-link-limit'),
      );
      context.line(
        'Created the ${group.internal ? 'internal' : 'external'} group '
        '"${group.name}"'
        '${group.publicLink == null ? '' : ': ${group.publicLink}'}',
      );
    });
  }
}

/// `testflight add --group <name>`.
final class TestFlightAddCommand extends TestFlightSubcommand {
  TestFlightAddCommand(super.context, {super.buildScoped = true}) {
    argParser.addOption('group', valueHelp: 'name', help: 'The beta group.');
  }

  @override
  String get name => 'add';

  @override
  String get description => 'Add a build to a TestFlight group.';

  @override
  Future<void> run() async {
    final groupName = requiredOption('group');
    await context.run(args, 'add the build to the group', (api, app) async {
      final build = await api.build(app.id, buildNumber: option('build'));
      final group = await api.group(app.id, groupName);
      await api.addBuildToGroup(group.id, build.id);
      context.line(
        'Added ${build.version ?? ''} (${build.buildNumber}) to "${group.name}".',
      );
    });
  }
}

/// `testflight what-to-test "<text>"`.
final class TestFlightWhatToTestCommand extends TestFlightSubcommand {
  TestFlightWhatToTestCommand(super.context, {super.buildScoped = true}) {
    argParser.addOption('locale', defaultsTo: 'en-US', help: 'Language.');
  }

  @override
  String get name => 'what-to-test';

  @override
  String get description => 'Set the "What to Test" notes of a build.';

  @override
  String get invocation => 'xcross testflight what-to-test "<text>"';

  @override
  Future<void> run() async {
    final text = args.rest.join(' ').trim();
    if (text.isEmpty) usageException('Pass the notes for testers.');
    await context.run(args, 'set What to Test', (api, app) async {
      final build = await api.build(app.id, buildNumber: option('build'));
      final updated = await api.setWhatToTest(
        build.id,
        text: text,
        locale: option('locale') ?? 'en-US',
      );
      context.line(
        '${updated ? 'Updated' : 'Set'} What to Test for '
        '${build.version ?? ''} (${build.buildNumber}).',
      );
    });
  }
}

/// `testflight testers add|list`.
final class TestFlightTestersCommand extends Command<void> {
  TestFlightTestersCommand(TestFlightContext context) {
    addSubcommand(TestFlightTestersAddCommand(context));
    addSubcommand(TestFlightTestersListCommand(context));
  }

  @override
  String get name => 'testers';

  @override
  String get description => 'Invite and list the testers of a group.';
}

/// `testflight testers add <email>… --group <name>`.
final class TestFlightTestersAddCommand extends TestFlightSubcommand {
  TestFlightTestersAddCommand(super.context) {
    argParser
      ..addOption('group', valueHelp: 'name', help: 'The beta group.')
      ..addOption('first-name', help: 'First name (one tester).')
      ..addOption('last-name', help: 'Last name (one tester).');
  }

  @override
  String get name => 'add';

  @override
  String get description => 'Invite testers into a group.';

  @override
  String get invocation =>
      'xcross testflight testers add <email>... --group <name>';

  @override
  Future<void> run() async {
    final emails = [
      for (final value in args.rest)
        if (value.trim().isNotEmpty) value.trim(),
    ];
    if (emails.isEmpty) usageException('Pass at least one email address.');
    final bad = emails.where((email) => !email.contains('@')).toList();
    if (bad.isNotEmpty) usageException('Not an email address: ${bad.first}');
    final groupName = requiredOption('group');
    await context.run(args, 'invite the testers', (api, app) async {
      final group = await api.group(app.id, groupName);
      for (final email in emails) {
        final added = await api.addTester(
          group.id,
          email: email,
          firstName: emails.length == 1 ? option('first-name') : null,
          lastName: emails.length == 1 ? option('last-name') : null,
        );
        context.line(
          added
              ? 'Invited $email to "${group.name}".'
              : 'Added the existing tester $email to "${group.name}".',
        );
      }
    });
  }
}

/// `testflight testers list --group <name>`.
final class TestFlightTestersListCommand extends TestFlightSubcommand {
  TestFlightTestersListCommand(super.context) {
    argParser
      ..addOption('group', valueHelp: 'name', help: 'The beta group.')
      ..addFlag('json', negatable: false, help: 'Print one JSON object.');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List the testers of a group.';

  @override
  Future<void> run() async {
    final groupName = requiredOption('group');
    await context.run(args, 'list the testers', (api, app) async {
      final group = await api.group(app.id, groupName);
      final testers = await api.testers(group.id);
      if (args.flag('json')) {
        context.json({
          'v': 1,
          'type': 'testflight_testers',
          'group': group.name,
          'testers': [for (final tester in testers) tester.toJson()],
        });
        return;
      }
      if (testers.isEmpty) context.line('No testers in "${group.name}".');
      for (final tester in testers) {
        final name = [tester.firstName, tester.lastName].whereType<String>();
        context.line(
          '${tester.email ?? tester.id}'
          '${name.isEmpty ? '' : '  ${name.join(' ')}'}'
          '${tester.state == null ? '' : '  ${tester.state}'}',
        );
      }
    });
  }
}

/// `testflight compliance --no-encryption|--uses-encryption`.
final class TestFlightComplianceCommand extends TestFlightSubcommand {
  TestFlightComplianceCommand(super.context, {super.buildScoped = true}) {
    argParser
      ..addFlag(
        'no-encryption',
        negatable: false,
        help: 'The app uses no non-exempt encryption (HTTPS only, …).',
      )
      ..addFlag(
        'uses-encryption',
        negatable: false,
        help: 'The app uses non-exempt encryption (documentation needed).',
      );
  }

  @override
  String get name => 'compliance';

  @override
  String get description => "Answer a build's export compliance question.";

  @override
  Future<void> run() async {
    final none = args.flag('no-encryption');
    final uses = args.flag('uses-encryption');
    if (none == uses) {
      usageException(
        'Pass exactly one of --no-encryption and --uses-encryption.',
      );
    }
    await context.run(args, 'answer export compliance', (api, app) async {
      final build = await api.build(app.id, buildNumber: option('build'));
      await api.setUsesEncryption(build.id, uses: uses);
      context.line(
        'Export compliance for ${build.version ?? ''} (${build.buildNumber}): '
        '${uses ? 'uses non-exempt encryption' : 'no non-exempt encryption'}.',
      );
    });
  }
}

/// `testflight app-info`.
final class TestFlightAppInfoCommand extends TestFlightSubcommand {
  TestFlightAppInfoCommand(super.context) {
    argParser
      ..addOption('description', help: 'Beta app description.')
      ..addOption('feedback-email', help: 'Where testers send feedback.')
      ..addOption('marketing-url', help: 'Marketing URL.')
      ..addOption('privacy-url', help: 'Privacy policy URL.')
      ..addOption('locale', defaultsTo: 'en-US', help: 'Language.');
  }

  @override
  String get name => 'app-info';

  @override
  String get description =>
      'Set the beta app information external testers see.';

  @override
  Future<void> run() async {
    final attributes = {
      'description': ?option('description'),
      'feedbackEmail': ?option('feedback-email'),
      'marketingUrl': ?option('marketing-url'),
      'privacyPolicyUrl': ?option('privacy-url'),
    };
    if (attributes.isEmpty) {
      usageException('Pass at least one of the information options.');
    }
    await context.run(args, 'set the beta app information', (api, app) async {
      final locale = option('locale') ?? 'en-US';
      final updated = await api.setBetaAppInfo(
        app.id,
        locale: locale,
        attributes: attributes,
      );
      context.line(
        '${updated ? 'Updated' : 'Set'} the beta app information ($locale): '
        '${attributes.keys.join(', ')}.',
      );
    });
  }
}

/// `testflight review-info`.
final class TestFlightReviewInfoCommand extends TestFlightSubcommand {
  TestFlightReviewInfoCommand(super.context) {
    argParser
      ..addOption('contact-first-name')
      ..addOption('contact-last-name')
      ..addOption('contact-email')
      ..addOption('contact-phone')
      ..addOption('demo-user', help: 'Sign-in the reviewer can use.')
      ..addOption('demo-password', help: 'Its password (never printed).')
      ..addOption('notes', help: 'Notes for the reviewer.');
  }

  @override
  String get name => 'review-info';

  @override
  String get description =>
      'Set the contact and demo account for TestFlight App Review.';

  @override
  Future<void> run() async {
    final demoUser = option('demo-user');
    final Map<String, Object> attributes = {
      'contactFirstName': ?option('contact-first-name'),
      'contactLastName': ?option('contact-last-name'),
      'contactEmail': ?option('contact-email'),
      'contactPhone': ?option('contact-phone'),
      'demoAccountName': ?demoUser,
      'demoAccountPassword': ?option('demo-password'),
      'notes': ?option('notes'),
      if (demoUser != null) 'demoAccountRequired': true,
    };
    if (attributes.isEmpty) {
      usageException('Pass at least one of the review options.');
    }
    await context.run(args, 'set the beta review details', (api, app) async {
      await api.setBetaReviewDetails(app.id, attributes);
      context.line(
        'Set the beta review details: '
        '${attributes.keys.where((k) => k != 'demoAccountPassword').join(', ')}'
        '${attributes.containsKey('demoAccountPassword') ? ', demo password' : ''}.',
      );
    });
  }
}

/// `testflight submit`.
final class TestFlightSubmitCommand extends TestFlightSubcommand {
  TestFlightSubmitCommand(super.context, {super.buildScoped = true});

  @override
  String get name => 'submit';

  @override
  String get description => 'Submit a build to TestFlight App Review.';

  @override
  Future<void> run() =>
      context.run(args, 'submit the build for beta review', (api, app) async {
        final build = await api.build(app.id, buildNumber: option('build'));
        final state = await api.submitForReview(build.id);
        context.line(
          'Submitted ${build.version ?? ''} (${build.buildNumber}) to '
          'TestFlight App Review${state == null ? '' : ': $state'}.',
        );
      });
}

/// `testflight public-link --group <name>`.
final class TestFlightPublicLinkCommand extends TestFlightSubcommand {
  TestFlightPublicLinkCommand(super.context) {
    argParser
      ..addOption('group', valueHelp: 'name', help: 'An external group.')
      ..addFlag('enable', negatable: false, help: 'Turn the link on.')
      ..addFlag('disable', negatable: false, help: 'Turn the link off.')
      ..addOption('limit', valueHelp: 'n', help: 'Maximum testers.');
  }

  @override
  String get name => 'public-link';

  @override
  String get description => "Turn a group's public TestFlight link on or off.";

  @override
  Future<void> run() async {
    final groupName = requiredOption('group');
    if (args.flag('enable') && args.flag('disable')) {
      usageException('Pass --enable or --disable, not both.');
    }
    final enabled = !args.flag('disable');
    await context.run(args, 'change the public link', (api, app) async {
      final group = await api.group(app.id, groupName);
      if (group.internal) {
        throw UsageException(
          'Public links are for external groups; "${group.name}" is internal.',
          usage,
        );
      }
      final updated = await api.setPublicLink(
        group.id,
        enabled: enabled,
        limit: intOption('limit'),
      );
      context.line(
        enabled
            ? 'Public link of "${updated.name}": ${updated.publicLink ?? '(App Store Connect did not return it yet)'}'
            : 'Turned off the public link of "${updated.name}".',
      );
    });
  }
}
