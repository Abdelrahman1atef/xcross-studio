import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/job.dart';
import '../../src/state/readiness.dart';
import '../common/job_views.dart';
import '../common/readiness_views.dart';

/// Signing (§6.4): authenticate securely and understand the trade-offs.
class SigningPage extends StatelessWidget {
  const SigningPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final readiness = services.readiness;
    return ListenableBuilder(
      listenable: readiness,
      builder: (context, _) {
        final auth = readiness.signing;
        final status = statusOfHealth(auth.health);
        return WorkspaceLayout(
          title: 'Signing',
          subtitle:
              'Apple credentials for signing and provisioning. XCross Studio '
              'never stores or shows your password.',
          actions: [
            XButton(
              label: 'Re-check',
              icon: Icons.refresh,
              variant: XButtonVariant.secondary,
              loading: readiness.checking,
              loadingLabel: 'Checking…',
              onPressed: readiness.runDoctor,
            ),
          ],
          children: [
            XCard(
              title: 'Status',
              child: Row(
                children: [
                  XStatusBadge(
                    status: status,
                    label: switch (auth.health) {
                      Health.ok => 'Authenticated',
                      Health.failed => 'Not configured',
                      Health.warning => 'Needs attention',
                      Health.checking => 'Checking…',
                      Health.unknown => 'Not checked yet',
                    },
                  ),
                  const SizedBox(width: XSpace.s3),
                  Expanded(
                    child: XNote(
                      auth.message ?? 'Run the checks to see whether credentials are saved.',
                    ),
                  ),
                ],
              ),
            ),
            const SigningForm(),
            const XCard(
              title: 'Bundle identity',
              child: XNote(
                'xcross reads the bundle id from your Flutter project and, '
                'with a free team, may qualify it with your team id so the '
                'App ID is unique; capabilities such as push need a paid '
                'team. App Groups are registered for you with an Apple ID '
                '(set XCROSS_APP_GROUP with an API key). See the README '
                'sections "Bundle identity" and "App extensions".',
              ),
            ),
            const _SignOutCard(),
          ],
        );
      },
    );
  }
}

/// Apple ID or App Store Connect API key sign-in, with the risk
/// explanations (§6.4, §12). Used by Signing and the setup wizard.
class SigningForm extends StatefulWidget {
  const SigningForm({super.key});

  @override
  State<SigningForm> createState() => _SigningFormState();
}

class _SigningFormState extends State<SigningForm> {
  Job? _auth;
  bool _useApiKey = false;

  /// Individual key (Users and Access → Integrations → Individual Keys):
  /// signed without an Issuer ID (feature 015).
  bool _individualKey = false;
  final _appleId = TextEditingController();
  final _password = TextEditingController();
  final _anisette = TextEditingController();
  final _issuer = TextEditingController();
  final _keyId = TextEditingController();
  String? _keyPath;
  String? _error;

  bool _showAuthDetails = false;

  void _onJob() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth?.removeListener(_onJob);
    for (final c in [_appleId, _password, _anisette, _issuer, _keyId]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The anisette server the CLI will use: the field, else
  /// `XCROSS_ANISETTE_URL`, else the CLI default.
  String get _anisetteInUse {
    final typed = _anisette.text.trim();
    if (typed.isNotEmpty) return typed;
    final env = Platform.environment['XCROSS_ANISETTE_URL'];
    if (env != null && env.isNotEmpty) return env;
    return XcrossCommands.defaultAnisetteUrl;
  }

  void _signIn() {
    final services = Services.of(context);
    final List<String> command;
    if (_useApiKey) {
      if ((!_individualKey && _issuer.text.trim().isEmpty) ||
          _keyId.text.trim().isEmpty ||
          _keyPath == null) {
        setState(
          () => _error = _individualKey
              ? 'Fill in the key ID and .p8 file.'
              : 'Fill in the issuer ID, key ID and .p8 file.',
        );
        return;
      }
      command = XcrossCommands.authApiKey(
        issuerId: _individualKey ? null : _issuer.text,
        keyId: _keyId.text,
        privateKeyPath: _keyPath!,
      );
    } else {
      if (_appleId.text.trim().isEmpty) {
        setState(() => _error = 'Enter your Apple ID.');
        return;
      }
      command = XcrossCommands.authAppleId(
        _appleId.text,
        password: _password.text,
        anisetteUrl: _anisette.text,
      );
    }
    _auth?.removeListener(_onJob);
    setState(() {
      _error = null;
      _showAuthDetails = false;
      // Listened to so "Signing in…" ends with the job (it stayed on).
      _auth = services.jobs.run('Sign in', command)..addListener(_onJob);
    });
    _password.clear();
    _auth!.done.then((_) {
      if (mounted) services.readiness.runDoctor();
    });
  }

  static const _ascKeysUrl =
      'https://appstoreconnect.apple.com/access/integrations/api';

  /// The sign-in outcome in the design system's diagnostic shape (§8.2):
  /// title, one sentence, steps, actions, raw text behind "Show details".
  Widget _result(BuildContext context) {
    final services = Services.of(context);
    final readiness = services.readiness;
    if (_auth?.status != JobStatus.succeeded) return const SizedBox.shrink();
    Widget card(XStatus status, String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: XSpace.s3),
      child: XCallout(title: title, status: status, children: children),
    );
    if (readiness.checking) {
      return card(XStatus.running, 'Saved. Verifying with Apple…', const [
        Text(
          'Your credentials are saved. XCross Studio is asking Apple whether '
          'it accepts them (about 10 seconds).',
        ),
      ]);
    }
    if (readiness.signing.health == Health.ok) {
      return card(XStatus.ready, 'Signed in', const [
        Text('Apple accepted your credentials.'),
      ]);
    }
    final raw = readiness.signing.message ?? '';
    // studio: 015 — the doctor's wording for an individual key Apple
    // accepts but will not let manage devices, certificates and profiles.
    if (_useApiKey && raw.contains('individual API key')) {
      return card(XStatus.failed, 'This individual key cannot sign apps', [
        const Text(
          'Apple accepts the key, but individual keys may not manage '
          'devices, certificates or provisioning profiles, which installing '
          'on an iPhone needs. Use a Team key (Admin or App Manager role) or '
          'your Apple ID instead.',
        ),
        const SizedBox(height: XSpace.s3),
        Wrap(
          spacing: XSpace.s2,
          runSpacing: XSpace.s2,
          children: [
            XButton(
              label: 'Create a Team key',
              icon: Icons.open_in_new,
              onPressed: () => services.launcher.openUrl(_ascKeysUrl),
            ),
            XButton(
              label: 'Use Apple ID instead',
              icon: Icons.person,
              variant: XButtonVariant.secondary,
              onPressed: () => setState(() => _useApiKey = false),
            ),
          ],
        ),
      ]);
    }
    final rejectedKey = _useApiKey && raw.contains('HTTP 401');
    final keyId = _keyId.text.trim().isEmpty ? 'your key' : _keyId.text.trim();
    return card(XStatus.failed, 'Apple did not accept these credentials', [
      if (rejectedKey) ...[
        const Text(
          'Your details are saved, but Apple refused the API key (HTTP 401). '
          'The key is probably not an App Store Connect API key, was revoked, '
          'or belongs to another team.',
        ),
        const SizedBox(height: XSpace.s2),
        Text(
          '1. In App Store Connect, open Users and Access → Integrations → '
          'App Store Connect API.\n'
          '2. Check that $keyId is listed as active, with the Admin or App '
          'Manager role.\n'
          '3. Copy the Issuer ID shown at the top of that page.\n'
          '4. If the key is missing, create a Team Key and pick its '
          'AuthKey_….p8 here. Push (APNs) and Sign in with Apple keys do not '
          'work.',
        ),
      ] else
        const Text(
          'Your details are saved, but the check with Apple failed. The '
          'details below say why.',
        ),
      const SizedBox(height: XSpace.s3),
      Wrap(
        spacing: XSpace.s2,
        runSpacing: XSpace.s2,
        children: [
          if (rejectedKey)
            XButton(
              label: 'Open App Store Connect',
              icon: Icons.open_in_new,
              onPressed: () => services.launcher.openUrl(_ascKeysUrl),
            ),
          if (_useApiKey)
            XButton(
              label: 'Use Apple ID instead',
              icon: Icons.person,
              variant: XButtonVariant.secondary,
              onPressed: () => setState(() => _useApiKey = false),
            ),
          XButton(
            label: _showAuthDetails ? 'Hide details' : 'Show details',
            variant: XButtonVariant.text,
            onPressed: () =>
                setState(() => _showAuthDetails = !_showAuthDetails),
          ),
        ],
      ),
      if (_showAuthDetails && raw.isNotEmpty) ...[
        const SizedBox(height: XSpace.s2),
        SelectableText(raw, style: XType.mono),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final running = _auth?.isRunning ?? false;
    return XCard(
      title: 'Sign in',
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
          const SizedBox(height: XSpace.s3),
          if (_useApiKey) ...[
            const XCallout(
              status: XStatus.ready,
              title: 'Recommended for supported workflows and CI',
              children: [
                XNote(
                  'An App Store Connect API key is Apple\'s documented '
                  'credential for automation. Create one under Users and '
                  'Access → Integrations in App Store Connect.',
                ),
              ],
            ),
            const SizedBox(height: XSpace.s3),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Team key')),
                ButtonSegment(value: true, label: Text('Individual key')),
              ],
              selected: {_individualKey},
              onSelectionChanged: (choice) =>
                  setState(() => _individualKey = choice.first),
            ),
            const SizedBox(height: XSpace.s2),
            XNote(
              _individualKey
                  ? 'Individual keys (Integrations → Individual Keys) need no '
                        'Issuer ID. Apple lets them read App Store Connect but '
                        'not manage devices, certificates or profiles, so '
                        'installing on an iPhone needs a Team key or your '
                        'Apple ID.'
                  : 'Team keys (Integrations → Team Keys) need the Issuer ID '
                        'shown above the key list and the Admin or App '
                        'Manager role. Not sure? xcross detects an individual '
                        'key when you sign in.',
            ),
            const SizedBox(height: XSpace.s3),
            if (!_individualKey) ...[
              XTextField(controller: _issuer, label: 'Issuer ID'),
              const SizedBox(height: XSpace.s2),
            ],
            XTextField(controller: _keyId, label: 'Key ID'),
            const SizedBox(height: XSpace.s2),
            XFilePickerField(
              label: 'Private key (.p8)',
              directory: false,
              extensions: const ['p8'],
              value: _keyPath,
              onChanged: (path) => setState(() => _keyPath = path),
            ),
          ] else ...[
            XCallout(
              status: XStatus.warning,
              title: 'Read before signing in with an Apple ID',
              children: [
                const XNote(
                  '• This uses Apple\'s private sign-in protocol, the way '
                  'Xcode does, not a documented API. Apple can lock an '
                  'account that signs in this way: use a secondary Apple ID '
                  'if you can.\n'
                  '• Two-factor authentication is supported: type the code '
                  'in the box under the output when Apple asks.\n'
                  '• Sign-in needs an "anisette" server. Public servers are '
                  'run by third parties and can see connection metadata and '
                  'device-attestation traffic; self-host one if you prefer.',
                ),
                const SizedBox(height: XSpace.s1),
                ListenableBuilder(
                  listenable: _anisette,
                  builder: (context, _) =>
                      XNote('Anisette server in use: $_anisetteInUse'),
                ),
              ],
            ),
            const SizedBox(height: XSpace.s3),
            XTextField(controller: _appleId, label: 'Apple ID (email)'),
            const SizedBox(height: XSpace.s2),
            XCredentialField(
              controller: _password,
              label: 'Password',
              helper: 'Passed to xcross only; never logged or saved here.',
            ),
            const SizedBox(height: XSpace.s2),
            XTextField(
              controller: _anisette,
              label: 'Anisette server (optional)',
              hint:
                  'Leave empty for ${XcrossCommands.defaultAnisetteUrl} or '
                  'XCROSS_ANISETTE_URL.',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: XSpace.s2),
            Text(
              _error!,
              style: TextStyle(color: XTheme.of(context).colors.error),
            ),
          ],
          const SizedBox(height: XSpace.s3),
          Align(
            alignment: Alignment.centerLeft,
            child: XButton(
              label: 'Sign in',
              icon: Icons.login,
              loading: running,
              loadingLabel: 'Signing in…',
              onPressed: running ? null : _signIn,
            ),
          ),
          if (_auth != null) ...[
            const SizedBox(height: XSpace.s3),
            JobDiagnostics(job: _auth!),
            // Saving takes a moment; checking the credentials with Apple
            // (flutter doctor) takes several seconds, so say which is which.
            ListenableBuilder(
              listenable: Listenable.merge([
                _auth!,
                Services.of(context).readiness,
              ]),
              builder: (context, _) => _result(context),
            ),
            JobConsole(
              job: _auth!,
              height: 180,
              input: true,
              inputHint: 'Two-factor code (or other input), then Enter',
            ),
          ],
        ],
      ),
    );
  }
}

class _SignOutCard extends StatefulWidget {
  const _SignOutCard();

  @override
  State<_SignOutCard> createState() => _SignOutCardState();
}

class _SignOutCardState extends State<_SignOutCard> {
  Job? _job;

  Future<void> _signOut() async {
    final services = Services.of(context);
    final confirmed = await showXConfirmDialog(
      context,
      title: 'Sign out and clear credentials?',
      message:
          'This deletes the saved App Store Connect key, the Apple ID '
          'session, and every certificate, private key and provisioning '
          'profile xcross created on this computer.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(
      () => _job = services.jobs.run('Sign out', XcrossCommands.authClean()),
    );
    await _job!.done;
    if (mounted) services.readiness.runDoctor();
  }

  @override
  Widget build(BuildContext context) => XCard(
    title: 'Sign out',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const XNote(
          'Runs "xcross auth clean". You can sign in again any time.',
        ),
        const SizedBox(height: XSpace.s3),
        Align(
          alignment: Alignment.centerLeft,
          child: XButton(
            label: 'Sign out / clear credentials',
            variant: XButtonVariant.danger,
            loading: _job?.isRunning ?? false,
            loadingLabel: 'Signing out…',
            onPressed: _signOut,
          ),
        ),
        if (_job != null) ...[
          const SizedBox(height: XSpace.s3),
          JobConsole(job: _job!, height: 120),
        ],
      ],
    ),
  );
}
