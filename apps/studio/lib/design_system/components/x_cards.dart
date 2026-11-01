import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'x_card.dart';
import 'x_status.dart';

/// One readiness requirement of a device or tool.
class XRequirement {
  const XRequirement(this.status, this.label, {this.detail});

  final XStatus status;
  final String label;
  final String? detail;
}

/// Device card states (design system §8).
enum XDeviceState { connected, unavailable, pairing, error }

/// Device identity plus every readiness requirement, so "discovered" is
/// never shown as "ready to run" (§6.3).
class XDeviceCard extends StatelessWidget {
  const XDeviceCard({
    super.key,
    required this.name,
    required this.state,
    this.osVersion,
    this.transport,
    this.udid,
    this.requirements = const [],
    this.selected = false,
    this.onTap,
    this.actions = const [],
  });

  final String name;
  final XDeviceState state;
  final String? osVersion;
  final String? transport;
  final String? udid;
  final List<XRequirement> requirements;
  final bool selected;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final (status, label) = switch (state) {
      XDeviceState.connected => (XStatus.ready, 'Connected'),
      XDeviceState.unavailable => (XStatus.idle, 'Unavailable'),
      XDeviceState.pairing => (XStatus.running, 'Pairing'),
      XDeviceState.error => (XStatus.failed, 'Error'),
    };
    return XCard(
      onTap: onTap,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.phone_iphone, color: c.textSecondary),
              const SizedBox(width: XSpace.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: XType.card.copyWith(color: c.textPrimary),
                    ),
                    Text(
                      [
                        if (osVersion != null) 'iOS $osVersion',
                        ?transport,
                      ].join(' · '),
                      style: XType.support.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              XStatusBadge(status: status, label: label),
            ],
          ),
          if (udid != null)
            Row(
              children: [
                Flexible(
                  child: SelectableText(
                    'UDID $udid',
                    style: XType.mono.copyWith(
                      color: c.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy UDID',
                  iconSize: 14,
                  color: c.textMuted,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: udid!)),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          if (requirements.isNotEmpty) ...[
            const SizedBox(height: XSpace.s2),
            for (final r in requirements)
              XCheckRow(status: r.status, label: r.label, detail: r.detail),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: XSpace.s3),
            Wrap(spacing: XSpace.s2, runSpacing: XSpace.s2, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Toolchain card states (design system §8).
enum XToolchainState { valid, missing, mismatched, checking, unknown }

/// Health of one prerequisite (Swift, LLVM, Darwin SDK, …).
class XToolchainCard extends StatelessWidget {
  const XToolchainCard({
    super.key,
    required this.title,
    required this.state,
    this.message,
    this.width = 240,
  });

  final String title;
  final XToolchainState state;
  final String? message;
  final double? width;

  static XStatus statusOf(XToolchainState state) => switch (state) {
    XToolchainState.valid => XStatus.ready,
    XToolchainState.missing => XStatus.failed,
    XToolchainState.mismatched => XStatus.warning,
    XToolchainState.checking => XStatus.running,
    XToolchainState.unknown => XStatus.idle,
  };

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final status = statusOf(state);
    final label = switch (state) {
      XToolchainState.valid => 'Ready',
      XToolchainState.missing => 'Missing',
      XToolchainState.mismatched => 'Needs attention',
      XToolchainState.checking => 'Checking…',
      XToolchainState.unknown => 'Not checked',
    };
    final card = XCard(
      padding: const EdgeInsets.all(XSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: XType.card.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: XSpace.s1),
          XStatusBadge(status: status, label: label),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: XSpace.s2),
            Text(
              message!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: XType.support.copyWith(color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// A navigation entry (design system §8): icon + label, or icon only with a
/// tooltip when [compact].
class XSidebarItem extends StatelessWidget {
  const XSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.enabled = true,
    this.shortcut,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final bool enabled;

  /// Shown in the tooltip (`Ctrl+L`).
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final color = !enabled
        ? c.textMuted
        : (selected ? c.textPrimary : c.textSecondary);
    final item = Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? c.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(XRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(XRadius.md),
          hoverColor: c.primary.withValues(alpha: 0.08),
          onTap: enabled ? onTap : null,
          child: Container(
            height: XSpace.control,
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : XSpace.s3),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? c.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: selected ? c.primary : color),
                if (!compact) ...[
                  const SizedBox(width: XSpace.s3),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: XType.body.copyWith(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final tip = compact
        ? '$label${shortcut == null ? '' : '  ($shortcut)'}'
        : shortcut;
    return tip == null ? item : Tooltip(message: tip, child: item);
  }
}
