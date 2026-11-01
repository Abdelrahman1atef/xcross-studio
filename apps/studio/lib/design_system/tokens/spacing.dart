/// Spacing tokens on the 8 px grid with 4 px half steps (design system §3.4).
abstract final class XSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s6 = 24;
  static const double s8 = 32;

  /// Target height for primary interactive rows and controls (40–44 px).
  static const double control = 40;
}

/// Corner radii (design system §3.4).
abstract final class XRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
}

/// Motion durations (design system §3.5). Use [of] so reduced-motion
/// settings turn animations off.
abstract final class XMotion {
  static const hover = Duration(milliseconds: 140);
  static const panel = Duration(milliseconds: 200);

  /// [duration], or zero when the platform asks to reduce motion.
  static Duration of(Duration duration, {required bool reduceMotion}) =>
      reduceMotion ? Duration.zero : duration;
}
