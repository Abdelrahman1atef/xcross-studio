import 'dart:io';

import 'package:flutter/material.dart';

import '../cli/xcross_commands.dart';
import '../state/job.dart';
import 'services.dart';
import 'widgets.dart';

/// Setup: the notice, where xcross is, the computer check and Apple sign-in.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Job? _doctor;
  Job? _auth;
  final _appleId = TextEditingController();
  final _password = TextEditingController();
  final _issuer = TextEditingController();
  final _keyId = TextEditingController();
  String? _keyPath;
  bool _useApiKey = false;

  /// "Run from source" selected (kept even before a folder is chosen).
  bool? _sourceMode;

  @override
  void dispose() {
    for (final c in [_appleId, _password, _issuer, _keyId]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    return Watch(
      listenable: settings,
      builder: (context) {
        final fromSource =
            _sourceMode ?? settings.invocation.executable == 'dart';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Section(
              title: 'Before you start',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'XCross Studio is free, open-source software (AGPL-3.0) '
                    'and is not affiliated with or endorsed by Apple. It never '
                    'downloads or ships Xcode, iOS SDKs or developer disk '
                    'images: you provide your own (for example the Xcode you '
                    'downloaded under the Xcode licence) and sign with your '
                    'own Apple ID or App Store Connect key.',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.acceptedNotice,
                    onChanged: (value) => settings.update(
                      (s) => s.acceptedNotice = value ?? false,
                    ),
                    title: const Text('I understand'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            Section(
              title: 'xcross command-line tool',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Installed xcross'),
                        icon: Icon(Icons.terminal),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Run from source'),
                        icon: Icon(Icons.code),
                      ),
                    ],
                    selected: {fromSource},
                    onSelectionChanged: (choice) {
                      setState(() => _sourceMode = choice.first);
                      settings.update((s) {
                        s.invocation =
                            choice.first && s.sourceRepository != null
                            ? XcrossInvocation.fromSource(s.sourceRepository!)
                            : const XcrossInvocation.binary();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (fromSource)
                    PathField(
                      label: 'XCross Studio repository folder',
                      hint: 'Runs: dart run <folder>/packages/xcross/bin/xcross.dart',
                      value: settings.sourceRepository,
                      onChanged: (path) => settings.update((s) {
                        s.sourceRepository = path;
                        s.invocation = path == null
                            ? const XcrossInvocation.binary()
                            : XcrossInvocation.fromSource(path);
                      }),
                    )
                  else
                    PathField(
                      label: 'xcross executable',
                      hint: 'Leave as "xcross" to use the one on PATH.',
                      directory: false,
                      extensions: Platform.isWindows
                          ? const ['exe', 'bat']
                          : const [],
                      value: settings.invocation.executable,
                      onChanged: (path) => settings.update(
                        (s) => s.invocation = XcrossInvocation.binary(
                          path ?? 'xcross',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Using: ${settings.invocation}',
                    style: mono.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Section(
              title: 'Check this computer',
              trailing: FilledButton.icon(
                onPressed: _doctor?.isRunning ?? false
                    ? null
                    : () => setState(
                        () => _doctor = services.jobs.run(
                          'Doctor',
                          XcrossCommands.doctor(),
                        ),
                      ),
                icon: const Icon(Icons.health_and_safety),
                label: const Text('Run doctor'),
              ),
              child: _doctor == null
                  ? const Text(
                      'Checks the iOS SDK, toolchain, Apple Mobile Device '
                      'Service / usbmuxd, pymobiledevice3 and your sign-in.',
                    )
                  : JobOutputView(job: _doctor!, showInput: false),
            ),
            Section(
              title: 'Apple sign-in',
              trailing: TextButton.icon(
                onPressed: _auth?.isRunning ?? false
                    ? null
                    : () => setState(
                        () => _auth = services.jobs.run(
                          'Sign out',
                          XcrossCommands.authClean(),
                        ),
                      ),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Apple ID')),
                      ButtonSegment(
                        value: true,
                        label: Text('App Store Connect API key'),
                      ),
                    ],
                    selected: {_useApiKey},
                    onSelectionChanged: (choice) =>
                        setState(() => _useApiKey = choice.first),
                  ),
                  const SizedBox(height: 12),
                  if (!_useApiKey) ...[
                    TextField(
                      controller: _appleId,
                      decoration: const InputDecoration(
                        labelText: 'Apple ID (email)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText:
                            'Sent to xcross only. When Apple asks for a '
                            'two-factor code, type it in the box below the '
                            'output.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _issuer,
                      decoration: const InputDecoration(
                        labelText: 'Issuer ID',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _keyId,
                      decoration: const InputDecoration(
                        labelText: 'Key ID',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PathField(
                      label: 'AuthKey_<keyId>.p8',
                      directory: false,
                      extensions: const ['p8'],
                      value: _keyPath,
                      onChanged: (path) => setState(() => _keyPath = path),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _auth?.isRunning ?? false
                          ? null
                          : () => _signIn(services),
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in'),
                    ),
                  ),
                  if (_auth != null) ...[
                    const SizedBox(height: 12),
                    JobOutputView(job: _auth!, height: 200),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _signIn(Services services) {
    final List<String> command;
    if (_useApiKey) {
      if (_issuer.text.trim().isEmpty ||
          _keyId.text.trim().isEmpty ||
          _keyPath == null) {
        _snack('Fill in the issuer ID, key ID and .p8 file.');
        return;
      }
      command = XcrossCommands.authApiKey(
        issuerId: _issuer.text,
        keyId: _keyId.text,
        privateKeyPath: _keyPath!,
      );
    } else {
      if (_appleId.text.trim().isEmpty) {
        _snack('Enter your Apple ID.');
        return;
      }
      command = XcrossCommands.authAppleId(
        _appleId.text,
        password: _password.text,
      );
    }
    setState(() => _auth = services.jobs.run('Sign in', command));
    _password.clear();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}
