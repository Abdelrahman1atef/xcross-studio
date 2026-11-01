// Renders the main screens to PNG with the bundled fonts for visual review.
// Opt-in: STUDIO_SCREENSHOTS=1 flutter test test/ui/screenshot_test.dart
// (images land in build/screenshots/). Not a golden comparison.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/src/state/settings.dart';

import 'app_test.dart' as app;

Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Inter', ['Inter-Regular', 'Inter-Medium', 'Inter-SemiBold']),
    ('JetBrainsMono', ['JetBrainsMono-Regular', 'JetBrainsMono-Medium']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file.ttf'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  final enabled = Platform.environment['STUDIO_SCREENSHOTS'] == '1';

  testWidgets('screenshots of the main screens', (tester) async {
    await tester.runAsync(_loadFonts);
    await app.pumpStudio(
      tester,
      doctor: app.failingDoctor,
      size: const Size(1440, 900),
      settings: Settings()..wizardDismissed = true,
    );
    final out = Directory('build/screenshots')..createSync(recursive: true);
    Future<void> shot(String name) async {
      await app.settle(tester, 3);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('${out.path}/$name.png').writeAsBytesSync(bytes!);
    }

    await shot('overview');
    for (final (label, name) in [
      ('Build & Run', 'build'),
      ('Devices', 'devices'),
      ('Signing', 'signing'),
      ('Logs & Debug', 'logs'),
      ('Settings', 'settings'),
    ]) {
      await tester.tap(
        find.descendant(
          of: find.byType(XSidebarItem),
          matching: find.text(label),
        ),
      );
      await shot(name);
    }
  }, skip: !enabled);
}
