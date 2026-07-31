// scripts/generate_logo.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ✅ Ajouter la couleur turquoise
const Color turquoise = Color(0xFF92DCE5);

Future<void> generateLogo() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 512, 512));

  // ─── Fond ──────────────────────────────────────────────
  // ✅ Utiliser turquoise
  final paint = Paint()..color = turquoise;
  canvas.drawCircle(Offset(256, 256), 256, paint);

  // ─── Icône monitor_heart ──────────────────────────────
  final iconData = Icons.monitor_heart;
  final iconPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        fontSize: 250,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  iconPainter.layout();

  final offset = Offset(
    (512 - iconPainter.width) / 2,
    (512 - iconPainter.height) / 2,
  );
  iconPainter.paint(canvas, offset);

  // ─── Sauvegarder ──────────────────────────────────────
  final image = await recorder.endRecording().toImage(512, 512);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final buffer = byteData!.buffer.asUint8List();

  final assetsDir = Directory('assets');
  if (!await assetsDir.exists()) {
    await assetsDir.create();
  }

  await File('assets/logo.png').writeAsBytes(buffer);
  print('✅ Logo généré avec couleur turquoise !');

  // ─── Foreground pour adaptive icon ────────────────────
  final recorder2 = ui.PictureRecorder();
  final canvas2 = Canvas(recorder2, Rect.fromLTWH(0, 0, 512, 512));

  final iconPainter2 = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        fontSize: 350,
        color: turquoise, // ✅ Icône en turquoise pour le foreground
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  iconPainter2.layout();

  final offset2 = Offset(
    (512 - iconPainter2.width) / 2,
    (512 - iconPainter2.height) / 2,
  );
  iconPainter2.paint(canvas2, offset2);

  final image2 = await recorder2.endRecording().toImage(512, 512);
  final byteData2 = await image2.toByteData(format: ui.ImageByteFormat.png);
  final buffer2 = byteData2!.buffer.asUint8List();

  await File('assets/logo_foreground.png').writeAsBytes(buffer2);
  print('✅ Foreground généré avec couleur turquoise !');
}

void main() => generateLogo();
