import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'process_launcher.dart';
import 'xcross_commands.dart';

enum CapabilitySupport { supported, unsupported, unknown }

/// Read-only command inventory for the selected xcross executable.
///
/// Only commands explicitly listed by the binary's top-level help are
/// supported. Version/help probing never invokes a project or authentication
/// operation. Less visible options and lifecycle features remain unknown.
class CliCapabilities extends ChangeNotifier {
  CliCapabilities({required this.launcher, required this.invocation});

  final ProcessLauncher launcher;
  XcrossInvocation invocation;
  String? version;
  String? evidence;
  Object? probeError;
  final Set<String> _commands = {};
  bool _probing = false;

  bool get probing => _probing;
  CapabilitySupport command(String name) => evidence == null
      ? CapabilitySupport.unknown
      : _commands.contains(name)
      ? CapabilitySupport.supported
      : CapabilitySupport.unsupported;

  CapabilitySupport get structuredEvents => CapabilitySupport.unknown;
  CapabilitySupport get cancellation => CapabilitySupport.unknown;
  CapabilitySupport get capture => CapabilitySupport.unknown;
  CapabilitySupport get inspection => command('inspect');
  CapabilitySupport get attachment => CapabilitySupport.unknown;

  Future<void> refresh({Duration timeout = const Duration(seconds: 8)}) async {
    if (_probing) return;
    _probing = true;
    version = null;
    evidence = null;
    probeError = null;
    _commands.clear();
    notifyListeners();
    try {
      final versionText = await _run(['--version'], timeout);
      final help = await _run(['--help'], timeout);
      final versionMatch = RegExp(
        r'xcross\s+([^\s]+)',
        caseSensitive: false,
      ).firstMatch(versionText);
      if (versionMatch == null || help.trim().isEmpty) {
        throw const FormatException(
          'The selected binary returned no xcross version or help.',
        );
      }
      version = versionMatch.group(1);
      final inCommands = RegExp(
        r'Available commands:\s*([\s\S]*?)(?:\n\s*Run |\s*$)',
        caseSensitive: false,
      ).firstMatch(help)?.group(1);
      if (inCommands == null) {
        throw const FormatException(
          'The selected binary help has no recognized command inventory.',
        );
      }
      for (final match in RegExp(
        r'^\s{2}([a-z][a-z0-9_-]*)\s{2,}',
        multiLine: true,
      ).allMatches(inCommands)) {
        _commands.add(match.group(1)!);
      }
      evidence = '${invocation.executable} ${version!}';
    } on Object catch (error) {
      probeError = error;
    } finally {
      _probing = false;
      notifyListeners();
    }
  }

  void updateInvocation(XcrossInvocation next) {
    if (invocation.executable == next.executable &&
        listEquals(invocation.prefixArguments, next.prefixArguments)) {
      return;
    }
    invocation = next;
    version = null;
    evidence = null;
    probeError = null;
    _commands.clear();
    notifyListeners();
  }

  Future<String> _run(List<String> args, Duration timeout) async {
    final process = await launcher.start(
      invocation.executable,
      invocation.argumentsFor(args),
    );
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final outDone = Completer<void>();
    final errDone = Completer<void>();
    final outSub = process.stdout
        .transform(utf8.decoder)
        .listen(stdout.write, onDone: outDone.complete);
    final errSub = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write, onDone: errDone.complete);
    try {
      final code = await process.exitCode.timeout(timeout);
      await Future.wait([outDone.future, errDone.future]).timeout(timeout);
      if (code != 0) {
        throw ProcessException(
          invocation.executable,
          args,
          stderr.toString(),
          code,
        );
      }
      return stdout.toString();
    } on TimeoutException {
      await launcher.killTree(process);
      await outSub.cancel();
      await errSub.cancel();
      rethrow;
    }
  }
}
