// studio: 021 — App Store screenshots: size check, then reserve → upload
// operations → commit (specs/021-app-store-submission, AC-021-5, AC-021-6).
import 'dart:typed_data';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:cli_kit/shared/errors/errors.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The pixel sizes App Store Connect accepts per screenshot display type
/// (portrait; landscape is the swap).
@internal
abstract final class ScreenshotSizes {
  static const byDisplayType = <String, List<(int, int)>>{
    'APP_IPHONE_67': [(1290, 2796), (1320, 2868), (1260, 2736)],
    'APP_IPHONE_65': [(1242, 2688), (1284, 2778)],
    'APP_IPHONE_61': [(1179, 2556), (1170, 2532)],
    'APP_IPHONE_58': [(1125, 2436), (1080, 2340), (1170, 2532)],
    'APP_IPHONE_55': [(1242, 2208)],
    'APP_IPHONE_47': [(750, 1334)],
    'APP_IPAD_PRO_3GEN_129': [(2048, 2732), (2064, 2752)],
    'APP_IPAD_PRO_129': [(2048, 2732)],
    'APP_IPAD_PRO_3GEN_11': [(1668, 2388), (1640, 2360), (1488, 2266)],
    'APP_IPAD_105': [(1668, 2224)],
    'APP_IPAD_97': [(1536, 2048)],
  };

  /// Whether [type] takes a [width]×[height] image.
  static bool accepts(String type, int width, int height) =>
      (byDisplayType[type] ?? const []).any(
        (size) =>
            (size.$1 == width && size.$2 == height) ||
            (size.$1 == height && size.$2 == width),
      );

  /// The accepted sizes of [type], for messages.
  static String describe(String type) => [
    for (final (w, h) in byDisplayType[type] ?? const <(int, int)>[])
      '$w×$h or $h×$w',
  ].join(', ');
}

/// The width and height in a PNG's `IHDR` chunk, or null when [bytes] is not
/// a PNG.
@internal
(int, int)? pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

/// One image of `appstore/screenshots/<locale>/<display type>/`.
@internal
@immutable
final class ScreenshotFile {
  const ScreenshotFile({
    required this.locale,
    required this.displayType,
    required this.path,
    required this.bytes,
  });

  final String locale;
  final String displayType;
  final String path;
  final Uint8List bytes;
}

/// Reads `appstore/screenshots/<locale>/<display type>/*.png`.
@internal
abstract final class ScreenshotFolder {
  /// Every image under [dir], after checking type, format and size. All
  /// problems are reported at once, before anything is uploaded.
  static List<ScreenshotFile> plan(
    HostFileSystemInterface fileSystem,
    p.Context paths,
    String dir,
  ) {
    final root = fileSystem.directory(dir);
    if (!root.existsSync()) {
      throw CliError('No screenshots folder at $dir.');
    }
    final files = <ScreenshotFile>[];
    final problems = <String>[];
    List<String> children(String path, {required bool directories}) => [
      for (final entity in fileSystem.directory(path).listSync())
        if (fileSystem.directory(entity.path).existsSync() == directories)
          paths.basename(entity.path),
    ]..sort();

    for (final locale in children(dir, directories: true)) {
      final localeDir = paths.join(dir, locale);
      for (final type in children(localeDir, directories: true)) {
        final typeDir = paths.join(localeDir, type);
        if (!ScreenshotSizes.byDisplayType.containsKey(type)) {
          problems.add(
            '$locale/$type: unknown display type (use one of '
            '${ScreenshotSizes.byDisplayType.keys.join(', ')})',
          );
          continue;
        }
        for (final name in children(typeDir, directories: false)) {
          final path = paths.join(typeDir, name);
          final bytes = fileSystem.file(path).readAsBytesSync();
          final size = pngSize(bytes);
          if (size == null) {
            problems.add('$locale/$type/$name: not a PNG image');
            continue;
          }
          final (width, height) = size;
          if (!ScreenshotSizes.accepts(type, width, height)) {
            problems.add(
              '$locale/$type/$name is $width×$height; $type takes '
              '${ScreenshotSizes.describe(type)}',
            );
            continue;
          }
          files.add(
            ScreenshotFile(
              locale: locale,
              displayType: type,
              path: path,
              bytes: bytes,
            ),
          );
        }
      }
    }
    if (problems.isNotEmpty) {
      throw CliError('Screenshots not uploaded:\n  ${problems.join('\n  ')}');
    }
    return files;
  }
}

/// Uploads screenshots to an App Store version.
@internal
final class ScreenshotUpload {
  ScreenshotUpload(
    this.api, {
    required this.paths,
    required this.versionId,
    required this.write,
  });

  final AscApi api;
  final p.Context paths;
  final String versionId;
  final void Function(String line) write;

  /// Uploads [files]; with [replace] the screenshots already in each set are
  /// deleted first, otherwise files whose name is already there are skipped.
  /// Returns how many images were uploaded.
  Future<int> push(List<ScreenshotFile> files, {required bool replace}) async {
    final localizations = {
      for (final localization in await api.getAll(
        '/v1/appStoreVersions/$versionId/appStoreVersionLocalizations',
      ))
        ?localization.string('locale'): localization.id,
    };
    final sets = <String, String>{};
    final existing = <String, Set<String>>{};
    var uploaded = 0;
    for (final file in files) {
      final localizationId = localizations[file.locale];
      if (localizationId == null) {
        throw CliError(
          'The version has no ${file.locale} localization; add it with '
          '`xcross appstore metadata push` first.',
        );
      }
      final key = '${file.locale}/${file.displayType}';
      var setId = sets[key];
      if (setId == null) {
        setId = await _set(localizationId, file.displayType);
        sets[key] = setId;
        final current = await api.getAll(
          '/v1/appScreenshotSets/$setId/appScreenshots',
        );
        if (replace) {
          for (final screenshot in current) {
            await api.delete('/v1/appScreenshots/${screenshot.id}');
          }
          existing[key] = {};
          if (current.isNotEmpty) {
            write('Removed ${current.length} screenshots from $key');
          }
        } else {
          existing[key] = {
            for (final screenshot in current) ?screenshot.string('fileName'),
          };
        }
      }
      final name = paths.basename(file.path);
      if (existing[key]!.contains(name)) {
        write('Skipped $key/$name (already uploaded; --replace replaces)');
        continue;
      }
      await _upload(setId, name, file.bytes);
      existing[key]!.add(name);
      uploaded++;
      write('Uploaded $key/$name');
    }
    return uploaded;
  }

  Future<String> _set(String localizationId, String displayType) async {
    for (final set in await api.getAll(
      '/v1/appStoreVersionLocalizations/$localizationId/appScreenshotSets',
    )) {
      if (set.string('screenshotDisplayType') == displayType) return set.id;
    }
    final created = AscApi.data(
      await api.post('/v1/appScreenshotSets', {
        'data': {
          'type': 'appScreenshotSets',
          'attributes': {'screenshotDisplayType': displayType},
          'relationships': {
            'appStoreVersionLocalization': {
              'data': {
                'type': 'appStoreVersionLocalizations',
                'id': localizationId,
              },
            },
          },
        },
      }),
    );
    return created.id;
  }

  Future<void> _upload(String setId, String name, Uint8List bytes) async {
    final reservation = AscApi.data(
      await api.post('/v1/appScreenshots', {
        'data': {
          'type': 'appScreenshots',
          'attributes': {'fileName': name, 'fileSize': bytes.length},
          'relationships': {
            'appScreenshotSet': {
              'data': {'type': 'appScreenshotSets', 'id': setId},
            },
          },
        },
      }),
    );
    final Object? operations = reservation.attributes['uploadOperations'];
    if (operations is! List || operations.isEmpty) {
      throw CliError('App Store Connect gave no upload operations for $name.');
    }
    for (final operation in operations) {
      if (operation is! Map) continue;
      final offset = (operation['offset'] as num?)?.toInt() ?? 0;
      final Object? requestHeaders = operation['requestHeaders'];
      final length = (operation['length'] as num?)?.toInt() ?? bytes.length;
      final request =
          http.Request(
              '${operation['method'] ?? 'PUT'}',
              Uri.parse('${operation['url']}'),
            )
            // Only Apple's own headers: the presigned URL never gets the
            // App Store Connect token.
            ..headers.addAll({
              if (requestHeaders is List<Object?>)
                for (final header in requestHeaders)
                  if (header case {
                    'name': final String key,
                    'value': final String value,
                  })
                    key: value,
            })
            ..bodyBytes = bytes.sublist(offset, offset + length);
      final response = await api.httpClient.send(request);
      await response.stream.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CliError(
          'Uploading $name failed (HTTP ${response.statusCode}); run the same '
          'command again (files already uploaded are skipped).',
        );
      }
    }
    await api.patch('/v1/appScreenshots/${reservation.id}', {
      'data': {
        'type': 'appScreenshots',
        'id': reservation.id,
        'attributes': {
          'uploaded': true,
          'sourceFileChecksum': md5.convert(bytes).toString(),
        },
      },
    });
  }
}
