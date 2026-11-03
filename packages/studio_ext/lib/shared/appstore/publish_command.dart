// studio: 019 — `xcross publish`: upload an App Store IPA to App Store Connect
// and follow its processing (specs/019-upload-processing).
import 'dart:convert';
import 'dart:io';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_api.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_client.dart';
import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:path/path.dart' as p;
import 'package:studio_ext/shared/appstore/command_exit.dart';
import 'package:studio_ext/src/shared/appstore/asc_session.dart';
import 'package:studio_ext/src/shared/appstore/build_processing.dart';
import 'package:studio_ext/src/shared/appstore/build_upload.dart';
import 'package:studio_ext/src/shared/appstore/release_record.dart';
import 'package:studio_ext/src/shared/appstore/transporter.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/inspect_source.dart';
import 'package:studio_ext/src/shared/inspect/inspector.dart';

/// Runs a process (Transporter, git) and returns its result.
typedef RunProcess =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// `xcross publish [<ipa>] [--app-id] [--wait] [--timeout] [--json]
/// [--transporter] [--validate]`.
final class PublishCommand extends Command<void> {
  PublishCommand({
    required OpenAscApi openApi,
    required Future<AscCredentials> Function() loadCredentials,
    required HostFileSystemInterface fileSystem,
    required String Function() currentDirectory,
    required WriteOut write,
    required RunProcess runProcess,
    required String temporaryRoot,
    Map<String, String> environment = const {},
    String? Function()? flutterVersion,
    Duration pollInterval = const Duration(seconds: 20),
    Future<void> Function(Duration delay)? sleep,
  }) : _openApi = openApi,
       _loadCredentials = loadCredentials,
       _fileSystem = fileSystem,
       _cwd = currentDirectory,
       _write = write,
       _runProcess = runProcess,
       _temporaryRoot = temporaryRoot,
       _environment = environment,
       _flutterVersion = flutterVersion,
       _pollInterval = pollInterval,
       _sleep = sleep {
    argParser
      ..addOption(
        'app-id',
        help: 'Apple ID of the app (default: by bundle ID).',
      )
      ..addFlag(
        'wait',
        negatable: false,
        help: 'Wait until Apple has processed the build.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '60',
        help: 'Minutes to wait with --wait (exit 2 when they run out).',
      )
      ..addFlag('json', negatable: false, help: 'NDJSON events on stdout.')
      ..addFlag(
        'transporter',
        negatable: false,
        help: "Upload with Apple's Transporter, if you installed it.",
      )
      ..addFlag(
        'validate',
        negatable: false,
        help: "Only validate with Apple's Transporter (-m verify).",
      );
  }

  final OpenAscApi _openApi;
  final Future<AscCredentials> Function() _loadCredentials;
  final HostFileSystemInterface _fileSystem;
  final String Function() _cwd;
  final WriteOut _write;
  final RunProcess _runProcess;
  final String _temporaryRoot;
  final Map<String, String> _environment;
  final String? Function()? _flutterVersion;
  final Duration _pollInterval;
  final Future<void> Function(Duration delay)? _sleep;

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Upload an App Store IPA to App Store Connect (TestFlight) and follow '
      'its processing.';

  @override
  String get invocation => 'xcross publish [<ipa>] [--app-id <id>] [--wait]';

  bool get _json => argResults!.flag('json');

  void _event(String event, Map<String, Object?> fields, String text) {
    if (_json) {
      _write(
        '${jsonEncode({'v': 1, 'type': 'publish', 'event': event, ...fields})}\n',
      );
    } else if (text.isNotEmpty) {
      _write('$text\n');
    }
  }

  @override
  Future<void> run() async {
    final results = argResults!;
    final ipaPath = _ipaPath(results.rest);
    final source = InspectSource.open(_fileSystem, ipaPath);
    final InspectReport report;
    try {
      report = BundleInspector(source).inspect();
    } finally {
      source.close();
    }
    final bundle = report.bundle;
    final bundleId = bundle.bundleId;
    final version = bundle.shortVersion;
    final build = bundle.buildNumber;
    if (bundleId == null || version == null || build == null) {
      throw CommandExit(
        '$ipaPath has no CFBundleIdentifier, CFBundleShortVersionString or '
        'CFBundleVersion.',
      );
    }
    final ipa = _fileSystem.file(ipaPath);
    final outputRoot = _outputRoot(ipaPath);
    final recordFile = _fileSystem.file(
      p.join(outputRoot, ReleaseRecord.fileName),
    );
    if (results.flag('validate') || results.flag('transporter')) {
      await _transporter(ipaPath, verify: results.flag('validate'));
      if (results.flag('validate')) return;
      ReleaseRecord.merge(recordFile, {
        'upload': {'via': 'transporter', 'at': _now()},
      });
      return;
    }
    final timeout = Duration(
      minutes: int.tryParse(results.option('timeout') ?? '') ?? 60,
    );
    final api = await _openApi();
    try {
      final app = await resolveAscApp(
        api,
        appId: results.option('app-id'),
        bundleId: bundleId,
      );
      final processing = BuildProcessing(
        api,
        interval: _pollInterval,
        sleep: _sleep,
      );
      final existing = await processing.findBuild(
        appId: app.id,
        version: version,
        build: build,
      );
      if (existing != null) {
        throw CommandExit(
          '[publish.duplicate_build] Build $build of $version is already on '
          'App Store Connect (${existing.string('processingState') ?? 'uploaded'}).'
          '\nhint: Build again with `--build-number auto` (or a higher build '
          'number), then publish.',
        );
      }
      final digests = await FileDigests.of(ipa);
      ReleaseRecord.merge(recordFile, {
        ..._identity(report, app),
        'ipa': {
          'path': ipaPath,
          'sha256': digests.sha256,
          'size': digests.size,
        },
        'git': await _git(),
        'flutter': _flutterVersion?.call(),
      });
      _event('start', {
        'appId': app.id,
        'version': version,
        'build': build,
      }, 'Uploading $version ($build) to ${app.string('name') ?? app.id}');
      final uploadId = await BuildUploader(api: api, sleep: _sleep).upload(
        appId: app.id,
        ipa: ipa,
        version: version,
        build: build,
        stateFile: _fileSystem.file(
          p.join(outputRoot, '.publish-$version-$build.json'),
        ),
        onNote: (message) => _event('note', {'message': message}, message),
        onProgress: (part, parts, sent, total) => _event(
          'progress',
          {'part': part, 'parts': parts, 'bytes': sent, 'total': total},
          '  part $part/$parts (${(sent * 100 / total).clamp(0, 100).round()}%)',
        ),
      );
      ReleaseRecord.merge(recordFile, {
        'upload': {'id': uploadId, 'state': 'UPLOADED', 'at': _now()},
      });
      _event('uploaded', {
        'uploadId': uploadId,
      }, 'Uploaded; Apple is processing it.');
      if (!results.flag('wait')) {
        _event(
          'published',
          {'uploadId': uploadId, 'uploadState': 'UPLOADED'},
          'Follow it with `xcross publish --wait` or `xcross testflight status`.',
        );
        return;
      }
      await _wait(
        processing,
        app.id,
        version,
        build,
        uploadId,
        timeout,
        recordFile,
      );
    } on AppleApiError catch (error) {
      throw ascFailure(error, action: 'upload the build');
    } finally {
      api.close();
    }
  }

  Future<void> _wait(
    BuildProcessing processing,
    String appId,
    String version,
    String build,
    String uploadId,
    Duration timeout,
    File recordFile,
  ) async {
    try {
      final outcome = await processing.waitForUpload(
        uploadId,
        timeout: timeout,
        onState: (state) =>
            _event('state', {'upload': state}, 'Upload state: $state'),
      );
      for (final issue in outcome.issues) {
        _event(
          'issue',
          issue.toJson(),
          '${issue.severity} ${issue.code}: ${issue.description}',
        );
      }
      ReleaseRecord.merge(recordFile, {
        'upload': {
          'state': outcome.state,
          'issues': [for (final issue in outcome.issues) issue.toJson()],
        },
      });
      if (outcome.state == 'FAILED') {
        throw CommandExit(
          '[publish.upload_failed] App Store Connect rejected the upload'
          '${outcome.issues.isEmpty ? '' : ': ${outcome.issues.where((i) => i.severity == 'error').map((i) => '${i.code} ${i.description}').join('; ')}'}.',
        );
      }
      final result = await processing.waitForProcessing(
        appId: appId,
        version: version,
        build: build,
        timeout: timeout,
        onState: (state) =>
            _event('state', {'processing': state}, 'Build processing: $state'),
      );
      ReleaseRecord.merge(recordFile, {
        'build_record': {'id': result.id, 'processingState': result.state},
      });
      _event('published', {
        'uploadId': uploadId,
        'uploadState': outcome.state,
        'buildId': result.id,
        'processingState': result.state,
        'issues': [for (final issue in outcome.issues) issue.toJson()],
      }, result.state == 'VALID' ? 'The build is ready for TestFlight.' : '');
      if (result.state != 'VALID') {
        throw CommandExit(
          '[publish.processing_failed] Apple finished processing the build as '
          '${result.state}.',
        );
      }
    } on ProcessingTimeout catch (timeoutError) {
      throw CommandExit(
        'Still ${timeoutError.lastState ?? 'processing'} after '
        '${timeout.inMinutes} minutes. The upload continues on Apple’s side; '
        'check later with `xcross testflight status`.',
        exitCode: 2,
      );
    }
  }

  Future<void> _transporter(String ipaPath, {required bool verify}) async {
    final transporter = Transporter.locate(
      _environment,
      exists: (path) => _fileSystem.file(path).existsSync(),
    );
    if (transporter == null) {
      throw const CommandExit(
        "[publish.transporter_missing] Apple's Transporter is not installed. "
        'Install it from Apple (${Transporter.downloadPage}) or set '
        '${Transporter.variable}; xcross does not download it.',
      );
    }
    final credentials = await _loadCredentials();
    if (credentials.keyType == AscKeyType.individual) {
      throw const CommandExit(
        'Transporter authenticates with a team key (Issuer ID); the saved key '
        'is an individual key. Upload without --transporter instead.',
      );
    }
    // Transporter reads AuthKey_<id>.p8 from ./private_keys.
    final workDir = _fileSystem
        .directory(_temporaryRoot)
        .createTempSync('xcross-transporter-');
    try {
      final keys = _fileSystem.directory(p.join(workDir.path, 'private_keys'))
        ..createSync();
      _fileSystem
          .file(credentials.privateKeyPath)
          .copySync(p.join(keys.path, 'AuthKey_${credentials.keyId}.p8'));
      final result = await _runProcess(
        transporter,
        Transporter.arguments(
          ipa: _fileSystem.file(ipaPath).absolute.path,
          keyId: credentials.keyId,
          issuerId: credentials.issuerId,
          verify: verify,
        ),
        workingDirectory: workDir.path,
      );
      _write('${result.stdout}');
      if (result.exitCode != 0) {
        throw CommandExit(
          'Transporter ${verify ? 'validation' : 'upload'} failed '
          '(exit ${result.exitCode}): ${'${result.stderr}'.trim()}',
        );
      }
    } finally {
      workDir.deleteSync(recursive: true);
    }
  }

  String _ipaPath(List<String> rest) {
    if (rest.length > 1) usageException('Pass at most one IPA.');
    if (rest.isNotEmpty) return rest.single;
    final root = _cwd();
    for (final dir in [
      p.join(root, 'build', 'xcross-ios', 'ipa'),
      p.join(root, 'build', 'xcross-ios'),
    ]) {
      final directory = _fileSystem.directory(dir);
      if (!directory.existsSync()) continue;
      final ipas =
          directory
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.ipa'))
              .toList()
            ..sort(
              (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
            );
      if (ipas.isNotEmpty) return ipas.first.path;
    }
    throw const CommandExit(
      '[publish.no_ipa] No IPA found. Build one with `xcross flutter build '
      '--release --ipa --export-method app-store`, or pass its path.',
    );
  }

  /// `build/xcross-ios` for an IPA in `build/xcross-ios/ipa`, else its folder.
  String _outputRoot(String ipaPath) {
    final folder = p.dirname(_fileSystem.file(ipaPath).absolute.path);
    return p.basename(folder) == 'ipa' ? p.dirname(folder) : folder;
  }

  static Map<String, Object?> _identity(InspectReport report, AscResource app) {
    final bundle = report.bundle;
    return {
      'app': app.string('name') ?? bundle.displayName ?? bundle.name,
      'appId': app.id,
      'bundleId': bundle.bundleId,
      'teamId': report.profile?.teamId ?? report.signature.teamId,
      'version': bundle.shortVersion,
      'build': bundle.buildNumber,
      'minimumOS': bundle.minimumOSVersion,
      'sdk': switch (bundle.plist['DTSDKName']) {
        final String sdk => sdk,
        _ => null,
      },
      'profile': report.profile?.kind.wire,
    };
  }

  Future<Map<String, Object?>?> _git() async {
    try {
      final commit = await _runProcess('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: _cwd());
      if (commit.exitCode != 0) return null;
      final status = await _runProcess('git', [
        'status',
        '--porcelain',
      ], workingDirectory: _cwd());
      return {
        'commit': '${commit.stdout}'.trim(),
        'dirty': '${status.stdout}'.trim().isNotEmpty,
      };
    } on Object {
      return null;
    }
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
}
