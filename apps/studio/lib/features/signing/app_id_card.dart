import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';

/// The App ID the open project is signed under, with a switch (feature 016,
/// AC-016-3). Everything goes through `xcross project bundle-id`.
class AppIdCard extends StatefulWidget {
  const AppIdCard({super.key});

  @override
  State<AppIdCard> createState() => _AppIdCardState();
}

class _AppIdCardState extends State<AppIdCard> {
  BundleIdStatus? _status;
  Job? _job;
  String? _loadedFor;
  bool _busy = false;

  Future<void> _run({bool? realAppId}) async {
    final services = Services.of(context);
    final project = services.settings.projectPath;
    if (project == null) return;
    setState(() => _busy = true);
    final (job, events) = await services.jobs.collect(
      realAppId == null ? 'App ID' : 'Save App ID choice',
      XcrossCommands.projectBundleId(realAppId: realAppId),
      workingDirectory: project,
    );
    if (!mounted) return;
    setState(() {
      _job = job;
      _busy = false;
      _status = events.whereType<BundleIdStatus>().lastOrNull ?? _status;
    });
  }

  Future<void> _switch({required bool realAppId}) async {
    final id = _status?.bundleId ?? 'the bundle ID';
    final confirmed = await showXConfirmDialog(
      context,
      title: realAppId
          ? 'Sign the app as $id?'
          : 'Sign the app under the prefixed App ID?',
      message: realAppId
          ? 'Push notifications, Firebase, Sign in with Apple and the App '
                'Store all need the real App ID. iOS treats it as a different '
                'app from the prefixed one: install it again, and its data '
                'starts empty.'
          : 'The prefixed App ID (XCR-<identity>.$id) never collides with '
                "another team, but push, Firebase and Sign in with Apple don't "
                'work under it. iOS treats it as a different app.',
      confirmLabel: realAppId ? 'Use the real App ID' : 'Use the prefixed ID',
    );
    if (confirmed && mounted) await _run(realAppId: realAppId);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Services.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final project = settings.projectPath;
        if (project != _loadedFor) {
          _loadedFor = project;
          _status = null;
          if (project != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _run();
            });
          }
        }
        return XCard(
          title: 'App ID',
          child: project == null
              ? const XNote(
                  'Open a Flutter project to see which App ID it is signed '
                  'under.',
                )
              : _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final status = _status;
    final failed = _job?.status == JobStatus.failed && status == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == null)
          XNote(
            failed
                ? 'Could not read the App ID choice (see the job log).'
                : 'Reading the App ID choice…',
          )
        else ...[
          Row(
            children: [
              XStatusBadge(
                status: status.usesRealAppId ? XStatus.ready : XStatus.warning,
                label: status.usesRealAppId ? 'Real App ID' : 'Prefixed App ID',
              ),
              const SizedBox(width: XSpace.s3),
              Expanded(
                child: XNote(
                  status.usesRealAppId
                      ? '${status.bundleId ?? 'The project bundle ID'}'
                            '${status.saved == null ? ' (default)' : ' (saved in the project)'}'
                      : 'XCR-<identity>.${status.bundleId ?? '<bundle ID>'}: '
                            "push, Firebase and Sign in with Apple don't work "
                            'under it.',
                ),
              ),
            ],
          ),
          if (status.override != null) ...[
            const SizedBox(height: XSpace.s2),
            XNote(
              'XCROSS_BUNDLE_ID=${status.override} is set and wins over the '
              'saved choice.',
            ),
          ],
          const SizedBox(height: XSpace.s3),
          Wrap(
            spacing: XSpace.s2,
            runSpacing: XSpace.s2,
            children: [
              XButton(
                label: 'Use the real App ID',
                variant: status.usesRealAppId
                    ? XButtonVariant.secondary
                    : XButtonVariant.primary,
                loading: _busy,
                loadingLabel: 'Saving…',
                onPressed: status.usesRealAppId && status.saved != null
                    ? null
                    : () => _switch(realAppId: true),
              ),
              XButton(
                label: 'Use the prefixed App ID',
                variant: XButtonVariant.secondary,
                onPressed: _busy || !status.usesRealAppId
                    ? null
                    : () => _switch(realAppId: false),
              ),
            ],
          ),
        ],
        const SizedBox(height: XSpace.s3),
        const XNote(
          'The real App ID is the bundle ID in your project, the one Firebase, '
          'push and the App Store record use. The prefixed form '
          'XCR-<identity>.<bundle ID> is only for a bundle ID another team '
          'owns. With a team key, set App Groups with XCROSS_APP_GROUP.',
        ),
      ],
    );
  }
}
