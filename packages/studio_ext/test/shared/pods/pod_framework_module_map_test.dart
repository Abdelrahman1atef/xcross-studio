import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:studio_ext/src/shared/pods/pod_framework_module_map.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const moduleMap = PodFrameworkModuleMap(
    directoryFactory: Directory.new,
    fileFactory: File.new,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('modulemap-test-');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'AC-046-8 synthesizes umbrella header modulemap when <Name>.h exists',
    () {
      final framework = Directory(
        path.join(tempDir.path, 'MyFramework.framework'),
      );
      final headers = Directory(path.join(framework.path, 'Headers'))
        ..createSync(recursive: true);
      File(
        path.join(headers.path, 'MyFramework.h'),
      ).writeAsStringSync('// umbrella');
      File(path.join(headers.path, 'Extra.h')).writeAsStringSync('// extra');

      final written = moduleMap.ensureModuleMap(framework);
      expect(written, isNotNull);
      expect(written!.existsSync(), isTrue);

      final content = written.readAsStringSync();
      expect(content, contains('framework module MyFramework {'));
      expect(content, contains('umbrella header "MyFramework.h"'));
      expect(content, contains('export *'));
      expect(content, contains('module * { export * }'));
    },
  );

  test('AC-046-8 lists every header when no umbrella header exists', () {
    final framework = Directory(path.join(tempDir.path, 'HeaderLib.framework'));
    final headers = Directory(path.join(framework.path, 'Headers'))
      ..createSync(recursive: true);
    File(path.join(headers.path, 'Alpha.h')).writeAsStringSync('// alpha');
    File(path.join(headers.path, 'Beta.h')).writeAsStringSync('// beta');

    final written = moduleMap.ensureModuleMap(framework);
    expect(written, isNotNull);

    final content = written!.readAsStringSync();
    expect(content, contains('framework module HeaderLib {'));
    expect(content, contains('header "Alpha.h"'));
    expect(content, contains('header "Beta.h"'));
    expect(content, isNot(contains('umbrella header')));
    expect(content, contains('export *'));
  });

  test('AC-046-8 does not overwrite existing module.modulemap', () {
    final framework = Directory(path.join(tempDir.path, 'Existing.framework'));
    final modules = Directory(path.join(framework.path, 'Modules'))
      ..createSync(recursive: true);
    final existing = File(path.join(modules.path, 'module.modulemap'))
      ..writeAsStringSync('// custom modulemap');

    final written = moduleMap.ensureModuleMap(framework);
    expect(written, isNull);
    expect(existing.readAsStringSync(), '// custom modulemap');
  });
}
