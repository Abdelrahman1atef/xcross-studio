import 'dart:ffi';
import 'dart:io';

import 'package:apple_developer_kit/shared/appstoreconnect/asc_config.dart';
import 'package:args/command_runner.dart';
import 'package:cli_kit/host/linux/linux_host.dart';
import 'package:cli_kit/host/windows/windows_host.dart';
import 'package:cli_kit/shared/logging/logging.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:dart_mobile_device/shared/diagnostics/device_probe.dart';
import 'package:darwin_sdk_kit/target/iphone/iphone_build_platform.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/composition/cli/doctor_sections.dart';
import 'package:xcross/src/composition/cli/runner.dart';
import 'package:xcross/src/shared/cli/basic/doctor_command.dart';
import 'package:xcross/src/shared/cli/basic/doctor_environment_checks.dart';
import 'package:xcross/src/shared/cli/basic/doctor_models.dart';
import 'package:xcross/src/shared/config/config.dart';
import 'package:xcross/src/shared/errors/errors.dart';
import 'package:xcross/src/shared/runtime/xcross_runtime.dart';

import '../log_fixture.dart';
import 'auth_fixture.dart';
import 'doctor_environment_checks_test.dart';
import 'runtime_fixture.dart';

void main() {
  for (final style in [p.Style.posix, p.Style.windows]) {
    test(
      'doctor credential detection uses selected namespace on $style',
      () async {
        final fixture = AuthNamespaceFixture(style: style);
        addTearDown(fixture.dispose);
        final runtime = testRuntime();
        final diagnostics = DoctorNamespaceDiagnostics();
        final checks = DoctorEnvironmentChecks(
          hostPlatform: runtime.host,
          buildPlatform: const IPhoneBuildPlatform(),
          appleHostServices: fixture.services,
          runner: runtime.runner,
          repository: runtime.sdkRepository,
          toolchain: runtime.darwinToolchain,
          deviceDiagnostics: diagnostics,
          sdkMismatch: (_) async => null,
          sdkToolchainIdentity: () async => {},
          createAppleHttpClient: () =>
              throw StateError('Unexpected authentication HTTP'),
        );
        final results = await checks.deployment();
        expect(results.first.status, DoctorStatus.success);
        expect(
          results
              .firstWhere((result) => result.name == 'Authentication')
              .message,
          contains('No credentials found'),
        );
        expect(
          fixture.fileSystem.acquisitions,
          contains(
            AscCredentials.defaultConfigPath(hostServices: fixture.services),
          ),
        );
        expect(diagnostics.discovered, isTrue);
      },
    );
  }

  // studio: 018 — App Store signing is reported on its own: an Apple ID or an
  // individual key signs for devices but not for the App Store.
  group('App Store signing', () {
    Future<DoctorCheck> appStoreSigning(String? saved) async {
      final fixture = AuthNamespaceFixture(style: p.Style.posix);
      addTearDown(fixture.dispose);
      if (saved != null) {
        fixture.fileSystem.file(
            AscCredentials.defaultConfigPath(hostServices: fixture.services),
          )
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(saved);
      }
      final runtime = testRuntime();
      final checks = DoctorEnvironmentChecks(
        hostPlatform: runtime.host,
        buildPlatform: const IPhoneBuildPlatform(),
        appleHostServices: fixture.services,
        runner: runtime.runner,
        repository: runtime.sdkRepository,
        toolchain: runtime.darwinToolchain,
        deviceDiagnostics: DoctorNamespaceDiagnostics(),
        sdkMismatch: (_) async => null,
        sdkToolchainIdentity: () async => {},
        createAppleHttpClient: () =>
            throw StateError('No App Store Connect in this test'),
      );
      final results = await checks.deployment();
      expect(results.map((r) => r.name).take(3), [
        'Device tools',
        'Authentication',
        'App Store signing',
      ]);
      return results.singleWhere(
        (r) => r.name == DoctorEnvironmentChecks.appStoreSigningName,
      );
    }

    test('no saved key: a warning naming the team key', () async {
      final check = await appStoreSigning(null);
      expect(check.status, DoctorStatus.warning);
      expect(check.message, contains('No App Store Connect team key'));
      expect(check.message, contains('Admin or App Manager'));
    });

    test('an individual key: a warning', () async {
      final check = await appStoreSigning(
        '{"keyId": "KEY", "privateKeyPath": "/k.p8", '
        '"keyType": "individual"}',
      );
      expect(check.status, DoctorStatus.warning);
      expect(check.message, contains('individual key'));
      expect(check.message, contains('Team Keys'));
      // The key ID is not printed.
      expect(check.message, isNot(contains('KEY ')));
    });

    test('a team key: success, without asking Apple', () async {
      final check = await appStoreSigning(
        '{"issuerId": "ISSUER", "keyId": "KEY", "privateKeyPath": "/k.p8"}',
      );
      expect(check.status, DoctorStatus.success);
      expect(check.message, contains('team key is saved'));
    });
  });

  test('doctor is a Flutter and Compose subcommand, not a top-level one', () {
    final runner = XcrossCli.buildRunner(
      testApplication(),
      configTerminal: TestTerminal(),
    );

    expect(runner.commands.keys, isNot(contains('doctor')));
    expect(runner.commands['flutter']!.subcommands.keys, contains('doctor'));
    expect(runner.commands['compose']!.subcommands.keys, contains('doctor'));
    expect(
      runner.commands['flutter']!.subcommands['doctor']!.description,
      contains('Flutter'),
    );
    expect(
      runner.commands['compose']!.subcommands['doctor']!.description,
      contains('Compose'),
    );
  });

  test('each framework examines only its own sections', () {
    final sections = doctorSections(testRuntime(), '/project');

    expect(sections.flutter.map((section) => section.title), [
      'Flutter project',
      'iOS toolchain',
      'Deployment',
    ]);
    expect(sections.compose.map((section) => section.title), [
      'Compose project',
      'Compose toolchain',
      'Deployment',
    ]);
  });

  test('section header carries the worst status of its checks', () {
    final log = ansiLog();
    expect(
      DoctorCommand.formatSection('iOS toolchain', const [
        DoctorCheck.success('swift', 'Found', path: '/bin/swift'),
        DoctorCheck.warning('iOS linker', 'old'),
      ], log: log),
      '\u001b[33m[!]\u001b[0m \u001b[1miOS toolchain\u001b[0m\n'
      '    \u001b[32m✓\u001b[0m swift       \u001b[2m/bin/swift\u001b[22m\n'
      '    \u001b[33m!\u001b[0m iOS linker  old',
    );
    expect(
      DoctorCommand.formatSection('Deployment', const [
        DoctorCheck.failure('Device tools', 'missing'),
        DoctorCheck.warning('Device', 'none'),
      ], log: log),
      startsWith('\u001b[31m[✗]\u001b[0m'),
    );
  });

  test('aligns check names and dims locations below messages', () {
    expect(
      DoctorCommand.formatSection('iOS toolchain', const [
        DoctorCheck.success('swift', 'Found', path: '/bin/swift'),
        DoctorCheck.success('Darwin SDK', 'Installed', path: '/sdk'),
        DoctorCheck.failure('Swift version', 'Too old.\nUpgrade Swift.'),
      ], log: testLog()),
      '[✗] iOS toolchain\n'
      '    ✓ swift          /bin/swift\n'
      '    ✓ Darwin SDK     Installed\n'
      '                     /sdk\n'
      '    ✗ Swift version  Too old.\n'
      '                     Upgrade Swift.',
    );
  });

  test('locations are shown without the Windows long-path prefix', () {
    expect(
      DoctorCommand.formatCheck(
        const DoctorCheck.success(
          'Flutter SDK',
          'Found',
          path: r'\\?\D:\Programing\flutter',
        ),
        log: testLog(),
      ),
      r'    ✓ Flutter SDK  D:\Programing\flutter',
    );
    expect(
      const DoctorCheck.success('x', 'y', path: r'\\?\UNC\srv\f').shownPath,
      r'\\srv\f',
    );
  });

  test('warnings do not fail doctor', () async {
    final lines = <String>[];
    final runner = doctorRunner(lines, [
      DoctorSection(
        'Flutter project',
        () async => const [DoctorCheck.warning('Project', 'No pubspec.yaml.')],
      ),
    ]);

    await runner.run(['doctor']);

    expect(lines, [
      '[!] Flutter project\n    ! Project  No pubspec.yaml.',
      '',
      'Doctor found 1 warning.',
    ]);
  });

  test('a healthy doctor reports no issues', () async {
    final lines = <String>[];
    final runner = doctorRunner(lines, [
      DoctorSection(
        'Compose project',
        () async => const [DoctorCheck.success('Project', 'composeApp')],
      ),
    ]);

    await runner.run(['doctor']);

    expect(lines.last, 'No issues found.');
  });

  test('failures are all reported across sections and fail doctor', () async {
    final lines = <String>[];
    final runner = doctorRunner(lines, [
      DoctorSection(
        'iOS toolchain',
        () async => const [
          DoctorCheck.failure('swift', 'Not found.'),
          DoctorCheck.success('Darwin SDK', 'Installed'),
        ],
      ),
      DoctorSection('Deployment', () => throw StateError('probe broke')),
      DoctorSection(
        'Flutter project',
        () async => const [DoctorCheck.warning('Project', 'none')],
      ),
    ]);

    await expectLater(
      runner.run(['doctor']),
      throwsA(
        isA<XcrossError>().having(
          (error) => error.message,
          'message',
          'Doctor found 2 failures and 1 warning.',
        ),
      ),
    );
    expect(lines, [
      [
        '[✗] iOS toolchain',
        '    ✗ swift       Not found.',
        '    ✓ Darwin SDK  Installed',
      ].join('\n'),
      '',
      '[✗] Deployment\n    ✗ Deployment  Bad state: probe broke',
      '',
      '[!] Flutter project\n    ! Project  none',
      '',
    ]);
  });

  test(
    'Flutter doctor outside a project still checks the Flutter SDK',
    () async {
      final checks = await doctorSections(
        testRuntime(
          configuration: XcrossConfig(),
          fileSystem: logicalProjectFiles(),
        ),
        '/empty',
      ).flutterProject();

      expect(checks.map((check) => (check.name, check.status)), [
        ('Project', DoctorStatus.warning),
        ('Flutter SDK', DoctorStatus.failure),
      ]);
    },
  );

  test('Compose doctor outside a project is a warning', () async {
    final checks = await doctorSections(
      testRuntime(fileSystem: logicalProjectFiles()),
      '/empty',
    ).composeProject();

    expect(checks.single.status, DoctorStatus.warning);
    expect(checks.single.message, contains('settings.gradle'));
  });

  test('Windows host checks resolve PATHEXT executable names', () async {
    final fixture = DoctorServiceFixture(
      baseHost: WindowsHost(
        currentDirectory: r'C:\',
        environment: const {'USERPROFILE': r'C:\Users\Fixture'},
      ),
      abi: Abi.windowsX64,
    );
    addTearDown(fixture.dispose);
    fixture.lookup.tools.addAll({
      'swift': r'C:\Tools\swift.exe',
      'clang++': r'C:\Tools\clang++.exe',
      'llvm-ar': r'C:\Tools\llvm-ar.exe',
      'clang': r'C:\Program Files\LLVM\bin\clang.exe',
      'ld64.lld': r'C:\Program Files\LLVM\bin\ld64.lld.exe',
    });
    final checks = await fixture.checks.flutterToolchain();
    final requested = fixture.lookup.requests
        .take(3)
        .map((request) => request.$1);

    expect(requested, ['swift', 'clang++', 'llvm-ar']);
    expect(checks.first.status, DoctorStatus.success);
    expect(
      checks.firstWhere((check) => check.name == 'iOS clang').path,
      r'C:\Program Files\LLVM\bin\clang.exe',
    );
    expect(
      checks.firstWhere((check) => check.name == 'iOS linker').path,
      r'C:\Program Files\LLVM\bin\ld64.lld.exe',
    );
    expect(checks.where((check) => check.path != null), hasLength(6));
  });

  test('host checks report an unusable iOS compiler clearly', () async {
    final fixture = DoctorServiceFixture(
      baseHost: WindowsHost(
        currentDirectory: r'C:\',
        environment: const {'USERPROFILE': r'C:\Users\Fixture'},
      ),
      abi: Abi.windowsX64,
    );
    addTearDown(fixture.dispose);
    fixture.processes.clangFailure = 'No clang that can target iOS.';
    final checks = await fixture.checks.flutterToolchain();

    expect(
      checks.firstWhere((check) => check.name == 'iOS clang'),
      isA<DoctorCheck>()
          .having((check) => check.status, 'status', DoctorStatus.failure)
          .having(
            (check) => check.message,
            'message',
            contains('No clang that can target iOS.'),
          ),
    );
  });

  test(
    'host checks warn about a linker with the selector-stub defect',
    () async {
      final fixture = DoctorServiceFixture(
        baseHost: LinuxHost(
          currentDirectory: '/fixture',
          environment: const {'HOME': '/fixture'},
        ),
      );
      addTearDown(fixture.dispose);
      fixture.lookup.tools['ld64.lld'] = '/fixture/ld64.lld';
      fixture.processes.linkerVersion = 'LLD 18.1';
      final checks = await fixture.checks.flutterToolchain();

      expect(
        checks.firstWhere((check) => check.name == 'iOS linker'),
        isA<DoctorCheck>()
            .having((check) => check.status, 'status', DoctorStatus.warning)
            .having((check) => check.path, 'path', '/fixture/ld64.lld')
            .having((check) => check.message, 'message', contains('18.1')),
      );
    },
  );

  test('host checks report the linker version when it is healthy', () async {
    final fixture = DoctorServiceFixture(
      baseHost: LinuxHost(
        currentDirectory: '/fixture',
        environment: const {'HOME': '/fixture'},
      ),
    );
    addTearDown(fixture.dispose);
    final checks = await fixture.checks.flutterToolchain();

    expect(
      checks.firstWhere((check) => check.name == 'iOS linker'),
      isA<DoctorCheck>()
          .having((check) => check.status, 'status', DoctorStatus.success)
          .having((check) => check.message, 'message', contains('LLD 19.1')),
    );
  });

  test('Flutter project reports only configured SDK resolution', () async {
    final files = logicalProjectFiles();
    files.file('/project/pubspec.yaml')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('name: demo');
    files.file('/project/lib/main.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('');

    final checks = await doctorSections(
      testRuntime(configuration: XcrossConfig(), fileSystem: files),
      '/project',
    ).flutterProject();
    final flutterSdkChecks = checks.where(
      (check) => check.name == 'Flutter SDK',
    );

    expect(flutterSdkChecks, hasLength(1));
    expect(flutterSdkChecks.single.status, DoctorStatus.failure);
    expect(flutterSdkChecks.single.message, contains('not configured'));
  });

  test(
    'Flutter package diagnostics use the selected filesystem resolver',
    () async {
      final files = logicalProjectFiles();
      files.file('/project/pubspec.yaml')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: demo');
      files.file('/project/.dart_tool/package_config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"configVersion":2,"packages":[]}');
      final runtime = testRuntime(
        configuration: XcrossConfig(),
        fileSystem: files,
      );
      final inspector = doctorSections(runtime, '/project');
      expect(
        inspector.packageConfigs.fileSystem,
        same(runtime.host.fileSystem),
      );
      expect(inspector.packageConfigs.paths, same(runtime.host.paths.context));
      final checks = await inspector.flutterProject();
      final packages = checks.singleWhere((check) => check.name == 'Packages');
      expect(packages.status, DoctorStatus.success);
      expect(packages.path, '/project/.dart_tool/package_config.json');
    },
  );

  test(
    'AC-032-12 the iOS project check says what a fresh app still needs',
    () async {
      Future<DoctorCheck> iosCheck(
        void Function(DoctorServiceFileSystem) setup,
      ) async {
        final files = logicalProjectFiles();
        files.file('/project/pubspec.yaml')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('name: demo');
        setup(files);
        final checks = await doctorSections(
          testRuntime(configuration: XcrossConfig(), fileSystem: files),
          '/project',
        ).flutterProject();
        return checks.singleWhere((check) => check.name == 'iOS project');
      }

      // No ios/ folder: the fix is flutter create, not a Mac.
      final none = await iosCheck((_) {});
      expect(none.status, DoctorStatus.warning);
      expect(none.message, contains('flutter create --platforms=ios'));

      // An ios/ project but no plugin list yet (pub get has not run).
      final noList = await iosCheck(
        (files) => files.file('/project/ios/Runner/Info.plist')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('<plist/>'),
      );
      expect(noList.status, DoctorStatus.warning);
      expect(noList.message, contains('xcross ios prepare'));

      // Both there: ready, with no Podfile, Pods or workspace.
      final ready = await iosCheck((files) {
        files.file('/project/ios/Runner/Info.plist')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('<plist/>');
        files
            .file('/project/.flutter-plugins-dependencies')
            .writeAsStringSync('{}');
      });
      expect(ready.status, DoctorStatus.success);
      expect(ready.message, contains('No pod install needed'));
    },
  );

  test('AC-005-1 device checks reject devices older than iOS 15', () async {
    final fixture = DoctorServiceFixture(
      baseHost: LinuxHost(
        currentDirectory: '/fixture',
        environment: const {'HOME': '/fixture'},
      ),
    );
    addTearDown(fixture.dispose);
    fixture.devices.versions.addAll({'old': 14, 'new': 16});
    final checks = await fixture.checks.devices(const [
      Device(name: 'Old iPhone', udid: 'old', type: ConnectionType.usb),
      Device(name: 'New iPhone', udid: 'new', type: ConnectionType.usb),
    ]);

    expect(checks.map((check) => check.status), [
      DoctorStatus.failure,
      DoctorStatus.success,
    ]);
  });
}

@internal
DoctorSections<T> doctorSections<T extends PlatformHostInterface>(
  XcrossRuntime<T> runtime,
  String projectRoot,
) => DoctorSections(
  runtime,
  projectRoot: projectRoot,
  environment: DoctorEnvironmentChecks(
    hostPlatform: runtime.host,
    buildPlatform: const IPhoneBuildPlatform(),
    appleHostServices: runtime.appleHostServices,
    runner: runtime.runner,
    repository: runtime.sdkRepository,
    toolchain: runtime.darwinToolchain,
    deviceDiagnostics: DoctorNamespaceDiagnostics(),
    sdkMismatch: (_) async => null,
    sdkToolchainIdentity: () async => {},
    createAppleHttpClient: () => throw StateError('Unexpected HTTP'),
  ),
);

@internal
CommandRunner<void> doctorRunner(
  List<String> lines,
  List<DoctorSection> sections,
) => CommandRunner<void>('xcross', 'test')
  ..addCommand(
    DoctorCommand(
      framework: 'Flutter',
      sections: sections,
      log: testLog(),
      writeLine: lines.add,
    ),
  );

@internal
Log ansiLog() => Log(output: AnsiLogOutput());

@internal
final class AnsiLogOutput implements LogOutput {
  @override
  bool get supportsAnsi => true;
  @override
  int get terminalColumns => 80;
  @override
  void stdout(String message) {}
  @override
  void stderr(String message) {}
  @override
  void write(String message) {}
}

@internal
final class DoctorNamespaceDiagnostics implements DeviceDiagnostics {
  bool discovered = false;
  @override
  Future<String> resolveExecutable() async => '/selected/pymd';
  @override
  Future<List<Device>> devices() async {
    discovered = true;
    return [];
  }

  @override
  Future<int?> osMajorVersion(Device device) async => 17;
}

@internal
DoctorServiceFileSystem logicalProjectFiles() {
  final root = Directory.systemTemp.createTempSync('xcross-doctor-project-');
  addTearDown(() => root.deleteSync(recursive: true));
  return DoctorServiceFileSystem(p.posix, '/', root.path);
}
