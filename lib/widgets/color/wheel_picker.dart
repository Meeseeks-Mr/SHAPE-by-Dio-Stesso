import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../theme/shape_theme.dart';

/// An Affinity-style color picker: an outer hue ring with an inner
/// saturation/value triangle that rotates to track the chosen hue. The triangle
/// is filled with a true 3-color barycentric gradient via [Canvas.drawVertices]
/// (hue → white → black).
class WheelColorPicker extends StatefulWidget {
  const WheelColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.onStart,
    this.onEnd,
    this.size = 240,
  });

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;
  final double size;

  @override
  State<WheelColorPicker> createState() => _WheelColorPickerState();
}

class _WheelColorPickerState extends State<WheelColorPicker> {
  static const _ringThickness = 26.0;

  late HSVColor _hsv = widget.color;
  bool _onRing = false;

  @override
  void didUpdateWidget(WheelColorPicker old) {
    super.didUpdateWidget(old);
    if (widget.color != old.color) _hsv = widget.color;
  }

  double get _r => widget.size / 2;
  double get _ringInner => _r - _ringThickness;
  double get _triR => _ringInner - 8;

  // Triangle vertices for the current hue.
  List<Offset> _triangle(Offset c) {
    final base = _hsv.hue * math.pi / 180;
    return [
      c + Offset(math.cos(base), math.sin(base)) * _triR, // hue
      c + Offset(math.cos(base + 2 * math.pi / 3),
              math.sin(base + 2 * math.pi / 3)) *
          _triR, // white
      c + Offset(math.cos(base + 4 * math.pi / 3),
              math.sin(base + 4 * math.pi / 3)) *
          _triR, // black
    ];
  }

  void _handle(Offset local, {required bool down}) {
    final c = Offset(_r, _r);
    final v = local - c;
    final dist = v.distance;
    if (down) _onRing = dist > _ringInner - 4;

    if (_onRing) {
      final hue = (math.atan2(v.dy, v.dx) * 180 / math.pi) % 360;
      _hsv = _hsv.withHue(hue < 0 ? hue + 360 : hue);
    } else {
      // Barycentric within the (hue, white, black) triangle.
      final t = _triangle(c);
      final w = _barycentric(local, t[0], t[1], t[2]);
      final a = w[0].clamp(0.0, 1.0);
      final b = w[1].clamp(0.0, 1.0);
      final sum = a + b == 0 ? 1 : a + b;
      final value = (a + b).clamp(0.0, 1.0);
      final sat = (a / sum).clamp(0.0, 1.0);
      _hsv = HSVColor.fromAHSV(_hsv.alpha, _hsv.hue, sat, value);
    }
    widget.onChanged(_hsv);
    setState(() {});
  }

  static List<double> _barycentric(Offset p, Offset a, Offset b, Offset c) {
    final v0 = b - a, v1 = c - a, v2 = p - a;
    final d00 = v0.dx * v0.dx + v0.dy * v0.dy;
    final d01 = v0.dx * v1.dx + v0.dy * v1.dy;
    final d11 = v1.dx * v1.dx + v1.dy * v1.dy;
    final d20 = v2.dx * v0.dx + v2.dy * v0.dy;
    final d21 = v2.dx * v1.dx + v2.dy * v1.dy;
    final denom = d00 * d11 - d01 * d01;
    final vb = (d11 * d20 - d01 * d21) / (denom == 0 ? 1 : denom);
    final vc = (d00 * d21 - d01 * d20) / (denom == 0 ? 1 : denom);
    final va = 1 - vb - vc;
    return [va, vb, vc]; // a=hue, b=white, c=black weights
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) {
        widget.onStart?.call();
        _handle(d.localPosition, down: true);
      },
      onPanUpdate: (d) => _handle(d.localPosition, down: false),
      onPanEnd: (_) => widget.onEnd?.call(),
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _WheelPainter(_hsv, _r, _ringInner, _triR, _triangle),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv, this.r, this.ringInner, this.triR, this.triFn);
  final HSVColor hsv;
  final double r;
  final double ringInner;
  final double triR;
  final List<Offset> Function(Offset) triFn;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(r, r);

    // Hue ring (sweep gradient).
    final hues = List.generate(
        13, (i) => HSVColor.fromAHSV(1, (i * 30) % 360, 1, 1).toColor());
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r - ringInner
      ..shader = SweepGradient(colors: hues).createShader(
          Rect.fromCircle(center: c, radius: (r + ringInner) / 2));
    canvas.drawCircle(c, (r + ringInner) / 2, ringPaint);

    // SV triangle via per-vertex barycentric gradient.
    final t = triFn(c);
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    final verts = ui.Vertices(
      ui.VertexMode.triangles,
      t,
      colors: [hueColor, const Color(0xFFFFFFFF), const Color(0xFF000000)],
    );
    // modulate against white paint => pure interpolated vertex colors.
    canvas.drawVertices(
        verts, BlendMode.modulate, Paint()..color = const Color(0xFFFFFFFF));
    // Subtle triangle border.
    final tri = Path()
      ..moveTo(t[0].dx, t[0].dy)
      ..lineTo(t[1].dx, t[1].dy)
      ..lineTo(t[2].dx, t[2].dy)
      ..close();
    canvas.drawPath(
        tri,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = ShapeColors.glassBorderDark);

    // Hue selector on the ring.
    final hueA = hsv.hue * math.pi / 180;
    final hueSel = c + Offset(math.cos(hueA), math.sin(hueA)) * (r + ringInner) / 2;
    canvas.drawCircle(hueSel, 9,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
    canvas.drawCircle(hueSel, 9,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = ShapeColors.primaryText);

    // SV selector inside the triangle.
    final a = (hsv.value * hsv.saturation);
    final b = (hsv.value * (1 - hsv.saturation));
    final cc = (1 - hsv.value);
    final sel = Offset(
      t[0].dx * a + t[1].dx * b + t[2].dx * cc,
      t[0].dy * a + t[1].dy * b + t[2].dy * cc,
    );
    canvas.drawCircle(sel, 8,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
    canvas.drawCircle(sel, 8,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = ShapeColors.primaryText);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.hsv != hsv;
}
