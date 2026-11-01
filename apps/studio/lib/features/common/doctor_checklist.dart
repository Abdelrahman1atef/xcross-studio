import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../src/cli/xcross_events.dart';

XStatus statusOfCheck(DoctorCheckResult check) => switch (check.status) {
  'success' => XStatus.ready,
  'failure' => XStatus.failed,
  _ => XStatus.warning,
};

/// `flutter doctor` checks grouped by section, exactly as the CLI reported
/// them (`check` events).
class DoctorChecklist extends StatelessWidget {
  const DoctorChecklist({super.key, required this.checks});

  final List<DoctorCheckResult> checks;

  @override
  Widget build(BuildContext context) {
    final sections = <String, List<DoctorCheckResult>>{};
    for (final check in checks) {
      sections.putIfAbsent(check.section, () => []).add(check);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: section, value: list) in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: XSpace.s2, bottom: 2),
            child: Text(section, style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final check in list)
            XCheckRow(
              status: statusOfCheck(check),
              label: check.name,
              detail:
                  '${check.message}'
                  '${check.path == null ? '' : '  (${check.path})'}',
            ),
        ],
      ],
    );
  }
}
