import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shape_object.dart';
import '../models/tool.dart';
import '../state/app_scope.dart';
import '../state/editor_model.dart';
import '../theme/breakpoints.dart';
import 'canvas_painter.dart';

enum _Mode {
  none,
  pan,
  move,
  resize,
  groupResize,
  rotate,
  radius,
  marquee,
  draw,
  pen,
  node,
  handle,
  nodeMarquee,
  perspective
}

/// What the pointer grabbed on the selected object.
class _HandleHit {
  _HandleHit.resize(this.sx, this.sy)
      : kind = _Mode.resize,
        corner = -1;
  _HandleHit.rotate()
      : kind = _Mode.rotate,
        sx = 0,
        sy = 0,
        corner = -1;
  _HandleHit.radius(this.corner)
      : kind = _Mode.radius,
        sx = 0,
        sy = 0;
  final _Mode kind;
  final int sx;
  final int sy;
  final int corner;
}

/// The infinite-canvas surface and its gesture architecture (§7, §13):
/// move, resize (rotation-aware), rotate, corner-radius, two-finger pan/zoom,
/// marquee multi-select, shift/ctrl-add, and the draw/pen/text tools.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  late EditorModel _m;
  _Mode _mode = _Mode.none;
  int _lastPointers = 0;

  // Pan/zoom baseline.
  double _startZoom = 1;
  Offset _startPan = Offset.zero;
  Offset _startFocal = Offset.zero;

  // Transform baseline.
  int _sx = 0, _sy = 0;
  int _radiusCorner = 0;
  int _handleNode = 0;
  bool _handleIsOut = true;
  int _perspCorner = 0;

  // Pen tool drag (click-drag to pull out a tangent).
  Offset _penStart = Offset.zero;
  Offset _penHandle = Offset.zero;
  bool _penMoved = false;
  Size _startSize = Size.zero;
  Offset _anchorWorld = Offset.zero;
  double _startRotation = 0;
  double _startAngle = 0;

  // Marquee / draw.
  Offset _marqueeStart = Offset.zero;
  final List<Offset> _drawPoints = [];
  Offset _stabPoint = Offset.zero; // stabilised (lagged) freehand cursor
  bool _didLayout = false;

  // Group resize: the selection's bounds when the drag began, plus each
  // object's starting centre/size so every frame scales from the original
  // rather than compounding rounding on the previous frame.
  Rect _groupStartRect = Rect.zero;
  final Map<String, (Offset, Size)> _groupStart = {};

  /// Where the pointer actually went down, captured by the [Listener] before
  /// the gesture arena resolves.
  ///
  /// `onScaleStart` only fires once touch-slop is exceeded, so by then
  /// `d.localFocalPoint` has already travelled ~18px away from the press — far
  /// enough to miss a handle you hit dead-on. Grabs test against this instead.
  Offset _downPos = Offset.zero;

  /// Cursor under the mouse. Only ever changes on hover, so touch is unaffected.
  MouseCursor _cursor = SystemMouseCursors.basic;

  bool get _additive =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  @override
  Widget build(BuildContext context) {
    _m = AppScope.read(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_didLayout) {
          _didLayout = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Center content for the current device (fixes "not centred" on
            // mobile when a saved viewport came from another screen size).
            if (_m.objects.isNotEmpty) {
              // The welcome art fills a phone nicely but overwhelms a desktop
              // window, so frame it 30% smaller there. Real projects fit full.
              final welcomeOnDesktop = _m.showingWelcome &&
                  constraints.maxWidth >= Breakpoints.desktopMinWidth;
              _m.zoomToFit(constraints.biggest,
                  fill: welcomeOnDesktop ? 0.7 : 1.0);
            } else {
              _m.setViewport(_m.zoom,
                  Offset(constraints.maxWidth / 2, constraints.maxHeight / 2));
            }
          });
        }
        // Web: a mouse gets the wheel, right-click and a cursor; touch keeps
        // every gesture below unchanged. Listener sees the wheel before the
        // GestureDetector's arena, so zooming never competes with dragging.
        return Listener(
          onPointerDown: (e) => _downPos = e.localPosition,
          onPointerSignal: _onPointerSignal,
          child: MouseRegion(
            cursor: _cursor,
            onHover: _onHover,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: _onTapUp,
              onDoubleTapDown: _onDoubleTapDown,
              onLongPressStart: _onLongPress,
              onSecondaryTapDown: _onSecondaryTapDown,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: CanvasPainter(_m),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- Handle hit testing ------------------------------------------------
  Offset _toLocal(ShapeObject o, Offset canvasPoint) {
    final d = canvasPoint - o.center;
    final c = math.cos(-o.rotation), s = math.sin(-o.rotation);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// The group box's padded rect — must match `_paintGroupBox`, or the handles
  /// you can see won't be the handles you can grab.
  Rect? _groupBox() {
    if (_m.selection.length < 2) return null;
    return _m.selectionBounds?.inflate(8 / _m.zoom);
  }

  /// Corner handle of a multi-selection's bounding box. The single-object
  /// [_hitHandle] bails out on `singleSelection == null`, so without this the
  /// group box's corners are painted but never hit-testable — visible handles
  /// that do nothing.
  _HandleHit? _hitGroupHandle(Offset screen) {
    final box = _groupBox();
    if (box == null) return null;
    final cp = _m.screenToCanvas(screen);
    final tol = 24 / _m.zoom;
    bool near(Offset a) => (cp - a).distance <= tol;
    if (near(box.bottomRight)) return _HandleHit.resize(1, 1);
    if (near(box.topLeft)) return _HandleHit.resize(-1, -1);
    if (near(box.topRight)) return _HandleHit.resize(1, -1);
    if (near(box.bottomLeft)) return _HandleHit.resize(-1, 1);
    return null;
  }

  _HandleHit? _hitHandle(Offset screen) {
    final o = _m.singleSelection;
    if (o == null) return null;
    final cp = _m.screenToCanvas(screen);
    final local = _toLocal(o, cp);
    final tol = 24 / _m.zoom;
    final hw = o.size.width / 2, hh = o.size.height / 2;

    bool near(Offset a, Offset b) => (a - b).distance <= tol;

    // Rotation handle.
    if (near(local, Offset(0, -hh - 24 / _m.zoom))) return _HandleHit.rotate();
    // Corner-radius knobs (one per corner) — checked before bbox corners.
    for (var i = 0; i < o.cornerCount; i++) {
      if (near(local, o.cornerKnob(i, _m.zoom))) return _HandleHit.radius(i);
    }
    // Corners.
    for (final sx in [-1, 1]) {
      for (final sy in [-1, 1]) {
        if (near(local, Offset(sx * hw, sy * hh))) {
          return _HandleHit.resize(sx, sy);
        }
      }
    }
    // Edge midpoints.
    if (near(local, Offset(0, -hh))) return _HandleHit.resize(0, -1);
    if (near(local, Offset(0, hh))) return _HandleHit.resize(0, 1);
    if (near(local, Offset(-hw, 0))) return _HandleHit.resize(-1, 0);
    if (near(local, Offset(hw, 0))) return _HandleHit.resize(1, 0);
    return null;
  }

  // ---- Gesture start -----------------------------------------------------
  void _onScaleStart(ScaleStartDetails d) {
    _startZoom = _m.zoom;
    _startPan = _m.pan;
    _startFocal = d.localFocalPoint;
    _lastPointers = d.pointerCount;

    if (d.pointerCount >= 2) {
      _mode = _Mode.pan;
      return;
    }

    // Perspective distort takes over single-finger input: grab a corner handle.
    if (_m.perspectiveEditId != null) {
      final i = _hitPerspectiveCorner(d.localFocalPoint);
      if (i != null) {
        _perspCorner = i;
        _mode = _Mode.perspective;
        _m.beginGesture();
      } else {
        _mode = _Mode.none;
      }
      return;
    }

    // Node editing takes over single-finger input.
    if (_m.nodeEditId != null) {
      // Tangent handles of selected nodes have priority over anchors.
      final h = _hitTangent(d.localFocalPoint);
      if (h != null) {
        _handleNode = h.$1;
        _handleIsOut = h.$2;
        _mode = _Mode.handle;
        _m.beginGesture();
        return;
      }
      final idx = _hitNode(d.localFocalPoint);
      if (idx != null) {
        // Keep an existing multi-selection if the grabbed node is part of it.
        if (!_m.selectedNodes.contains(idx)) _m.selectNode(idx);
        _mode = _Mode.node;
        _m.beginGesture();
      } else {
        // Drag on empty → rubber-band select multiple nodes.
        _mode = _Mode.nodeMarquee;
        _marqueeStart = _m.screenToCanvas(d.localFocalPoint);
        _m.setMarquee(Rect.fromPoints(_marqueeStart, _marqueeStart));
      }
      return;
    }

    // Tool-driven drawing.
    if (_m.tool == ActiveTool.draw) {
      _mode = _Mode.draw;
      final p = _m.screenToCanvas(d.localFocalPoint);
      _stabPoint = p;
      _drawPoints
        ..clear()
        ..add(p);
      _m.drawStart(p);
      return;
    }
    // Pen supports click-drag: a tap (handled in onTapUp) drops a corner; a
    // drag pulls out a symmetric tangent handle for a smooth anchor.
    if (_m.tool == ActiveTool.pen) {
      _penStart = _m.screenToCanvas(d.localFocalPoint);
      _penHandle = Offset.zero;
      _penMoved = false;
      _mode = _Mode.pen;
      return;
    }
    if (_m.tool == ActiveTool.text) {
      _mode = _Mode.none; // tap tool
      return;
    }

    // Handle grab on a multi-selection's group box. Checked before the object
    // grab below, so a corner sitting over a shape still resizes rather than
    // starting a move.
    final groupHandle = _hitGroupHandle(_downPos);
    if (groupHandle != null) {
      final gb = _m.selectionBounds!;
      _m.beginGesture();
      _mode = _Mode.groupResize;
      _sx = groupHandle.sx;
      _sy = groupHandle.sy;
      _groupStartRect = gb;
      // Anchor is the corner opposite the one grabbed; it stays put.
      _anchorWorld = Offset(
        _sx > 0 ? gb.left : gb.right,
        _sy > 0 ? gb.top : gb.bottom,
      );
      _groupStart
        ..clear()
        ..addEntries(
            _m.selectedObjects.map((o) => MapEntry(o.id, (o.center, o.size))));
      return;
    }

    // Handle grab on the single selection.
    final handle = _hitHandle(d.localFocalPoint);
    if (handle != null) {
      final o = _m.singleSelection!;
      _m.beginGesture();
      _startSize = o.size;
      _startRotation = o.rotation;
      if (handle.kind == _Mode.resize) {
        _mode = _Mode.resize;
        _sx = handle.sx;
        _sy = handle.sy;
        final anchorLocal = Offset(-_sx * _startSize.width / 2,
            -_sy * _startSize.height / 2);
        _anchorWorld = o.center + _rotate(anchorLocal, o.rotation);
      } else if (handle.kind == _Mode.rotate) {
        _mode = _Mode.rotate;
        final p = _m.screenToCanvas(d.localFocalPoint);
        _startAngle = math.atan2(p.dy - o.center.dy, p.dx - o.center.dx);
      } else {
        _mode = _Mode.radius;
        _radiusCorner = handle.corner;
        _m.selectCorner(handle.corner);
      }
      return;
    }

    // Object grab → move (selecting first if needed).
    final cp = _m.screenToCanvas(d.localFocalPoint);
    final hit = _m.hitTest(cp);
    if (hit != null) {
      if (_additive) {
        _m.addToSelection(hit.id);
      } else if (!_m.selection.contains(hit.id)) {
        _m.selectOnly(hit.id);
      }
      _mode = _Mode.move;
      _m.beginGesture();
    } else {
      // Empty → marquee select.
      _mode = _Mode.marquee;
      _marqueeStart = cp;
      _m.setMarquee(Rect.fromPoints(cp, cp));
    }
  }

  // ---- Gesture update ----------------------------------------------------
  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _lastPointers) {
      _commitActive();
      _startZoom = _m.zoom;
      _startPan = _m.pan;
      _startFocal = d.localFocalPoint;
      _lastPointers = d.pointerCount;
      _mode = d.pointerCount >= 2 ? _Mode.pan : _Mode.none;
    }

    switch (_mode) {
      case _Mode.pan:
        final newZoom = (_startZoom * d.scale).clamp(0.05, 64.0).toDouble();
        final focalCanvas = (_startFocal - _startPan) / _startZoom;
        _m.setViewport(newZoom, d.localFocalPoint - focalCanvas * newZoom);
      case _Mode.move:
        final deltaCanvas = d.focalPointDelta / _m.zoom;
        _m.mutate(() {
          for (final o in _m.selectedObjects) {
            o.center += deltaCanvas;
          }
        });
      case _Mode.resize:
        _applyResize(_m.screenToCanvas(d.localFocalPoint));
      case _Mode.groupResize:
        _applyGroupResize(_m.screenToCanvas(d.localFocalPoint));
      case _Mode.rotate:
        final o = _m.singleSelection!;
        final p = _m.screenToCanvas(d.localFocalPoint);
        final ang = math.atan2(p.dy - o.center.dy, p.dx - o.center.dx);
        _m.mutate(() => o.rotation = _startRotation + (ang - _startAngle));
      case _Mode.radius:
        final o = _m.singleSelection!;
        final local = _toLocal(o, _m.screenToCanvas(d.localFocalPoint));
        final v = o.cornerPoints()[_radiusCorner % o.cornerCount];
        final dir = o.cornerBisector(_radiusCorner % o.cornerCount);
        final proj = (local - v).dx * dir.dx + (local - v).dy * dir.dy;
        final r = proj - ShapeObject.cornerKnobInset(_m.zoom);
        _m.setCorner(_radiusCorner,
            r.clamp(0.0, math.min(o.size.width, o.size.height) / 2));
      case _Mode.marquee:
        final cp = _m.screenToCanvas(d.localFocalPoint);
        _m.setMarquee(Rect.fromPoints(_marqueeStart, cp));
      case _Mode.draw:
        final raw = _m.screenToCanvas(d.localFocalPoint);
        // Procreate-style "streamline": a small dead-zone kills micro-jitter,
        // then the brush springs toward the finger with an exponential filter.
        // Off (0) → raw input; max (1) → buttery, heavily smoothed trailing line.
        final s = _m.drawStabilization;
        if (s <= 0) {
          _stabPoint = raw;
        } else {
          final dead = (s * 12) / _m.zoom; // jitter dead-zone radius
          final vec = raw - _stabPoint;
          final dist = vec.distance;
          var target = _stabPoint;
          if (dist > dead) target = _stabPoint + vec * ((dist - dead) / dist);
          final k = 1.0 - s * 0.93; // s=1 → 0.07 (very smooth spring)
          _stabPoint += (target - _stabPoint) * k;
        }
        _drawPoints.add(_stabPoint);
        _m.drawExtend(_stabPoint);
      case _Mode.pen:
        _penHandle = _m.screenToCanvas(d.localFocalPoint) - _penStart;
        if (_penHandle.distance > 6 / _m.zoom) _penMoved = true;
        _m.penPreview(_penStart, _penMoved ? _penHandle : null);
      case _Mode.node:
        _m.moveNode(_m.selectedNode ?? 0, d.focalPointDelta / _m.zoom);
      case _Mode.handle:
        _m.moveHandle(_handleNode, _handleIsOut, d.focalPointDelta / _m.zoom);
      case _Mode.nodeMarquee:
        _m.setMarquee(
            Rect.fromPoints(_marqueeStart, _m.screenToCanvas(d.localFocalPoint)));
      case _Mode.perspective:
        _m.setPerspectiveCorner(
            _perspCorner, _m.screenToCanvas(d.localFocalPoint));
      case _Mode.none:
        break;
    }
  }

  void _applyResize(Offset pointerWorld) {
    final o = _m.singleSelection!;
    final localVec = _rotate(pointerWorld - _anchorWorld, -_startRotation);
    var newW = _sx != 0 ? math.max(localVec.dx * _sx, 8.0) : _startSize.width;
    var newH = _sy != 0 ? math.max(localVec.dy * _sy, 8.0) : _startSize.height;

    // Bottom-right corner (or Shift) locks the aspect ratio.
    final lockAspect = (_sx == 1 && _sy == 1) || _additive;
    if (lockAspect && _sx != 0 && _sy != 0) {
      final factor = math.max(newW / _startSize.width, newH / _startSize.height);
      newW = _startSize.width * factor;
      newH = _startSize.height * factor;
    }

    final cxo = _sx != 0 ? _sx * newW / 2 : 0.0;
    final cyo = _sy != 0 ? _sy * newH / 2 : 0.0;
    final newCenter = _anchorWorld + _rotate(Offset(cxo, cyo), _startRotation);
    _m.mutate(() {
      o.size = Size(newW, newH);
      o.center = newCenter;
    });
  }

  /// Scales the whole selection about the anchored corner.
  ///
  /// Uniform on purpose: scaling x and y by different factors turns a *rotated*
  /// rectangle into a parallelogram, and an object only stores a size and an
  /// angle — it has nowhere to put the shear. One factor keeps every object a
  /// faithful rotated rect, so mixed-rotation selections stay correct.
  void _applyGroupResize(Offset pointerWorld) {
    final w0 = _groupStartRect.width, h0 = _groupStartRect.height;
    if (w0 <= 0 || h0 <= 0) return;
    final v = pointerWorld - _anchorWorld;
    // Extent along each axis, measured from the anchor, as a fraction of the
    // original. _sx/_sy flip the sign so every corner grows the same way.
    final fx = (v.dx * _sx) / w0;
    final fy = (v.dy * _sy) / h0;
    var f = math.max(fx, fy);
    if (!f.isFinite) return;
    // Floor it: a zero or negative factor would collapse or mirror everything.
    f = f.clamp(0.02, 64.0);

    _m.mutate(() {
      for (final o in _m.selectedObjects) {
        final start = _groupStart[o.id];
        if (start == null) continue;
        final (c0, s0) = start;
        o.center = _anchorWorld + (c0 - _anchorWorld) * f;
        o.size = Size(math.max(1, s0.width * f), math.max(1, s0.height * f));
      }
    });
  }

  // ---- Gesture end -------------------------------------------------------
  void _onScaleEnd(ScaleEndDetails d) {
    _commitActive();
    _mode = _Mode.none;
    _lastPointers = 0;
  }

  void _commitActive() {
    switch (_mode) {
      case _Mode.move:
        _m.commitGesture('Move');
      case _Mode.resize:
        _m.commitGesture('Resize');
      case _Mode.groupResize:
        _groupStart.clear();
        _m.commitGesture('Resize group');
      case _Mode.rotate:
        _m.commitGesture('Rotate');
      case _Mode.radius:
        _m.commitGesture('Corner radius');
      case _Mode.node:
        _m.commitGesture('Move node');
      case _Mode.handle:
        _m.commitGesture('Edit handle');
      case _Mode.perspective:
        _m.commitGesture('Perspective');
      case _Mode.nodeMarquee:
        final rect = _m.marquee;
        _m.setMarquee(null);
        if (rect != null) _m.selectNodesInRect(rect);
      case _Mode.marquee:
        final rect = _m.marquee;
        _m.setMarquee(null);
        if (rect != null && rect.shortestSide > 3 / _m.zoom) {
          final ids = _m.objectsInRect(rect).map((o) => o.id);
          _m.setSelection(ids);
        }
      case _Mode.draw:
        _m.drawClear();
        if (_drawPoints.length >= 2) {
          _m.addSmoothPath(List.of(_drawPoints), strokeWidth: 4);
        }
        _drawPoints.clear();
      case _Mode.pen:
        // A real drag → smooth anchor with the pulled tangent. A non-drag tap
        // is left to onTapUp (drops a corner / closes the path).
        if (_penMoved) _m.penAddSmooth(_penStart, _penHandle);
        _m.penPreview(null, null);
      default:
        break;
    }
  }

  /// Hits a perspective corner handle (0 TL,1 TR,2 BR,3 BL) → its index.
  int? _hitPerspectiveCorner(Offset screen) {
    final o = _m.byId(_m.perspectiveEditId ?? '');
    if (o == null || !o.hasPerspective) return null;
    final p = _m.screenToCanvas(screen);
    var best = -1;
    var bestD = 24 / _m.zoom;
    for (var i = 0; i < 4; i++) {
      final c = _m.perspectiveCornerCanvas(o, i);
      final dist = (c - p).distance;
      if (dist < bestD) {
        bestD = dist;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  int? _hitNode(Offset screen) {
    final o = _m.byId(_m.nodeEditId ?? '');
    if (o == null) return null;
    final tol = 22 / _m.zoom;
    final cp = _m.screenToCanvas(screen);
    final local = _toLocal(o, cp);
    for (var i = 0; i < o.pathPoints.length; i++) {
      final p = Offset(
          o.pathPoints[i].dx * o.size.width, o.pathPoints[i].dy * o.size.height);
      if ((p - local).distance <= tol) return i;
    }
    return null;
  }

  /// Hits a tangent control handle of a selected node → (nodeIndex, isOut).
  (int, bool)? _hitTangent(Offset screen) {
    final o = _m.byId(_m.nodeEditId ?? '');
    if (o == null || !o.hasHandles) return null;
    final tol = 20 / _m.zoom;
    // Match the painter's minimum on-screen handle length so the grab target is
    // exactly where the handle is drawn (even for very short tangents).
    final minLen = 18 / _m.zoom;
    final local = _toLocal(o, _m.screenToCanvas(screen));
    bool zero(Offset h) => h.dx.abs() < 1e-6 && h.dy.abs() < 1e-6;
    for (final i in _m.selectedNodes) {
      if (i >= o.pathPoints.length) continue;
      if (!zero(o.handleOut[i]) &&
          (o.nodeOutDisplay(i, minLen) - local).distance <= tol) {
        return (i, true);
      }
      if (!zero(o.handleIn[i]) &&
          (o.nodeInDisplay(i, minLen) - local).distance <= tol) {
        return (i, false);
      }
    }
    return null;
  }

  // ---- Taps --------------------------------------------------------------
  void _onTapUp(TapUpDetails d) {
    final cp = _m.screenToCanvas(d.localPosition);

    // While perspective-distorting, taps are inert (finish via the HUD's Done).
    if (_m.perspectiveEditId != null) return;

    // Node-edit taps: select a node, add one on a segment, or exit on empty.
    if (_m.nodeEditId != null) {
      final idx = _hitNode(d.localPosition);
      if (idx != null) {
        _m.selectNode(idx, add: _additive);
      } else {
        final o = _m.byId(_m.nodeEditId!)!;
        if (o.hitTest(cp, tolerance: 10 / _m.zoom)) {
          _m.addNodeNear(cp);
        } else {
          _m.exitNodeEdit();
        }
      }
      return;
    }

    // Tap tools.
    if (_m.tool == ActiveTool.text) {
      final o = _m.addText(cp);
      _m.beginTextEdit(o.id);
      _m.setTool(ActiveTool.none);
      return;
    }
    if (_m.tool == ActiveTool.pen) {
      // A drag already committed a smooth anchor — don't also drop a corner.
      if (_penMoved) {
        _penMoved = false;
        return;
      }
      // Close if tapping near the first anchor.
      if (_m.penDraft.length >= 2 &&
          (_m.penDraft.first - cp).distance < 18 / _m.zoom) {
        _m.penFinish(closed: true);
      } else {
        _m.penAddPoint(cp);
      }
      return;
    }

    if (_m.contextMenuAt != null) {
      _m.closeContextMenu();
      return;
    }
    if (_m.orbExpanded) {
      _m.collapseOrb();
      return;
    }

    final hit = _m.hitTest(cp);
    if (hit == null) {
      if (!_additive) _m.clearSelection();
    } else if (_additive) {
      _m.toggleSelection(hit.id);
    } else {
      _m.selectOnly(hit.id);
    }
  }

  void _onDoubleTapDown(TapDownDetails d) {
    final cp = _m.screenToCanvas(d.localPosition);
    final hit = _m.hitTest(cp);
    if (hit != null && hit.type == ShapeType.text) {
      _m.selectOnly(hit.id);
      _m.beginTextEdit(hit.id);
    } else if (hit != null && hit.type == ShapeType.path) {
      _m.enterNodeEdit(hit.id);
    } else {
      final media = MediaQuery.of(context).size;
      _m.zoomToFit(media);
    }
  }

  void _onLongPress(LongPressStartDetails d) => _openMenuAt(d.localPosition);

  /// Right-click is the mouse equivalent of the touch long-press.
  void _onSecondaryTapDown(TapDownDetails d) => _openMenuAt(d.localPosition);

  void _openMenuAt(Offset localPosition) {
    if (_m.tool != ActiveTool.none) return;
    final cp = _m.screenToCanvas(localPosition);
    final hit = _m.hitTest(cp);
    if (hit == null) return;
    if (!_m.selection.contains(hit.id)) _m.selectOnly(hit.id);
    _m.openContextMenu(localPosition);
  }

  // ---- Mouse (web/desktop) ------------------------------------------------

  /// Wheel = zoom about the cursor; shift+wheel and trackpad two-finger
  /// swipes = pan, matching what every other design tool does.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isShiftPressed) {
      _m.setViewport(_m.zoom, _m.pan - e.scrollDelta);
      return;
    }
    _zoomAbout(e.localPosition, math.exp(-e.scrollDelta.dy / 320));
  }

  /// Scales by [factor] while pinning the canvas point under [focus] in place.
  void _zoomAbout(Offset focus, double factor) {
    final before = _m.screenToCanvas(focus);
    final zoom = (_m.zoom * factor).clamp(0.05, 64.0);
    // Re-derive pan so `focus` still maps to the same canvas point.
    _m.setViewport(zoom, focus - before * zoom);
  }

  void _onHover(PointerHoverEvent e) {
    final c = _cursorFor(e.localPosition);
    if (c != _cursor) setState(() => _cursor = c);
  }

  /// The cursor for a point: handles win over the object, the object wins over
  /// empty canvas. Mirrors the priority [_onScaleStart] uses to pick a gesture,
  /// so what you see is what you'd grab.
  MouseCursor _cursorFor(Offset p) {
    switch (_m.tool) {
      case ActiveTool.text:
        return SystemMouseCursors.text;
      case ActiveTool.none:
        break;
      default:
        return SystemMouseCursors.precise; // pen / draw
    }
    // Group corners are unrotated, so their cursor is a straight diagonal.
    final g = _hitGroupHandle(p);
    if (g != null) {
      return g.sx * g.sy > 0
          ? SystemMouseCursors.resizeUpLeftDownRight
          : SystemMouseCursors.resizeUpRightDownLeft;
    }
    final h = _hitHandle(p);
    if (h != null) {
      return switch (h.kind) {
        _Mode.rotate => SystemMouseCursors.grab,
        _Mode.radius => SystemMouseCursors.grab,
        _Mode.resize => _resizeCursor(h.sx, h.sy),
        _ => SystemMouseCursors.basic,
      };
    }
    if (_m.hitTest(_m.screenToCanvas(p)) != null) {
      return SystemMouseCursors.move;
    }
    return SystemMouseCursors.basic;
  }

  /// Picks the directional resize cursor for a handle, honouring the object's
  /// rotation — a 90°-turned object's side handle must read as up/down, not
  /// left/right. The handle's outward normal is rotated into screen space and
  /// snapped to the nearest of the four diagonal/axis cursors.
  MouseCursor _resizeCursor(int sx, int sy) {
    final o = _m.singleSelection;
    final v = _rotate(Offset(sx.toDouble(), sy.toDouble()), o?.rotation ?? 0);
    // Fold to a half-circle: a resize axis is symmetric (N-S reads as S-N).
    var a = math.atan2(v.dy, v.dx) % math.pi;
    if (a < 0) a += math.pi;
    // Four 45°-wide buckets centred on 0, 45, 90, 135 degrees.
    final bucket = ((a / (math.pi / 4)).round()) % 4;
    return switch (bucket) {
      0 => SystemMouseCursors.resizeLeftRight,
      1 => SystemMouseCursors.resizeUpLeftDownRight,
      2 => SystemMouseCursors.resizeUpDown,
      _ => SystemMouseCursors.resizeUpRightDownLeft,
    };
  }

  Offset _rotate(Offset v, double a) {
    final c = math.cos(a), s = math.sin(a);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }
}
