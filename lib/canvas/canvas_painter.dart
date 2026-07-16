import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../models/shape_object.dart';
import '../state/editor_model.dart';
import '../state/image_store.dart';
import '../theme/fonts.dart';
import '../theme/shape_theme.dart';

/// Single [CustomPainter] that composites the canvas (§25.2): checkerboard
/// background, the user content layer stack, selection overlays and handles.
/// Wrapped in a RepaintBoundary by [CanvasView]; only repaints on model change.
class CanvasPainter extends CustomPainter {
  CanvasPainter(this.model) : super(repaint: model);
  final EditorModel model;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);

    canvas.save();
    canvas.translate(model.pan.dx, model.pan.dy);
    canvas.scale(model.zoom);

    for (final o in model.objects) {
      if (!o.visible) continue;
      // The object being text-edited paints like any other: the editor field is
      // an input, not a preview, so the canvas is where you watch it take shape.
      _paintObject(canvas, o);
    }

    // Overlays in canvas-space. The standard selection chrome yields to the
    // perspective-distort editor (which draws its own corner handles).
    final selected = model.selectedObjects;
    if (model.perspectiveEditId == null) {
      if (selected.length > 1) {
        // Group bounding box + thin per-object outlines (§10.3).
        for (final o in selected) {
          _paintSelection(canvas, o, single: false, thin: true);
        }
        final gb = model.selectionBounds;
        if (gb != null) _paintGroupBox(canvas, gb);
      } else {
        for (final o in selected) {
          _paintSelection(canvas, o, single: true);
        }
      }
    }

    // Live marquee rectangle.
    final marquee = model.marquee;
    if (marquee != null) _paintMarquee(canvas, marquee);

    // Node-edit anchors.
    if (model.nodeEditId != null) _paintNodes(canvas);
    // Perspective-distort corner handles.
    if (model.perspectiveEditId != null) _paintPerspective(canvas);
    // Pen tool in-progress polyline.
    if (model.penDraft.isNotEmpty || model.penDragAnchor != null) {
      _paintPenDraft(canvas);
    }
    // Freehand live stroke.
    if (model.drawDraft.length > 1) {
      final p = Path()..moveTo(model.drawDraft.first.dx, model.drawDraft.first.dy);
      for (var i = 1; i < model.drawDraft.length; i++) {
        p.lineTo(model.drawDraft[i].dx, model.drawDraft[i].dy);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 / model.zoom
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ShapeColors.primaryText,
      );
    }
    canvas.restore();
  }

  /// Draws the 4 draggable perspective corner handles + the distorted quad edge.
  void _paintPerspective(Canvas canvas) {
    final o = model.byId(model.perspectiveEditId!);
    if (o == null || !o.hasPerspective) return;
    final z = model.zoom;
    canvas.save();
    canvas.translate(o.center.dx, o.center.dy);
    canvas.rotate(o.rotation);
    final corners = [
      for (final p in o.perspective)
        Offset(p.dx * o.size.width, p.dy * o.size.height)
    ];
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / z
      ..color = ShapeColors.shapeBlue;
    final quad = Path()..moveTo(corners[0].dx, corners[0].dy);
    for (var i = 1; i < 4; i++) {
      quad.lineTo(corners[i].dx, corners[i].dy);
    }
    quad.close();
    canvas.drawPath(quad, edge);
    final white = Paint()..color = const Color(0xFFFFFFFF);
    for (final c in corners) {
      canvas.drawCircle(c, 8 / z, white);
      canvas.drawCircle(c, 8 / z, edge);
    }
    canvas.restore();
  }

  void _paintNodes(Canvas canvas) {
    final o = model.byId(model.nodeEditId!);
    if (o == null) return;
    final z = model.zoom;
    canvas.save();
    canvas.translate(o.center.dx, o.center.dy);
    canvas.rotate(o.rotation);
    final white = Paint()..color = const Color(0xFFFFFFFF);
    final blue = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / z
      ..color = ShapeColors.shapeBlue;
    final blueFill = Paint()..color = ShapeColors.shapeBlue;
    final handleLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / z
      ..color = ShapeColors.shapeBlue.withValues(alpha: 0.7);

    bool zero(Offset h) => h.dx.abs() < 1e-6 && h.dy.abs() < 1e-6;

    // Tangent handles (drawn for selected nodes only, beneath the anchors).
    if (o.hasHandles) {
      for (final i in model.selectedNodes) {
        if (i >= o.pathPoints.length) continue;
        final a = o.nodeLocal(i);
        // Keep handles at least ~18px on screen from the anchor so a short
        // tangent on an obtuse/near-straight node isn't hidden under the node.
        final minLen = 18 / z;
        for (final ctl in [
          if (!zero(o.handleOut[i])) o.nodeOutDisplay(i, minLen),
          if (!zero(o.handleIn[i])) o.nodeInDisplay(i, minLen),
        ]) {
          canvas.drawLine(a, ctl, handleLine);
          canvas.drawCircle(ctl, 5 / z, white);
          canvas.drawCircle(ctl, 5 / z, blue);
        }
      }
    }

    for (var i = 0; i < o.pathPoints.length; i++) {
      final p = o.nodeLocal(i);
      final selected = model.selectedNodes.contains(i);
      final smooth = o.nodeModeAt(i) != 0;
      final r = (selected ? 7 : 5.5) / z;
      if (smooth) {
        canvas.drawCircle(p, r, white);
        canvas.drawCircle(p, r, selected ? blueFill : blue);
      } else {
        // Hard corner → diamond marker.
        final d = r * 1.15;
        final diamond = Path()
          ..moveTo(p.dx, p.dy - d)
          ..lineTo(p.dx + d, p.dy)
          ..lineTo(p.dx, p.dy + d)
          ..lineTo(p.dx - d, p.dy)
          ..close();
        canvas.drawPath(diamond, white);
        canvas.drawPath(diamond, selected ? blueFill : blue);
      }
    }
    canvas.restore();
  }

  void _paintPenDraft(Canvas canvas) {
    final z = model.zoom;
    final pts = model.penDraft;
    final outs = model.penOut;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / z
      ..color = ShapeColors.shapeBlue;
    Offset out(int i) => i < outs.length ? outs[i] : Offset.zero;

    // Committed path through anchors using symmetric handles (in = -out).
    if (pts.length >= 2) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 0; i < pts.length - 1; i++) {
        final a = pts[i], b = pts[i + 1];
        final straight = out(i).distance < 0.5 && out(i + 1).distance < 0.5;
        if (straight) {
          path.lineTo(b.dx, b.dy);
        } else {
          final c1 = a + out(i);
          final c2 = b - out(i + 1);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
        }
      }
      canvas.drawPath(path, line);
    }

    // Live rubber-band segment from the last anchor to the finger.
    final drag = model.penDragAnchor;
    if (drag != null && pts.isNotEmpty) {
      canvas.drawLine(
          pts.last,
          drag,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / z
            ..color = ShapeColors.shapeBlue.withValues(alpha: 0.5));
    }

    final dot = Paint()..color = ShapeColors.shapeBlue;
    final white = Paint()..color = const Color(0xFFFFFFFF);

    // The tangent being dragged out (both directions, symmetric).
    final h = model.penDragHandle;
    if (drag != null && h != null) {
      final thin = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / z
        ..color = ShapeColors.shapeBlue.withValues(alpha: 0.8);
      canvas.drawLine(drag - h, drag + h, thin);
      for (final c in [drag - h, drag + h]) {
        canvas.drawCircle(c, 4 / z, white);
        canvas.drawCircle(c, 4 / z, line);
      }
    }

    for (final p in pts) {
      canvas.drawCircle(p, 5 / z, white);
      canvas.drawCircle(p, 4 / z, dot);
    }
    if (drag != null) {
      canvas.drawCircle(drag, 5 / z, white);
      canvas.drawCircle(drag, 4 / z, dot);
    }
  }

  // A soft, light, multi-pastel gradient — the "light & fun" canvas backdrop.
  // Drawn as a shader (not an image) so it stays crisp at any zoom.
  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = ui.Gradient.linear(
      rect.topCenter,
      rect.bottomCenter,
      const [ShapeColors.bgTop, ShapeColors.bgMid, ShapeColors.bgBottom],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  void _paintObject(Canvas canvas, ShapeObject o) {
    // Blend mode (§16.2): isolate the object on its own layer when not normal.
    final blendMode =
        BlendMode.values[o.blend.clamp(0, BlendMode.values.length - 1)];
    final useLayer = blendMode != BlendMode.srcOver;
    if (useLayer) {
      canvas.saveLayer(null, Paint()..blendMode = blendMode);
    }

    canvas.save();
    canvas.translate(o.center.dx, o.center.dy);
    canvas.rotate(o.rotation);
    // 4-corner perspective distort applies to every object type.
    if (o.hasPerspective) canvas.transform(o.perspectiveStorage());

    final opacity = o.opacity.clamp(0.0, 1.0);

    if (o.type == ShapeType.image) {
      _paintImage(canvas, o, opacity);
      canvas.restore();
      if (useLayer) canvas.restore();
      return;
    }

    if (o.type == ShapeType.text) {
      _paintText(canvas, o, opacity);
      if (model.pulseIds.contains(o.id)) {
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset.zero,
                width: o.size.width,
                height: o.size.height),
            Paint()..color = ShapeColors.shapeBlue.withValues(alpha: 0.20));
      }
      canvas.restore();
      if (useLayer) canvas.restore();
      return;
    }

    final path = o.localPath();
    _clipToMask(canvas, o);

    // Gaussian blur wraps the whole object.
    final blurLayer = o.blurAmount > 0.1;
    if (blurLayer) {
      canvas.saveLayer(
          null,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: o.blurAmount, sigmaY: o.blurAmount));
    }

    // Outer glow (behind fill).
    if (o.glow.enabled) {
      canvas.drawPath(
        path,
        Paint()
          ..color = o.glow.color.withValues(alpha: o.glow.color.a * opacity)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, o.glow.blur.clamp(0.1, 200)),
      );
    }
    // Drop shadow (§12.5) — drawn beneath the fill.
    if (o.shadow.enabled) {
      canvas.save();
      canvas.translate(o.shadow.dx, o.shadow.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = o.shadow.color.withValues(alpha: o.shadow.color.a * opacity)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, o.shadow.blur.clamp(0.1, 200)),
      );
      canvas.restore();
    }

    if (o.isFilled) {
      _paintFill(canvas, o, path, opacity);
    }

    // Inner shadow — clip to the shape and draw an offset blurred edge inside.
    if (o.innerShadow.enabled && o.isFilled) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        path.shift(Offset(o.innerShadow.dx, o.innerShadow.dy)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (o.innerShadow.blur).clamp(1.0, 60.0)
          ..color = o.innerShadow.color
              .withValues(alpha: o.innerShadow.color.a * opacity)
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal, o.innerShadow.blur.clamp(0.5, 60)),
      );
      canvas.restore();
    }

    // Inner glow — clip to the shape and bloom the glow colour inward from the
    // edge (centered, no offset), the inside counterpart of the outer glow.
    if (o.innerGlow.enabled && o.isFilled) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (o.innerGlow.blur).clamp(1.0, 60.0)
          ..color =
              o.innerGlow.color.withValues(alpha: o.innerGlow.color.a * opacity)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, o.innerGlow.blur.clamp(0.5, 60)),
      );
      canvas.restore();
    }

    _paintStrokes(canvas, o, path, opacity);

    if (model.pulseIds.contains(o.id)) {
      canvas.drawPath(
        path,
        Paint()..color = ShapeColors.shapeBlue.withValues(alpha: 0.20),
      );
    }
    if (blurLayer) canvas.restore();
    canvas.restore();
    if (useLayer) canvas.restore();
  }

  /// Fills [path] according to the object's [FillSpec]. Delegates to the shared
  /// top-level [paintShapeFill] so the exporter can fill identically.
  void _paintFill(Canvas canvas, ShapeObject o, Path path, double opacity) =>
      paintShapeFill(canvas, o, path, opacity);

  /// Delegates to the shared top-level [paintShapeStrokes] so the exporter
  /// strokes identically (stroke stack, varied width, opacity).
  void _paintStrokes(Canvas canvas, ShapeObject o, Path path, double opacity) =>
      paintShapeStrokes(canvas, o, path, opacity);

  void _paintText(Canvas canvas, ShapeObject o, double opacity) {
    // Whole-object gaussian blur (§12.5) now applies to text too.
    final blurLayer = o.blurAmount > 0.1;
    if (blurLayer) {
      canvas.saveLayer(
          null,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: o.blurAmount, sigmaY: o.blurAmount));
    }
    final fill = textPainterFor(o, opacity);
    final off = Offset(-fill.width / 2, -fill.height / 2);

    // Outer glow (behind).
    if (o.glow.enabled) {
      final tp = textPainterFor(
          o,
          opacity,
          Paint()
            ..color = o.glow.color.withValues(alpha: o.glow.color.a * opacity)
            ..maskFilter =
                MaskFilter.blur(BlurStyle.normal, o.glow.blur.clamp(0.1, 200)));
      tp.paint(canvas, off);
    }
    // Drop shadow (behind, offset).
    if (o.shadow.enabled) {
      final tp = textPainterFor(
          o,
          opacity,
          Paint()
            ..color =
                o.shadow.color.withValues(alpha: o.shadow.color.a * opacity)
            ..maskFilter = MaskFilter.blur(
                BlurStyle.normal, o.shadow.blur.clamp(0.1, 200)));
      tp.paint(canvas, off + Offset(o.shadow.dx, o.shadow.dy));
    }

    // Fill glyphs.
    fill.paint(canvas, off);

    // Stroke / outline (stroke stack or legacy stroke) — drawn over the fill,
    // honoring per-stroke align (center / inside / outside).
    paintTextStrokes(canvas, o, fill, off, opacity);

    if (blurLayer) canvas.restore();
  }

  /// Clips the current (object-local) canvas to the object's mask shape (§16.3).
  void _clipToMask(Canvas canvas, ShapeObject o) {
    if (o.maskId == null) return;
    final mask = model.byId(o.maskId!);
    if (mask == null) return;
    final selfM = Matrix4.translationValues(o.center.dx, o.center.dy, 0)
      ..multiply(Matrix4.rotationZ(o.rotation));
    final maskM = Matrix4.translationValues(mask.center.dx, mask.center.dy, 0)
      ..multiply(Matrix4.rotationZ(mask.rotation));
    final combined =
        (Matrix4.tryInvert(selfM) ?? Matrix4.identity()).multiplied(maskM);
    canvas.clipPath(mask.localPath().transform(combined.storage));
  }

  void _paintImage(Canvas canvas, ShapeObject o, double opacity) {
    final img = ImageStore.instance.get(o.id);
    final dst = Rect.fromCenter(
        center: Offset.zero, width: o.size.width, height: o.size.height);

    if (img == null) {
      // Decode lazily; repaint when ready. Show a soft placeholder meanwhile.
      ImageStore.instance.ensure(
          o.id, o.imageBytes, () => model.notifyListeners());
      canvas.drawRRect(
          RRect.fromRectXY(dst, 8, 8),
          Paint()..color = ShapeColors.fieldBase);
      return;
    }

    canvas.save();
    _clipToMask(canvas, o);

    final src = Rect.fromLTWH(
      o.crop.left * img.width,
      o.crop.top * img.height,
      o.crop.width * img.width,
      o.crop.height * img.height,
    );
    // Draw the image through its OWN alpha. Two things make transparent PNGs go
    // black on Android/Impeller, so both are avoided here:
    //  1) modulating the draw with `Paint.color` — apply opacity via a layer.
    //  2) `FilterQuality.medium/high` builds MIPMAPS, and Impeller renders the
    //     transparent areas of mip-mapped alpha textures as black. Use
    //     `FilterQuality.low` (bilinear, no mipmaps) so transparency survives.
    final imgPaint = Paint()
      ..filterQuality = FilterQuality.low
      ..isAntiAlias = true;
    if (opacity < 1.0) {
      canvas.saveLayer(
          dst, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      canvas.drawImageRect(img, src, dst, imgPaint);
      canvas.restore();
    } else {
      canvas.drawImageRect(img, src, dst, imgPaint);
    }
    canvas.restore();

    if (model.pulseIds.contains(o.id)) {
      canvas.drawRect(
          dst, Paint()..color = ShapeColors.shapeBlue.withValues(alpha: 0.20));
    }
  }

  // §10.6 Selection border + handles.
  void _paintSelection(Canvas canvas, ShapeObject o,
      {required bool single, bool thin = false}) {
    final z = model.zoom;
    canvas.save();
    canvas.translate(o.center.dx, o.center.dy);
    canvas.rotate(o.rotation);

    final half = Offset(o.size.width / 2, o.size.height / 2);
    final rect = Rect.fromCenter(
        center: Offset.zero, width: o.size.width, height: o.size.height);

    canvas.drawRRect(
      RRect.fromRectXY(rect, 4 / z, 4 / z),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (thin ? 1.0 : 1.5) / z
        ..color = ShapeColors.shapeBlue
            .withValues(alpha: thin ? 0.5 : 1.0),
    );

    if (!single) {
      canvas.restore();
      return;
    }

    final corner = 10 / z;
    final mid = 8 / z;
    final fill = Paint()..color = ShapeColors.shapeBlue;
    final white = Paint()..color = const Color(0xFFFFFFFF);
    final blueStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / z
      ..color = ShapeColors.shapeBlue;

    final corners = [
      Offset(-half.dx, -half.dy),
      Offset(half.dx, -half.dy),
      Offset(half.dx, half.dy),
      Offset(-half.dx, half.dy),
    ];
    for (var i = 0; i < corners.length; i++) {
      final c = corners[i];
      final r = Rect.fromCenter(center: c, width: corner, height: corner);
      canvas.drawRect(r, white);
      canvas.drawRect(r.deflate(2 / z), fill);
      // Bottom-right corner = aspect-ratio-lock handle (highlighted ring).
      if (i == 2) {
        canvas.drawCircle(
            c,
            corner,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 / z
              ..color = ShapeColors.shapeBlue);
      }
    }
    final mids = [
      Offset(0, -half.dy),
      Offset(half.dx, 0),
      Offset(0, half.dy),
      Offset(-half.dx, 0),
    ];
    for (final m in mids) {
      canvas.drawCircle(m, mid / 2, white);
      canvas.drawCircle(m, mid / 2, blueStroke);
    }

    // Rotation handle above top-center, dashed connector.
    final topCenter = Offset(0, -half.dy);
    final handle = Offset(0, -half.dy - 24 / z);
    _dashedLine(canvas, topCenter, handle, blueStroke, z);
    canvas.drawCircle(handle, 6 / z, white);
    canvas.drawCircle(handle, 6 / z, blueStroke);

    // Corner-radius knobs — one per corner (diamonds), for corner-capable types.
    final amber = Paint()..color = ShapeColors.warning;
    for (var i = 0; i < o.cornerCount; i++) {
      final knob = o.cornerKnob(i, z);
      final selected = model.selectedCorner == i;
      final d = (selected ? 7 : 5.5) / z;
      final diamond = Path()
        ..moveTo(knob.dx, knob.dy - d)
        ..lineTo(knob.dx + d, knob.dy)
        ..lineTo(knob.dx, knob.dy + d)
        ..lineTo(knob.dx - d, knob.dy)
        ..close();
      canvas.drawPath(diamond, white);
      canvas.drawPath(diamond, selected ? amber : blueStroke);
    }

    canvas.restore();
  }

  void _paintGroupBox(Canvas canvas, Rect box) {
    final z = model.zoom;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / z
      ..color = ShapeColors.shapeBlue;
    canvas.drawRect(box.inflate(8 / z), paint);
    // Corner handles for the group box.
    final white = Paint()..color = const Color(0xFFFFFFFF);
    final fill = Paint()..color = ShapeColors.shapeBlue;
    final s = 10 / z;
    for (final c in [
      box.inflate(8 / z).topLeft,
      box.inflate(8 / z).topRight,
      box.inflate(8 / z).bottomRight,
      box.inflate(8 / z).bottomLeft,
    ]) {
      final r = Rect.fromCenter(center: c, width: s, height: s);
      canvas.drawRect(r, white);
      canvas.drawRect(r.deflate(2 / z), fill);
    }
  }

  void _paintMarquee(Canvas canvas, Rect r) {
    final z = model.zoom;
    canvas.drawRect(
        r, Paint()..color = ShapeColors.shapeBlue.withValues(alpha: 0.12));
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / z
          ..color = ShapeColors.shapeBlue);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint p, double z) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    const dash = 3.0, gap = 3.0;
    double d = 0;
    while (d < total) {
      final start = a + dir * d;
      final end = a + dir * math.min(d + dash / z, total);
      canvas.drawLine(start, end, p..strokeWidth = 1 / z);
      d += (dash + gap) / z;
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter old) => false; // repaint: model
}

/// Half-width multiplier (0..1) at fraction [f] along the path for a
/// variable-width stroke [profile]: 1 taper-in, 2 taper-out, 3 pointed-ends,
/// 4 pinched-middle. Shared so the live painter and exporter taper identically.
double strokeProfileMul(int profile, double f) {
  final x = f.clamp(0.0, 1.0);
  switch (profile) {
    case 1: // taper in: thin start → thick end
      return x;
    case 2: // taper out: thick start → thin end
      return 1 - x;
    case 3: // pointed ends: thin at both ends, thick in the middle
      return math.sin(math.pi * x);
    case 4: // pinch: thick ends, thin middle
      return 1 - 0.82 * math.sin(math.pi * x);
    default:
      return 1.0;
  }
}

/// Builds a fillable ribbon outline for a variable-width stroke: walks each
/// contour of [src], offsetting left/right by a [profile]-scaled half-[width]
/// along the surface normal. Returns null when there's nothing to draw.
ui.Path? buildVariableStrokePath(ui.Path src, double width, int profile) {
  if (width <= 0) return null;
  final metrics = src.computeMetrics().toList();
  if (metrics.isEmpty) return null;
  final out = ui.Path();
  var any = false;
  for (final m in metrics) {
    final len = m.length;
    if (len <= 0) continue;
    final samples = math.max(24, (len / 6).round()).clamp(24, 240);
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= samples; i++) {
      final f = i / samples;
      final tan = m.getTangentForOffset(len * f);
      if (tan == null) continue;
      final v = tan.vector; // unit tangent
      final normal = Offset(-v.dy, v.dx);
      final hw = width / 2 * strokeProfileMul(profile, f);
      left.add(tan.position + normal * hw);
      right.add(tan.position - normal * hw);
    }
    if (left.length < 2) continue;
    out.moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      out.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      out.lineTo(p.dx, p.dy);
    }
    out.close();
    any = true;
  }
  return any ? out : null;
}

/// Strokes [path] from the object's stroke stack (or legacy single stroke),
/// honouring per-stroke colour, width, alignment, taper profile and opacity.
/// Shared by the live painter and the PNG exporter so strokes — including a
/// morph's varied widths and transparency — render identically in both.
void paintShapeStrokes(Canvas canvas, ShapeObject o, Path path, double opacity) {
  final fillable = o.isFilled;

  void drawStroke(Color color, double width, int align, int profile,
      [FillSpec? grad]) {
    if (width <= 0) return;
    // A non-solid stroke paints with a gradient/pattern shader instead of a
    // flat colour (full colour + gradients for strokes).
    final useShader = grad != null && !grad.isSolid;
    if (profile != 0) {
      final ribbon = buildVariableStrokePath(path, width, profile);
      if (ribbon != null) {
        final p = Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        if (useShader) {
          p.shader = _gradientShader(grad, ribbon.getBounds(), opacity);
        } else {
          p.color = color.withValues(alpha: color.a * opacity);
        }
        canvas.drawPath(ribbon, p);
      }
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (useShader) {
      paint.shader = _gradientShader(grad, path.getBounds(), opacity);
    } else {
      paint.color = color.withValues(alpha: color.a * opacity);
    }

    if (align == 0 || !fillable) {
      canvas.drawPath(path, paint..strokeWidth = width);
      return;
    }

    paint.strokeWidth = width * 2;
    canvas.save();
    if (align == 1) {
      canvas.clipPath(path);
      canvas.drawPath(path, paint);
    } else {
      canvas.saveLayer(path.getBounds().inflate(width * 2 + 2), Paint());
      canvas.drawPath(path, paint);
      canvas.drawPath(path,
          Paint()..blendMode = BlendMode.clear ..style = PaintingStyle.fill);
      canvas.restore();
    }
    canvas.restore();
  }

  if (o.strokes.isNotEmpty) {
    // Painted bottom-up so the first stroke sits on top (Illustrator order).
    for (final s in o.strokes.reversed) {
      if (s.enabled) {
        drawStroke(s.color, s.width, s.align, s.profile, s.paintFill);
      }
    }
  } else if (o.isStroked) {
    drawStroke(
        o.stroke,
        o.type == ShapeType.line && o.strokeWidth == 0 ? 2 : o.strokeWidth,
        0,
        0);
  }
}

/// Fills [path] (in the object's local, rotated space) according to the
/// object's [FillSpec]: a solid color, a linear/radial gradient shader, or a
/// built-in tiling pattern. Shared by the live painter and the PNG exporter so
/// gradient/pattern fills render identically in both. Gradients are built in
/// LOCAL space (the path bounds) since the canvas is already translate+rotated.
void paintShapeFill(Canvas canvas, ShapeObject o, Path path, double opacity) {
  final spec = o.fillSpec;
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  if (spec.isSolid) {
    paint.color = o.fill.withValues(alpha: o.fill.a * opacity);
    canvas.drawPath(path, paint);
    return;
  }

  final r = path.getBounds();
  if (r.isEmpty) {
    paint.color = o.fill.withValues(alpha: o.fill.a * opacity);
    canvas.drawPath(path, paint);
    return;
  }

  switch (spec.kind) {
    case FillKind.linearGradient:
    case FillKind.radialGradient:
      paint.shader = _gradientShader(spec, r, opacity);
      canvas.drawPath(path, paint);
    case FillKind.pattern:
      _paintPattern(canvas, spec, path, r, opacity);
    case FillKind.solid:
      paint.color = o.fill.withValues(alpha: o.fill.a * opacity);
      canvas.drawPath(path, paint);
  }
}

ui.Shader _gradientShader(FillSpec spec, Rect r, double opacity) {
  final stops = [...spec.stops]..sort((a, b) => a.pos.compareTo(b.pos));
  final colors = [
    for (final s in stops) s.color.withValues(alpha: s.color.a * opacity)
  ];
  final positions = [for (final s in stops) s.pos.clamp(0.0, 1.0)];
  if (spec.kind == FillKind.radialGradient) {
    return ui.Gradient.radial(r.center, r.longestSide / 2, colors, positions);
  }
  // Linear: a unit vector at [angle] mapped across the bounds.
  final c = r.center;
  final dir = Offset(math.cos(spec.angle), math.sin(spec.angle));
  final half = Offset(r.width / 2, r.height / 2);
  // Project the half-extent onto the direction so the gradient spans the box.
  final reach = (dir.dx.abs() * half.dx) + (dir.dy.abs() * half.dy);
  return ui.Gradient.linear(
      c - dir * reach, c + dir * reach, colors, positions);
}

/// Draws a built-in tiling pattern clipped to [path]. Background fill first,
/// then a repeating foreground motif covering [r].
void _paintPattern(
    Canvas canvas, FillSpec spec, Path path, Rect r, double opacity) {
  canvas.save();
  canvas.clipPath(path);
  final bg = spec.patternBg.withValues(alpha: spec.patternBg.a * opacity);
  final fg = Paint()
    ..isAntiAlias = true
    ..color = spec.patternFg.withValues(alpha: spec.patternFg.a * opacity);
  canvas.drawRect(r, Paint()..color = bg);

  final step = (16.0 * spec.patternScale).clamp(4.0, 80.0);
  switch (spec.pattern) {
    case PatternId.dots:
      final rad = step * 0.22;
      for (var y = r.top; y <= r.bottom + step; y += step) {
        for (var x = r.left; x <= r.right + step; x += step) {
          canvas.drawCircle(Offset(x, y), rad, fg);
        }
      }
    case PatternId.stripes:
      fg.style = PaintingStyle.stroke;
      fg.strokeWidth = step * 0.4;
      final extent = r.width + r.height;
      for (var d = -r.height; d <= extent; d += step) {
        canvas.drawLine(Offset(r.left + d, r.top),
            Offset(r.left + d - r.height, r.bottom), fg);
      }
    case PatternId.grid:
      fg.style = PaintingStyle.stroke;
      fg.strokeWidth = step * 0.12;
      for (var x = r.left; x <= r.right + step; x += step) {
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), fg);
      }
      for (var y = r.top; y <= r.bottom + step; y += step) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), fg);
      }
    case PatternId.checker:
      var row = 0;
      for (var y = r.top; y <= r.bottom + step; y += step) {
        for (var x = r.left; x <= r.right + step; x += step) {
          final col = ((x - r.left) / step).floor();
          if ((col + row).isEven) {
            canvas.drawRect(Rect.fromLTWH(x, y, step, step), fg);
          }
        }
        row++;
      }
  }
  canvas.restore();
}

TextAlign textAlignFor(int a) => switch (a) {
      0 => TextAlign.left,
      2 => TextAlign.right,
      3 => TextAlign.justify,
      _ => TextAlign.center,
    };

/// Builds a laid-out [TextPainter] for a text object — shared by the painter
/// (drawing) and the editor (measuring bounds after edits). When [override] is
/// supplied it replaces the fill with that paint (used for stroke/shadow/glow).
TextPainter textPainterFor(ShapeObject o, [double opacity = 1, Paint? override]) {
  final weight = FontWeight.values[
      (o.fontWeight ~/ 100 - 1).clamp(0, FontWeight.values.length - 1)];
  var style = FontCatalog.style(
    family: o.fontFamily,
    fontSize: o.fontSize,
    weight: weight,
    color: o.fill.withValues(alpha: o.fill.a * opacity),
    letterSpacing: o.letterSpacing,
    height: o.lineHeight,
    italic: o.italic,
  );
  if (override != null) {
    // Pass ONLY foreground: TextStyle.copyWith asserts that color and
    // foreground are never both supplied, and that assert throws mid-paint —
    // killing the stroke/glow/shadow AND every object painted after it.
    // copyWith already drops the inherited color once a foreground is given,
    // so the glyph fill is replaced by this paint exactly as intended.
    style = style.copyWith(foreground: override);
  }
  final tp = TextPainter(
    text: TextSpan(text: o.text.isEmpty ? ' ' : o.text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: textAlignFor(o.textAlignH),
  );
  tp.layout(maxWidth: o.size.width > 0 ? o.size.width : double.infinity);
  return tp;
}

/// Paints [o]'s text outline strokes (stroke stack or the legacy single stroke)
/// over an already-painted fill at [off], honoring each stroke's [align]
/// (0 = center, 1 = inside, 2 = outside). Inside/outside are achieved by
/// rendering a double-width centered stroke into a layer and masking it to (or
/// away from) the glyph coverage with dstIn / dstOut — Flutter doesn't expose
/// glyph paths, so this is how text gets true inside/outside alignment. Shared
/// by the live painter and the exporter so canvas and export match. (Width
/// profile / taper doesn't apply to text and is ignored.)
void paintTextStrokes(
    Canvas canvas, ShapeObject o, TextPainter fill, Offset off, double opacity) {
  void one(Color color, double width, int align) {
    if (width <= 0) return;
    final col = color.withValues(alpha: color.a * opacity);
    if (align == 0) {
      textPainterFor(
              o,
              opacity,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = width
                ..color = col)
          .paint(canvas, off);
      return;
    }
    final bounds = Rect.fromLTWH(off.dx, off.dy, fill.width, fill.height)
        .inflate(width * 2 + 4);
    canvas.saveLayer(bounds, Paint());
    textPainterFor(
            o,
            opacity,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = width * 2
              ..color = col)
        .paint(canvas, off);
    // Keep the inner half (inside) or remove it (outside) using glyph coverage.
    textPainterFor(
            o,
            opacity,
            Paint()
              ..style = PaintingStyle.fill
              ..color = const Color(0xFFFFFFFF)
              ..blendMode = align == 1 ? BlendMode.dstIn : BlendMode.dstOut)
        .paint(canvas, off);
    canvas.restore();
  }

  if (o.strokes.isNotEmpty) {
    for (final s in o.strokes.reversed) {
      if (s.enabled) one(s.color, s.width, s.align);
    }
  } else if (o.strokeWidth > 0) {
    one(o.stroke, o.strokeWidth, 0);
  }
}
