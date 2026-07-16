import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shape/canvas/canvas_painter.dart';
import 'package:shape/models/shape_object.dart';

/// Regression guard for the text stroke / glow / shadow crash.
///
/// `textPainterFor` used to build its override style with
/// `copyWith(color: ..., foreground: ...)`. TextStyle.copyWith asserts that the
/// two are never both supplied, so every stroked/glowing/shadowed text object
/// threw mid-paint — silently dropping the effect and aborting the rest of the
/// frame (which is why the selection chrome vanished too).
void main() {
  ShapeObject text({List<StrokeSpec> strokes = const []}) => ShapeObject(
        type: ShapeType.text,
        center: Offset.zero,
        size: const Size(200, 60),
        text: 'Shape',
        strokes: strokes,
      );

  Paint strokePaint() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..color = const Color(0xFF000000);

  test('an override paint does not trip the color+foreground assert', () {
    // The exact call the stroke/glow/shadow paths make.
    expect(() => textPainterFor(text(), 1, strokePaint()), returnsNormally);
  });

  test('the override replaces the fill rather than sitting beside it', () {
    final tp = textPainterFor(text(), 1, strokePaint());
    final style = (tp.text as TextSpan).style!;
    // Both set at once is exactly what the framework forbids.
    expect(style.foreground, isNotNull);
    expect(style.color, isNull);
  });

  test('without an override the glyphs keep their fill colour', () {
    final tp = textPainterFor(text(), 1);
    final style = (tp.text as TextSpan).style!;
    expect(style.color, isNotNull);
    expect(style.foreground, isNull);
  });

  test('painting stroked text completes instead of throwing', () {
    final o = text(strokes: [StrokeSpec(width: 6)]);
    final tp = textPainterFor(o, 1);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Would previously throw before drawing anything.
    expect(
      () => paintTextStrokes(canvas, o, tp, Offset.zero, 1),
      returnsNormally,
    );
    recorder.endRecording().dispose();
  });

  test('every stroke alignment paints without throwing', () {
    for (final align in [0, 1, 2]) {
      final o = text(strokes: [StrokeSpec(width: 6, align: align)]);
      final tp = textPainterFor(o, 1);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => paintTextStrokes(canvas, o, tp, Offset.zero, 1),
        returnsNormally,
        reason: 'align=$align threw',
      );
      recorder.endRecording().dispose();
    }
  });
}
