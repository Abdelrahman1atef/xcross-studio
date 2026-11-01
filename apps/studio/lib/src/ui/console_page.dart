import 'package:flutter/material.dart';

import '../state/job.dart';
import 'services.dart';
import 'widgets.dart';

/// Tool logs: every xcross command of this session with its full output.
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  Job? _selected;

  @override
  Widget build(BuildContext context) {
    final jobs = Services.of(context).jobs;
    return Watch(
      listenable: jobs,
      builder: (context) {
        final list = jobs.jobs.reversed.toList();
        final selected = list.contains(_selected)
            ? _selected
            : list.firstOrNull;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Commands',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: jobs.clearFinished,
                          child: const Text('Clear finished'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final job in list)
                          ListTile(
                            selected: job == selected,
                            dense: true,
                            leading: Icon(switch (job.status) {
                              JobStatus.running => Icons.hourglass_top,
                              JobStatus.succeeded => Icons.check_circle,
                              JobStatus.failed => Icons.error,
                              JobStatus.cancelled => Icons.stop_circle,
                            }),
                            title: Text(job.title),
                            subtitle: Text(
                              job.displayCommand,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => _selected = job),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const Center(child: Text('No commands run yet.'))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: JobOutputView(job: selected, height: null),
                    ),
            ),
          ],
        );
      },
    );
  }
}
