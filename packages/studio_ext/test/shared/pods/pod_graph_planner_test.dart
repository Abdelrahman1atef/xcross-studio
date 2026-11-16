import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:studio_ext/shared/plugins/plugin_command.dart';
import 'package:studio_ext/shared/pods/pod_graph_planner.dart';
import 'package:studio_ext/shared/pods/pods_cdn.dart';
import 'package:test/test.dart';

import '../../support/test_file_system.dart';

void main() {
  late Directory root;
  late PodsCdn cdn;
  late ProjectPlugins plugins;
  var networkCalls = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pod-planner-test-');
    final pluginRoot = Directory(path.join(root.path, 'pub', 'example'));
    await pluginRoot.create(recursive: true);
    await File(
      path.join(pluginRoot.path, 'ios', 'example.podspec'),
    ).create(recursive: true);
    await File(
      path.join(pluginRoot.path, 'ios', 'example.podspec'),
    ).writeAsString('''
Pod::Spec.new do |s|
  s.name = 'example'
  s.dependency 'Flutter'
  s.dependency 'WebRTC-SDK', '= 137.7151.04'
end
''');
    await File(
      path.join(root.path, '.flutter-plugins-dependencies'),
    ).writeAsString(
      jsonEncode({
        'plugins': {
          'ios': [
            {'name': 'example', 'path': pluginRoot.path},
          ],
        },
      }),
    );
    networkCalls = 0;
    cdn = PodsCdn(
      cacheRoot: Directory(path.join(root.path, 'cache')),
      client: MockClient((_) {
        networkCalls++;
        throw StateError('status must not call network');
      }),
      environment: const {},
      fileFactory: File.new,
    );
    plugins = ProjectPlugins(const IoFileSystem(), path.context);
    final index = File(
      path.join(cdn.cacheRoot.path, 'index', '${cdn.shard('WebRTC-SDK')}.txt'),
    );
    await index.create(recursive: true);
    await index.writeAsString('WebRTC-SDK/137.7151.04\n');
    final spec = File(
      path.join(cdn.cacheRoot.path, 'specs', 'WebRTC-SDK', '137.7151.04.json'),
    );
    await spec.create(recursive: true);
    await spec.writeAsString(
      '{"name":"WebRTC-SDK",'
      '"vendored_frameworks":"SDK.xcframework"}',
    );
  });

  tearDown(() async {
    cdn.close();
    await root.delete(recursive: true);
  });

  test('AC-046-8 classifies from cache without network', () async {
    final planner = PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
      enabledKinds: const {'binary'},
    );
    final plan = await planner.plan(root.path, offline: true);
    final pods = plan.byPlugin['example']!;
    expect(pods.map((pod) => pod.classification), ['flutter', 'converted']);
    expect(pods.last.version, '137.7151.04');
    expect(pods.last.source, 'cache');
    expect(networkCalls, 0);
  });

  test('AC-046-24 skip and disabled kind give distinct reasons', () async {
    final disabled = await PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
    ).plan(root.path, offline: true);
    expect(disabled.byPlugin['example']!.last.reason, 'not_yet_supported');
    final skipped = await PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
      enabledKinds: const {'binary'},
      skipped: const {'WebRTC-SDK'},
    ).plan(root.path, offline: true);
    expect(skipped.byPlugin['example']!.last.reason, 'skipped_by_user');
    expect(networkCalls, 0);
  });

  test('AC-046-8 own subspec is not a sibling plugin', () async {
    final podspec = File(
      path.join(root.path, 'pub', 'example', 'ios', 'example.podspec'),
    );
    await podspec.writeAsString('''
Pod::Spec.new do |s|
  s.name = 'example'
  s.dependency 'example/ObjC'
end
''');
    final plan = await PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
    ).plan(root.path, offline: true);
    expect(plan.byPlugin['example']!.single.classification, 'own_subspec');
    expect(networkCalls, 0);
  });

  test('AC-046-23 scans a changed override manifest on every plan', () async {
    final manifest = File(
      path.join(root.path, 'xcross_overrides', 'example', 'Package.swift'),
    );
    await manifest.create(recursive: true);
    await manifest.writeAsString(
      '.package(name: "pod-ObjectBox", path: "../pod-ObjectBox")',
    );
    final planner = PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
      enabledKinds: const {'binary'},
    );
    var pods = (await planner.plan(
      root.path,
      offline: true,
    )).byPlugin['example']!;
    expect(pods.where((pod) => pod.name == 'ObjectBox'), hasLength(1));
    await manifest.writeAsString('// no pod dependency');
    pods = (await planner.plan(root.path, offline: true)).byPlugin['example']!;
    expect(pods.where((pod) => pod.name == 'ObjectBox'), isEmpty);
    expect(networkCalls, 0);
  });

  test(
    'AC-046-23 scans a plugin-shipped Swift manifest for pod aliases',
    () async {
      final manifest = File(
        path.join(
          root.path,
          'pub',
          'example',
          'ios',
          'example',
          'Package.swift',
        ),
      );
      await manifest.create(recursive: true);
      await manifest.writeAsString(
        '.package(name: "pod-ObjectBox", path: "../pod-ObjectBox")',
      );
      final plan = await PodGraphPlanner(
        plugins: plugins,
        cdn: cdn,
        converterEnabled: true,
      ).plan(root.path, offline: true);
      expect(plan.byPlugin['example']!.single.name, 'ObjectBox');
      expect(networkCalls, 0);
    },
  );

  test('AC-046-3 shared pod uses one version or reports conflict', () async {
    final second = Directory(path.join(root.path, 'pub', 'second'));
    await second.create(recursive: true);
    await File(
      path.join(second.path, 'ios', 'second.podspec'),
    ).create(recursive: true);
    await File(path.join(second.path, 'ios', 'second.podspec')).writeAsString(
      '''
Pod::Spec.new do |s|
  s.name = 'second'
  s.dependency 'WebRTC-SDK', '< 138'
end
''',
    );
    await File(
      path.join(root.path, '.flutter-plugins-dependencies'),
    ).writeAsString(
      jsonEncode({
        'plugins': {
          'ios': [
            {'name': 'example', 'path': path.join(root.path, 'pub', 'example')},
            {'name': 'second', 'path': second.path},
          ],
        },
      }),
    );
    final index = File(
      path.join(cdn.cacheRoot.path, 'index', '${cdn.shard('WebRTC-SDK')}.txt'),
    );
    await index.writeAsString('WebRTC-SDK/137.7151.04/138.0.0\n');
    final plan = await PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
      enabledKinds: const {'binary'},
    ).plan(root.path, offline: true);
    expect(plan.byPlugin['example']!.last.version, '137.7151.04');
    expect(plan.byPlugin['second']!.single.version, '137.7151.04');

    await File(path.join(second.path, 'ios', 'second.podspec')).writeAsString(
      '''
Pod::Spec.new do |s|
  s.name = 'second'
  s.dependency 'WebRTC-SDK', '>= 138'
end
''',
    );
    final conflict = await PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
    ).plan(root.path, offline: true);
    expect(conflict.byPlugin['example']!.last.reason, 'resolve_conflict');
    expect(conflict.byPlugin['second']!.single.reason, 'resolve_conflict');
    expect(networkCalls, 0);
  });

  test('AC-046-8 classifies source files in the selected subspec', () async {
    final podspec = File(
      path.join(root.path, 'pub', 'example', 'ios', 'example.podspec'),
    );
    await podspec.writeAsString('''
Pod::Spec.new do |s|
  s.name = 'example'
  s.dependency 'goSellSDK/Core', '= 2.3.49'
end
''');
    final index = File(
      path.join(cdn.cacheRoot.path, 'index', '${cdn.shard('goSellSDK')}.txt'),
    );
    await index.create(recursive: true);
    await index.writeAsString('goSellSDK/2.3.49\n');
    final spec = File(
      path.join(cdn.cacheRoot.path, 'specs', 'goSellSDK', '2.3.49.json'),
    );
    await spec.create(recursive: true);
    await spec.writeAsString('''
{"name":"goSellSDK","default_subspecs":"Core","subspecs":[
{"name":"Core","source_files":"Core/**/*.swift"},
{"name":"Optional","source_files":"Optional/**/*.m"}]}
''');
    final plan = await PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
      enabledKinds: const {'swift'},
    ).plan(root.path, offline: true);
    final pod = plan.byPlugin['example']!.single;
    expect(pod.kind, 'swift');
    expect(pod.classification, 'converted');
    expect(networkCalls, 0);

    await podspec.writeAsString('''
Pod::Spec.new do |s|
  s.name = 'example'
  s.dependency 'goSellSDK/Optional', '= 2.3.49'
end
''');
    final optional = await PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
      enabledKinds: const {'objc'},
    ).plan(root.path, offline: true);
    expect(optional.byPlugin['example']!.single.kind, 'objc');
    expect(networkCalls, 0);
  });

  test('AC-046-8 wildcard source is ObjC; vendored headers are binary', () async {
    final podspec = File(
      path.join(root.path, 'pub', 'example', 'ios', 'example.podspec'),
    );
    Future<String?> classify(String name, String version, String json) async {
      await podspec.writeAsString('''
Pod::Spec.new do |s|
  s.name = 'example'
  s.dependency '$name', '= $version'
end
''');
      final index = File(
        path.join(cdn.cacheRoot.path, 'index', '${cdn.shard(name)}.txt'),
      );
      await index.create(recursive: true);
      await index.writeAsString('$name/$version\n');
      final spec = File(
        path.join(cdn.cacheRoot.path, 'specs', name, '$version.json'),
      );
      await spec.create(recursive: true);
      await spec.writeAsString(json);
      final plan = await PodGraphPlanner(
        plugins: plugins,
        cdn: cdn,
        converterEnabled: true,
      ).plan(root.path, offline: true);
      return plan.byPlugin['example']!.single.kind;
    }

    expect(
      await classify(
        'GoogleDataTransport',
        '10.1.1',
        await File(
          'test/fixtures/pods/mlkit/GoogleDataTransport-10.1.1.json',
        ).readAsString(),
      ),
      'objc',
    );
    expect(
      await classify(
        'MyFatoorah',
        '2.0.164',
        '{"source_files":"SDK/**/*.h","vendored_frameworks":"SDK.xcframework"}',
      ),
      'binary',
    );
    expect(networkCalls, 0);
  });

  test('AC-046-8 plugin status JSON gains pods without network', () async {
    final planner = PodGraphPlanner(
      plugins: plugins,
      cdn: cdn,
      converterEnabled: true,
      enabledKinds: const {'binary'},
    );
    final output = <String>[];
    final runner = CommandRunner<void>('xcross', 'test')
      ..addCommand(
        PluginCommand(
          fileSystem: const IoFileSystem(),
          paths: path.context,
          write: output.add,
          podPlanner: planner,
        ),
      );
    await runner.run(['plugin', 'status', '--project', root.path, '--json']);
    final json = jsonDecode(output.single) as Map<String, dynamic>;
    final status = (json['plugins'] as List).single as Map<String, dynamic>;
    final pods = (status['pods'] as List).cast<Map<String, dynamic>>();
    expect(pods, hasLength(2));
    expect(pods.last['class'], 'converted');
    expect(networkCalls, 0);
  });
}
