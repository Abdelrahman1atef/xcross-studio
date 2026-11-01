import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'x_status.dart';

/// How a console line is coloured.
enum XConsoleTone {
  plain,
  command,
  success,
  failure,
  warning,
  error,
  hint,
  muted,
}

/// One console line.
class XConsoleLine {
  const XConsoleLine(this.text, [this.tone = XConsoleTone.plain]);

  final String text;
  final XConsoleTone tone;
}

/// Console states (design system §6.5).
enum XConsoleState { live, paused, complete, failed, stopped }

extension on XConsoleState {
  (XStatus, String) get badge => switch (this) {
    XConsoleState.live => (XStatus.running, 'Following live output'),
    XConsoleState.paused => (XStatus.warning, 'Paused'),
    XConsoleState.complete => (XStatus.ready, 'Ended'),
    XConsoleState.failed => (XStatus.failed, 'Failed'),
    XConsoleState.stopped => (XStatus.idle, 'Stopped'),
  };
}

/// Colour of a console [tone] from the theme tokens.
Color xConsoleColor(BuildContext context, XConsoleTone tone) {
  final c = XTheme.of(context).colors;
  return switch (tone) {
    XConsoleTone.error || XConsoleTone.failure => c.error,
    XConsoleTone.warning => c.warning,
    XConsoleTone.hint => c.primaryHover,
    XConsoleTone.success => c.success,
    XConsoleTone.command => c.primary,
    XConsoleTone.muted => c.textMuted,
    XConsoleTone.plain => c.textPrimary,
  };
}

/// Selectable, copyable log output with a state badge, auto-follow and an
/// optional input line ([onInput]: 2FA codes, `r`, `q`).
class XConsole extends StatefulWidget {
  const XConsole({
    super.key,
    required this.lines,
    required this.state,
    this.title,
    this.height = 280,
    this.onInput,
    this.inputHint = 'Type input for the command and press Enter',
    this.trailing,
    this.showHeader = true,
  });

  final List<XConsoleLine> lines;
  final XConsoleState state;
  final String? title;

  /// `null` fills the available height.
  final double? height;
  final ValueChanged<String>? onInput;
  final String inputHint;

  /// Extra header actions (Stop, …).
  final Widget? trailing;
  final bool showHeader;

  @override
  State<XConsole> createState() => _XConsoleState();
}

class _XConsoleState extends State<XConsole> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  bool _follow = true;
  int _seen = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _followIfNeeded() {
    if (widget.lines.length == _seen) return;
    _seen = widget.lines.length;
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    _followIfNeeded();
    final (status, label) = widget.state.badge;
    final output = Container(
      decoration: BoxDecoration(
        color: c.console,
        borderRadius: BorderRadius.circular(XRadius.md),
        border: Border.all(color: c.border),
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          _follow = n.metrics.pixels >= n.metrics.maxScrollExtent - 24;
          return false;
        },
        child: SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(XSpace.s3),
            itemCount: widget.lines.length,
            itemBuilder: (context, index) {
              final line = widget.lines[index];
              return Text(
                line.text,
                style: XType.mono.copyWith(
                  color: xConsoleColor(context, line.tone),
                ),
              );
            },
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.height == null ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.showHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: XSpace.s2),
            child: Row(
              children: [
                if (widget.title != null) ...[
                  Flexible(
                    child: Text(
                      widget.title!,
                      overflow: TextOverflow.ellipsis,
                      style: XType.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: XSpace.s2),
                ],
                XStatusBadge(status: status, label: label),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy output',
                  iconSize: 16,
                  color: c.textSecondary,
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: [for (final l in widget.lines) l.text].join('\n'),
                    ),
                  ),
                  icon: const Icon(Icons.copy),
                ),
                ?widget.trailing,
              ],
            ),
          ),
        if (widget.height == null)
          Expanded(child: output)
        else
          SizedBox(height: widget.height, child: output),
        if (widget.onInput != null) ...[
          const SizedBox(height: XSpace.s2),
          TextField(
            controller: _input,
            style: XType.mono.copyWith(color: c.textPrimary),
            decoration: InputDecoration(
              hintText: widget.inputHint,
              prefixIcon: const Icon(Icons.keyboard_return, size: 16),
            ),
            onSubmitted: (text) {
              widget.onInput!(text);
              _input.clear();
            },
          ),
        ],
      ],
    );
  }
}
