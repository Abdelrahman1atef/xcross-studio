/// Spacing tokens on the 8 px grid with 4 px half steps (§2.4).
abstract final class XSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s6 = 24;
  static const double s8 = 32;

  /// Target height for primary interactive rows and controls in page-style
  /// screens (40–44 px). Workspace chrome uses [XDimensions] instead.
  static const double control = 40;
}

/// Icon sizes (§2.4): compact, standard and toolbar.
abstract final class XIcon {
  static const double compact = 16;
  static const double standard = 18;
  static const double toolbar = 20;
}

/// Corner radii (§2.4: panels and popovers 6–10 px; editors and primary
/// panes stay square-edged).
abstract final class XRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;

  /// Smallest and largest panel / popover corner (§2.4).
  static const double panelMin = 6;
  static const double panelMax = 10;
}

/// Motion durations (§2.4: 120–180 ms). Use [of] so reduced-motion
/// settings turn animations off.
abstract final class XMotion {
  static const hover = Duration(milliseconds: 140);
  static const panel = Duration(milliseconds: 160);

  /// [duration], or zero when the platform asks to reduce motion.
  static Duration of(Duration duration, {required bool reduceMotion}) =>
      reduceMotion ? Duration.zero : duration;
}
