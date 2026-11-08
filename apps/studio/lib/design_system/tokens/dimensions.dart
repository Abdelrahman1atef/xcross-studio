/// Workspace geometry (§2.4, §3.1). Widths and heights are logical pixels.
abstract final class XDimensions {
  // Window.
  static const double windowWidth = 1600;
  static const double windowHeight = 900;
  static const double windowMinWidth = 1100;
  static const double windowMinHeight = 700;

  // Chrome.
  static const double toolbarHeight = 52;
  static const double toolbarMinHeight = 48;
  static const double statusHeight = 25;
  static const double statusMinHeight = 24;

  // Regions: default and minimum.
  static const double navigatorWidth = 280;
  static const double navigatorMinWidth = 190;
  static const double inspectorWidth = 300;
  static const double inspectorMinWidth = 240;
  static const double previewWidth = 350;
  static const double previewMinWidth = 260;
  static const double consoleHeight = 210;
  static const double consoleMinHeight = 120;
  static const double editorMinWidth = 360;

  // Responsive breakpoints (window width, §3.1 and §9).
  /// Below this, preview or inspector collapses by default.
  static const double previewBreakpoint = 1360;

  /// Below this, only navigator + editor are open by default.
  static const double inspectorBreakpoint = 1180;

  /// Large screens where every region can be open (§9).
  static const double largeBreakpoint = 1600;

  // Controls.
  static const double toolbarControlHeight = 30;
  static const double runButtonMinTarget = 36;
  static const double treeRowHeight = 26;
  static const double inputHeight = 31;

  // Split handle: 1 px visible divider, larger invisible hit target.
  static const double divider = 1;
  static const double splitHitTarget = 8;

  // Compact icon button sizes (XIconButton: 28 / 32 / 36).
  static const double iconButtonSmall = 28;
  static const double iconButtonMedium = 32;
  static const double iconButtonLarge = 36;
}
