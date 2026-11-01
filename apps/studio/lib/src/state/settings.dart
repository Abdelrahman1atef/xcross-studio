import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../cli/xcross_commands.dart';

/// Theme preference (feature 013).
enum ThemePreference { dark, light, system }

/// What the GUI remembers between runs, in `<config>/settings.json`.
class Settings extends ChangeNotifier {
  Settings({this.file});

  /// `null` keeps settings in memory only (tests).
  final File? file;

  XcrossInvocation invocation = const XcrossInvocation.binary();

  /// The source checkout used by "Run from source", when chosen.
  String? sourceRepository;
  String? projectPath;
  String? udid;
  String? ddiDirectory;
  String? lastIpa;
  String? logApp;
  bool acceptedNotice = false;

  // studio: 013 — design system shell.
  /// The first-run wizard was closed; it no longer opens by itself.
  bool wizardDismissed = false;
  ThemePreference theme = ThemePreference.dark;
  bool consoleOpen = true;
  double consoleHeight = 220;

  /// The Xcode.xip chosen in the wizard.
  String? xcodeXip;

  static Future<Settings> load(String directory) async {
    final settings = Settings(file: File(p.join(directory, 'settings.json')));
    try {
      final json = jsonDecode(await settings.file!.readAsString());
      if (json is Map<String, Object?>) settings._read(json);
    } on Object {
      // First run or unreadable file: defaults.
    }
    return settings;
  }

  void _read(Map<String, Object?> json) {
    String? text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    invocation = XcrossInvocation.fromJson(json['invocation']);
    sourceRepository = text('sourceRepository');
    projectPath = text('projectPath');
    udid = text('udid');
    ddiDirectory = text('ddiDirectory');
    lastIpa = text('lastIpa');
    logApp = text('logApp');
    acceptedNotice = json['acceptedNotice'] == true;
    wizardDismissed = json['wizardDismissed'] == true;
    theme =
        ThemePreference.values.asNameMap()[text('theme')] ??
        ThemePreference.dark;
    consoleOpen = json['consoleOpen'] != false;
    if (json['consoleHeight'] case final num height) {
      consoleHeight = height.toDouble().clamp(120, 900);
    }
    xcodeXip = text('xcodeXip');
  }

  Map<String, Object?> toJson() => {
    'invocation': invocation.toJson(),
    'sourceRepository': sourceRepository,
    'projectPath': projectPath,
    'udid': udid,
    'ddiDirectory': ddiDirectory,
    'lastIpa': lastIpa,
    'logApp': logApp,
    'acceptedNotice': acceptedNotice,
    'wizardDismissed': wizardDismissed,
    'theme': theme.name,
    'consoleOpen': consoleOpen,
    'consoleHeight': consoleHeight,
    'xcodeXip': xcodeXip,
  };

  /// Applies [change], notifies and saves.
  Future<void> update(void Function(Settings settings) change) async {
    change(this);
    notifyListeners();
    final target = file;
    if (target == null) return;
    try {
      await target.parent.create(recursive: true);
      await target.writeAsString(
        const JsonEncoder.withIndent('  ').convert(toJson()),
      );
    } on FileSystemException {
      // Settings are a convenience; a read-only profile must not break the app.
    }
  }
}
