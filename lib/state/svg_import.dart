import 'dart:ui';

import '../models/shape_object.dart';
import '../theme/shape_theme.dart';

/// A compact, dependency-free SVG importer. Parses the common primitives and
/// `<path>` data (M L H V C S Q T Z, absolute & relative; arcs degrade to
/// lines) into editable [ShapeObject]s. Good enough for icons and logos.
class SvgImporter {
  static List<ShapeObject> parse(String svg) {
    final out = <ShapeObject>[];

    for (final m in RegExp(r'<path[^>]*\sd="([^"]*)"[^>]*>').allMatches(svg)) {
      final fill = _fill(m.group(0)!);
      final path = _parsePathData(m.group(1)!);
      for (final metric in path.computeMetrics()) {
        final pts = <Offset>[];
        for (double d = 0; d < metric.length; d += 4) {
          final t = metric.getTangentForOffset(d);
          if (t != null) pts.add(t.position);
        }
        final o = _fromPoints(pts, metric.isClosed, fill);
        if (o != null) out.add(o);
      }
    }

    for (final m in RegExp(r'<rect([^>]*)>').allMatches(svg)) {
      final a = m.group(1)!;
      final x = _num(a, 'x'), y = _num(a, 'y');
      final w = _num(a, 'width'), h = _num(a, 'height');
      if (w <= 0 || h <= 0) continue;
      out.add(ShapeObject(
        type: ShapeType.rectangle,
        center: Offset(x + w / 2, y + h / 2),
        size: Size(w, h),
        cornerRadius: _num(a, 'rx'),
        fill: _fill(m.group(0)!),
      ));
    }
    for (final m in RegExp(r'<circle([^>]*)>').allMatches(svg)) {
      final a = m.group(1)!;
      final r = _num(a, 'r');
      if (r <= 0) continue;
      out.add(ShapeObject(
        type: ShapeType.ellipse,
        center: Offset(_num(a, 'cx'), _num(a, 'cy')),
        size: Size(r * 2, r * 2),
        fill: _fill(m.group(0)!),
      ));
    }
    for (final m in RegExp(r'<ellipse([^>]*)>').allMatches(svg)) {
      final a = m.group(1)!;
      final rx = _num(a, 'rx'), ry = _num(a, 'ry');
      if (rx <= 0 || ry <= 0) continue;
      out.add(ShapeObject(
        type: ShapeType.ellipse,
        center: Offset(_num(a, 'cx'), _num(a, 'cy')),
        size: Size(rx * 2, ry * 2),
        fill: _fill(m.group(0)!),
      ));
    }
    for (final m in RegExp(r'<(polygon|polyline)([^>]*)>').allMatches(svg)) {
      final closed = m.group(1) == 'polygon';
      final raw = RegExp(r'points="([^"]*)"').firstMatch(m.group(2)!)?.group(1);
      if (raw == null) continue;
      final nums = _numbers(raw);
      final pts = <Offset>[];
      for (var i = 0; i + 1 < nums.length; i += 2) {
        pts.add(Offset(nums[i], nums[i + 1]));
      }
      final o = _fromPoints(pts, closed, _fill(m.group(0)!));
      if (o != null) out.add(o);
    }
    return out;
  }

  static ShapeObject? _fromPoints(List<Offset> pts, bool closed, Color fill) {
    if (pts.length < 2) return null;
    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = (maxX - minX).clamp(1.0, double.infinity);
    final h = (maxY - minY).clamp(1.0, double.infinity);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    return ShapeObject(
      type: ShapeType.path,
      center: center,
      size: Size(w, h),
      pathPoints: pts
          .map((p) => Offset((p.dx - center.dx) / w, (p.dy - center.dy) / h))
          .toList(),
      closed: closed,
      fill: closed ? fill : const Color(0x00000000),
      stroke: ShapeColors.primaryText,
      strokeWidth: closed ? 0 : 2,
    );
  }

  // ---- Path `d` parsing --------------------------------------------------
  static Path _parsePathData(String d) {
    final path = Path();
    final tokens =
        RegExp(r'[a-zA-Z]|-?\d*\.?\d+(?:e-?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
    var i = 0;
    var cur = Offset.zero;
    var start = Offset.zero;
    String cmd = 'M';
    // Previous segment's trailing control point — needed to reflect for the
    // smooth-curve commands S (cubic) and T (quadratic).
    Offset? lastC2;
    Offset? lastQ;
    double next() => double.parse(tokens[i++]);
    bool isNum(String s) => RegExp(r'^-?\d|\.').hasMatch(s);

    while (i < tokens.length) {
      if (!isNum(tokens[i])) {
        cmd = tokens[i++];
      }
      final rel = cmd == cmd.toLowerCase();
      // Snapshot, then clear; each curve command re-arms its own kind below.
      final prevC2 = lastC2, prevQ = lastQ;
      lastC2 = null;
      lastQ = null;
      switch (cmd.toUpperCase()) {
        case 'M':
          cur = _pt(next(), next(), cur, rel);
          path.moveTo(cur.dx, cur.dy);
          start = cur;
          cmd = rel ? 'l' : 'L';
        case 'L':
          cur = _pt(next(), next(), cur, rel);
          path.lineTo(cur.dx, cur.dy);
        case 'H':
          cur = Offset(rel ? cur.dx + next() : next(), cur.dy);
          path.lineTo(cur.dx, cur.dy);
        case 'V':
          cur = Offset(cur.dx, rel ? cur.dy + next() : next());
          path.lineTo(cur.dx, cur.dy);
        case 'C':
          final c1 = _pt(next(), next(), cur, rel);
          final c2 = _pt(next(), next(), cur, rel);
          cur = _pt(next(), next(), cur, rel);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, cur.dx, cur.dy);
          lastC2 = c2;
        case 'S':
          // First control = reflection of the previous cubic's c2 about cur.
          final c1 = prevC2 != null ? cur * 2 - prevC2 : cur;
          final c2 = _pt(next(), next(), cur, rel);
          cur = _pt(next(), next(), cur, rel);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, cur.dx, cur.dy);
          lastC2 = c2;
        case 'Q':
          final c = _pt(next(), next(), cur, rel);
          cur = _pt(next(), next(), cur, rel);
          path.quadraticBezierTo(c.dx, c.dy, cur.dx, cur.dy);
          lastQ = c;
        case 'T':
          // Control = reflection of the previous quadratic's control about cur.
          final c = prevQ != null ? cur * 2 - prevQ : cur;
          cur = _pt(next(), next(), cur, rel);
          path.quadraticBezierTo(c.dx, c.dy, cur.dx, cur.dy);
          lastQ = c;
        case 'A':
          // Arc unsupported — consume params, line to endpoint.
          next();
          next();
          next();
          next();
          next();
          cur = _pt(next(), next(), cur, rel);
          path.lineTo(cur.dx, cur.dy);
        case 'Z':
          path.close();
          cur = start;
        default:
          i++; // skip unknown
      }
    }
    return path;
  }

  static Offset _pt(double x, double y, Offset cur, bool rel) =>
      rel ? Offset(cur.dx + x, cur.dy + y) : Offset(x, y);

  static double _num(String attrs, String key) {
    final m = RegExp('$key="([^"]*)"').firstMatch(attrs);
    return m == null ? 0 : (double.tryParse(m.group(1)!) ?? 0);
  }

  static List<double> _numbers(String s) => RegExp(r'-?\d*\.?\d+')
      .allMatches(s)
      .map((m) => double.parse(m.group(0)!))
      .toList();

  static Color _fill(String tag) {
    final m = RegExp(r'fill="([^"]*)"').firstMatch(tag);
    final v = m?.group(1);
    if (v == null || v == 'none') return ShapeColors.lavender;
    if (v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(0xFF000000 | n);
    }
    return ShapeColors.lavender;
  }
}
