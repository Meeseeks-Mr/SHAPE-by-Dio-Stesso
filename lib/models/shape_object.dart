import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// The primitive vector types Shape can create — §9.3 Shapes Sub-menu, plus
/// freehand/pen paths, text, and imported images.
enum ShapeType {
  rectangle,
  ellipse,
  triangle,
  star,
  polygon,
  line,
  path,
  text,
  image
}

extension ShapeTypeLabel on ShapeType {
  String get label => switch (this) {
        ShapeType.rectangle => 'Rectangle',
        ShapeType.ellipse => 'Ellipse',
        ShapeType.triangle => 'Triangle',
        ShapeType.star => 'Star',
        ShapeType.polygon => 'Polygon',
        ShapeType.line => 'Line',
        ShapeType.path => 'Path',
        ShapeType.text => 'Text',
        ShapeType.image => 'Image',
      };
}

int _idSeed = 0;
String _nextId() =>
    'shape-${DateTime.now().microsecondsSinceEpoch}-${_idSeed++}';

/// One stroke in an object's stroke stack (Illustrator-style appearance).
class StrokeSpec {
  StrokeSpec({
    this.enabled = true,
    this.color = const Color(0xFF3A3742),
    this.width = 4,
    this.align = 0, // 0 center, 1 inside, 2 outside
    this.dashed = false,
    this.profile = 0, // 0 uniform, 1 taper-in, 2 taper-out, 3 both, 4 pinch
    this.paintFill,
  });
  bool enabled;
  Color color;
  double width;
  int align;
  bool dashed;

  /// Variable-width profile applied along the path. 0 = uniform (constant
  /// [width]); 1..4 are taper presets rendered as a filled outline.
  int profile;

  /// Optional gradient/pattern paint for the stroke (full color + gradient
  /// support). When null or [FillSpec.isSolid] the flat [color] is used; a
  /// non-solid spec paints the stroke with a shader instead.
  FillSpec? paintFill;

  /// Whether this stroke paints with a non-solid gradient/pattern.
  bool get hasGradient => paintFill != null && !paintFill!.isSolid;

  StrokeSpec copy() => StrokeSpec(
      enabled: enabled,
      color: color,
      width: width,
      align: align,
      dashed: dashed,
      profile: profile,
      paintFill: paintFill?.copy());

  Map<String, dynamic> toJson() => {
        'on': enabled,
        'c': color.toARGB32(),
        'w': width,
        'a': align,
        'd': dashed,
        'p': profile,
        if (paintFill != null) 'grad': paintFill!.toJson(),
      };

  factory StrokeSpec.fromJson(Map<String, dynamic> j) => StrokeSpec(
        enabled: j['on'] as bool? ?? true,
        color: Color(j['c'] as int? ?? 0xFF3A3742),
        width: (j['w'] as num?)?.toDouble() ?? 4,
        align: j['a'] as int? ?? 0,
        dashed: j['d'] as bool? ?? false,
        profile: j['p'] as int? ?? 0,
        paintFill: j['grad'] is Map
            ? FillSpec.fromJson((j['grad'] as Map).cast<String, dynamic>())
            : null,
      );
}

/// Fill kind for [FillSpec]. [solid] uses the object's legacy [ShapeObject.fill]
/// color; the rest describe gradient / pattern paints rendered by the painter.
enum FillKind { solid, linearGradient, radialGradient, pattern }

/// A single gradient color stop — position 0..1 along the gradient + color.
class GradientStop {
  GradientStop(this.pos, this.color);
  double pos;
  Color color;

  GradientStop copy() => GradientStop(pos, color);
  Map<String, dynamic> toJson() => {'p': pos, 'c': color.toARGB32()};
  factory GradientStop.fromJson(Map<String, dynamic> j) =>
      GradientStop((j['p'] as num?)?.toDouble() ?? 0,
          Color(j['c'] as int? ?? 0xFFFFFFFF));
}

/// Built-in tiling patterns (§12.3 Pattern tab). Rendered procedurally by the
/// painter so they stay crisp at any zoom and need no asset bundle.
enum PatternId { dots, stripes, grid, checker }

extension PatternIdLabel on PatternId {
  String get label => switch (this) {
        PatternId.dots => 'Dots',
        PatternId.stripes => 'Stripes',
        PatternId.grid => 'Grid',
        PatternId.checker => 'Checker',
      };
}

/// Describes how an object is filled (§12.3). The default ([FillKind.solid])
/// defers to the legacy [ShapeObject.fill] color so existing documents and all
/// the solid-color UI keep working untouched. Gradient/pattern fills add stops,
/// a linear angle (radians) and a built-in pattern id + two pattern colors.
class FillSpec {
  FillSpec({
    this.kind = FillKind.solid,
    List<GradientStop>? stops,
    this.angle = 0,
    this.pattern = PatternId.dots,
    this.patternFg = const Color(0xFF3A3742),
    this.patternBg = const Color(0xFFFFFFFF),
    this.patternScale = 1,
  }) : stops = stops ??
            [GradientStop(0, const Color(0xFFC9B8F0)),
             GradientStop(1, const Color(0xFFA9CBEE))];

  FillKind kind;

  /// Gradient stops (ascending position). Always at least two.
  List<GradientStop> stops;

  /// Linear-gradient angle in radians (0 = left→right).
  double angle;

  PatternId pattern;
  Color patternFg;
  Color patternBg;
  double patternScale;

  bool get isSolid => kind == FillKind.solid;

  FillSpec copy() => FillSpec(
        kind: kind,
        stops: stops.map((s) => s.copy()).toList(),
        angle: angle,
        pattern: pattern,
        patternFg: patternFg,
        patternBg: patternBg,
        patternScale: patternScale,
      );

  Map<String, dynamic> toJson() => {
        'k': kind.index,
        'st': stops.map((s) => s.toJson()).toList(),
        'a': angle,
        'p': pattern.index,
        'pf': patternFg.toARGB32(),
        'pb': patternBg.toARGB32(),
        'ps': patternScale,
      };

  factory FillSpec.fromJson(Map<String, dynamic> j) => FillSpec(
        kind: FillKind
            .values[(j['k'] as int? ?? 0).clamp(0, FillKind.values.length - 1)],
        stops: (j['st'] as List?)
            ?.map((e) => GradientStop.fromJson(e as Map<String, dynamic>))
            .toList(),
        angle: (j['a'] as num?)?.toDouble() ?? 0,
        pattern: PatternId.values[
            (j['p'] as int? ?? 0).clamp(0, PatternId.values.length - 1)],
        patternFg: Color(j['pf'] as int? ?? 0xFF3A3742),
        patternBg: Color(j['pb'] as int? ?? 0xFFFFFFFF),
        patternScale: (j['ps'] as num?)?.toDouble() ?? 1,
      );
}

/// A shadow / glow effect (§12.5 Effects). Reused for drop shadow, inner
/// shadow and glow. Stored per object.
class ShadowSpec {
  ShadowSpec({
    this.enabled = false,
    this.dx = 0,
    this.dy = 8,
    this.blur = 16,
    this.color = const Color(0x55000000),
  });
  bool enabled;
  double dx;
  double dy;
  double blur;
  Color color;

  ShadowSpec copy() => ShadowSpec(
      enabled: enabled, dx: dx, dy: dy, blur: blur, color: color);

  Map<String, dynamic> toJson() =>
      {'on': enabled, 'dx': dx, 'dy': dy, 'b': blur, 'c': color.toARGB32()};

  factory ShadowSpec.fromJson(Map<String, dynamic> j) => ShadowSpec(
        enabled: j['on'] as bool? ?? false,
        dx: (j['dx'] as num?)?.toDouble() ?? 0,
        dy: (j['dy'] as num?)?.toDouble() ?? 8,
        blur: (j['b'] as num?)?.toDouble() ?? 16,
        color: Color(j['c'] as int? ?? 0x55000000),
      );
}

/// A single object on the infinite canvas. Position/rotation/scale are stored
/// in canvas-space (§7.4 Object Coordinate System); the viewport transform is
/// applied at paint time. Freehand/pen objects store [pathPoints] normalized to
/// a unit box so they scale uniformly with [size], like every other type.
class ShapeObject {
  ShapeObject({
    String? id,
    required this.type,
    required this.center,
    required this.size,
    this.rotation = 0,
    this.fill = const Color(0xFFC9B8F0),
    FillSpec? fillSpec,
    this.stroke = const Color(0xFF3A3742),
    this.strokeWidth = 0,
    this.opacity = 1,
    this.cornerRadius = 0,
    this.cornerRadii = const [],
    this.starInner = 0.45,
    this.points = 5,
    this.visible = true,
    this.locked = false,
    this.pathPoints = const [],
    this.handleIn = const [],
    this.handleOut = const [],
    this.nodeModes = const [],
    this.holes = const [],
    this.perspective = const [],
    this.closed = false,
    this.smooth = false,
    this.text = '',
    this.fontSize = 48,
    this.fontWeight = 400,
    this.fontFamily,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.textAlignH = 1,
    this.italic = false,
    this.groupId,
    this.superGroupId,
    this.imageBytes,
    Rect? crop,
    this.maskId,
    this.blend = 3, // BlendMode.srcOver
    this.strokes = const [],
    this.blurAmount = 0,
    ShadowSpec? shadow,
    ShadowSpec? innerShadow,
    ShadowSpec? glow,
    ShadowSpec? innerGlow,
    String? name,
  })  : id = id ?? _nextId(),
        fillSpec = fillSpec ?? FillSpec(),
        crop = crop ?? const Rect.fromLTRB(0, 0, 1, 1),
        innerShadow = innerShadow ?? ShadowSpec(dy: 0, blur: 10),
        glow = glow ?? ShadowSpec(dy: 0, blur: 18, color: const Color(0x886C63D6)),
        innerGlow = innerGlow ??
            ShadowSpec(dy: 0, blur: 16, color: const Color(0x88FFE08A)),
        shadow = shadow ?? ShadowSpec(),
        name = name ?? type.label;

  final String id;
  final ShapeType type;

  Offset center;
  Size size;

  /// Radians, clockwise.
  double rotation;

  Color fill;

  /// Fill description (solid / gradient / pattern). When [FillSpec.isSolid]
  /// the legacy [fill] color is used, so all existing code paths still work.
  FillSpec fillSpec;

  Color stroke;
  double strokeWidth;
  double opacity;

  /// Uniform corner radius fallback (canvas units).
  double cornerRadius;

  /// Per-corner radii (one per corner). Empty = uniform [cornerRadius].
  List<double> cornerRadii;

  /// Star inner-radius ratio (0..1).
  double starInner;

  int points;
  bool visible;
  bool locked;

  /// Normalized ([-0.5, 0.5]) path points (anchors) for freehand/pen objects.
  List<Offset> pathPoints;

  /// Per-anchor incoming/outgoing bezier control offsets, in the SAME
  /// normalized space as [pathPoints], stored RELATIVE to their anchor.
  /// Empty (or all-zero) = a corner with no tangent (straight segments).
  /// When present they make each segment a true cubic bezier — the vector
  /// node + tangent-handle model every shape converts to for node editing.
  List<Offset> handleIn;
  List<Offset> handleOut;

  /// Per-node handle mode: 0 corner (independent), 1 smooth (mirrored
  /// direction), 2 symmetric (mirrored direction + length).
  List<int> nodeModes;

  bool closed;

  /// Optional interior cut-outs (holes) for a path, each a closed contour in the
  /// same normalized space as [pathPoints]. Filled with the even-odd rule so the
  /// holes punch through — used by Expand so letter counters (o, e, a) stay open.
  List<List<Offset>> holes;

  /// Optional 4-corner perspective distort (TL, TR, BR, BL) as normalized
  /// positions in the object's local box (±0.5 = box edges). Empty = no
  /// distort. Applies to every object type — shapes, images and text.
  List<Offset> perspective;

  bool get hasPerspective => perspective.length == 4;

  /// The identity (undistorted) corner quad.
  static const List<Offset> identityPerspective = [
    Offset(-0.5, -0.5),
    Offset(0.5, -0.5),
    Offset(0.5, 0.5),
    Offset(-0.5, 0.5),
  ];

  /// 3×3 projective transform (row-major) mapping the centred bounding box to
  /// the dragged perspective quad, in local pixel space.
  List<double> _perspectiveH() {
    final w = size.width, h = size.height;
    final src = <Offset>[
      Offset(-w / 2, -h / 2),
      Offset(w / 2, -h / 2),
      Offset(w / 2, h / 2),
      Offset(-w / 2, h / 2),
    ];
    final dst = [for (final p in perspective) Offset(p.dx * w, p.dy * h)];
    return _mat3Mul(_squareToQuad(dst), _mat3Inv(_squareToQuad(src)));
  }

  /// Column-major 4×4 storage for [Canvas.transform] applying the perspective.
  Float64List perspectiveStorage() {
    final m = _perspectiveH();
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], hh = m[7], i = m[8];
    return Float64List.fromList(
        [a, d, 0, g, b, e, 0, hh, 0, 0, 1, 0, c, f, 0, i]);
  }

  /// Maps a distorted local point back into the undistorted box (for hit-test).
  Offset perspectiveUnmap(Offset p) {
    final inv = _mat3Inv(_perspectiveH());
    final x = inv[0] * p.dx + inv[1] * p.dy + inv[2];
    final y = inv[3] * p.dx + inv[4] * p.dy + inv[5];
    final w = inv[6] * p.dx + inv[7] * p.dy + inv[8];
    return w.abs() < 1e-9 ? p : Offset(x / w, y / w);
  }

  /// When true, the path is rendered as a smooth curve through its nodes.
  bool smooth;

  /// Text content & styling (type == text).
  String text;
  double fontSize;
  int fontWeight;

  /// Google-Fonts family name (null = bundled default). Plus typographic
  /// controls: letter spacing (horizontal), line height (vertical), horizontal
  /// alignment (0 left, 1 center, 2 right, 3 justify), and italic.
  String? fontFamily;
  double letterSpacing;
  double lineHeight;
  int textAlignH;
  bool italic;

  /// Objects sharing a non-null [groupId] select and move together. This is the
  /// innermost (leaf) group.
  String? groupId;

  /// Optional OUTER group, one level above [groupId], used for nested
  /// "group of groups" structures (e.g. a Repeat applied to a group, item 6a).
  /// When set, this is the outermost container for selection/grouping.
  String? superGroupId;

  /// Image payload (type == image) and its normalized source crop rect.
  Uint8List? imageBytes;
  Rect crop;

  /// Id of another object used to clip this one (mask).
  String? maskId;

  /// Layer blend mode — index into [BlendMode.values] (§16.2).
  int blend;

  /// Stroke stack (empty = use legacy [stroke]/[strokeWidth]).
  List<StrokeSpec> strokes;

  /// Gaussian blur amount applied to the whole object (0 = off).
  double blurAmount;

  ShadowSpec shadow;
  ShadowSpec innerShadow;
  ShadowSpec glow;
  ShadowSpec innerGlow;
  String name;

  Rect get bounds =>
      Rect.fromCenter(center: center, width: size.width, height: size.height);

  double get rotationDegrees {
    final d = rotation * 180 / math.pi % 360;
    return d < 0 ? d + 360 : d;
  }

  /// Number of editable corners for the corner-radius nodes.
  int get cornerCount => switch (type) {
        ShapeType.rectangle => 4,
        ShapeType.triangle => 3,
        ShapeType.polygon => points,
        ShapeType.star => points * 2,
        _ => 0,
      };

  double radiusAt(int i) =>
      cornerRadii.isEmpty ? cornerRadius : cornerRadii[i % cornerRadii.length];

  bool get cornersLinked => cornerRadii.isEmpty;

  /// True when this path carries real tangent handles (bezier node model).
  bool get hasHandles =>
      handleIn.length == pathPoints.length &&
      handleOut.length == pathPoints.length &&
      pathPoints.isNotEmpty;

  int nodeModeAt(int i) =>
      (i >= 0 && i < nodeModes.length) ? nodeModes[i] : 0;

  /// Local-space anchor for path node [i].
  Offset nodeLocal(int i) =>
      Offset(pathPoints[i].dx * size.width, pathPoints[i].dy * size.height);

  /// Local-space outgoing/incoming control point for path node [i].
  Offset nodeOutLocal(int i) => Offset(
      (pathPoints[i].dx + handleOut[i].dx) * size.width,
      (pathPoints[i].dy + handleOut[i].dy) * size.height);
  Offset nodeInLocal(int i) => Offset(
      (pathPoints[i].dx + handleIn[i].dx) * size.width,
      (pathPoints[i].dy + handleIn[i].dy) * size.height);

  /// On-screen control-point positions used for DRAWING and HIT-TESTING the
  /// tangent handles. A very short tangent (e.g. a near-straight cusp) would
  /// otherwise land on top of the anchor and be impossible to see or grab, so
  /// the displayed point is pushed out to at least [minLen] world units along
  /// the handle's own direction. The underlying curve data is unchanged.
  Offset nodeOutDisplay(int i, double minLen) =>
      _displayHandle(nodeLocal(i), nodeOutLocal(i), minLen);
  Offset nodeInDisplay(int i, double minLen) =>
      _displayHandle(nodeLocal(i), nodeInLocal(i), minLen);

  Offset _displayHandle(Offset node, Offset ctl, double minLen) {
    final v = ctl - node;
    final d = v.distance;
    if (d >= minLen || d < 1e-6) return ctl;
    return node + v * (minLen / d);
  }

  bool _handleZero(Offset h) => h.dx.abs() < 1e-6 && h.dy.abs() < 1e-6;

  /// A compact signature of all effect/stroke state for undo change-detection.
  String fxSignature() =>
      '$blurAmount|${shadow.toJson()}|${innerShadow.toJson()}|'
      '${glow.toJson()}|${innerGlow.toJson()}|'
      '${strokes.map((s) => s.toJson()).join(';')}';

  /// Inward bisector direction at corner [i] (unit vector, local space).
  Offset cornerBisector(int i) {
    final v = cornerPoints();
    if (v.length < 3) return Offset.zero;
    final n = v.length, cur = v[i];
    Offset unit(Offset o) => o.distance == 0 ? Offset.zero : o / o.distance;
    final b = unit(v[(i - 1 + n) % n] - cur) + unit(v[(i + 1) % n] - cur);
    return b.distance == 0 ? Offset.zero : b / b.distance;
  }

  /// Base inset of a corner-radius knob from its corner (screen px / zoom),
  /// keeping it clear of the corner resize handle.
  static double cornerKnobInset(double zoom) => 18 / zoom;

  /// Local position of corner [i]'s radius knob. The inward travel is capped at
  /// a fraction of the shape so that, at large/maxed radii, the per-corner knobs
  /// stay separated near their own corners instead of collapsing onto the
  /// centre (which made them look like they "disappeared").
  Offset cornerKnob(int i, double zoom) {
    final cur = cornerPoints()[i];
    final cap = math.min(size.width, size.height) * 0.3;
    final travel = radiusAt(i).clamp(0.0, cap).toDouble();
    return cur + cornerBisector(i) * (travel + cornerKnobInset(zoom));
  }

  /// Corner positions in local space (for drawing the radius nodes).
  List<Offset> cornerPoints() {
    switch (type) {
      case ShapeType.rectangle:
        final hw = size.width / 2, hh = size.height / 2;
        return [
          Offset(-hw, -hh),
          Offset(hw, -hh),
          Offset(hw, hh),
          Offset(-hw, hh),
        ];
      case ShapeType.triangle:
      case ShapeType.polygon:
      case ShapeType.star:
        return _vertices();
      default:
        return const [];
    }
  }

  bool get isStroked =>
      type != ShapeType.image && (strokeWidth > 0 || type == ShapeType.line);
  bool get isFilled =>
      type != ShapeType.line &&
      type != ShapeType.image &&
      !(type == ShapeType.path && !closed);

  /// Builds the object's geometry centered on the origin (caller applies the
  /// translate+rotate). Used by both the painter and hit-testing.
  Path localPath() {
    final w = size.width, h = size.height;
    final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final path = Path();
    final maxR = math.min(w, h) / 2;
    switch (type) {
      case ShapeType.rectangle:
        if (cornerRadii.isNotEmpty || cornerRadius > 0) {
          Radius rad(int i) =>
              Radius.circular(radiusAt(i).clamp(0, maxR).toDouble());
          path.addRRect(RRect.fromRectAndCorners(r,
              topLeft: rad(0),
              topRight: rad(1),
              bottomRight: rad(2),
              bottomLeft: rad(3)));
        } else {
          path.addRect(r);
        }
      case ShapeType.ellipse:
        path.addOval(r);
      case ShapeType.triangle:
      case ShapeType.polygon:
      case ShapeType.star:
        _roundedPolygon(path, _vertices());
      case ShapeType.line:
        path
          ..moveTo(-w / 2, h / 2)
          ..lineTo(w / 2, -h / 2);
      case ShapeType.path:
        if (pathPoints.isNotEmpty) {
          final pts = pathPoints
              .map((p) => Offset(p.dx * w, p.dy * h))
              .toList();
          if (hasHandles) {
            _bezierPath(path, pts);
          } else if (smooth && pts.length > 2) {
            _catmullRom(path, pts, closed);
          } else {
            path.moveTo(pts.first.dx, pts.first.dy);
            for (var i = 1; i < pts.length; i++) {
              path.lineTo(pts[i].dx, pts[i].dy);
            }
            if (closed) path.close();
          }
          // Punch interior holes (letter counters) using the even-odd rule.
          if (holes.isNotEmpty) {
            path.fillType = PathFillType.evenOdd;
            for (final hole in holes) {
              if (hole.length < 3) continue;
              path.moveTo(hole.first.dx * w, hole.first.dy * h);
              for (var i = 1; i < hole.length; i++) {
                path.lineTo(hole[i].dx * w, hole[i].dy * h);
              }
              path.close();
            }
          }
        }
      case ShapeType.text:
      case ShapeType.image:
        path.addRect(r); // bounds proxy; content drawn by the painter
    }
    return path;
  }

  /// Builds the path from the bezier node model (anchors + tangent handles).
  /// A segment with both adjoining handles ~zero is drawn straight.
  void _bezierPath(Path path, List<Offset> pts) {
    final n = pts.length;
    final w = size.width, h = size.height;
    Offset out(int i) =>
        Offset(handleOut[i].dx * w, handleOut[i].dy * h);
    Offset inn(int i) => Offset(handleIn[i].dx * w, handleIn[i].dy * h);
    path.moveTo(pts.first.dx, pts.first.dy);
    final segs = closed ? n : n - 1;
    for (var i = 0; i < segs; i++) {
      final a = i, b = (i + 1) % n;
      final straight = _handleZero(handleOut[a]) && _handleZero(handleIn[b]);
      if (straight) {
        path.lineTo(pts[b].dx, pts[b].dy);
      } else {
        final c1 = pts[a] + out(a);
        final c2 = pts[b] + inn(b);
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pts[b].dx, pts[b].dy);
      }
    }
    if (closed) path.close();
  }

  /// Converts this object into the data for an editable bezier path of the same
  /// silhouette: returns normalized anchors + relative in/out handles + modes.
  /// Used by node editing so *every* shape becomes node + tangent editable.
  ({
    List<Offset> anchors,
    List<Offset> hIn,
    List<Offset> hOut,
    List<int> modes,
    bool closed
  }) toEditableNodes() {
    final w = size.width, h = size.height;
    final anchors = <Offset>[];
    final hIn = <Offset>[];
    final hOut = <Offset>[];
    final modes = <int>[];
    Offset norm(Offset local) => Offset(local.dx / w, local.dy / h);

    void addCorner(Offset local) {
      anchors.add(norm(local));
      hIn.add(Offset.zero);
      hOut.add(Offset.zero);
      modes.add(0);
    }

    void addSmooth(Offset local, Offset inLocal, Offset outLocal) {
      anchors.add(norm(local));
      hIn.add(norm(inLocal - local));
      hOut.add(norm(outLocal - local));
      modes.add(1);
    }

    switch (type) {
      case ShapeType.path:
        // Already a path — surface its current geometry, synthesizing handles
        // from the smooth curve so existing freehand paths gain real tangents.
        if (hasHandles) {
          return (
            anchors: List.of(pathPoints),
            hIn: List.of(handleIn),
            hOut: List.of(handleOut),
            modes: nodeModes.length == pathPoints.length
                ? List.of(nodeModes)
                : List.filled(pathPoints.length, smooth ? 1 : 0),
            closed: closed
          );
        }
        final pts = pathPoints
            .map((p) => Offset(p.dx * w, p.dy * h))
            .toList();
        final n = pts.length;
        for (var i = 0; i < n; i++) {
          if (smooth && n > 2) {
            final prev = pts[(i - 1 + n) % n];
            final next = pts[(i + 1) % n];
            final tangent = (next - prev) * (1 / 6);
            addSmooth(pts[i], pts[i] - tangent, pts[i] + tangent);
          } else {
            addCorner(pts[i]);
          }
        }
        return (
          anchors: anchors,
          hIn: hIn,
          hOut: hOut,
          modes: modes,
          closed: closed
        );
      case ShapeType.ellipse:
        const k = 0.5522847498 * 0.5; // kappa, normalized to half-extent
        final rx = w / 2, ry = h / 2;
        final kx = k * w, ky = k * h;
        // top, right, bottom, left (clockwise) with mirrored tangents.
        addSmooth(Offset(0, -ry), Offset(-kx, -ry), Offset(kx, -ry));
        addSmooth(Offset(rx, 0), Offset(rx, -ky), Offset(rx, ky));
        addSmooth(Offset(0, ry), Offset(kx, ry), Offset(-kx, ry));
        addSmooth(Offset(-rx, 0), Offset(-rx, ky), Offset(-rx, -ky));
        return (anchors: anchors, hIn: hIn, hOut: hOut, modes: modes, closed: true);
      case ShapeType.line:
        addCorner(Offset(-w / 2, h / 2));
        addCorner(Offset(w / 2, -h / 2));
        return (anchors: anchors, hIn: hIn, hOut: hOut, modes: modes, closed: false);
      case ShapeType.rectangle:
      case ShapeType.triangle:
      case ShapeType.polygon:
      case ShapeType.star:
        final v = cornerPoints();
        final nv = v.length;
        for (var i = 0; i < nv; i++) {
          final r = radiusAt(i);
          if (r <= 0.5) {
            addCorner(v[i]);
            continue;
          }
          final prev = v[(i - 1 + nv) % nv], cur = v[i], next = v[(i + 1) % nv];
          final toPrev = prev - cur, toNext = next - cur;
          final lp = toPrev.distance, ln = toNext.distance;
          final cut = math.min(r, math.min(lp, ln) / 2);
          final p1 = cur + toPrev * (cut / lp); // entry anchor (edge in)
          final p2 = cur + toNext * (cut / ln); // exit anchor (edge out)
          // Arc p1→cur→p2: handles toward the corner; outer edges stay straight.
          const c = 0.5523;
          Offset nrm(Offset o) => Offset(o.dx / w, o.dy / h);
          // Entry: straight edge before, curve after → OUT toward corner.
          anchors.add(nrm(p1));
          hIn.add(Offset.zero);
          hOut.add(nrm((cur - p1) * c));
          modes.add(0);
          // Exit: curve before → IN toward corner, straight edge after.
          anchors.add(nrm(p2));
          hIn.add(nrm((cur - p2) * c));
          hOut.add(Offset.zero);
          modes.add(0);
        }
        return (anchors: anchors, hIn: hIn, hOut: hOut, modes: modes, closed: true);
      default:
        // Fallback: bounding rectangle.
        final hw = w / 2, hh = h / 2;
        for (final p in [
          Offset(-hw, -hh),
          Offset(hw, -hh),
          Offset(hw, hh),
          Offset(-hw, hh)
        ]) {
          addCorner(p);
        }
        return (anchors: anchors, hIn: hIn, hOut: hOut, modes: modes, closed: true);
    }
  }

  /// Smooth curve through points using a Catmull-Rom → cubic Bézier conversion.
  void _catmullRom(Path path, List<Offset> p, bool close) {
    final pts = List<Offset>.of(p);
    if (close) {
      pts.insert(0, p.last);
      pts.add(p.first);
      pts.add(p[1]);
    } else {
      pts.insert(0, p.first);
      pts.add(p.last);
    }
    path.moveTo(pts[1].dx, pts[1].dy);
    for (var i = 1; i < pts.length - 2; i++) {
      final p0 = pts[i - 1], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2];
      final c1 = p1 + (p2 - p0) * (1 / 6);
      final c2 = p2 - (p3 - p1) * (1 / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    if (close) path.close();
  }

  /// Local-space vertices for triangle / polygon / star.
  List<Offset> _vertices() {
    final rx = size.width / 2, ry = size.height / 2;
    if (type == ShapeType.triangle) {
      return [Offset(0, -ry), Offset(rx, ry), Offset(-rx, ry)];
    }
    final star = type == ShapeType.star;
    final n = star ? points * 2 : points;
    final verts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final radial = (star && i.isOdd) ? starInner.clamp(0.05, 1.0) : 1.0;
      final a = -math.pi / 2 + (2 * math.pi * i / n);
      verts.add(Offset(math.cos(a) * rx * radial, math.sin(a) * ry * radial));
    }
    return verts;
  }

  /// Builds a closed polygon path, rounding each corner by its radius.
  void _roundedPolygon(Path path, List<Offset> v) {
    final n = v.length;
    if (n < 3) return;
    final hasRadius = cornerRadii.isNotEmpty || cornerRadius > 0;
    if (!hasRadius) {
      path.moveTo(v[0].dx, v[0].dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(v[i].dx, v[i].dy);
      }
      path.close();
      return;
    }
    for (var i = 0; i < n; i++) {
      final prev = v[(i - 1 + n) % n];
      final cur = v[i];
      final next = v[(i + 1) % n];
      final r = radiusAt(i);
      final toPrev = prev - cur, toNext = next - cur;
      final lenPrev = toPrev.distance, lenNext = toNext.distance;
      final cut = math.min(r, math.min(lenPrev, lenNext) / 2);
      if (cut <= 0.5) {
        i == 0 ? path.moveTo(cur.dx, cur.dy) : path.lineTo(cur.dx, cur.dy);
        continue;
      }
      final p1 = cur + toPrev * (cut / lenPrev);
      final p2 = cur + toNext * (cut / lenNext);
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
    }
    path.close();
  }

  /// Hit test a canvas-space point against this object (accounts for rotation).
  bool hitTest(Offset canvasPoint, {double tolerance = 0}) {
    final d = canvasPoint - center;
    final cos = math.cos(-rotation), sin = math.sin(-rotation);
    var local = Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
    // Undo any perspective distort so the test runs in the base box space.
    if (hasPerspective) local = perspectiveUnmap(local);

    if (type == ShapeType.line ||
        (type == ShapeType.path && !closed)) {
      return _hitStroke(local, tolerance);
    }
    final t = tolerance;
    final inflated = Rect.fromCenter(
        center: Offset.zero,
        width: size.width + t * 2,
        height: size.height + t * 2);
    if (!inflated.contains(local)) return false;
    if (type == ShapeType.text ||
        type == ShapeType.image ||
        type == ShapeType.rectangle) {
      return true;
    }
    return localPath().contains(local) || t > 0;
  }

  bool _hitStroke(Offset local, double tolerance) {
    final pad = strokeWidth / 2 + tolerance + 12;
    if (type == ShapeType.line) {
      return _distanceToSegment(
              local,
              Offset(-size.width / 2, size.height / 2),
              Offset(size.width / 2, -size.height / 2)) <=
          pad;
    }
    // Open path: distance to any segment.
    for (var i = 0; i < pathPoints.length - 1; i++) {
      final a = Offset(
          pathPoints[i].dx * size.width, pathPoints[i].dy * size.height);
      final b = Offset(pathPoints[i + 1].dx * size.width,
          pathPoints[i + 1].dy * size.height);
      if (_distanceToSegment(local, a, b) <= pad) return true;
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
        (ab.distanceSquared == 0 ? 1 : ab.distanceSquared);
    final clamped = t.clamp(0.0, 1.0);
    final proj = a + ab * clamped;
    return (p - proj).distance;
  }

  /// A fresh-identity copy (for duplicate / paste). [superGroupId] preserves the
  /// outer group by default; pass a value to re-parent the copy.
  ShapeObject clone(
          {Offset offset = Offset.zero,
          String? groupId,
          String? superGroupId}) =>
      ShapeObject(
        type: type,
        center: center + offset,
        size: size,
        rotation: rotation,
        fill: fill,
        fillSpec: fillSpec.copy(),
        stroke: stroke,
        strokeWidth: strokeWidth,
        opacity: opacity,
        cornerRadius: cornerRadius,
        cornerRadii: List.of(cornerRadii),
        starInner: starInner,
        points: points,
        visible: visible,
        locked: locked,
        pathPoints: List.of(pathPoints),
        handleIn: List.of(handleIn),
        handleOut: List.of(handleOut),
        nodeModes: List.of(nodeModes),
        holes: holes.map((h) => List.of(h)).toList(),
        perspective: List.of(perspective),
        closed: closed,
        smooth: smooth,
        text: text,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        letterSpacing: letterSpacing,
        lineHeight: lineHeight,
        textAlignH: textAlignH,
        italic: italic,
        groupId: groupId,
        superGroupId: superGroupId ?? this.superGroupId,
        imageBytes: imageBytes,
        crop: crop,
        maskId: maskId,
        blend: blend,
        strokes: strokes.map((s) => s.copy()).toList(),
        blurAmount: blurAmount,
        shadow: shadow.copy(),
        innerShadow: innerShadow.copy(),
        glow: glow.copy(),
        innerGlow: innerGlow.copy(),
        name: name,
      );

  ShapeObject copyDeep() => ShapeObject(
        id: id,
        type: type,
        center: center,
        size: size,
        rotation: rotation,
        fill: fill,
        fillSpec: fillSpec.copy(),
        stroke: stroke,
        strokeWidth: strokeWidth,
        opacity: opacity,
        cornerRadius: cornerRadius,
        cornerRadii: List.of(cornerRadii),
        starInner: starInner,
        points: points,
        visible: visible,
        locked: locked,
        pathPoints: List.of(pathPoints),
        handleIn: List.of(handleIn),
        handleOut: List.of(handleOut),
        nodeModes: List.of(nodeModes),
        holes: holes.map((h) => List.of(h)).toList(),
        perspective: List.of(perspective),
        closed: closed,
        smooth: smooth,
        text: text,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        letterSpacing: letterSpacing,
        lineHeight: lineHeight,
        textAlignH: textAlignH,
        italic: italic,
        groupId: groupId,
        superGroupId: superGroupId,
        imageBytes: imageBytes,
        crop: crop,
        maskId: maskId,
        blend: blend,
        strokes: strokes.map((s) => s.copy()).toList(),
        blurAmount: blurAmount,
        shadow: shadow.copy(),
        innerShadow: innerShadow.copy(),
        glow: glow.copy(),
        innerGlow: innerGlow.copy(),
        name: name,
      );

  // ---- Serialization (persistence §25.5) --------------------------------
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'cx': center.dx,
        'cy': center.dy,
        'w': size.width,
        'h': size.height,
        'rot': rotation,
        'fill': fill.toARGB32(),
        'fillSpec': fillSpec.toJson(),
        'stroke': stroke.toARGB32(),
        'sw': strokeWidth,
        'op': opacity,
        'cr': cornerRadius,
        'crs': cornerRadii,
        'sin': starInner,
        'pts': points,
        'vis': visible,
        'lock': locked,
        'name': name,
        'closed': closed,
        'smooth': smooth,
        'text': text,
        'fs': fontSize,
        'fw': fontWeight,
        'ff': fontFamily,
        'ls': letterSpacing,
        'lh': lineHeight,
        'tah': textAlignH,
        'ital': italic,
        'gid': groupId,
        'sgid': superGroupId,
        'path': pathPoints.expand((p) => [p.dx, p.dy]).toList(),
        'hin': handleIn.expand((p) => [p.dx, p.dy]).toList(),
        'hout': handleOut.expand((p) => [p.dx, p.dy]).toList(),
        'nmodes': nodeModes,
        'holes': holes
            .map((h) => h.expand((p) => [p.dx, p.dy]).toList())
            .toList(),
        'persp': perspective.expand((p) => [p.dx, p.dy]).toList(),
        'shadow': shadow.toJson(),
        'img': imageBytes == null ? null : base64Encode(imageBytes!),
        'crop': [crop.left, crop.top, crop.right, crop.bottom],
        'mask': maskId,
        'blend': blend,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'blur': blurAmount,
        'ishadow': innerShadow.toJson(),
        'glow': glow.toJson(),
        'iglow': innerGlow.toJson(),
      };

  factory ShapeObject.fromJson(Map<String, dynamic> j) {
    List<Offset> unflat(String key) {
      final flat = (j[key] as List?)?.cast<num>() ?? const [];
      final out = <Offset>[];
      for (var i = 0; i + 1 < flat.length; i += 2) {
        out.add(Offset(flat[i].toDouble(), flat[i + 1].toDouble()));
      }
      return out;
    }

    List<Offset> unflatList(List<dynamic> flat) {
      final out = <Offset>[];
      for (var i = 0; i + 1 < flat.length; i += 2) {
        out.add(Offset(
            (flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()));
      }
      return out;
    }

    final pts = unflat('path');
    final holes = (j['holes'] as List?)
            ?.map((h) => unflatList(h as List))
            .toList() ??
        const <List<Offset>>[];
    return ShapeObject(
      id: j['id'] as String?,
      type: ShapeType.values.byName(j['type'] as String),
      center: Offset((j['cx'] as num).toDouble(), (j['cy'] as num).toDouble()),
      size: Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
      rotation: (j['rot'] as num).toDouble(),
      fill: Color(j['fill'] as int),
      fillSpec: j['fillSpec'] == null
          ? null
          : FillSpec.fromJson(j['fillSpec'] as Map<String, dynamic>),
      stroke: Color(j['stroke'] as int),
      strokeWidth: (j['sw'] as num).toDouble(),
      opacity: (j['op'] as num).toDouble(),
      cornerRadius: (j['cr'] as num).toDouble(),
      cornerRadii:
          (j['crs'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
              const [],
      starInner: (j['sin'] as num?)?.toDouble() ?? 0.45,
      points: j['pts'] as int,
      visible: j['vis'] as bool? ?? true,
      locked: j['lock'] as bool? ?? false,
      name: j['name'] as String?,
      closed: j['closed'] as bool? ?? false,
      smooth: j['smooth'] as bool? ?? false,
      text: j['text'] as String? ?? '',
      fontSize: (j['fs'] as num?)?.toDouble() ?? 48,
      fontWeight: j['fw'] as int? ?? 400,
      fontFamily: j['ff'] as String?,
      letterSpacing: (j['ls'] as num?)?.toDouble() ?? 0,
      lineHeight: (j['lh'] as num?)?.toDouble() ?? 1.2,
      textAlignH: j['tah'] as int? ?? 1,
      italic: j['ital'] as bool? ?? false,
      groupId: j['gid'] as String?,
      superGroupId: j['sgid'] as String?,
      imageBytes:
          j['img'] == null ? null : base64Decode(j['img'] as String),
      crop: j['crop'] == null
          ? const Rect.fromLTRB(0, 0, 1, 1)
          : Rect.fromLTRB(
              (j['crop'][0] as num).toDouble(),
              (j['crop'][1] as num).toDouble(),
              (j['crop'][2] as num).toDouble(),
              (j['crop'][3] as num).toDouble()),
      maskId: j['mask'] as String?,
      blend: j['blend'] as int? ?? 3,
      blurAmount: (j['blur'] as num?)?.toDouble() ?? 0,
      strokes: (j['strokes'] as List?)
              ?.map((e) => StrokeSpec.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      pathPoints: pts,
      handleIn: unflat('hin'),
      handleOut: unflat('hout'),
      nodeModes: (j['nmodes'] as List?)?.map((e) => e as int).toList() ??
          const [],
      holes: holes,
      perspective: unflat('persp'),
      shadow: j['shadow'] == null
          ? ShadowSpec()
          : ShadowSpec.fromJson(j['shadow'] as Map<String, dynamic>),
      innerShadow: j['ishadow'] == null
          ? null
          : ShadowSpec.fromJson(j['ishadow'] as Map<String, dynamic>),
      glow: j['glow'] == null
          ? null
          : ShadowSpec.fromJson(j['glow'] as Map<String, dynamic>),
      innerGlow: j['iglow'] == null
          ? null
          : ShadowSpec.fromJson(j['iglow'] as Map<String, dynamic>),
    );
  }
}

// ---- Projective (perspective) transform helpers --------------------------
// 3×3 matrices are row-major lists of 9 doubles.

/// Projective transform mapping the unit square — corners (0,0)(1,0)(1,1)(0,1)
/// — onto quad [q] (4 corners). Handles the affine (parallelogram) case too.
List<double> _squareToQuad(List<Offset> q) {
  final p0 = q[0], p1 = q[1], p2 = q[2], p3 = q[3];
  final dx1 = p1.dx - p2.dx, dx2 = p3.dx - p2.dx;
  final dx3 = p0.dx - p1.dx + p2.dx - p3.dx;
  final dy1 = p1.dy - p2.dy, dy2 = p3.dy - p2.dy;
  final dy3 = p0.dy - p1.dy + p2.dy - p3.dy;
  double a, b, c, d, e, f, g, h;
  if (dx3.abs() < 1e-9 && dy3.abs() < 1e-9) {
    a = p1.dx - p0.dx;
    b = p3.dx - p0.dx;
    c = p0.dx;
    d = p1.dy - p0.dy;
    e = p3.dy - p0.dy;
    f = p0.dy;
    g = 0;
    h = 0;
  } else {
    final denom = dx1 * dy2 - dx2 * dy1;
    g = (dx3 * dy2 - dx2 * dy3) / denom;
    h = (dx1 * dy3 - dx3 * dy1) / denom;
    a = p1.dx - p0.dx + g * p1.dx;
    b = p3.dx - p0.dx + h * p3.dx;
    c = p0.dx;
    d = p1.dy - p0.dy + g * p1.dy;
    e = p3.dy - p0.dy + h * p3.dy;
    f = p0.dy;
  }
  return [a, b, c, d, e, f, g, h, 1.0];
}

List<double> _mat3Mul(List<double> a, List<double> b) {
  final r = List<double>.filled(9, 0);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      var s = 0.0;
      for (var k = 0; k < 3; k++) {
        s += a[row * 3 + k] * b[k * 3 + col];
      }
      r[row * 3 + col] = s;
    }
  }
  return r;
}

List<double> _mat3Inv(List<double> m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final A = e * i - f * h;
  final B = -(d * i - f * g);
  final C = d * h - e * g;
  var det = a * A + b * B + c * C;
  if (det.abs() < 1e-12) det = 1e-12;
  final inv = 1 / det;
  return [
    A * inv,
    (c * h - b * i) * inv,
    (b * f - c * e) * inv,
    B * inv,
    (a * i - c * g) * inv,
    (c * d - a * f) * inv,
    C * inv,
    (b * g - a * h) * inv,
    (a * e - b * d) * inv,
  ];
}
