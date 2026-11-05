import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/state/project_health.dart';
import '../common/attention_widgets.dart';
import 'capabilities_tab.dart';
import 'permissions_tab.dart';
import 'plugins_tab.dart';

/// Project (features 027 and 028): what the app asks iOS for (permissions and
/// capabilities, like Xcode's Info and Signing & Capabilities tabs) and how
/// each plugin is built, with what needs doing at the top.
class ProjectPage extends StatelessWidget {
  const ProjectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.app,
        services.settings,
        services.projectHealth,
      ]),
      builder: (context, _) {
        final project = services.settings.projectPath;
        final health = services.projectHealth;
        final tab = services.app.projectTab;
        return WorkspaceLayout(
          title: 'Project',
          subtitle:
              'Permissions, capabilities and plugins of the iOS app'
              '${project == null ? '' : ': $project'}',
          actions: [
            XButton(
              label: 'Check again',
              icon: Icons.refresh,
              loading: health.refreshing,
              loadingLabel: 'Checking…',
              disabledReason: 'Open a Flutter project first.',
              onPressed: project == null ? null : health.refresh,
            ),
          ],
          children: [
            const AttentionList(title: 'To do'),
            SegmentedButton<ProjectTab>(
              segments: [
                ButtonSegment(
                  value: ProjectTab.permissions,
                  label: const Text('Permissions'),
                  icon: const Icon(Icons.privacy_tip_outlined),
                ),
                ButtonSegment(
                  value: ProjectTab.capabilities,
                  label: const Text('Capabilities'),
                  icon: const Icon(Icons.verified_outlined),
                ),
                ButtonSegment(
                  value: ProjectTab.plugins,
                  label: const Text('Plugins'),
                  icon: const Icon(Icons.extension_outlined),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (choice) =>
                  services.app.goProject(choice.first),
            ),
            switch (tab) {
              ProjectTab.permissions => const PermissionsTab(),
              ProjectTab.capabilities => const CapabilitiesTab(),
              ProjectTab.plugins => const PluginsTab(),
            },
          ],
        );
      },
    );
  }
}
