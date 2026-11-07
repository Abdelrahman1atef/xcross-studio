import 'package:flutter/foundation.dart';

/// Pure UI state only. No device, CLI, credential, or file operations.
///
/// Hosts can persist [toJson] in their existing settings service. Restoring
/// values is defensive: malformed and non-finite dimensions are discarded.
class WorkspaceLayoutController extends ChangeNotifier {
  WorkspaceLayoutController({
    double navigatorWidth = 280,
    double inspectorWidth = 300,
    double previewWidth = 350,
    double consoleHeight = 210,
    bool showNavigator = true,
    bool showInspector = true,
    bool showPreview = false,
    bool showConsole = true,
  })  : _navigatorWidth = _dimension(navigatorWidth, 190, 600, 280),
        _inspectorWidth = _dimension(inspectorWidth, 240, 550, 300),
        _previewWidth = _dimension(previewWidth, 260, 600, 350),
        _consoleHeight = _dimension(consoleHeight, 120, 550, 210),
        _showNavigator = showNavigator,
        _showInspector = showInspector,
        _showPreview = showPreview,
        _showConsole = showConsole;

  double _navigatorWidth;
  double _inspectorWidth;
  double _previewWidth;
  double _consoleHeight;
  bool _showNavigator;
  bool _showInspector;
  bool _showPreview;
  bool _showConsole;

  double get navigatorWidth => _navigatorWidth;
  double get inspectorWidth => _inspectorWidth;
  double get previewWidth => _previewWidth;
  double get consoleHeight => _consoleHeight;
  bool get showNavigator => _showNavigator;
  bool get showInspector => _showInspector;
  bool get showPreview => _showPreview;
  bool get showConsole => _showConsole;

  static double _dimension(num? value, double min, double max, double fallback) {
    if (value == null || !value.isFinite) return fallback;
    return value.toDouble().clamp(min, max).toDouble();
  }

  set navigatorWidth(double value) {
    final next = _dimension(value, 190, 600, 280);
    if (next != _navigatorWidth) { _navigatorWidth = next; notifyListeners(); }
  }

  set inspectorWidth(double value) {
    final next = _dimension(value, 240, 550, 300);
    if (next != _inspectorWidth) { _inspectorWidth = next; notifyListeners(); }
  }

  set previewWidth(double value) {
    final next = _dimension(value, 260, 600, 350);
    if (next != _previewWidth) { _previewWidth = next; notifyListeners(); }
  }

  set consoleHeight(double value) {
    final next = _dimension(value, 120, 550, 210);
    if (next != _consoleHeight) { _consoleHeight = next; notifyListeners(); }
  }

  set showNavigator(bool value) {
    if (value != _showNavigator) { _showNavigator = value; notifyListeners(); }
  }

  set showInspector(bool value) {
    if (value != _showInspector) { _showInspector = value; notifyListeners(); }
  }

  set showPreview(bool value) {
    if (value != _showPreview) { _showPreview = value; notifyListeners(); }
  }

  set showConsole(bool value) {
    if (value != _showConsole) { _showConsole = value; notifyListeners(); }
  }

  Map<String, Object> toJson() => {
    'navigatorWidth': _navigatorWidth,
    'inspectorWidth': _inspectorWidth,
    'previewWidth': _previewWidth,
    'consoleHeight': _consoleHeight,
    'showNavigator': _showNavigator,
    'showInspector': _showInspector,
    'showPreview': _showPreview,
    'showConsole': _showConsole,
  };

  factory WorkspaceLayoutController.fromJson(Map<String, dynamic> json) {
    num? readNumber(String key) => json[key] is num ? json[key] as num : null;
    bool readBool(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    return WorkspaceLayoutController(
      navigatorWidth: _dimension(readNumber('navigatorWidth'), 190, 600, 280),
      inspectorWidth: _dimension(readNumber('inspectorWidth'), 240, 550, 300),
      previewWidth: _dimension(readNumber('previewWidth'), 260, 600, 350),
      consoleHeight: _dimension(readNumber('consoleHeight'), 120, 550, 210),
      showNavigator: readBool('showNavigator', true),
      showInspector: readBool('showInspector', true),
      showPreview: readBool('showPreview', false),
      showConsole: readBool('showConsole', true),
    );
  }
}
