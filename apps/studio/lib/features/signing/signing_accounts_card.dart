// studio: 030 — switch between the App Store Connect accounts used before.
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/state/job.dart';
import '../../src/state/signing_accounts.dart';
import '../common/job_views.dart';

/// The accounts signed in with before, one click to switch. Signing stays
/// with the CLI: "Use" runs `xcross auth` with the saved Key ID, Issuer ID and
/// `.p8` path; only those three are kept, never the key or a password.
class SigningAccountsCard extends StatefulWidget {
  const SigningAccountsCard({super.key});

  @override
  State<SigningAccountsCard> createState() => _SigningAccountsCardState();
}

class _SigningAccountsCardState extends State<SigningAccountsCard> {
  Job? _switch;
  String? _switchingKeyId;

  void _onJob() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _switch?.removeListener(_onJob);
    super.dispose();
  }

  void _use(SigningAccount account) {
    final services = Services.of(context);
    _switch?.removeListener(_onJob);
    final job = services.jobs.run(
      'Switch to ${account.name}',
      XcrossCommands.authApiKey(
        issuerId: account.issuerId,
        keyId: account.keyId,
        privateKeyPath: account.privateKeyPath,
      ),
    );
    setState(() {
      _switch = job..addListener(_onJob);
      _switchingKeyId = account.keyId;
    });
    job.done.then((status) {
      if (!mounted) return;
      if (status == JobStatus.succeeded) {
        services.signingAccounts.markUsed(account);
      }
      // Apple's answer decides whether the account is "In use": a refused
      // key is not saved by the CLI, so the previous sign-in stays.
      services.readiness.runDoctor();
    });
  }

  Future<void> _rename(SigningAccount account) async {
    final accounts = Services.of(context).signingAccounts;
    final result = await showDialog<({String name, String note})>(
      context: context,
      builder: (context) => _RenameDialog(account),
    );
    if (result != null) {
      accounts.rename(account, result.name, note: result.note);
    }
  }

  Future<void> _remove(SigningAccount account) async {
    final accounts = Services.of(context).signingAccounts;
    final confirmed = await showXConfirmDialog(
      context,
      title: 'Remove ${account.name} from the list?',
      message:
          'Only the entry here is removed. The key file and the key in App '
          'Store Connect are not touched, and a sign-in that is saved stays.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed) accounts.remove(account);
  }

  static String _when(DateTime? value) {
    if (value == null) return 'never used here';
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'used ${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.signingAccounts,
        services.readiness,
      ]),
      builder: (context, _) {
        final accounts = services.signingAccounts.accounts;
        if (accounts.isEmpty) return const SizedBox.shrink();
        final saved = services.readiness.savedSignIn?.apiKey;
        final switching = _switch?.isRunning ?? false;
        final failed = _switch?.status == JobStatus.failed;
        return XCard(
          title: 'Accounts',
          subtitle:
              'App Store Connect keys you signed in with. Switching saves that '
              'key as the one builds and uploads use. Only the Key ID, Issuer '
              'ID and file path are remembered here.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final account in accounts)
                _AccountRow(
                  account: account,
                  inUse: account.isSavedKey(saved),
                  busy: switching && _switchingKeyId == account.keyId,
                  switching: switching,
                  when: _when(account.lastUsed),
                  onUse: () => _use(account),
                  onRename: () => _rename(account),
                  onRemove: () => _remove(account),
                ),
              if (failed && _switch != null) ...[
                const SizedBox(height: XSpace.s2),
                XCallout(
                  status: XStatus.failed,
                  title: 'Could not switch',
                  children: [
                    const XNote(
                      'The saved sign-in is unchanged. The details are in '
                      'the diagnostics below.',
                    ),
                    const SizedBox(height: XSpace.s2),
                    JobDiagnostics(job: _switch!, limit: 2),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.inUse,
    required this.busy,
    required this.switching,
    required this.when,
    required this.onUse,
    required this.onRename,
    required this.onRemove,
  });

  final SigningAccount account;
  final bool inUse;
  final bool busy;
  final bool switching;
  final String when;
  final VoidCallback onUse;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = XTheme.of(context).colors;
    final missing = !account.fileExists;
    final details = [
      'Key ${account.keyId}',
      account.isIndividual ? 'individual key' : 'team key',
      when,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: XSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (inUse) ...[
                      const SizedBox(width: XSpace.s2),
                      const XStatusBadge(
                        status: XStatus.ready,
                        label: 'In use',
                        compact: true,
                      ),
                    ],
                  ],
                ),
                Text(details, style: TextStyle(color: colors.textSecondary)),
                if (account.note case final note?)
                  Text(note, style: TextStyle(color: colors.textSecondary)),
                if (missing)
                  Text(
                    'The key file is gone: ${account.privateKeyPath}',
                    style: TextStyle(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: XSpace.s3),
          if (!inUse)
            XButton(
              label: 'Use',
              icon: Icons.swap_horiz,
              loading: busy,
              loadingLabel: 'Switching…',
              disabledReason: missing
                  ? 'The key file is missing. Pick it again under Sign in.'
                  : switching
                  ? 'Another switch is running.'
                  : null,
              onPressed: missing || switching ? null : onUse,
            ),
          XIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Rename',
            onPressed: onRename,
          ),
          XIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove from the list',
            destructive: true,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Owns its text controllers, so they live as long as the dialog's closing
/// animation needs them.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog(this.account);

  final SigningAccount account;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.account.name);
  late final _note = TextEditingController(text: widget.account.note ?? '');

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename account'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          XTextField(controller: _name, label: 'Name'),
          const SizedBox(height: XSpace.s3),
          XTextField(
            controller: _note,
            label: 'Note (optional)',
            hint: 'For example the team or the app it signs.',
          ),
        ],
      ),
    ),
    actions: [
      XButton(
        label: 'Cancel',
        variant: XButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
      XButton(
        label: 'Save',
        onPressed: () =>
            Navigator.pop(context, (name: _name.text, note: _note.text)),
      ),
    ],
  );
}
