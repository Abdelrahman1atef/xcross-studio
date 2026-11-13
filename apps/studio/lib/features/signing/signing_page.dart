import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/product.dart';
import '../../src/state/job.dart';
import '../../src/state/readiness.dart';
import '../common/job_views.dart';
import '../common/readiness_views.dart';
import 'app_id_card.dart';
import 'signing_accounts_card.dart';

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
              'Your App Store Connect team key for signing and provisioning. '
              '$productName never shows the key\'s contents.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
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
                  if (readiness.savedSignIn case final saved?) ...[
                    const SizedBox(height: XSpace.s3),
                    SavedSignInDetails(saved),
                  ],
                ],
              ),
            ),
            const SigningAccountsCard(), // feature 030
            const SigningForm(),
            const AppIdCard(), // feature 016
            const _SignOutCard(),
          ],
        );
      },
    );
  }
}

/// How the user signed in and what each kind of build uses (feature 026).
class SavedSignInDetails extends StatelessWidget {
  const SavedSignInDetails(this.saved, {super.key});

  final AuthStatusReport saved;

  static const _apiKeyLabel = 'App Store Connect API key';

  static String _uses(String? credential) => switch (credential) {
    'apple-id' => 'Apple ID (not used by $productName)',
    'api-key' => _apiKeyLabel,
    _ => 'Nothing yet',
  };

  @override
  Widget build(BuildContext context) {
    final appleId = saved.appleId;
    final apiKey = saved.apiKey;
    if (appleId == null && apiKey == null) {
      return const XNote('No sign-in is saved on this computer.');
    }
    final warnings = [
      // Runbook F18: Studio signs with a team key only.
      if (appleId != null)
        'An Apple ID session from the command-line tool is saved. '
            '$productName does not use Apple ID: sign in with a team key.',
      if (apiKey != null && apiKey.problem == null && apiKey.isIndividual)
        'The saved key is an individual key, which cannot sign. Sign in '
            'with a team key (Admin or App Manager).',
      if (apiKey?.problem case final problem?)
        'The saved API key cannot be used: $problem',
      if (apiKey != null && apiKey.problem == null && !apiKey.privateKeyFound)
        'The private key file is gone: ${apiKey.privateKeyPath}. Pick it again.',
      if (saved.appStoreBuilds == null)
        'App Store builds need a team key, and none is saved. Device builds '
            'do not need it.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Details([
          ('Device builds use', _uses(saved.deviceBuilds)),
          ('App Store builds use', _uses(saved.appStoreBuilds)),
        ]),
        if (apiKey != null && apiKey.problem == null) ...[
          const SizedBox(height: XSpace.s3),
          _Details(title: _apiKeyLabel, [
            ('Key type', apiKey.isIndividual ? 'Individual key' : 'Team key'),
            if (apiKey.issuerId case final issuer?) ('Issuer ID', issuer),
            ('Key ID', apiKey.keyId ?? ''),
            ('Private key', apiKey.privateKeyPath ?? ''),
          ]),
        ],
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: XSpace.s3),
          XCallout(
            status: XStatus.warning,
            title: 'Needs attention',
            children: [XNote(warnings.join('\n'))],
          ),
        ],
      ],
    );
  }
}

/// Labelled values, in one aligned column.
class _Details extends StatelessWidget {
  const _Details(this.rows, {this.title});

  final String? title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final colors = XTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title case final title?)
          Padding(
            padding: const EdgeInsets.only(bottom: XSpace.s1),
            child: Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: XSpace.s1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 170,
                  child: Text(
                    label,
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          ),
      ],
    );
  }
}

/// App Store Connect **team key** sign-in (runbook F18: team key only; Studio
/// never signs in with an Apple ID). Used by Signing and the setup wizard.
class SigningForm extends StatefulWidget {
  const SigningForm({super.key});

  @override
  State<SigningForm> createState() => _SigningFormState();
}

class _SigningFormState extends State<SigningForm> {
  Job? _auth;
  final _issuer = TextEditingController();
  final _keyId = TextEditingController();
  String? _keyPath;
  String? _error;

  bool _showAuthDetails = false;
  ReadinessController? _readiness;
  AuthStatusReport? _applied;

  /// What each field was last filled with from the saved sign-in: a field
  /// showing anything else was typed by the user and is left alone.
  final _filled = <TextEditingController, String>{};
  String? _filledKeyPath;

  void _onJob() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final readiness = Services.of(context).readiness;
    if (identical(readiness, _readiness)) return;
    _readiness?.removeListener(_applySaved);
    _readiness = readiness..addListener(_applySaved);
    _applySaved();
  }

  void _fill(TextEditingController field, String? value) {
    if (field.text.isNotEmpty && field.text != _filled[field]) return;
    field.text = value ?? '';
    _filled[field] = field.text;
  }

  /// Starts the form from what is saved; the password is never saved.
  void _applySaved() {
    final saved = _readiness?.savedSignIn;
    if (saved == null || identical(saved, _applied)) return;
    _applied = saved;
    final key = saved.apiKey;
    // Only a team key is offered back; an individual key is not usable here.
    final team = key != null && !key.isIndividual ? key : null;
    _fill(_issuer, team?.issuerId);
    _fill(_keyId, team?.keyId);
    if (_keyPath == null || _keyPath == _filledKeyPath) {
      _keyPath = team != null && team.privateKeyFound
          ? team.privateKeyPath
          : null;
      _filledKeyPath = _keyPath;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _readiness?.removeListener(_applySaved);
    _auth?.removeListener(_onJob);
    for (final c in [_issuer, _keyId]) {
      c.dispose();
    }
    super.dispose();
  }

  void _signIn() {
    final services = Services.of(context);
    if (_issuer.text.trim().isEmpty ||
        _keyId.text.trim().isEmpty ||
        _keyPath == null) {
      setState(() => _error = 'Fill in the issuer ID, key ID and .p8 file.');
      return;
    }
    final command = XcrossCommands.authApiKey(
      issuerId: _issuer.text,
      keyId: _keyId.text,
      privateKeyPath: _keyPath!,
    );
    _auth?.removeListener(_onJob);
    setState(() {
      _error = null;
      _showAuthDetails = false;
      // Listened to so "Signing in…" ends with the job (it stayed on).
      _auth = services.jobs.run('Sign in', command)..addListener(_onJob);
    });
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
          'Your credentials are saved. $productName is asking Apple whether '
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
    if (raw.contains('individual API key')) {
      return card(XStatus.failed, 'This is an individual key', [
        const Text(
          '$productName needs a team key (Admin or App Manager role). Apple '
          'lets individual keys read App Store Connect but not manage '
          'devices, certificates or provisioning profiles, which signing '
          'needs. Create a team key under Users and Access → Integrations → '
          'Team Keys and sign in with it.',
        ),
        const SizedBox(height: XSpace.s3),
        XButton(
          label: 'Create a team key',
          icon: Icons.open_in_new,
          onPressed: () => services.launcher.openUrl(_ascKeysUrl),
        ),
      ]);
    }
    final rejectedKey = raw.contains('HTTP 401');
    final keyId = _keyId.text.trim().isEmpty ? 'your key' : _keyId.text.trim();
    return card(XStatus.failed, 'Apple did not accept these credentials', [
      if (rejectedKey) ...[
        const Text(
          'Apple refused the API key (HTTP 401), so it was not saved and your '
          'current sign-in is unchanged. The Key ID may not match the file '
          '(AuthKey_<Key ID>.p8), or the key is not an App Store Connect API '
          'key, was revoked, or belongs to another team.',
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
        const Text('The check with Apple failed. The details below say why.'),
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
          const XCallout(
            status: XStatus.ready,
            title: 'Sign in with an App Store Connect team key',
            children: [
              XNote(
                '$productName signs with a team key, Apple\'s documented '
                'credential for automation. It needs a paid Apple Developer '
                'Program membership. Create the key in App Store Connect under '
                'Users and Access → Integrations → Team Keys, with the Admin '
                'or App Manager role, then copy the Issuer ID shown above the '
                'key list.',
              ),
            ],
          ),
          const SizedBox(height: XSpace.s3),
          XTextField(controller: _issuer, label: 'Issuer ID'),
          const SizedBox(height: XSpace.s2),
          XTextField(controller: _keyId, label: 'Key ID'),
          const SizedBox(height: XSpace.s2),
          XFilePickerField(
            label: 'Private key (.p8)',
            directory: false,
            extensions: const ['p8'],
            value: _keyPath,
            onChanged: (path) => setState(() => _keyPath = path),
          ),
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
            JobConsole(job: _auth!, height: 180),
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
