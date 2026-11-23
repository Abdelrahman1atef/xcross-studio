// studio: 014 — a Flutter SDK with an iOS compiler for this host.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/cli/flutter/subcommands/flutter_sdk_command.dart';
import 'package:xcross/src/shared/config/config.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/flutter/sdk/ios_compiler_catalog.dart';
import 'package:xcross/src/shared/flutter/sdk/managed_flutter_sdks.dart';

import '../../log_fixture.dart';

const _platform = 'windows-x64';

String _releases(Map<String, List<String>> releases) => jsonEncode([
  for (final MapEntry(:key, :value) in releases.entries)
    {
      'tag_name': key,
      'assets': [
        for (final name in value) {'name': name},
      ],
    },
]);

List<String> _assets(String platform) => [
  'gen_snapshot-release-$platform.zip',
  'gen_snapshot-profile-$platform.zip',
  'manifest.json',
];

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('xcross-sdk-'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('AC-014-1 version choice', () {
    const available = ['3.44.9', '3.47.6', '3.47.1', '3.48.0-0.1.pre'];

    test('newest of the same major.minor line', () {
      final choice = suggestFlutterSdk('3.47.8', available)!;
      expect(choice.version, '3.47.6');
      expect(choice.sameLine, isTrue);
    });

    test('falls back to the newest stable overall', () {
      final choice = suggestFlutterSdk('3.50.1', available)!;
      expect(choice.version, '3.47.6');
      expect(choice.sameLine, isFalse);
    });

    test('a Flutter that has a compiler needs nothing', () {
      expect(suggestFlutterSdk('3.47.6', available), isNull);
      expect(suggestFlutterSdk('3.47.8', const []), isNull);
    });
  });

  group('AC-014-2 published compiler catalog', () {
    IosCompilerCatalog catalogFor(http.Client client, {DateTime? now}) =>
        IosCompilerCatalog(
          fileSystem: const SdkTestFileSystem(),
          paths: p.context,
          cacheRoot: temp.path,
          platform: _platform,
          createHttpClient: () => client,
          now: now == null ? null : () => now,
        );

    test('merges every source; a missing source is left out', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('studio')) {
          return http.Response(
            _releases({
              '3.50.1': _assets(_platform),
              '3.47.8': _assets(_platform),
            }),
            200,
          );
        }
        if (request.url.path.contains('gone')) {
          return http.Response('Not Found', 404);
        }
        return http.Response(
          _releases({
            '3.47.6': _assets(_platform),
            '3.47.8': ['gen_snapshot-profile-$_platform.zip'],
          }),
          200,
        );
      });
      final catalog = await IosCompilerCatalog(
        fileSystem: const SdkTestFileSystem(),
        paths: p.context,
        cacheRoot: temp.path,
        platform: _platform,
        createHttpClient: () => client,
        apiUrl: 'https://api.test/repos/studio/releases',
        moreApiUrls: const [
          'https://api.test/repos/gone/releases',
          'https://api.test/repos/upstream/releases',
        ],
      ).load();
      expect(catalog.versions, ['3.50.1', '3.47.8', '3.47.6']);
    });

    test('fails only when no source answers', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      await expectLater(
        IosCompilerCatalog(
          fileSystem: const SdkTestFileSystem(),
          paths: p.context,
          cacheRoot: temp.path,
          platform: _platform,
          createHttpClient: () => client,
          moreApiUrls: const ['https://api.test/repos/gone/releases'],
        ).load(),
        throwsA(isA<HttpException>()),
      );
    });

    test('lists versions with a release compiler for this host', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          _releases({
            '3.47.6': _assets(_platform),
            '3.47.5': _assets('linux-x64'),
            '3.44.9': _assets(_platform),
            '3.48.0-0.1.pre': _assets(_platform),
          }),
          200,
        );
      });
      final catalog = await catalogFor(client).load();
      expect(catalog.versions, ['3.47.6', '3.44.9']);
      expect(catalog.stale, isFalse);
      expect(requests.single.queryParameters['per_page'], '100');
      expect(
        File(p.join(temp.path, 'gen-snapshot', 'catalog.json')).existsSync(),
        isTrue,
      );
    });

    test('a fresh cache answers without the network; offline uses an old '
        'one', () async {
      final now = DateTime.utc(2026, 11, 2, 12);
      await catalogFor(
        MockClient(
          (_) async =>
              http.Response(_releases({'3.47.6': _assets(_platform)}), 200),
        ),
        now: now,
      ).load();
      final offline = MockClient((_) async => throw const SocketException('x'));
      final cached = await catalogFor(
        offline,
        now: now.add(const Duration(hours: 1)),
      ).load();
      expect(cached.versions, ['3.47.6']);
      expect(cached.stale, isFalse);
      final stale = await catalogFor(
        offline,
        now: now.add(const Duration(days: 3)),
      ).load();
      expect(stale.versions, ['3.47.6']);
      expect(stale.stale, isTrue);
    });
  });

  group('AC-014-3 managed install', () {
    late List<String> calls;
    late List<Duration> waits;
    late ManagedFlutterSdks sdks;
    var failClone = false;
    Exception cloneError = const ProcessException('git', [], 'offline');

    setUp(() {
      calls = [];
      waits = [];
      failClone = false;
      cloneError = const ProcessException('git', [], 'offline');
      sdks = ManagedFlutterSdks(
        fileSystem: const SdkTestFileSystem(),
        paths: p.context,
        root: p.join(temp.path, 'flutter-sdks'),
        flutterExecutableName: 'flutter.bat',
        log: Log(output: TestLogOutput()),
        processId: 77,
        sleep: (delay) async => waits.add(delay),
        runTool:
            (executable, arguments, {required label, workingDirectory}) async {
              calls.add('$label ${arguments.join(' ')}');
              if (label == 'git') {
                if (failClone) throw cloneError;
                File(p.join(arguments.last, 'bin', 'flutter'))
                  ..createSync(recursive: true)
                  ..writeAsStringSync('#!/bin/sh');
              } else {
                Directory(
                  p.join(workingDirectory!, 'bin', 'cache', 'dart-sdk'),
                ).createSync(recursive: true);
                File(
                  p.join(
                    workingDirectory,
                    'bin',
                    'cache',
                    'flutter.version.json',
                  ),
                ).writeAsStringSync('{"frameworkVersion":"3.47.6"}');
              }
            },
      );
    });

    test(
      'clones into a partial folder, renames it, then prepares it',
      () async {
        final root = await sdks.install('3.47.6', git: 'git');
        expect(root, p.join(temp.path, 'flutter-sdks', '3.47.6'));
        final partial = p.join(temp.path, 'flutter-sdks', '.3.47.6.partial-77');
        const clone =
            'git -c core.longpaths=true clone --depth 1 --branch 3.47.6 '
            'https://github.com/flutter/flutter.git';
        expect(calls, ['$clone $partial', 'flutter --version']);
        expect(sdks.stateOf(root), ManagedSdkState.ready);
        expect(sdks.installed().single.version, '3.47.6');
        calls.clear();
        await sdks.install('3.47.6', git: 'git');
        expect(calls, isEmpty, reason: 'a ready SDK is reused');
      },
    );

    test(
      'a retry removes leftovers; a failed clone is a coded error',
      () async {
        final leftover = Directory(
          p.join(temp.path, 'flutter-sdks', '.3.47.6.partial-12'),
        )..createSync(recursive: true);
        failClone = true;
        await expectLater(
          sdks.install('3.47.6', git: 'git'),
          throwsA(
            isA<XcrossError>().having(
              (e) => e.message,
              'message',
              startsWith('[toolchain.flutter_sdk_install_failed]'),
            ),
          ),
        );
        expect(leftover.existsSync(), isFalse);
        failClone = false;
        await sdks.install('3.47.6', git: 'git');
        expect(calls.last, 'flutter --version');
      },
    );

    test('only plain release versions are accepted', () async {
      await expectLater(
        sdks.install('--upload-pack=x', git: 'git'),
        throwsA(isA<XcrossError>()),
      );
      expect(calls, isEmpty);
    });

    test('a dropped download is tried twice more over HTTP/1.1; the error '
        'keeps what git said', () async {
      failClone = true;
      cloneError = Exception(
        'command failed (128): git clone --depth 1 --branch 3.47.6 x y\n'
        "Cloning into 'y'...\n"
        'error: RPC failed; curl 92 HTTP/2 stream 5 was not closed cleanly\n'
        'fatal: early EOF',
      );
      await expectLater(
        sdks.install('3.47.6', git: 'git'),
        throwsA(
          isA<XcrossError>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('[toolchain.flutter_sdk_install_failed]'),
              contains('tried 3 times'),
              contains('The connection to github.com dropped'),
              contains('error: RPC failed; curl 92'),
              contains('fatal: early EOF'),
            ),
          ),
        ),
      );
      final clones = calls.where((c) => c.startsWith('git ')).toList();
      expect(clones, hasLength(3));
      expect(clones.first, isNot(contains('http.version')));
      expect(clones.skip(1), everyElement(contains('http.version=HTTP/1.1')));
      expect(waits, ManagedFlutterSdks.defaultCloneRetryDelays);
      expect(
        Directory(p.join(temp.path, 'flutter-sdks')).listSync(),
        isEmpty,
        reason: 'no partial folder is left behind',
      );
    });

    test('a retry that works installs Flutter', () async {
      var failures = 1;
      final flaky = ManagedFlutterSdks(
        fileSystem: const SdkTestFileSystem(),
        paths: p.context,
        root: p.join(temp.path, 'flutter-sdks'),
        flutterExecutableName: 'flutter.bat',
        log: Log(output: TestLogOutput()),
        processId: 78,
        sleep: (_) async {},
        runTool:
            (executable, arguments, {required label, workingDirectory}) async {
              calls.add(label);
              if (label == 'git') {
                if (failures-- > 0) {
                  throw Exception('command failed (128)\nfatal: early EOF');
                }
                File(p.join(arguments.last, 'bin', 'flutter'))
                  ..createSync(recursive: true)
                  ..writeAsStringSync('#!/bin/sh');
              } else {
                Directory(
                  p.join(workingDirectory!, 'bin', 'cache', 'dart-sdk'),
                ).createSync(recursive: true);
                File(
                  p.join(
                    workingDirectory,
                    'bin',
                    'cache',
                    'flutter.version.json',
                  ),
                ).writeAsStringSync('{}');
              }
            },
      );
      final root = await flaky.install('3.47.6', git: 'git');
      expect(calls, ['git', 'git', 'flutter']);
      expect(flaky.stateOf(root), ManagedSdkState.ready);
    });

    test('a missing version is not tried again', () async {
      failClone = true;
      cloneError = Exception(
        'command failed (128)\n'
        'fatal: Remote branch 3.47.6 not found in upstream origin',
      );
      await expectLater(
        sdks.install('3.47.6', git: 'git'),
        throwsA(
          isA<XcrossError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('tried 1 time)'),
              contains('GitHub has no Flutter 3.47.6.'),
            ),
          ),
        ),
      );
      expect(calls.where((c) => c.startsWith('git ')), hasLength(1));
      expect(waits, isEmpty);
    });
  });

  group('clone failure words', () {
    test('known git errors get plain reasons', () {
      String? reason(String output) =>
          ManagedFlutterSdks.cloneFailure(output, '3.47.0').reason;
      expect(
        reason('fatal: unable to access x: Could not resolve host: github.com'),
        startsWith('Could not reach github.com'),
      );
      expect(
        reason('error: unable to create file a/b: Filename too long'),
        'A file path is too long for Windows.',
      );
      expect(
        reason('SSL certificate problem: unable to get local issuer'),
        contains('antivirus web protection'),
      );
      expect(
        reason('fatal: write error: No space left on device'),
        'The disk is full.',
      );
      expect(reason('fatal: something new'), isNull);
      expect(
        ManagedFlutterSdks.cloneFailure('Filename too long', '1.0.0').retry,
        isFalse,
      );
    });

    test('toolSaid keeps fatal and error lines, else the last line', () {
      expect(
        ManagedFlutterSdks.toolSaid(
          'command failed (128): git clone\nCloning...\nfatal: a\nfatal: a',
        ),
        'fatal: a',
      );
      expect(
        ManagedFlutterSdks.toolSaid('command failed (1): x\nlast words'),
        'last words',
      );
      expect(
        ManagedFlutterSdks.toolSaid('command failed (128): git clone'),
        'command failed (128): git clone',
      );
    });
  });

  group('AC-014-4 config', () {
    ManagedFlutterSdks sdks() => ManagedFlutterSdks(
      fileSystem: const SdkTestFileSystem(),
      paths: p.windows,
      root: r'C:\Users\u\AppData\Roaming\xcross\flutter-sdks',
      flutterExecutableName: 'flutter.bat',
      log: Log(output: TestLogOutput()),
      runTool: (_, _, {required label, workingDirectory}) async {},
    );

    test('selecting an SDK keeps every other setting; Windows paths are '
        'quoted', () {
      final original = XcrossConfig(
        roots: const XcrossConfigRoots(darwinSdk: r'C:\sdk'),
        environment: const {'CC': r'C:\llvm\clang.exe'},
        tools: const {'xcrun': r'C:\x\xcrun.exe'},
        iosGenSnapshot: const {
          '3.44.0': XcrossIosGenSnapshotPin(release: r'C:\g\gen_snapshot.exe'),
        },
      );
      const root = r'C:\Users\u\AppData\Roaming\xcross\flutter-sdks\3.47.6';
      final updated = sdks().withSdk(original, root);
      expect(updated.roots.flutterSdk, root);
      expect(updated.roots.darwinSdk, r'C:\sdk');
      expect(
        updated.tool('flutter'),
        p.windows.join(root, 'bin', 'flutter.bat'),
      );
      expect(updated.tool('xcrun'), r'C:\x\xcrun.exe');
      expect(updated.environment['CC'], r'C:\llvm\clang.exe');
      expect(updated.iosGenSnapshot.keys, ['3.44.0']);
      final yaml = updated.toYaml();
      expect(yaml, contains('flutterSdk: ${jsonEncode(root)}'));
      expect(yaml, contains(r'C:\\Users\\u'));
    });

    test('reset removes only the SDK; an otherwise empty config goes', () {
      final only = sdks().withSdk(null, r'C:\f\3.47.6');
      expect(ManagedFlutterSdks.withoutSdk(only), isNull);
      final mixed = sdks().withSdk(
        XcrossConfig(roots: const XcrossConfigRoots(darwinSdk: r'C:\sdk')),
        r'C:\f\3.47.6',
      );
      final cleared = ManagedFlutterSdks.withoutSdk(mixed)!;
      expect(cleared.roots.flutterSdk, isNull);
      expect(cleared.tool('flutter'), isNull);
      expect(cleared.roots.darwinSdk, r'C:\sdk');
    });
  });

  group('AC-014-5 sdk commands', () {
    late List<String> written;
    late List<String> toolCalls;
    late XcrossConfig? savedConfig;
    late String? deleted;
    late ActiveFlutter active;
    XcrossConfig? existing;

    FlutterSdkServices services({bool interactive = false}) {
      final sdks = ManagedFlutterSdks(
        fileSystem: const SdkTestFileSystem(),
        paths: p.context,
        root: p.join(temp.path, 'flutter-sdks'),
        flutterExecutableName: 'flutter.bat',
        log: Log(output: TestLogOutput()),
        runTool:
            (executable, arguments, {required label, workingDirectory}) async {
              toolCalls.add(label);
              if (label == 'git') {
                File(
                  p.join(arguments.last, 'bin', 'flutter'),
                ).createSync(recursive: true);
              } else {
                Directory(
                  p.join(workingDirectory!, 'bin', 'cache', 'dart-sdk'),
                ).createSync(recursive: true);
                File(
                  p.join(
                    workingDirectory,
                    'bin',
                    'cache',
                    'flutter.version.json',
                  ),
                ).writeAsStringSync('{}');
              }
            },
      );
      return FlutterSdkServices(
        log: Log(output: TestLogOutput()),
        write: written.add,
        sdks: sdks,
        platform: _platform,
        catalog: ({refresh = false}) async => CompilerCatalog(
          versions: const ['3.47.6', '3.44.9'],
          fetchedAt: DateTime.utc(2026, 11, 2),
        ),
        activeFlutter: () async => active,
        loadConfig: () async => (
          config: existing,
          path: existing == null ? null : p.join(temp.path, 'config.yaml'),
        ),
        saveConfig: (config) async {
          savedConfig = config;
          return p.join(temp.path, 'config.yaml');
        },
        deleteConfig: (path) async => deleted = path,
        locateGit: () async => 'git',
        confirm: interactive ? (_) async => true : null,
      );
    }

    CommandRunner<void> runner(FlutterSdkServices s) =>
        CommandRunner<void>('xcross', 'test')..addCommand(FlutterSdkCommand(s));

    setUp(() {
      written = [];
      toolCalls = [];
      savedConfig = null;
      deleted = null;
      existing = null;
      active = const ActiveFlutter(
        root: r'D:\flutter',
        version: '3.47.8',
        compiler: CompilerStatus.missing,
      );
    });

    test('list --json names the active Flutter and the suggestion', () async {
      await runner(services()).run(['sdk', 'list', '--json']);
      final json = jsonDecode(written.single) as Map<String, Object?>;
      expect(json['type'], 'flutter_sdks');
      expect(json['suggested'], '3.47.6');
      expect((json['active']! as Map)['compiler'], 'missing');
      expect(json['available'], ['3.47.6', '3.44.9']);
    });

    test('auto installs and selects the suggested version', () async {
      await runner(services()).run(['sdk', 'auto', '--yes']);
      expect(toolCalls, ['git', 'flutter']);
      expect(
        savedConfig!.roots.flutterSdk,
        p.join(temp.path, 'flutter-sdks', '3.47.6'),
      );
      expect(written.join(), contains('your Flutter 3.47.8'));
    });

    test('auto does nothing when the active Flutter has a compiler', () async {
      active = const ActiveFlutter(
        root: r'D:\flutter',
        version: '3.47.6',
        compiler: CompilerStatus.available,
      );
      await runner(services()).run(['sdk', 'auto', '--yes']);
      expect(toolCalls, isEmpty);
      expect(savedConfig, isNull);
    });

    test('auto asks first; without a terminal it needs --yes', () async {
      await expectLater(
        runner(services()).run(['sdk', 'auto']),
        throwsA(isA<UsageException>()),
      );
      expect(toolCalls, isEmpty);
      await runner(services(interactive: true)).run(['sdk', 'auto']);
      expect(toolCalls, ['git', 'flutter']);
    });

    test(
      'install refuses versions without a compiler unless --force',
      () async {
        await expectLater(
          runner(services()).run(['sdk', 'install', '3.47.8']),
          throwsA(
            isA<XcrossError>().having(
              (e) => e.message,
              'message',
              startsWith('[toolchain.flutter_sdk_version_unavailable]'),
            ),
          ),
        );
        await runner(services()).run(['sdk', 'install', '3.47.8', '--force']);
        expect(toolCalls, ['git', 'flutter']);
      },
    );

    test('reset removes a config that only selected the SDK', () async {
      existing = XcrossConfig(
        roots: const XcrossConfigRoots(flutterSdk: r'C:\f\3.47.6'),
        tools: const {'flutter': r'C:\f\3.47.6\bin\flutter.bat'},
      );
      await runner(services()).run(['sdk', 'reset']);
      expect(deleted, p.join(temp.path, 'config.yaml'));
      expect(savedConfig, isNull);
    });

    test('use rejects a folder without bin/flutter', () async {
      await expectLater(
        runner(services()).run(['sdk', 'use', temp.path]),
        throwsA(isA<XcrossError>()),
      );
    });
  });
}

/// dart:io-backed host file system for these tests.
@internal
final class SdkTestFileSystem implements HostFileSystemInterface {
  const SdkTestFileSystem();

  @override
  File file(String path) => File(path);
  @override
  Directory directory(String path) => Directory(path);
  @override
  Link link(String path) => Link(path);
  @override
  void makeExecutable(String path) {}
  @override
  void setPermissions(String path, int mode) {}
  @override
  Future<void> createArchiveLink(String destination, String target) =>
      Link(destination).create(target);
}
