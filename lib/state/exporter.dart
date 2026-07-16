import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../canvas/canvas_painter.dart';
import '../models/shape_object.dart';
import 'image_store.dart';

/// Renders objects to PNG bytes or an SVG string for the export wizard (§17).
class Exporter {
  /// A gaussian blur (mask filter or layer) fades to nothing by roughly 3σ —
  /// past that it paints no visible pixels.
  static const double _blurSpread = 3.0;

  /// Combined world bounds of every pixel [objects] actually paint — geometry
  /// plus strokes, shadows, glows and blur — padded by [pad]. Hidden objects
  /// contribute nothing. Null when nothing is visible.
  static ui.Rect? bounds(List<ShapeObject> objects, {double pad = 8}) {
    ui.Rect? r;
    for (final o in objects) {
      if (!o.visible) continue;
      final b = visualBounds(o);
      r = r == null ? b : r.expandToInclude(b);
    }
    return r?.inflate(pad);
  }

  /// World-space axis-aligned bounds of everything [o] paints, mapped through
  /// the same perspective → rotation → position stack [_draw] sets up.
  static ui.Rect visualBounds(ShapeObject o) {
    final local = _localVisualBounds(o);
    final m = o.hasPerspective ? o.perspectiveStorage() : null;
    final cos = math.cos(o.rotation), sin = math.sin(o.rotation);
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var p in [
      local.topLeft,
      local.topRight,
      local.bottomRight,
      local.bottomLeft
    ]) {
      if (m != null) p = _project(m, p);
      final x = o.center.dx + p.dx * cos - p.dy * sin;
      final y = o.center.dy + p.dx * sin + p.dy * cos;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Local-space bounds of every pixel [o] paints. Inner shadow and inner glow
  /// are clipped to the shape, so they never extend it.
  static ui.Rect _localVisualBounds(ShapeObject o) {
    // Images paint no effects — the drawn rect is all there is.
    if (o.type == ShapeType.image) {
      return ui.Rect.fromCenter(
          center: ui.Offset.zero, width: o.size.width, height: o.size.height);
    }
    final ui.Rect base;
    if (o.type == ShapeType.text) {
      final tp = textPainterFor(o);
      base = ui.Rect.fromCenter(
          center: ui.Offset.zero, width: tp.width, height: tp.height);
    } else {
      base = o.localPath().getBounds();
    }
    var r = base.inflate(_strokeOutset(o));
    if (o.glow.enabled) {
      r = r.expandToInclude(
          base.inflate(o.glow.blur.clamp(0.1, 200) * _blurSpread));
    }
    if (o.shadow.enabled) {
      r = r.expandToInclude(base
          .inflate(o.shadow.blur.clamp(0.1, 200) * _blurSpread)
          .shift(ui.Offset(o.shadow.dx, o.shadow.dy)));
    }
    // Whole-object blur wraps everything above it.
    if (o.blurAmount > 0.1) r = r.inflate(o.blurAmount * _blurSpread);
    return r;
  }

  /// How far [o]'s strokes paint outside its geometry, in local pixels.
  static double _strokeOutset(ShapeObject o) {
    // A shape with no fill to mask against falls back to a centred stroke;
    // text always honours align, masking against glyph coverage.
    final honoursAlign = o.type == ShapeType.text || o.isFilled;
    double outset(double width, int align) => !honoursAlign
        ? width / 2
        : switch (align) {
            1 => 0.0, // inside — clipped to the shape
            2 => width, // outside — double-width centred, inner half removed
            _ => width / 2, // centred; taper ribbons peak at half-width
          };
    var out = 0.0;
    if (o.strokes.isNotEmpty) {
      for (final s in o.strokes) {
        if (s.enabled) out = math.max(out, outset(s.width, s.align));
      }
    } else if (o.type == ShapeType.text ? o.strokeWidth > 0 : o.isStroked) {
      final w =
          o.type == ShapeType.line && o.strokeWidth == 0 ? 2.0 : o.strokeWidth;
      out = math.max(out, w / 2);
    }
    return out;
  }

  /// Maps a local point through a [ShapeObject.perspectiveStorage] matrix
  /// (column-major 4×4 carrying a 3×3 projective transform).
  static ui.Offset _project(Float64List m, ui.Offset p) {
    final x = m[0] * p.dx + m[4] * p.dy + m[12];
    final y = m[1] * p.dx + m[5] * p.dy + m[13];
    final w = m[3] * p.dx + m[7] * p.dy + m[15];
    return w.abs() < 1e-9 ? p : ui.Offset(x / w, y / w);
  }

  static Future<Uint8List?> png(List<ShapeObject> objects,
      {double scale = 2, ui.Color? background}) async {
    if (objects.isEmpty) return null;
    final b = bounds(objects);
    if (b == null || b.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    canvas.translate(-b.left, -b.top);
    if (background != null) {
      canvas.drawRect(b, ui.Paint()..color = background);
    }
    // Decode image objects at FULL (original) resolution for export — the
    // on-screen cache is downsampled for performance, but exports must keep the
    // source's native resolution.
    final fullRes = await _decodeFullRes(objects);
    for (final o in objects) {
      if (o.visible) _draw(canvas, o, fullRes);
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(
        (b.width * scale).ceil(), (b.height * scale).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    for (final im in fullRes.values) {
      im.dispose();
    }
    return data?.buffer.asUint8List();
  }

  /// Decodes every image object's original bytes at full resolution, keyed by id.
  static Future<Map<String, ui.Image>> _decodeFullRes(
      List<ShapeObject> objects) async {
    final out = <String, ui.Image>{};
    for (final o in objects) {
      if (o.type == ShapeType.image && o.imageBytes != null) {
        final codec = await ui.instantiateImageCodec(o.imageBytes!);
        out[o.id] = (await codec.getNextFrame()).image;
      }
    }
    return out;
  }

  /// Paints a single object exactly as the PNG exporter would. Used by
  /// flatten-mask, which rasterizes clipped content into a new image. The caller
  /// sets up the canvas transform / clip first. [images] supplies full-res
  /// image textures (falls back to the on-screen cache).
  static void paintObject(ui.Canvas canvas, ShapeObject o,
          [Map<String, ui.Image>? images]) =>
      _draw(canvas, o, images);

  static void _draw(ui.Canvas canvas, ShapeObject o,
      [Map<String, ui.Image>? images]) {
    // Blend mode parity with the live canvas: isolate the object on its own
    // layer when it isn't the normal srcOver mode, so multiply/screen/etc.
    // export exactly as seen on screen (fixes washed-out / dark PNG output).
    final blendMode =
        ui.BlendMode.values[o.blend.clamp(0, ui.BlendMode.values.length - 1)];
    final useLayer = blendMode != ui.BlendMode.srcOver;
    if (useLayer) {
      canvas.saveLayer(null, ui.Paint()..blendMode = blendMode);
    }
    canvas.save();
    canvas.translate(o.center.dx, o.center.dy);
    canvas.rotate(o.rotation);
    if (o.hasPerspective) canvas.transform(o.perspectiveStorage());
    final op = o.opacity.clamp(0.0, 1.0);

    if (o.type == ShapeType.image) {
      final img = images?[o.id] ?? ImageStore.instance.get(o.id);
      if (img != null) {
        final dst = ui.Rect.fromCenter(
            center: ui.Offset.zero, width: o.size.width, height: o.size.height);
        final src = ui.Rect.fromLTWH(o.crop.left * img.width,
            o.crop.top * img.height, o.crop.width * img.width, o.crop.height * img.height);
        // Preserve the image's own alpha: don't modulate with Paint.color, and
        // use FilterQuality.low (no mipmaps) — both blacken transparent pixels
        // on Impeller. Opacity is applied via a layer instead.
        final imgPaint = ui.Paint()
          ..filterQuality = ui.FilterQuality.low
          ..isAntiAlias = true;
        if (op < 1.0) {
          canvas.saveLayer(
              dst, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, op));
          canvas.drawImageRect(img, src, dst, imgPaint);
          canvas.restore();
        } else {
          canvas.drawImageRect(img, src, dst, imgPaint);
        }
      }
      canvas.restore();
      if (useLayer) canvas.restore();
      return;
    }
    // Whole-object gaussian blur wraps everything below it, as on the canvas.
    final blurLayer = o.blurAmount > 0.1;
    if (blurLayer) {
      canvas.saveLayer(
          null,
          ui.Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: o.blurAmount, sigmaY: o.blurAmount));
    }

    if (o.type == ShapeType.text) {
      final tp = textPainterFor(o, op);
      final off = ui.Offset(-tp.width / 2, -tp.height / 2);
      // Outer glow, then drop shadow — both behind the glyphs.
      if (o.glow.enabled) {
        textPainterFor(
                o,
                op,
                ui.Paint()
                  ..color = o.glow.color.withValues(alpha: o.glow.color.a * op)
                  ..maskFilter = ui.MaskFilter.blur(
                      ui.BlurStyle.normal, o.glow.blur.clamp(0.1, 200)))
            .paint(canvas, off);
      }
      if (o.shadow.enabled) {
        textPainterFor(
                o,
                op,
                ui.Paint()
                  ..color =
                      o.shadow.color.withValues(alpha: o.shadow.color.a * op)
                  ..maskFilter = ui.MaskFilter.blur(
                      ui.BlurStyle.normal, o.shadow.blur.clamp(0.1, 200)))
            .paint(canvas, off + ui.Offset(o.shadow.dx, o.shadow.dy));
      }
      tp.paint(canvas, off);
      // Outline strokes (with align) — matches the live canvas.
      paintTextStrokes(canvas, o, tp, off, op);
      if (blurLayer) canvas.restore();
      canvas.restore();
      if (useLayer) canvas.restore();
      return;
    }
    final path = o.localPath();
    // Outer glow (behind fill).
    if (o.glow.enabled) {
      canvas.drawPath(
          path,
          ui.Paint()
            ..color = o.glow.color.withValues(alpha: o.glow.color.a * op)
            ..maskFilter = ui.MaskFilter.blur(
                ui.BlurStyle.normal, o.glow.blur.clamp(0.1, 200)));
    }
    if (o.shadow.enabled) {
      canvas.save();
      canvas.translate(o.shadow.dx, o.shadow.dy);
      canvas.drawPath(
          path,
          ui.Paint()
            ..color = o.shadow.color.withValues(alpha: o.shadow.color.a * op)
            ..maskFilter = ui.MaskFilter.blur(
                ui.BlurStyle.normal, o.shadow.blur.clamp(0.1, 200)));
      canvas.restore();
    }
    if (o.isFilled) {
      // Shared fill renderer → solid / gradient / pattern parity with canvas.
      paintShapeFill(canvas, o, path, op);
    }
    // Inner shadow / inner glow — clipped to the shape, bloomed in from the edge.
    void inner(ShadowSpec spec, ui.Offset shift) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
          path.shift(shift),
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = spec.blur.clamp(1.0, 60.0)
            ..color = spec.color.withValues(alpha: spec.color.a * op)
            ..maskFilter =
                ui.MaskFilter.blur(ui.BlurStyle.normal, spec.blur.clamp(0.5, 60)));
      canvas.restore();
    }

    if (o.innerShadow.enabled && o.isFilled) {
      inner(o.innerShadow, ui.Offset(o.innerShadow.dx, o.innerShadow.dy));
    }
    if (o.innerGlow.enabled && o.isFilled) inner(o.innerGlow, ui.Offset.zero);
    // Shared stroke renderer → stroke stack, varied widths, taper & opacity
    // parity with the canvas (fixes morph strokes / transparency in export).
    paintShapeStrokes(canvas, o, path, op);
    if (blurLayer) canvas.restore();
    canvas.restore();
    if (useLayer) canvas.restore();
  }

  /// SVG export — shapes as `<path>` (curves sampled to polylines), text as
  /// `<text>`. Clean, importable output.
  static String svg(List<ShapeObject> objects) {
    final b = bounds(objects) ?? ui.Rect.zero;
    final sb = StringBuffer()
      ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="${b.width.round()}" '
          'height="${b.height.round()}" viewBox="0 0 ${b.width.round()} ${b.height.round()}">');
    for (final o in objects) {
      if (!o.visible) continue;
      sb.writeln(_svgFor(o, b.topLeft));
    }
    sb.writeln('</svg>');
    return sb.toString();
  }

  static String _svgFor(ShapeObject o, ui.Offset origin) {
    // SVG output is solid-color only; gradient/pattern fills approximate to a
    // representative color (first stop / pattern ink) so vectors stay valid.
    final fillColor = _representativeFill(o);
    final fill = o.isFilled ? _hex(fillColor) : 'none';
    final fa = (fillColor.a * o.opacity).toStringAsFixed(2);
    if (o.type == ShapeType.text) {
      final p = o.center - origin;
      return '<text x="${p.dx.toStringAsFixed(1)}" y="${p.dy.toStringAsFixed(1)}" '
          'font-size="${o.fontSize}" fill="${_hex(fillColor)}" '
          'text-anchor="middle">${_esc(o.text)}</text>';
    }
    final affine = _affine(
        o.center.dx - origin.dx, o.center.dy - origin.dy, o.rotation);
    final world = o.localPath().transform(affine);
    final d = _pathToSvgD(world);

    final out = StringBuffer();
    // Fill path first (drawn beneath strokes), with even-odd holes preserved.
    if (o.isFilled) {
      final rule = o.holes.isNotEmpty ? ' fill-rule="evenodd"' : '';
      out.write('<path d="$d" fill="$fill" fill-opacity="$fa"$rule/>');
    }

    // Strokes — emitted to match the canvas EXACTLY:
    //  * A uniform, centre-aligned stroke → a real <path> with stroke-width
    //    (true vector, scales cleanly).
    //  * A variable-width / tapered profile → the same filled ribbon outline
    //    the canvas builds, so the varied thickness is preserved (item 1/2).
    // Painted in the same bottom-up order as the live painter so the topmost
    // stroke ends up last (on top) in the SVG too.
    void emitStroke(ui.Color color, double width, int profile, FillSpec? grad) {
      if (width <= 0) return;
      // Gradients approximate to a representative colour in SVG (vectors stay
      // valid; the PNG export carries the true gradient).
      final col = grad != null && !grad.isSolid && grad.stops.isNotEmpty
          ? grad.stops.first.color
          : color;
      final so = (col.a * o.opacity).toStringAsFixed(2);
      if (profile != 0) {
        final ribbon = buildVariableStrokePath(world, width, profile);
        if (ribbon != null) {
          out.write('<path d="${_pathToSvgD(ribbon)}" fill="${_hex(col)}" '
              'fill-opacity="$so"/>');
        }
        return;
      }
      out.write('<path d="$d" fill="none" stroke="${_hex(col)}" '
          'stroke-width="${width.toStringAsFixed(2)}" stroke-opacity="$so" '
          'stroke-linecap="round" stroke-linejoin="round"/>');
    }

    if (o.strokes.isNotEmpty) {
      for (final s in o.strokes.reversed) {
        if (s.enabled) emitStroke(s.color, s.width, s.profile, s.paintFill);
      }
    } else if (o.isStroked) {
      final w = o.strokeWidth == 0 ? 2.0 : o.strokeWidth;
      emitStroke(o.stroke, w, 0, null);
    }
    return out.toString();
  }

  /// Samples a (already world-space) [path] into an SVG `d` polyline string,
  /// closing each contour that is closed. Shared by fill + ribbon emission.
  static String _pathToSvgD(ui.Path path) {
    final d = StringBuffer();
    for (final metric in path.computeMetrics()) {
      var first = true;
      for (double dd = 0; dd <= metric.length; dd += 3) {
        final t = metric.getTangentForOffset(dd);
        if (t == null) continue;
        d.write(first
            ? 'M${t.position.dx.toStringAsFixed(1)} ${t.position.dy.toStringAsFixed(1)}'
            : ' L${t.position.dx.toStringAsFixed(1)} ${t.position.dy.toStringAsFixed(1)}');
        first = false;
      }
      if (metric.isClosed) d.write(' Z');
    }
    return d.toString();
  }

  static Float64List _affine(double tx, double ty, double rot) {
    final c = math.cos(rot), s = math.sin(rot);
    final m = Float64List(16);
    m[0] = c;
    m[1] = s;
    m[4] = -s;
    m[5] = c;
    m[10] = 1;
    m[12] = tx;
    m[13] = ty;
    m[15] = 1;
    return m;
  }

  /// A single representative color for SVG fills (which are solid here): the
  /// solid color, first gradient stop, or pattern ink.
  static ui.Color _representativeFill(ShapeObject o) {
    final s = o.fillSpec;
    return switch (s.kind) {
      FillKind.solid => o.fill,
      FillKind.linearGradient ||
      FillKind.radialGradient =>
        s.stops.isEmpty ? o.fill : s.stops.first.color,
      FillKind.pattern => s.patternFg,
    };
  }

  static String _hex(ui.Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
