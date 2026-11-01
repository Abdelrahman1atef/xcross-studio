import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../src/cli/xcross_events.dart';

/// An installed app's signer, push / associated-domain badges and
/// entitlements, from `xcross app info --json`.
class AppInfoView extends StatelessWidget {
  const AppInfoView({super.key, required this.info});

  final AppInfo info;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${info.name ?? info.bundleId} ${info.version ?? ''} '
        '(${info.build ?? '-'})',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      XNote('signer: ${info.signer} · team ${info.teamId ?? '-'}'),
      const SizedBox(height: XSpace.s2),
      XCheckRow(
        status: info.push != null ? XStatus.ready : XStatus.failed,
        label: 'Push entitlement',
        detail: info.push ?? 'missing',
      ),
      XCheckRow(
        status: info.associatedDomains.isNotEmpty
            ? XStatus.ready
            : XStatus.failed,
        label: 'Associated domains',
        detail: info.associatedDomains.isEmpty
            ? 'none'
            : info.associatedDomains.join(', '),
      ),
      const Divider(height: XSpace.s4),
      for (final MapEntry(:key, :value) in info.entitlements.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText(
            '$key: $value',
            style: XType.mono.copyWith(
              color: XTheme.of(context).colors.textSecondary,
            ),
          ),
        ),
    ],
  );
}
