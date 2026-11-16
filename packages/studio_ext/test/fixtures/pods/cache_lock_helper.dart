import 'dart:io';

import 'package:studio_ext/shared/pods/pod_cache.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args[0]);
  final key = args[1];
  final label = args[2];
  final cache = PodCache(
    root: root,
    fileFactory: File.new,
    directoryFactory: Directory.new,
    processAlive: (_) => true,
    processId: pid,
  );
  await cache.withLock(key, () async {
    File('${root.path}/entered-$label').writeAsStringSync('yes');
    final release = File('${root.path}/release-$label');
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!release.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Timed out waiting for release');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
}
