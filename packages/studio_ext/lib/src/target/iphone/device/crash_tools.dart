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
    // A report can be listed both at the top level and under /Retired.
    final seen = <String>{};
    return [
      for (final entry in await backend.crashNames(udid))
        if (CrashName.tryParse(entry) case final name?
            when (process == null || name.process == process) &&
                seen.add(name.name))
          name,
    ]..sort(CrashName.newestFirst);
  }

  /// Pulls [names] into [directory] and reads their summaries, keyed by
  /// report name. Reports that could not be copied are missing.
  Future<Map<String, PulledCrash>> pullAndRead(
    String udid,
    List<CrashName> names,
    String directory,
  ) async {
    fileSystem.directory(directory).createSync(recursive: true);
    await backend.pullCrashes(udid, [for (final n in names) n.path], directory);
    final found = <String, String>{};
    final root = fileSystem.directory(directory);
    for (final entity in root.listSync(recursive: true)) {
      final base = paths.basename(entity.path);
      if (names.any((n) => n.name == base)) found[base] = entity.path;
    }
    return {
      for (final MapEntry(key: name, value: path) in found.entries)
        name: PulledCrash(
          path,
          CrashReportSummary.fromIps(fileSystem.file(path).readAsStringSync()),
        ),
    };
  }
}

/// A report copied off the device: where it was saved and what it says.
@internal
final class PulledCrash {
  const PulledCrash(this.path, this.summary);

  final String path;
  final CrashReportSummary summary;
}
