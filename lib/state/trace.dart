import 'dart:ui';

/// Marching-squares contour extraction for image tracing. Produces one closed
/// polyline per region boundary (outer contours *and* holes), so tracing keeps
/// multiple shapes and interior cut-outs — not just a single silhouette.
class MarchingSquares {
  /// [grid] is `[cols][rows]` of inside/outside booleans. Returns contours in
  /// grid coordinates (each a closed loop of points).
  static List<List<Offset>> contours(List<List<bool>> grid) {
    final cols = grid.length;
    if (cols == 0) return const [];
    final rows = grid[0].length;

    // Edge midpoints per cell: 0=top,1=right,2=bottom,3=left.
    Offset mid(int x, int y, int edge) => switch (edge) {
          0 => Offset(x + 0.5, y.toDouble()),
          1 => Offset(x + 1.0, y + 0.5),
          2 => Offset(x + 0.5, y + 1.0),
          _ => Offset(x.toDouble(), y + 0.5),
        };

    const table = <List<List<int>>>[
      [], // 0
      [[2, 3]], // 1 BL
      [[1, 2]], // 2 BR
      [[1, 3]], // 3
      [[0, 1]], // 4 TR
      [[0, 1], [2, 3]], // 5 saddle
      [[0, 2]], // 6
      [[0, 3]], // 7
      [[0, 3]], // 8 TL
      [[0, 2]], // 9
      [[0, 3], [1, 2]], // 10 saddle
      [[0, 1]], // 11
      [[1, 3]], // 12
      [[1, 2]], // 13
      [[2, 3]], // 14
      [], // 15
    ];

    final segments = <List<Offset>>[];
    bool ink(int x, int y) =>
        x >= 0 && y >= 0 && x < cols && y < rows && grid[x][y];

    for (var x = -1; x < cols; x++) {
      for (var y = -1; y < rows; y++) {
        final tl = ink(x, y) ? 8 : 0;
        final tr = ink(x + 1, y) ? 4 : 0;
        final br = ink(x + 1, y + 1) ? 2 : 0;
        final bl = ink(x, y + 1) ? 1 : 0;
        final c = tl | tr | br | bl;
        for (final seg in table[c]) {
          segments.add([mid(x, y, seg[0]), mid(x, y, seg[1])]);
        }
      }
    }
    return _chain(segments);
  }

  static String _key(Offset p) =>
      '${(p.dx * 2).round()}_${(p.dy * 2).round()}';

  /// Stitches unordered segments into closed loops by matching endpoints.
  static List<List<Offset>> _chain(List<List<Offset>> segments) {
    final adj = <String, List<Offset>>{};
    final points = <String, Offset>{};
    for (final s in segments) {
      for (final p in s) {
        points[_key(p)] = p;
      }
      adj.putIfAbsent(_key(s[0]), () => []).add(s[1]);
      adj.putIfAbsent(_key(s[1]), () => []).add(s[0]);
    }

    final used = <String>{};
    final loops = <List<Offset>>[];
    for (final start in points.values) {
      final sk = _key(start);
      if (used.contains(sk)) continue;
      final loop = <Offset>[];
      var cur = start;
      var guard = 0;
      while (guard++ < 100000) {
        final ck = _key(cur);
        if (used.contains(ck)) break;
        used.add(ck);
        loop.add(cur);
        final neighbors = adj[ck] ?? const [];
        Offset? next;
        for (final n in neighbors) {
          if (!used.contains(_key(n))) {
            next = n;
            break;
          }
        }
        if (next == null) break;
        cur = next;
      }
      if (loop.length >= 6) loops.add(loop);
    }
    return loops;
  }

  /// Drops points that are nearly collinear (cheap Douglas–Peucker-ish pass).
  static List<Offset> simplify(List<Offset> pts, double tol) {
    if (pts.length < 4) return pts;
    final out = <Offset>[pts.first];
    for (var i = 1; i < pts.length - 1; i++) {
      final a = out.last, b = pts[i], c = pts[i + 1];
      final ab = b - a, bc = c - b;
      final cross = (ab.dx * bc.dy - ab.dy * bc.dx).abs();
      if (cross > tol) out.add(b);
    }
    out.add(pts.last);
    return out;
  }
}
