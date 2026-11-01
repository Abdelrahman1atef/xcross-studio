import 'package:flutter/material.dart';

import '../design_system/design_system.dart';

/// One entry of the quick-command palette (Ctrl+K).
class QuickCommand {
  const QuickCommand(this.label, this.icon, this.run);

  final String label;
  final IconData icon;
  final VoidCallback run;
}

/// Opens the palette; Enter runs the first match.
Future<void> showQuickCommands(
  BuildContext context,
  List<QuickCommand> commands,
) => showDialog<void>(
  context: context,
  builder: (context) => QuickCommandPalette(commands: commands),
);

class QuickCommandPalette extends StatefulWidget {
  const QuickCommandPalette({super.key, required this.commands});

  final List<QuickCommand> commands;

  @override
  State<QuickCommandPalette> createState() => _QuickCommandPaletteState();
}

class _QuickCommandPaletteState extends State<QuickCommandPalette> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<QuickCommand> get _matches {
    final query = _filter.text.trim().toLowerCase();
    return [
      for (final command in widget.commands)
        if (query.isEmpty || command.label.toLowerCase().contains(query))
          command,
    ];
  }

  void _run(QuickCommand command) {
    Navigator.of(context).pop();
    command.run();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.all(XSpace.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _filter,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type a command…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (matches.isNotEmpty) _run(matches.first);
                },
              ),
              const SizedBox(height: XSpace.s2),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final command in matches)
                      ListTile(
                        dense: true,
                        leading: Icon(command.icon, size: 18),
                        title: Text(command.label),
                        onTap: () => _run(command),
                      ),
                    if (matches.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(XSpace.s3),
                        child: XNote('No matching command.'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
