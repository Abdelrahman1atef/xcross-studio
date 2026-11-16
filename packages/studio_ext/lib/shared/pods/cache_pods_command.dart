import 'package:args/command_runner.dart';
import 'package:studio_ext/shared/pods/pod_cache.dart';

/// Lists or clears the CocoaPods conversion cache.
final class CachePodsCommand extends Command<void> {
  CachePodsCommand({required this.cache, required this.write}) {
    argParser.addFlag(
      'clear',
      negatable: false,
      help: 'Delete cached pod specs, sources, and generated packages.',
    );
  }

  final PodCache cache;
  final void Function(String) write;

  @override
  String get name => 'pods';

  @override
  String get description =>
      'List or clear cached CocoaPods sources and packages.';

  @override
  Future<void> run() async {
    if (argResults?['clear'] == true) {
      await cache.clear(confirmed: true);
      write('Cleared the pod cache.');
      return;
    }
    final entries = cache.listEntries();
    if (entries.isEmpty) {
      write('No cached pods.');
      return;
    }
    for (final entry in entries) {
      write(entry);
    }
  }
}
