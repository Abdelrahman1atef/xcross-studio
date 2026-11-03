// studio: 021 — the product page as a fastlane-deliver-style folder
// (specs/021-app-store-submission, AC-021-3, AC-021-4).
import 'dart:convert';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Folder file stems of app info localization fields → API attributes.
@internal
const appInfoFields = {
  'name': 'name',
  'subtitle': 'subtitle',
  'privacy_url': 'privacyPolicyUrl',
};

/// Folder file stems of version localization fields → API attributes.
@internal
const versionFields = {
  'description': 'description',
  'keywords': 'keywords',
  'promotional_text': 'promotionalText',
  'release_notes': 'whatsNew',
  'support_url': 'supportUrl',
  'marketing_url': 'marketingUrl',
};

/// `appstore/metadata`: per-locale texts plus app-level values. A value that
/// is absent leaves App Store Connect's value as it is.
@internal
final class MetadataFolder {
  MetadataFolder({
    Map<String, Map<String, String>>? locales,
    this.copyright,
    this.primaryCategory,
    this.secondaryCategory,
    this.ageRating,
  }) : locales = locales ?? {};

  /// Reads [dir]; missing files are absent values.
  factory MetadataFolder.read(
    HostFileSystemInterface fileSystem,
    p.Context paths,
    String dir,
  ) {
    String? text(List<String> parts) {
      final file = fileSystem.file(paths.joinAll([dir, ...parts]));
      return file.existsSync() ? file.readAsStringSync().trimRight() : null;
    }

    final locales = <String, Map<String, String>>{};
    final root = fileSystem.directory(dir);
    if (root.existsSync()) {
      final names = [
        for (final entity in root.listSync())
          if (fileSystem.directory(entity.path).existsSync())
            paths.basename(entity.path),
      ]..sort();
      for (final locale in names) {
        final values = <String, String>{
          for (final stem in [...appInfoFields.keys, ...versionFields.keys])
            stem: ?text([locale, '$stem.txt']),
        };
        if (values.isNotEmpty) locales[locale] = values;
      }
    }
    Map<String, Object?>? ageRating;
    final rating = text(['age_rating.json']);
    if (rating != null && rating.isNotEmpty) {
      final Object? decoded = jsonDecode(rating);
      if (decoded is Map) ageRating = decoded.cast<String, Object?>();
    }
    return MetadataFolder(
      locales: locales,
      copyright: text(['copyright.txt']),
      primaryCategory: text(['primary_category.txt']),
      secondaryCategory: text(['secondary_category.txt']),
      ageRating: ageRating,
    );
  }

  /// locale → file stem → text.
  final Map<String, Map<String, String>> locales;
  String? copyright;
  String? primaryCategory;
  String? secondaryCategory;
  Map<String, Object?>? ageRating;

  /// Writes every value to [dir]; returns the files written, relative.
  Future<List<String>> write(
    HostFileSystemInterface fileSystem,
    p.Context paths,
    String dir,
  ) async {
    final written = <String>[];
    Future<void> put(List<String> parts, String value) async {
      final file = fileSystem.file(paths.joinAll([dir, ...parts]));
      await file.parent.create(recursive: true);
      await file.writeAsString('$value\n');
      written.add(parts.join('/'));
    }

    for (final MapEntry(key: locale, value: values) in locales.entries) {
      for (final MapEntry(key: stem, value: text) in values.entries) {
        await put([locale, '$stem.txt'], text);
      }
    }
    if (copyright case final value?) await put(['copyright.txt'], value);
    if (primaryCategory case final value?) {
      await put(['primary_category.txt'], value);
    }
    if (secondaryCategory case final value?) {
      await put(['secondary_category.txt'], value);
    }
    if (ageRating case final value?) {
      await put([
        'age_rating.json',
      ], const JsonEncoder.withIndent('  ').convert(value));
    }
    return written;
  }
}

/// Moves the product page between App Store Connect and a [MetadataFolder].
@internal
final class MetadataSync {
  MetadataSync(this.api, {required this.appId, required this.version});

  final AscApi api;
  final String appId;

  /// The App Store version whose localizations and copyright are used.
  final AscResource version;

  /// App info states that can no longer be edited.
  static const _liveInfoStates = {
    'READY_FOR_DISTRIBUTION',
    'READY_FOR_SALE',
    'REPLACED_WITH_NEW_INFO',
  };

  /// The app info record that can still be edited, else the first.
  Future<AscResource?> appInfo() async {
    final infos = AscApi.dataList(
      await api.get(
        '/v1/apps/$appId/appInfos',
        query: {'include': 'primaryCategory,secondaryCategory'},
      ),
    );
    String? state(AscResource info) =>
        info.string('state') ?? info.string('appStoreState');
    return infos
            .where((i) => !_liveInfoStates.contains(state(i)))
            .firstOrNull ??
        infos.firstOrNull;
  }

  /// App Store Connect's current page as a folder.
  Future<MetadataFolder> pull() async {
    final info = await appInfo();
    final folder = MetadataFolder(copyright: version.string('copyright'));
    if (info != null) {
      folder
        ..primaryCategory = info.relatedId('primaryCategory')
        ..secondaryCategory = info.relatedId('secondaryCategory');
      for (final localization in await api.getAll(
        '/v1/appInfos/${info.id}/appInfoLocalizations',
      )) {
        final locale = localization.string('locale');
        if (locale == null) continue;
        final values = folder.locales.putIfAbsent(locale, () => {});
        for (final MapEntry(key: stem, value: attribute)
            in appInfoFields.entries) {
          if (localization.string(attribute) case final value?) {
            values[stem] = value;
          }
        }
      }
      final rating = await api.get(
        '/v1/appInfos/${info.id}/ageRatingDeclaration',
      );
      final Object? data = rating['data'];
      if (data is Map) {
        final attributes = AscResource.fromJson(
          data.cast<String, dynamic>(),
        ).attributes;
        folder.ageRating = {
          for (final MapEntry(:key, :value) in attributes.entries)
            key: ?(value as Object?),
        };
      }
    }
    for (final localization in await api.getAll(
      '/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations',
    )) {
      final locale = localization.string('locale');
      if (locale == null) continue;
      final values = folder.locales.putIfAbsent(locale, () => {});
      for (final MapEntry(key: stem, value: attribute)
          in versionFields.entries) {
        if (localization.string(attribute) case final value?) {
          values[stem] = value;
        }
      }
    }
    return folder;
  }

  /// Applies [folder]: creates missing localizations, patches changed fields
  /// and app-level values. Returns one line per change.
  Future<List<String>> push(MetadataFolder folder) async {
    final changes = <String>[];
    final info = await appInfo();
    if (info != null) {
      await _pushLocalizations(
        folder,
        fields: appInfoFields,
        listPath: '/v1/appInfos/${info.id}/appInfoLocalizations',
        type: 'appInfoLocalizations',
        parent: ('appInfo', 'appInfos', info.id),
        label: 'app info',
        changes: changes,
      );
    }
    await _pushLocalizations(
      folder,
      fields: versionFields,
      listPath:
          '/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations',
      type: 'appStoreVersionLocalizations',
      parent: ('appStoreVersion', 'appStoreVersions', version.id),
      label: 'version',
      changes: changes,
    );

    if (folder.copyright case final copyright?
        when copyright != (version.string('copyright') ?? '')) {
      await api.patch('/v1/appStoreVersions/${version.id}', {
        'data': {
          'type': 'appStoreVersions',
          'id': version.id,
          'attributes': {'copyright': copyright},
        },
      });
      changes.add('Copyright: $copyright');
    }

    if (info != null) {
      final relationships = <String, Object?>{
        if (folder.primaryCategory case final category?
            when category != info.relatedId('primaryCategory'))
          'primaryCategory': {
            'data': {'type': 'appCategories', 'id': category},
          },
        if (folder.secondaryCategory case final category?
            when category != info.relatedId('secondaryCategory'))
          'secondaryCategory': {
            'data': {'type': 'appCategories', 'id': category},
          },
      };
      if (relationships.isNotEmpty) {
        await api.patch('/v1/appInfos/${info.id}', {
          'data': {
            'type': 'appInfos',
            'id': info.id,
            'relationships': relationships,
          },
        });
        changes.add('Categories: ${relationships.keys.join(', ')}');
      }
      if (folder.ageRating case final wanted? when wanted.isNotEmpty) {
        final rating = await api.get(
          '/v1/appInfos/${info.id}/ageRatingDeclaration',
        );
        final Object? data = rating['data'];
        if (data is Map) {
          final current = AscResource.fromJson(data.cast<String, dynamic>());
          final changed = {
            for (final MapEntry(:key, :value) in wanted.entries)
              if (current.attributes[key] != value) key: value,
          };
          if (changed.isNotEmpty) {
            await api.patch('/v1/ageRatingDeclarations/${current.id}', {
              'data': {
                'type': 'ageRatingDeclarations',
                'id': current.id,
                'attributes': changed,
              },
            });
            changes.add(
              'Age rating: ${(changed.keys.toList()..sort()).join(', ')}',
            );
          }
        }
      }
    }
    return changes;
  }

  Future<void> _pushLocalizations(
    MetadataFolder folder, {
    required Map<String, String> fields,
    required String listPath,
    required String type,
    required (String, String, String) parent,
    required String label,
    required List<String> changes,
  }) async {
    final existing = {
      for (final localization in await api.getAll(listPath))
        ?localization.string('locale'): localization,
    };
    for (final MapEntry(key: locale, value: values) in folder.locales.entries) {
      final wanted = {
        for (final MapEntry(key: stem, value: attribute) in fields.entries)
          attribute: ?values[stem],
      };
      if (wanted.isEmpty) continue;
      final current = existing[locale];
      if (current == null) {
        final (relationship, parentType, parentId) = parent;
        await api.post('/v1/$type', {
          'data': {
            'type': type,
            'attributes': {'locale': locale, ...wanted},
            'relationships': {
              relationship: {
                'data': {'type': parentType, 'id': parentId},
              },
            },
          },
        });
        changes.add('Created the $label localization $locale');
        continue;
      }
      final changed = {
        for (final MapEntry(key: attribute, value: text) in wanted.entries)
          if ((current.string(attribute) ?? '').trimRight() != text.trimRight())
            attribute: text,
      };
      if (changed.isEmpty) continue;
      await api.patch('/v1/$type/${current.id}', {
        'data': {'type': type, 'id': current.id, 'attributes': changed},
      });
      changes.add(
        'Updated $locale ${label == 'version' ? '' : 'app info '}'
        '${changed.keys.join(', ')}',
      );
    }
  }
}
