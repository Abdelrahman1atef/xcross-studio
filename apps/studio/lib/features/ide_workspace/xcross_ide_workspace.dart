import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'workspace_layout_controller.dart';
import 'workspace_tokens.dart';

/// UI-only capabilities. Map these explicitly from the existing T006 service.
enum WorkspaceCapability { supported, unsupported, unknown }

/// Minimal, non-invasive workspace shell for an existing Flutter desktop app.
///
/// The host supplies all real actions and data. No CLI process is started here,
/// no secrets are retained, and the editor is deliberately not integrated while
/// T002 (native editor evidence) remains open.
class XCrossIdeWorkspace extends StatefulWidget {
  const XCrossIdeWorkspace({
    super.key,
    required this.layout,
    required this.projectName,
    this.navigator,
    this.editor,
    this.inspector,
    this.devicePreview,
    this.console,
    this.deviceLabel,
    this.statusLabel,
    this.buildMode,
    this.runCapability = WorkspaceCapability.unknown,
    this.hasVerifiedRunReadiness = false,
    this.readinessMessage,
    this.onRun,
    this.onStop,
    this.isRunning = false,
    this.canStop = false,
  });

  final WorkspaceLayoutController layout;
  final String projectName;
  final Widget? navigator;
  final Widget? editor;
  final Widget? inspector;
  final Widget? devicePreview;
  final Widget? console;
  final String? deviceLabel;
  final String? statusLabel;
  final String? buildMode;
  final WorkspaceCapability runCapability;
  /// Command support is not sufficient: device/auth/project readiness must
  /// also have been verified by the host before Run can be enabled.
  final bool hasVerifiedRunReadiness;
  final String? readinessMessage;
  final VoidCallback? onRun;
  final VoidCallback? onStop;
  final bool isRunning;
  final bool canStop;

  @override
  State<XCrossIdeWorkspace> createState() => _XCrossIdeWorkspaceState();
}

class _XCrossIdeWorkspaceState extends State<XCrossIdeWorkspace> {
  // Respect the actual minimum editor width even for restored oversized panes.
  bool _canDockNavigator(double width) =>
      width >= WorkspaceTokens.navigatorBreakpoint &&
      width - widget.layout.navigatorWidth - WorkspaceTokens.dividerHandle >=
          WorkspaceTokens.minimumEditorWidth;

  bool _showNavigator(double width) =>
      widget.layout.showNavigator && _canDockNavigator(width);

  bool _canDockInspector(double width) {
    final navigatorSpace = _showNavigator(width)
        ? widget.layout.navigatorWidth + WorkspaceTokens.dividerHandle
        : 0.0;
    return width >= WorkspaceTokens.inspectorBreakpoint &&
        width - navigatorSpace - widget.layout.inspectorWidth -
                WorkspaceTokens.dividerHandle >=
            WorkspaceTokens.minimumEditorWidth;
  }

  bool _showInspector(double width) =>
      widget.layout.showInspector && _canDockInspector(width);

  bool _canDockPreview(double width) {
    final navigatorSpace = _showNavigator(width)
        ? widget.layout.navigatorWidth + WorkspaceTokens.dividerHandle
        : 0.0;
    final inspectorSpace = _showInspector(width)
        ? widget.layout.inspectorWidth + WorkspaceTokens.dividerHandle
        : 0.0;
    return width >= WorkspaceTokens.previewBreakpoint &&
        width - navigatorSpace - inspectorSpace - widget.layout.previewWidth -
                WorkspaceTokens.dividerHandle >=
            WorkspaceTokens.minimumEditorWidth;
  }

  bool _showPreview(double width) =>
      widget.layout.showPreview && _canDockPreview(width);

  Future<void> _openOverlay(String title, Widget content) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: WorkspaceTokens.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 48,
              child: Row(children: [
                const SizedBox(width: 16),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: 'Close $title',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ]),
            ),
            const Divider(height: 1, color: WorkspaceTokens.border),
            Flexible(child: content),
          ]),
        ),
      ),
    );
  }

  void _navigatorPressed(double width) {
    if (!_canDockNavigator(width)) {
      _openOverlay('Project Navigator', widget.navigator ??
          const _EmptyPane('Open a Flutter project to browse files.'));
    } else {
      widget.layout.showNavigator = !widget.layout.showNavigator;
    }
  }

  void _inspectorPressed(double width) {
    if (!_canDockInspector(width)) {
      _openOverlay('Inspector', widget.inspector ??
          const _EmptyPane('Select an item to inspect.'));
    } else {
      widget.layout.showInspector = !widget.layout.showInspector;
    }
  }

  void _previewPressed(double width) {
    if (!_canDockPreview(width)) {
      _openOverlay('Device Preview', widget.devicePreview ??
          const _EmptyPane('No live device preview is available.'));
    } else {
      widget.layout.showPreview = !widget.layout.showPreview;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: WorkspaceTokens.accent,
          surface: WorkspaceTokens.surface,
        ),
        iconTheme: const IconThemeData(color: WorkspaceTokens.secondary),
      ),
      child: AnimatedBuilder(
      animation: widget.layout,
      builder: (context, _) => LayoutBuilder(builder: (context, limits) {
        final width = limits.maxWidth;
        final navigatorVisible = _showNavigator(width);
        final inspectorVisible = _showInspector(width);
        final previewVisible = _showPreview(width);
        final consoleVisible = widget.layout.showConsole;

        // Prioritize editor space, then inspector, then optional device preview.
        final editorWithNavigator = width -
            (navigatorVisible ? widget.layout.navigatorWidth + WorkspaceTokens.dividerHandle : 0);
        final useInspector = inspectorVisible &&
            editorWithNavigator - widget.layout.inspectorWidth - WorkspaceTokens.dividerHandle >=
                WorkspaceTokens.minimumEditorWidth;
        final editorWithInspector = editorWithNavigator -
            (useInspector ? widget.layout.inspectorWidth + WorkspaceTokens.dividerHandle : 0);
        final usePreview = previewVisible &&
            editorWithInspector - widget.layout.previewWidth - WorkspaceTokens.dividerHandle >=
                WorkspaceTokens.minimumEditorWidth;

        return ColoredBox(
          color: WorkspaceTokens.canvas,
          child: Column(children: [
            _toolbar(width),
            Expanded(child: Row(children: [
              if (navigatorVisible) ...[
                SizedBox(width: widget.layout.navigatorWidth,
                  child: _pane(WorkspaceTokens.navigator, widget.navigator ??
                      const _EmptyPane('Open a Flutter project to browse files.'))),
                _ResizeHandle(horizontal: true,
                  onDelta: (d) => widget.layout.navigatorWidth += d),
              ],
              Expanded(child: _pane(WorkspaceTokens.editor,
                widget.editor ?? const _EmptyPane(
                  'Source editor not connected. Native editor integration requires T002 evidence.'))),
              if (usePreview) ...[
                _ResizeHandle(horizontal: true,
                  onDelta: (d) => widget.layout.previewWidth -= d),
                SizedBox(width: widget.layout.previewWidth,
                  child: _pane(WorkspaceTokens.inspector, widget.devicePreview ??
                      const _EmptyPane('No live device preview is available.'))),
              ],
              if (useInspector) ...[
                _ResizeHandle(horizontal: true,
                  onDelta: (d) => widget.layout.inspectorWidth -= d),
                SizedBox(width: widget.layout.inspectorWidth,
                  child: _pane(WorkspaceTokens.inspector, widget.inspector ??
                      const _EmptyPane('Select an item to inspect.'))),
              ],
            ])),
            if (consoleVisible) ...[
              _ResizeHandle(horizontal: false,
                onDelta: (d) => widget.layout.consoleHeight -= d),
              SizedBox(
                height: widget.layout.consoleHeight.clamp(
                  WorkspaceTokens.minimumConsoleHeight,
                  (limits.maxHeight * 0.5).clamp(WorkspaceTokens.minimumConsoleHeight, 550),
                ).toDouble(),
                child: _pane(WorkspaceTokens.console,
                  widget.console ?? const _EmptyPane('No build or device output.')),
              ),
            ],
            Container(
              height: WorkspaceTokens.statusHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: WorkspaceTokens.toolbar,
                border: Border(top: BorderSide(color: WorkspaceTokens.border)),
              ),
              alignment: Alignment.centerLeft,
              child: Row(children: [
                const Icon(Icons.code, size: 13, color: WorkspaceTokens.secondary),
                const SizedBox(width: 6),
                Flexible(child: Text(widget.projectName, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: WorkspaceTokens.secondary))),
                if (widget.buildMode != null) ...[
                  const SizedBox(width: 16),
                  Text(widget.buildMode!, style: const TextStyle(fontSize: 11, color: WorkspaceTokens.secondary)),
                ],
                if (widget.deviceLabel != null) ...[
                  const SizedBox(width: 16),
                  Flexible(child: Text(widget.deviceLabel!, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: WorkspaceTokens.secondary))),
                ],
              ]),
            ),
          ]),
        );
      }),
      ),
    );
  }

  Widget _toolbar(double width) {
    final canRun = widget.runCapability == WorkspaceCapability.supported &&
        widget.hasVerifiedRunReadiness && widget.onRun != null && !widget.isRunning;
    final canStop = widget.isRunning && widget.canStop && widget.onStop != null;
    final runReason = switch (widget.runCapability) {
      WorkspaceCapability.supported => widget.isRunning
          ? 'A run is already active'
          : !widget.hasVerifiedRunReadiness
              ? widget.readinessMessage ?? 'Project/device/signing readiness is unverified'
              : widget.onRun == null
                  ? 'Run action is not connected'
                  : 'Run current configuration',
      WorkspaceCapability.unsupported => 'Run is not supported by the selected XCross CLI',
      WorkspaceCapability.unknown => 'XCross CLI run capability has not been verified',
    };
    return Container(
      height: WorkspaceTokens.toolbarHeight,
      decoration: const BoxDecoration(
        color: WorkspaceTokens.toolbar,
        border: Border(bottom: BorderSide(color: WorkspaceTokens.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        const Icon(Icons.developer_board_outlined, size: 21, color: WorkspaceTokens.accent),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width > 900 ? 220 : 120),
          child: Text(widget.projectName, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WorkspaceTokens.text, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: runReason,
          child: FilledButton.icon(
            onPressed: canRun ? widget.onRun : null,
            icon: const Icon(Icons.play_arrow, size: 17),
            label: const Text('Run'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              backgroundColor: WorkspaceTokens.accent,
              disabledBackgroundColor: WorkspaceTokens.surface,
              foregroundColor: Colors.white,
              disabledForegroundColor: WorkspaceTokens.muted,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        Tooltip(
          message: canStop ? 'Stop active run' : 'Stop is unavailable',
          child: IconButton(
            icon: const Icon(Icons.stop, size: 19),
            onPressed: canStop ? widget.onStop : null,
          ),
        ),
        if (width > 920) ...[
          const SizedBox(width: 8),
          Flexible(child: Text(widget.statusLabel ?? 'Status unknown',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WorkspaceTokens.secondary, fontSize: 12))),
        ],
        const Spacer(),
        IconButton(
          tooltip: 'Project Navigator',
          isSelected: widget.layout.showNavigator,
          onPressed: () => _navigatorPressed(width),
          icon: const Icon(Icons.account_tree_outlined, size: 19),
        ),
        IconButton(
          tooltip: 'Device Preview',
          isSelected: widget.layout.showPreview,
          onPressed: () => _previewPressed(width),
          icon: const Icon(Icons.phone_iphone, size: 19),
        ),
        IconButton(
          tooltip: 'Inspector',
          isSelected: widget.layout.showInspector,
          onPressed: () => _inspectorPressed(width),
          icon: const Icon(Icons.tune, size: 19),
        ),
        IconButton(
          tooltip: 'Console',
          isSelected: widget.layout.showConsole,
          onPressed: () => widget.layout.showConsole = !widget.layout.showConsole,
          icon: const Icon(Icons.terminal, size: 19),
        ),
      ]),
    );
  }

  Widget _pane(Color color, Widget child) => ColoredBox(color: color, child: child);
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center,
        style: const TextStyle(color: WorkspaceTokens.secondary, fontSize: 12)),
    ),
  );
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.horizontal, required this.onDelta});
  final bool horizontal;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final positive = horizontal
          ? event.logicalKey == LogicalKeyboardKey.arrowRight
          : event.logicalKey == LogicalKeyboardKey.arrowDown;
      final negative = horizontal
          ? event.logicalKey == LogicalKeyboardKey.arrowLeft
          : event.logicalKey == LogicalKeyboardKey.arrowUp;
      if (!positive && !negative) return KeyEventResult.ignored;
      onDelta(positive ? 12 : -12);
      return KeyEventResult.handled;
    },
    child: MouseRegion(
      cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      child: Semantics(
        label: horizontal ? 'Resize workspace panel horizontally' : 'Resize console vertically',
        hint: 'Use arrow keys to resize',
        onIncrease: () => onDelta(12),
        onDecrease: () => onDelta(-12),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: horizontal ? (event) => onDelta(event.delta.dx) : null,
          onVerticalDragUpdate: horizontal ? null : (event) => onDelta(event.delta.dy),
          child: SizedBox(
            width: horizontal ? WorkspaceTokens.dividerHandle : double.infinity,
            height: horizontal ? double.infinity : WorkspaceTokens.dividerHandle,
            child: Center(child: Container(
              width: horizontal ? 1 : double.infinity,
              height: horizontal ? double.infinity : 1,
              color: WorkspaceTokens.border,
            )),
          ),
        ),
      ),
    ),
  );
}
