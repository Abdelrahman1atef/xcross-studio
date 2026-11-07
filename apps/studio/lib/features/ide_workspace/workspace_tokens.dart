import 'package:flutter/material.dart';

/// Original dark tokens inspired by an IDE layout; not Apple assets or fonts.
abstract final class WorkspaceTokens {
  static const canvas = Color(0xFF111318);
  static const toolbar = Color(0xFF202329);
  static const navigator = Color(0xFF1B1D23);
  static const editor = Color(0xFF17191F);
  static const inspector = Color(0xFF202228);
  static const console = Color(0xFF111318);
  static const surface = Color(0xFF262931);
  static const border = Color(0xFF343840);
  static const selection = Color(0xFF1B4E8E);
  static const accent = Color(0xFF0A84FF);
  static const text = Color(0xFFEBEDF2);
  static const secondary = Color(0xFFACB1BB);
  static const muted = Color(0xFF808794);
  static const success = Color(0xFF32D77B);
  static const warning = Color(0xFFFFB340);
  static const error = Color(0xFFFF5E5B);
  static const focus = Color(0xFF80BEFF);

  static const toolbarHeight = 52.0;
  static const statusHeight = 25.0;
  static const dividerHandle = 8.0;
  static const minimumEditorWidth = 360.0;
  static const minimumNavigatorWidth = 190.0;
  static const minimumInspectorWidth = 240.0;
  static const minimumPreviewWidth = 260.0;
  static const minimumConsoleHeight = 120.0;

  static const inspectorBreakpoint = 1180.0;
  static const previewBreakpoint = 1360.0;
  static const navigatorBreakpoint = 760.0;
}
