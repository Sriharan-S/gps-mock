import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Rasterises a Material icon into PNG bytes.
///
/// MapLibre draws annotation icons from registered bitmaps, so the pin has to
/// be handed to it as pixels rather than as a widget. Rendering the glyph at
/// the device pixel ratio keeps it crisp; the caller scales it back down with
/// `iconSize`.
Future<Uint8List> rasterizeIcon(
  IconData icon, {
  required Color color,
  required double size,
  required double devicePixelRatio,
  Color shadowColor = const Color(0x66000000),
}) async {
  final pixelSize = size * devicePixelRatio;
  final painter = TextPainter(textDirection: TextDirection.ltr);
  painter.text = TextSpan(
    text: String.fromCharCode(icon.codePoint),
    style: TextStyle(
      fontSize: pixelSize,
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      color: color,
      shadows: [
        Shadow(
          color: shadowColor,
          blurRadius: 6 * devicePixelRatio,
          offset: Offset(0, 1.5 * devicePixelRatio),
        ),
      ],
    ),
  );
  painter.layout();

  // Pad so the shadow isn't clipped at the glyph's bounds.
  final padding = 6 * devicePixelRatio;
  final width = (painter.width + padding * 2).ceil();
  final height = (painter.height + padding * 2).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Offset(padding, padding));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Rasterises a map pin, optionally with a number sitting in its head.
///
/// Used for route waypoints: a green start, numbered blue stops and a red
/// destination, all drawn at device resolution so MapLibre can render them
/// pixel-for-pixel.
Future<Uint8List> rasterizePin({
  required Color color,
  required double size,
  required double devicePixelRatio,
  String? label,
  Color labelColor = Colors.white,
}) async {
  final pixelSize = size * devicePixelRatio;
  final padding = 6 * devicePixelRatio;

  final pin = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(Icons.location_pin.codePoint),
      style: TextStyle(
        fontSize: pixelSize,
        fontFamily: Icons.location_pin.fontFamily,
        package: Icons.location_pin.fontPackage,
        color: color,
        shadows: [
          Shadow(
            color: const Color(0x73000000),
            blurRadius: 6 * devicePixelRatio,
            offset: Offset(0, 1.5 * devicePixelRatio),
          ),
        ],
      ),
    )
    ..layout();

  final width = (pin.width + padding * 2).ceil();
  final height = (pin.height + padding * 2).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  pin.paint(canvas, Offset(padding, padding));

  if (label != null) {
    // The glyph's round head sits a little above the middle of its box; the
    // number goes in its centre.
    final headCentre = Offset(
      padding + pin.width / 2,
      padding + pin.height * 0.38,
    );
    canvas.drawCircle(
      headCentre,
      pixelSize * 0.17,
      Paint()..color = labelColor,
    );
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: pixelSize * 0.24,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    )..layout();
    text.paint(
      canvas,
      headCentre - Offset(text.width / 2, text.height / 2),
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}
