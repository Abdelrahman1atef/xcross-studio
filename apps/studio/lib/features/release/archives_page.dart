import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/services.dart';
import '../../design_system/design_system.dart';

/// One `.xcarchive` the CLI wrote, read from its `Info.plist` for display.
class ArchiveEntry {
  const ArchiveEntry({
    required this.path,
    required this.created,
    this.bundleId,
    this.version,
    this.build,
    this.signingIdentity,
    this.team,
    this.ipa,
  });

  final String path;
  final DateTime created;
  final String? bundleId;
  final String? version;
  final String? build;
  final String? signingIdentity;
  final String? team;

  /// The IPA in `build/xcross-ios/ipa` next to it, when there is one.
  final String? ipa;

  /// Every archive under `<project>/build/xcross-ios/archive`, newest first.
  static List<ArchiveEntry> list(String project) {
    final outputs = p.join(project, 'build', 'xcross-ios');
    final dir = Directory(p.join(outputs, 'archive'));
    if (!dir.existsSync()) return const [];
    final ipas = Directory(p.join(outputs, 'ipa'));
    final ipa = !ipas.existsSync()
        ? null
        : ipas
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.ipa'))
              .map((f) => f.path)
              .firstOrNull;
    return [
      for (final entity in dir.listSync())
        if (entity is Directory && entity.path.endsWith('.xcarchive'))
          read(entity.path, ipa: ipa),
    ]..sort((a, b) => b.created.compareTo(a.created));
  }

  /// Reads the archive `Info.plist` (XML, as xcross writes it).
  static ArchiveEntry read(String path, {String? ipa}) {
    final info = File(p.join(path, 'Info.plist'));
    final text = info.existsSync() ? info.readAsStringSync() : '';
    String? value(String key) =>
        RegExp('<key>$key</key>\\s*<string>([^<]*)</string>')
            .firstMatch(text)
            ?.group(1);
    final date = RegExp('<key>CreationDate</key>\\s*<date>([^<]*)</date>')
        .firstMatch(text)
        ?.group(1);
    return ArchiveEntry(
      path: path,
      created:
          DateTime.tryParse(date ?? '') ??
          (info.existsSync()
              ? info.statSync().modified
              : DateTime.fromMillisecondsSinceEpoch(0)),
      bundleId: value('CFBundleIdentifier'),
      version: value('CFBundleShortVersionString'),
      build: value('CFBundleVersion'),
      signingIdentity: value('SigningIdentity'),
      team: value('Team'),
      ipa: ipa,
    );
  }
}

/// Archives (feature 022): the Organizer list without Xcode.
class ArchivesPage extends StatefulWidget {
  const ArchivesPage({super.key});

  @override
  State<ArchivesPage> createState() => _ArchivesPageState();
}

class _ArchivesPageState extends State<ArchivesPage> {
  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.jobs]),
      builder: (context, _) {
        final project = services.settings.projectPath;
        final archives = project == null
            ? const <ArchiveEntry>[]
            : ArchiveEntry.list(project);
        return WorkspaceLayout(
          title: 'Archives',
          subtitle:
              'App Store archives xcross built for this project '
              '(build/xcross-ios/archive).',
          actions: [
            XButton(
              label: 'Refresh',
              icon: Icons.refresh,
              variant: XButtonVariant.secondary,
              onPressed: () => setState(() {}),
            ),
          ],
          children: [
            if (project == null)
              const XEmptyState(
                icon: Icons.archive_outlined,
                title: 'Open a Flutter project',
                message: 'Choose a project on Overview to see its archives.',
              )
            else if (archives.isEmpty)
              const XEmptyState(
                icon: Icons.archive_outlined,
                title: 'No archives yet',
                message:
                    'Build one on Release (step 5) or run `xcross flutter build '
                    '--release --ipa --export-method app-store`.',
              )
            else
              for (final archive in archives)
                Padding(
                  padding: const EdgeInsets.only(bottom: XSpace.s3),
                  child: XCard(
                    title:
                        '${archive.version ?? '?'} (${archive.build ?? '?'})',
                    subtitle: archive.bundleId,
                    trailing: XButton(
                      label: 'Open folder',
                      variant: XButtonVariant.secondary,
                      onPressed: () =>
                          services.launcher.openFolder(p.dirname(archive.path)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        XNote('Created ${archive.created.toLocal()}'),
                        XNote(
                          'Signed by ${archive.signingIdentity ?? 'unknown'}'
                          '${archive.team == null ? '' : ' · team ${archive.team}'}',
                        ),
                        if (archive.ipa != null) XNote('IPA: ${archive.ipa}'),
                        XNote(archive.path),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
