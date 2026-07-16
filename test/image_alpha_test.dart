import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies that a transparent PNG survives the app's exact import path
/// (instantiateImageCodec) and draw path (drawImageRect) with its alpha intact.
/// If this passes, the Dart/Skia code is correct and any on-device black is the
/// renderer (Impeller).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('transparent PNG keeps alpha through decode + draw', () async {
    // 2x1 source: opaque red, then fully transparent.
    final pixels = Uint8List.fromList([
      255, 0, 0, 255, // red, opaque
      0, 0, 0, 0, // transparent
    ]);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, 2, 1, ui.PixelFormat.rgba8888, c.complete);
    final src = await c.future;
    final png = await src.toByteData(format: ui.ImageByteFormat.png);
    expect(png, isNotNull);

    // App import path:
    final codec = await ui.instantiateImageCodec(png!.buffer.asUint8List());
    final img = (await codec.getNextFrame()).image;

    // App draw path (bare paint, no color modulation):
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawImageRect(
      img,
      const Rect.fromLTWH(0, 0, 2, 1),
      const Rect.fromLTWH(0, 0, 2, 1),
      Paint()..filterQuality = FilterQuality.none,
    );
    final out = await rec.endRecording().toImage(2, 1);
    final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    final b = data!.buffer.asUint8List();

    // Pixel 0 opaque red, pixel 1 transparent.
    expect(b[3], 255, reason: 'opaque pixel alpha');
    expect(b[7], 0,
        reason: 'transparent pixel should stay alpha=0, got '
            'rgba(${b[4]},${b[5]},${b[6]},${b[7]})');
  });
}
