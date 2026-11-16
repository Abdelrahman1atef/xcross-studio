import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:studio_ext/shared/pods/cache_pods_command.dart';
import 'package:studio_ext/shared/pods/pod_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late PodCache cache;
  late List<String> output;
  late CommandRunner<void> runner;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cache-pods-command-');
    cache = PodCache(
      root: root,
      fileFactory: File.new,
      directoryFactory: Directory.new,
      processAlive: (_) => true,
      processId: 42,
    );
    output = [];
    runner = CommandRunner<void>('xcross cache', 'cache')
      ..addCommand(CachePodsCommand(cache: cache, write: output.add));
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'AC-046-28 cache pods lists entries and clears on explicit flag',
    () async {
      final key = cache.key12('pod');
      await cache.package('A', '1.0', key).create(recursive: true);
      await runner.run(['pods']);
      expect(output.single, contains('A'));
      output.clear();
      await runner.run(['pods', '--clear']);
      expect(cache.listEntries(), isEmpty);
      expect(output.single, 'Cleared the pod cache.');
    },
  );
}
