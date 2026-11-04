// Feature 024: text, clipart and badges drawn into PNGs, because the CLI has no
// font engine. Everything else about the icon is drawn by the CLI.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class SourceRender {
  static const side = 1024.0;

  /// [text] in white on transparent, fitted to a 1024 px square.
  static Future<Uint8List> text(
    String text, {
    String? fontFamily,
    bool bold = false,
    bool italic = false,
  }) => _render((canvas) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? ' ' : text,
        style: TextStyle(
          color: Colors.white,
          fontFamily: fontFamily,
          fontSize: 700,
          height: 1,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final longest = painter.width > painter.height
        ? painter.width
        : painter.height;
    final scale = longest > side ? side / longest : 1.0;
    canvas
      ..translate(side / 2, side / 2)
      ..scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  });

  /// [icon] in white on transparent, filling a 1024 px square.
  static Future<Uint8List> clipart(IconData icon) => _render((canvas) {
    TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            color: Colors.white,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: side,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, Offset.zero);
  });

  /// A band with [text] in it, as wide as the icon.
  static Future<Uint8List> badge(String text, Color color) async {
    const height = 170.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, side, height),
        Paint()..color = color,
      );
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          fontSize: 104,
          height: 1,
          fontWeight: FontWeight.bold,
          letterSpacing: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final scale = painter.width > side * 0.9 ? side * 0.9 / painter.width : 1.0;
    canvas
      ..translate(side / 2, height / 2)
      ..scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    return _encode(recorder, side.toInt(), height.toInt());
  }

  /// [path], an image in any format Flutter can read, as PNG bytes.
  static Future<Uint8List> toPng(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// A font file loaded under a new family name, for [text].
  static Future<String> loadFont(String path) async {
    final family = 'studio-font-${path.hashCode}';
    final loader = FontLoader(family)
      ..addFont(
        File(path).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    await loader.load();
    return family;
  }

  static Future<Uint8List> _render(void Function(Canvas) paint) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    return _encode(recorder, side.toInt(), side.toInt());
  }

  static Future<Uint8List> _encode(
    ui.PictureRecorder recorder,
    int width,
    int height,
  ) async {
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}
