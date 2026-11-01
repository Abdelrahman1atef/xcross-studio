import 'dart:convert';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'package:studio_ext/src/target/iphone/device/crash_reports.dart';
import 'package:studio_ext/src/target/iphone/device/device_codes.dart';
import 'package:studio_ext/target/iphone/device/device_log_backend.dart';

/// Shared helpers for the crash subcommands.
@internal
final class CrashTools {
  CrashTools({
    required this.backend,
    required this.fileSystem,
    required this.paths,
    required this.cacheRoot,
    required this.writeBytes,
  });

  final DeviceLogBackend backend;
  final HostFileSystemInterface fileSystem;
  final p.Context paths;
  final String cacheRoot;
  final void Function(List<int>) writeBytes;

  void write(String text) => writeBytes(utf8.encode(text));

  /// Reports on the device, newest first, limited to [appId]'s process.
  Future<List<CrashName>> reports(String udid, String? appId) async {
    String? process;
    if (appId != null) {
      final entry = (await backend.installedApps(udid))[appId];
      if (entry == null) {
        throw DeviceFailure(
          DeviceCodes.appNotInstalled,
          '$appId is not installed on the iPhone.',
        );
      }
      process = entry['CFBundleExecutable'] as String? ?? appId;
    }
    return [
      for (final entry in await backend.crashNames(udid))
        if (CrashName.tryParse(entry) case final name?
            when process == null || name.process == process)
          name,
    ]..sort(CrashName.newestFirst);
  }

  /// Pulls [names] into [directory] and reads their summaries.
  Future<Map<String, CrashReportSummary>> pullAndRead(
    String udid,
    List<CrashName> names,
    String directory,
  ) async {
    fileSystem.directory(directory).createSync(recursive: true);
    await backend.pullCrashes(udid, [for (final n in names) n.name], directory);
    final found = <String, String>{};
    final root = fileSystem.directory(directory);
    for (final entity in root.listSync(recursive: true)) {
      final base = paths.basename(entity.path);
      if (names.any((n) => n.name == base)) found[base] = entity.path;
    }
    return {
      for (final MapEntry(key: name, value: path) in found.entries)
        name: CrashReportSummary.fromIps(
          fileSystem.file(path).readAsStringSync(),
        ),
    };
  }
}
