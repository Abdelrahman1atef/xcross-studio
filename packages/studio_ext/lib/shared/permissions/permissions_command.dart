// studio: 027 — `xcross permissions` and `xcross capabilities`: see, add and
// remove the purpose strings in ios/Runner/Info.plist and the capabilities in
// the entitlements file, the way Xcode's Info and Signing & Capabilities tabs
// do (specs/027-permissions).
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/icons/icons_generate_command.dart' as icons;
import 'package:studio_ext/src/shared/permissions/capability_catalog.dart';
import 'package:studio_ext/src/shared/permissions/permission_catalog.dart';
import 'package:studio_ext/src/shared/permissions/permissions_report.dart';
import 'package:studio_ext/src/shared/permissions/plist_text.dart';
import 'package:studio_ext/src/shared/permissions/project_plists.dart';
import 'package:studio_ext/src/shared/release/release_checks.dart';
import 'package:studio_ext/src/shared/release/release_tables.dart';

/// What the permissions and capabilities commands need from the host.
final class PermissionsContext {
  PermissionsContext({
    required this.fileSystem,
    required this.paths,
    required this.currentDirectory,
    required this.write,
    this.now,
  });

  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String Function() currentDirectory;
  final void Function(String) write;
  final DateTime Function()? now;
}

/// Shared options and file access of the subcommands.
abstract base class PermissionsSubcommand extends Command<void> {
  PermissionsSubcommand(this.context) {
    argParser
      ..addFlag('json', negatable: false, help: 'Print one JSON object.')
      ..addOption(
        'project',
        valueHelp: 'dir',
        help: 'The Flutter project (default: the current folder).',
      );
  }

  final PermissionsContext context;

  bool get json => argResults!.flag('json');

  ProjectPlists open() {
    final root = icons.projectOption(
      this,
      context.fileSystem,
      context.currentDirectory(),
    );
    final plists = ProjectPlists(
      fileSystem: context.fileSystem,
      paths: context.paths,
      root: root,
      now: context.now,
    );
    if (!plists.hasIos) {
      throw CliError(
        '[permissions.no_ios] No ios/Runner/Info.plist in $root.\n'
        'hint: Run in a Flutter project folder, or pass --project <dir>.',
      );
    }
    return plists;
  }

  ReleaseProject releaseProject(ProjectPlists plists) => ReleaseProject(
    fileSystem: context.fileSystem,
    paths: context.paths,
    root: plists.root,
  );

  void emit(Map<String, Object?> event, String text) =>
      context.write(json ? '${jsonEncode(event)}\n' : text);

  /// Runs [edit], turning an unsafe plist into a coded error.
  T guarded<T>(T Function() edit) {
    try {
      return edit();
    } on PlistEditException catch (error) {
      throw CliError('$error');
    }
  }

  String relative(ProjectPlists plists, String? backup) => backup == null
      ? ''
      : context.paths.relative(backup, from: plists.root).replaceAll(r'\', '/');
}

/// `xcross permissions list|set|remove`.
final class PermissionsCommand extends Command<void> {
  PermissionsCommand(PermissionsContext context) {
    addSubcommand(PermissionsListCommand(context));
    addSubcommand(PermissionsSetCommand(context));
    addSubcommand(PermissionsRemoveCommand(context));
  }

  @override
  String get name => 'permissions';

  @override
  String get description =>
      'See, add and remove the iOS purpose strings (camera, location, …) in '
      'ios/Runner/Info.plist.';
}

final class PermissionsListCommand extends PermissionsSubcommand {
  PermissionsListCommand(super.context);

  @override
  String get name => 'list';

  @override
  String get description =>
      'The purpose strings set in Info.plist, the ones plugins need and are '
      'missing, and the ones you can add.';

  @override
  Future<void> run() async {
    final plists = open();
    final info = plists.info();
    final report = guarded(() {
      info.editable; // refuses a binary or broken file up front
      return PermissionsReport.permissions(info, releaseProject(plists));
    });
    final out = StringBuffer('Permissions in ${info.relativePath}\n');
    for (final entry in report.permissions) {
      final mark = entry.status == 'ok' ? '✔' : '!';
      out.writeln(
        '  $mark ${entry.name} (${entry.key})'
        '${entry.status == 'ok' ? '' : '  ${entry.status}'}: "${entry.value}"',
      );
    }
    if (report.permissions.isEmpty) out.writeln('  none set');
    for (final missing in report.missing) {
      out.writeln(
        '  ✖ missing: ${missing.resource} (${missing.plugins.join(', ')}) '
        'needs ${missing.keys.join(' or ')}',
      );
    }
    emit({
      'v': 1,
      'type': 'permissions',
      'project': plists.root,
      'infoPlist': info.relativePath,
      'permissions': [for (final e in report.permissions) e.toJson()],
      'missing': [for (final m in report.missing) m.toJson()],
      'catalog': [for (final c in PermissionCatalog.all) c.toJson()],
    }, out.toString());
  }
}

final class PermissionsSetCommand extends PermissionsSubcommand {
  PermissionsSetCommand(super.context);

  @override
  String get name => 'set';

  @override
  String get description =>
      'Add a purpose string or change its sentence: set <key> "<sentence>".';

  @override
  String get invocation =>
      'xcross permissions set <NS…UsageDescription> "<sentence>" '
      '[--json] [--project <dir>]';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      usageException('Pass the key and the sentence.');
    }
    final [key, sentence] = rest;
    if (!ReleaseTables.isUsageKey(key)) {
      throw CliError(
        '[permissions.bad_key] $key is not a purpose string key.\n'
        'hint: Keys look like NSCameraUsageDescription; '
        '`xcross permissions list` shows the ones you can add.',
      );
    }
    if (sentence.trim().isEmpty) {
      throw CliError(
        '[permissions.empty_value] The sentence for $key is empty.\n'
        'hint: App Review rejects an empty purpose string; say what the app '
        'does with it.',
      );
    }
    final plists = open();
    final info = plists.info();
    final backup = guarded(() {
      final updated = info.editable.set(key, sentence.trim());
      return (plists.write(info, updated), updated != info.text);
    });
    const placeholderNote =
        'The sentence looks like a placeholder; App Review wants a full '
        'sentence about what the app does with it.';
    final notes = [
      if (ReleaseTables.isPlaceholderPurpose(key, sentence)) placeholderNote,
    ];
    emit(
      {
        'v': 1,
        'type': 'permissions_change',
        'action': 'set',
        'key': key,
        'changed': backup.$2,
        'backup': backup.$1 == null ? null : relative(plists, backup.$1),
        'notes': notes,
      },
      '${backup.$2 ? 'Set' : 'Already set:'} $key in ${info.relativePath}'
      '${backup.$1 == null ? '' : ' (backup: ${relative(plists, backup.$1)})'}\n'
      '${notes.map((n) => 'note: $n\n').join()}',
    );
  }
}

final class PermissionsRemoveCommand extends PermissionsSubcommand {
  PermissionsRemoveCommand(super.context);

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a purpose string: remove <key>.';

  @override
  String get invocation =>
      'xcross permissions remove <NS…UsageDescription> [--json] '
      '[--project <dir>]';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Pass the key to remove.');
    final key = rest.single;
    if (!ReleaseTables.isUsageKey(key)) {
      throw CliError(
        '[permissions.bad_key] $key is not a purpose string key.\n'
        'hint: Only NS…UsageDescription keys are removed here.',
      );
    }
    final plists = open();
    final info = plists.info();
    final result = guarded(() {
      final updated = info.editable.remove(key);
      return (plists.write(info, updated), updated != info.text);
    });
    emit(
      {
        'v': 1,
        'type': 'permissions_change',
        'action': 'remove',
        'key': key,
        'changed': result.$2,
        'backup': result.$1 == null ? null : relative(plists, result.$1),
        'notes': const <String>[],
      },
      '${result.$2 ? 'Removed' : 'Was not set:'} $key in ${info.relativePath}'
      '${result.$1 == null ? '' : ' (backup: ${relative(plists, result.$1)})'}\n',
    );
  }
}

/// `xcross capabilities list|add|remove`.
final class CapabilitiesCommand extends Command<void> {
  CapabilitiesCommand(PermissionsContext context) {
    addSubcommand(CapabilitiesListCommand(context));
    addSubcommand(CapabilitiesAddCommand(context));
    addSubcommand(CapabilitiesRemoveCommand(context));
  }

  @override
  String get name => 'capabilities';

  @override
  String get description =>
      'See, add and remove capabilities (push, associated domains, Sign in '
      'with Apple, …) in the entitlements file.';
}

final class CapabilitiesListCommand extends PermissionsSubcommand {
  CapabilitiesListCommand(super.context);

  @override
  String get name => 'list';

  @override
  String get description =>
      'Which capabilities are on, and the ones you can add.';

  @override
  Future<void> run() async {
    final plists = open();
    final info = plists.info();
    final entitlements = plists.entitlements();
    final report = guarded(() {
      info.editable;
      if (entitlements.exists) entitlements.editable;
      return PermissionsReport.capabilities(info, entitlements);
    });
    final out = StringBuffer(
      'Capabilities (${entitlements.relativePath}'
      '${entitlements.exists ? '' : ', not created yet'})\n',
    );
    for (final entry in report.capabilities) {
      out.writeln(
        '  ${entry.enabled ? '✔' : '·'} ${entry.info.name}'
        '${entry.enabled && entry.value is! bool ? ': ${entry.value}' : ''}',
      );
    }
    for (final key in report.unknown) {
      out.writeln('  ? $key (not in the catalog)');
    }
    emit({
      'v': 1,
      'type': 'capabilities',
      'project': plists.root,
      'entitlements': {
        'path': entitlements.relativePath,
        'exists': entitlements.exists,
        'xcodeKnowsFile': plists.xcodeKnowsEntitlements,
      },
      'capabilities': [for (final c in report.capabilities) c.toJson()],
      'unknownEntitlements': report.unknown,
    }, out.toString());
  }
}

/// The capability named on the command line.
CapabilityInfo _capability(Command<void> command) {
  final rest = command.argResults!.rest;
  if (rest.length != 1) {
    command.usageException(
      'Pass one capability: '
      '${CapabilityCatalog.all.map((c) => c.id).join(', ')}.',
    );
  }
  return CapabilityCatalog.byId(rest.single) ??
      command.usageException(
        'Unknown capability "${rest.single}". Known: '
        '${CapabilityCatalog.all.map((c) => c.id).join(', ')}.',
      );
}

final class CapabilitiesAddCommand extends PermissionsSubcommand {
  CapabilitiesAddCommand(super.context) {
    argParser.addMultiOption(
      'value',
      valueHelp: 'text',
      help:
          'The value: push development|production; a domain, group or mode '
          'for the list ones (repeat it). Added to what is there.',
    );
  }

  @override
  String get name => 'add';

  @override
  String get description =>
      'Turn a capability on: add <capability> [--value …].';

  @override
  String get invocation =>
      'xcross capabilities add <capability> [--value <text>]… [--json] '
      '[--project <dir>]';

  @override
  Future<void> run() async {
    final capability = _capability(this);
    final values = argResults!.multiOption('value');
    final plists = open();
    final info = plists.info();
    final target = capability.inInfoPlist ? info : plists.entitlements();
    final Object value = _valueToWrite(capability, values, target);
    final result = guarded(() {
      final updated = target.editable.set(capability.key, value);
      return (plists.write(target, updated), updated != target.text);
    });
    final xcodeNote =
        'Xcode does not know ${target.relativePath} yet: add it to the '
        'Runner target as CODE_SIGN_ENTITLEMENTS if you also build in '
        'Xcode. xcross builds use the file as it is.';
    final appIdNote =
        'The App ID needs the ${capability.ascCapability} capability; xcross '
        'switches it on when it signs.';
    final notes = [
      if (!capability.inInfoPlist && !plists.xcodeKnowsEntitlements) xcodeNote,
      if (capability.ascCapability != null) appIdNote,
    ];
    emit(
      {
        'v': 1,
        'type': 'capabilities_change',
        'action': 'add',
        'id': capability.id,
        'changed': result.$2,
        'backup': result.$1 == null ? null : relative(plists, result.$1),
        'notes': notes,
      },
      '${result.$2 ? 'Added' : 'Already on:'} ${capability.name} '
      'in ${target.relativePath}'
      '${result.$1 == null ? '' : ' (backup: ${relative(plists, result.$1)})'}\n'
      '${notes.map((n) => 'note: $n\n').join()}',
    );
  }

  Object _valueToWrite(
    CapabilityInfo capability,
    List<String> values,
    ProjectPlist target,
  ) {
    switch (capability.value) {
      case CapabilityValue.flag:
        if (values.isNotEmpty) {
          usageException('${capability.name} takes no --value.');
        }
        return true;
      case CapabilityValue.choice:
        final chosen = values.isEmpty
            ? '${capability.defaultValue}'
            : values.single;
        if (values.length > 1 || !capability.choices.contains(chosen)) {
          usageException(
            '${capability.name} is one of ${capability.choices.join(', ')}.',
          );
        }
        return chosen;
      case CapabilityValue.list:
        final given = values.isEmpty
            ? [...?(capability.defaultValue as List<Object?>?)]
            : values;
        if (given.isEmpty) {
          throw CliError(
            '[capabilities.value_required] ${capability.name} needs a value.\n'
            'hint: Pass --value${capability.example == null ? '' : ' (for example ${capability.example})'}.',
          );
        }
        final bad = [
          for (final v in given)
            if (capability.choices.isNotEmpty &&
                !capability.choices.contains(v))
              '$v',
        ];
        if (bad.isNotEmpty) {
          usageException(
            '${capability.name}: ${bad.join(', ')} is not one of '
            '${capability.choices.join(', ')}.',
          );
        }
        final existing = target.values[capability.key];
        return [
          if (existing is List) ...existing.whereType<String>(),
          for (final v in given)
            if (existing is! List || !existing.contains(v)) '$v',
        ];
    }
  }
}

final class CapabilitiesRemoveCommand extends PermissionsSubcommand {
  CapabilitiesRemoveCommand(super.context) {
    argParser.addMultiOption(
      'value',
      valueHelp: 'text',
      help:
          'Only remove these domains, groups or modes from a list; the '
          'capability goes off when none is left.',
    );
  }

  @override
  String get name => 'remove';

  @override
  String get description => 'Turn a capability off: remove <capability>.';

  @override
  String get invocation =>
      'xcross capabilities remove <capability> [--value <text>]… [--json] '
      '[--project <dir>]';

  @override
  Future<void> run() async {
    final capability = _capability(this);
    final values = argResults!.multiOption('value');
    final plists = open();
    final info = plists.info();
    final target = capability.inInfoPlist ? info : plists.entitlements();
    final result = guarded(() {
      final text = target.editable;
      final existing = target.values[capability.key];
      final String updated;
      if (values.isNotEmpty && existing is List) {
        final left = [
          for (final item in existing.whereType<String>())
            if (!values.contains(item)) item,
        ];
        updated = left.isEmpty
            ? text.remove(capability.key)
            : text.set(capability.key, left);
      } else {
        updated = text.remove(capability.key);
      }
      return (
        target.exists ? plists.write(target, updated) : null,
        updated != target.text,
      );
    });
    emit(
      {
        'v': 1,
        'type': 'capabilities_change',
        'action': 'remove',
        'id': capability.id,
        'changed': result.$2,
        'backup': result.$1 == null ? null : relative(plists, result.$1),
        'notes': const <String>[],
      },
      '${result.$2 ? 'Removed' : 'Was not on:'} ${capability.name} '
      'in ${target.relativePath}'
      '${result.$1 == null ? '' : ' (backup: ${relative(plists, result.$1)})'}\n',
    );
  }
}
