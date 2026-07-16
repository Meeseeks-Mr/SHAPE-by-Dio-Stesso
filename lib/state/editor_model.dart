import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/shape_object.dart';
import '../models/tool.dart';
import '../theme/fonts.dart';
import '../theme/shape_theme.dart';
import 'command.dart';
import 'exporter.dart';
import 'image_store.dart';
import 'project_store.dart';
import 'svg_import.dart';
import 'trace.dart';

/// The single source of truth for the editor — document (objects + selection +
/// undo history) and ephemeral UI state (orb, sheets, viewport). Mirrors the
/// "selection controller both the painter and chrome listen to" design in
/// §25.2 Rendering Architecture. Also owns project identity and debounced
/// autosave (§25.5).
class EditorModel extends ChangeNotifier {
  EditorModel() {
    _startNewDocument(seedWelcome: true);
  }

  // ---- Project identity / persistence ------------------------------------
  String projectId = '';
  String projectName = 'Untitled';
  DateTime _createdAt = DateTime.now();
  bool _persistReady = false;
  // A document is only persisted once the user explicitly saves it ("Save As").
  // Untitled drafts are never auto-saved, so the project list stays clean.
  bool _explicitlySaved = false;
  bool get isSaved => _explicitlySaved;
  Timer? _saveTimer;
  int _pastelCursor = 1; // 0 used by the welcome shape

  /// Next pastel fill for a newly created object.
  Color nextPastel() => ShapeColors.pastelFor(_pastelCursor++);

  /// True while the untouched welcome composition is what's on screen. Only the
  /// welcome art is framed smaller on desktop; a real project always fits full.
  bool showingWelcome = false;

  void _startNewDocument({bool seedWelcome = false}) {
    showingWelcome = seedWelcome;
    projectId = 'proj-${DateTime.now().microsecondsSinceEpoch}';
    projectName = 'Untitled';
    _explicitlySaved = false;
    _createdAt = DateTime.now();
    _objects.clear();
    _selection.clear();
    _undo.clear();
    _redo.clear();
    _pastelCursor = 1;
    zoom = 1.0;
    pan = Offset.zero;
    if (seedWelcome) {
      // A subtle welcome composition in the app's pastel palette — a soft
      // cluster that greets the user with the product's aesthetic instead of a
      // bare rectangle. Left unselected for a calm first impression; a tap on
      // any shape reveals the selection border + property halo. Not part of
      // undo history.
      _objects.addAll([
        ShapeObject(
          type: ShapeType.rectangle,
          center: const Offset(4, 16),
          size: const Size(236, 178),
          rotation: -0.05,
          cornerRadius: 34,
          fill: ShapeColors.lavender,
          opacity: 0.95,
        ),
        ShapeObject(
          type: ShapeType.ellipse,
          center: const Offset(86, -40),
          size: const Size(150, 150),
          fill: ShapeColors.mint,
          opacity: 0.9,
        ),
        ShapeObject(
          type: ShapeType.ellipse,
          center: const Offset(-96, -48),
          size: const Size(70, 70),
          fill: ShapeColors.peach,
        ),
        ShapeObject(
          type: ShapeType.triangle,
          center: const Offset(74, 84),
          size: const Size(84, 84),
          rotation: 0.5,
          fill: ShapeColors.shapeBlue,
          opacity: 0.45,
        ),
        ShapeObject(
          type: ShapeType.star,
          center: const Offset(-78, 78),
          size: const Size(58, 58),
          rotation: 0.2,
          fill: ShapeColors.butter,
          opacity: 0.9,
        ),
      ]);
    }
  }

  /// Loads the last-opened project after a normal exit or crash; otherwise
  /// keeps the welcome document and persists it. Call once at startup.
  Future<void> bootstrap() async {
    await ProjectStore.instance.init();
    savedColors
      ..clear()
      ..addAll((await ProjectStore.instance.palette()).map(Color.new));
    // Crash recovery first: the scratch slot holds the exact last canvas,
    // including unsaved Untitled drafts, so prefer it over the last saved
    // project. (After a normal exit the scratch equals the open document, so
    // this also restores the usual last-opened project.)
    final scratch = await ProjectStore.instance.loadScratch();
    if (scratch != null) {
      try {
        final m = jsonDecode(scratch) as Map<String, dynamic>;
        _applyProject(Project.fromJson(m['p'] as Map<String, dynamic>));
        _explicitlySaved = (m['saved'] as bool?) ?? false;
        _persistReady = true;
        notifyListeners();
        return;
      } catch (_) {
        // Corrupt scratch — fall through to the last saved project.
      }
    }

    final last = ProjectStore.instance.lastId;
    if (last != null) {
      final p = await ProjectStore.instance.load(last);
      if (p != null) {
        _applyProject(p);
        _persistReady = true;
        notifyListeners();
        return;
      }
    }
    _persistReady = true;
    await saveNow();
  }

  void _applyProject(Project p) {
    showingWelcome = false; // a real document replaced the welcome art
    projectId = p.id;
    projectName = p.name;
    _explicitlySaved = true; // already persisted on disk
    _createdAt = p.createdAt;
    _objects
      ..clear()
      ..addAll(p.objects);
    _selection.clear();
    _undo.clear();
    _redo.clear();
    zoom = p.zoom;
    pan = Offset(p.panX, p.panY);
    _pastelCursor = _objects.length + 1;
  }

  Project _toProject() => Project(
        id: projectId,
        name: projectName,
        createdAt: _createdAt,
        objects: _objects.map((o) => o.copyDeep()).toList(),
        zoom: zoom,
        panX: pan.dx,
        panY: pan.dy,
      );

  // ---- Portable documents (save to / open from disk) ----------------------

  /// The open document as a self-contained `.shape` file: the same JSON the
  /// browser-storage slot uses, with images embedded as base64 — so the file
  /// survives clearing site data and moves between machines.
  String toDocumentJson() => jsonEncode(_toProject().toJson());

  /// Replaces the canvas with a `.shape` document read from disk. Throws if
  /// [source] isn't a valid document, leaving the current canvas untouched —
  /// the parse happens before anything is mutated.
  Future<void> openDocumentJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a Shape document');
    }
    // Parse first: a malformed file must not half-replace the open project.
    final project = Project.fromJson(decoded);
    _applyProject(project);
    notifyListeners();
    await saveNow();
  }

  /// Persist immediately (used on lifecycle pause and after an explicit Save).
  /// Always writes the crash-recovery scratch slot (even for never-saved
  /// Untitled drafts, so a crash can't lose the canvas). Only writes to the
  /// named project list when the document has been explicitly saved, so drafts
  /// don't litter the history.
  Future<void> saveNow() async {
    _saveTimer?.cancel();
    if (!_persistReady) return;
    await _saveScratch();
    if (_explicitlySaved) {
      await ProjectStore.instance.save(_toProject());
    }
  }

  /// Writes the current canvas to the scratch slot, tagged with whether it
  /// corresponds to an explicitly-saved project (so restore can rebuild state).
  Future<void> _saveScratch() async {
    final payload = jsonEncode({
      'saved': _explicitlySaved,
      'p': _toProject().toJson(),
    });
    await ProjectStore.instance.saveScratch(payload);
  }

  void _scheduleSave() {
    if (!_persistReady) return;
    _saveTimer?.cancel();
    _saveTimer =
        Timer(const Duration(milliseconds: 800), () => unawaited(saveNow()));
  }

  /// Explicit "Save As": names the document, marks it persistable and writes it.
  /// This is the only path that turns an Untitled draft into a saved project.
  Future<void> saveAs(String name) async {
    final trimmed = name.trim();
    projectName = trimmed.isEmpty ? 'Untitled' : trimmed;
    _explicitlySaved = true;
    notifyListeners();
    await saveNow();
  }

  /// Autosave hooks onto every state change (debounced).
  @override
  void notifyListeners() {
    super.notifyListeners();
    _scheduleSave();
  }

  /// Create a fresh blank project (used by "New Document").
  Future<void> newProject() async {
    _startNewDocument();
    notifyListeners();
    await saveNow();
  }

  /// Open a project from history.
  Future<void> openProject(String id) async {
    final p = await ProjectStore.instance.load(id);
    if (p == null) return;
    _applyProject(p);
    await ProjectStore.instance.setLast(id);
    notifyListeners();
  }

  void renameProject(String name) {
    projectName = name.trim().isEmpty ? 'Untitled' : name.trim();
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ---- Document ----------------------------------------------------------
  final List<ShapeObject> _objects = [];
  List<ShapeObject> get objects => List.unmodifiable(_objects);

  final Set<String> _selection = {};
  Set<String> get selection => _selection;

  List<ShapeObject> get selectedObjects =>
      _objects.where((o) => _selection.contains(o.id)).toList();

  ShapeObject? get singleSelection =>
      _selection.length == 1 ? byId(_selection.first) : null;

  /// The object whose style the styling sheets display when editing — the lone
  /// selection, or the first of a multi-selection (so a group can be styled).
  ShapeObject? get styleTarget =>
      singleSelection ?? (selectedObjects.isEmpty ? null : selectedObjects.first);

  ShapeObject? byId(String id) {
    for (final o in _objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  // ---- Undo / redo (§25.3) ----------------------------------------------
  final List<Command> _undo = [];
  final List<Command> _redo = [];
  static const _historyLimit = 200;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get nextUndoDescription => _undo.isEmpty ? null : _undo.last.description;
  String? get nextRedoDescription => _redo.isEmpty ? null : _redo.last.description;

  /// Objects briefly pulsed in Shape Blue to show "what changed" (§6).
  final Set<String> pulseIds = {};

  void _run(Command c) {
    c.execute(_objects);
    _push(c);
    notifyListeners();
  }

  /// Runs several commands as a SINGLE undo step (so a Repeat / Expand / Trace
  /// that creates many objects undoes in one press, not one-per-object).
  void _runBatch(List<Command> cmds, String description) {
    if (cmds.isEmpty) return;
    if (cmds.length == 1) {
      _run(cmds.first);
      return;
    }
    _run(CompositeCommand(cmds, description));
  }

  void _push(Command c) {
    _undo.add(c);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Push a command whose effect was already applied during a live gesture.
  void pushApplied(Command c) {
    _push(c);
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final c = _undo.removeLast();
    c.undo(_objects);
    _redo.add(c);
    _pulse(c.affectedIds);
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final c = _redo.removeLast();
    c.execute(_objects);
    _undo.add(c);
    _pulse(c.affectedIds);
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  void _pulse(Iterable<String> ids) {
    pulseIds
      ..clear()
      ..addAll(ids);
    Future.delayed(const Duration(milliseconds: 320), () {
      pulseIds.clear();
      notifyListeners();
    });
  }

  // ---- Saved palette -----------------------------------------------------
  final List<Color> savedColors = [];

  void saveColor(Color c) {
    if (savedColors.any((x) => x.toARGB32() == c.toARGB32())) return;
    savedColors.insert(0, c);
    if (savedColors.length > 24) savedColors.removeLast();
    ProjectStore.instance
        .setPalette(savedColors.map((c) => c.toARGB32()).toList());
    notifyListeners();
  }

  void removeSavedColor(Color c) {
    savedColors.removeWhere((x) => x.toARGB32() == c.toARGB32());
    ProjectStore.instance
        .setPalette(savedColors.map((c) => c.toARGB32()).toList());
    notifyListeners();
  }

  // ---- Object operations -------------------------------------------------
  void addObject(ShapeObject o, {bool select = true}) {
    _run(AddObjectCommand(o));
    if (select) selectOnly(o.id);
  }

  /// Create a freehand/pen path from canvas-space points.
  void addPath(List<Offset> canvasPoints,
      {required bool closed, Color? stroke, double strokeWidth = 4}) {
    if (canvasPoints.length < 2) return;
    var minX = canvasPoints.first.dx, maxX = canvasPoints.first.dx;
    var minY = canvasPoints.first.dy, maxY = canvasPoints.first.dy;
    for (final p in canvasPoints) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = math.max(maxX - minX, 1.0);
    final h = math.max(maxY - minY, 1.0);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final normalized = canvasPoints
        .map((p) => Offset((p.dx - center.dx) / w, (p.dy - center.dy) / h))
        .toList();
    final strokeColor = stroke ?? ShapeColors.primaryText;
    addObject(ShapeObject(
      type: ShapeType.path,
      center: center,
      size: Size(w, h),
      pathPoints: normalized,
      closed: closed,
      fill: closed ? nextPastel() : const Color(0x00000000),
      stroke: strokeColor,
      strokeWidth: strokeWidth,
      // Paths carry an explicit stroke so the Strokes panel shows it (item 4).
      // Default to a taper-out profile so the line thins toward its end, like a
      // natural brush stroke (item 3).
      strokes: [StrokeSpec(color: strokeColor, width: strokeWidth, profile: 2)],
    ));
  }

  /// Freehand stroke → a clean **bezier path** with a handful of nodes and
  /// real tangent handles (item: draw should use nodes + tangents, not hundreds
  /// of raw points). Simplifies with Ramer–Douglas–Peucker, then fits smooth
  /// Catmull-Rom tangents.
  void addSmoothPath(List<Offset> canvasPoints,
      {bool closed = false, Color? stroke, double strokeWidth = 4}) {
    if (canvasPoints.length < 2) return;
    final eps = 2.5 / zoom;
    var pts = _rdp(canvasPoints, eps);
    if (pts.length < 2) pts = canvasPoints;
    // Auto-close if the user returned near the start.
    final autoClose = closed ||
        (pts.length > 3 && (pts.first - pts.last).distance < 12 / zoom);
    if (autoClose && (pts.first - pts.last).distance < 1) pts.removeLast();

    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = math.max(maxX - minX, 1.0), h = math.max(maxY - minY, 1.0);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final anchors = pts
        .map((p) => Offset((p.dx - center.dx) / w, (p.dy - center.dy) / h))
        .toList();
    final n = anchors.length;
    final hIn = <Offset>[], hOut = <Offset>[];
    final modes = <int>[];
    for (var i = 0; i < n; i++) {
      final prev = anchors[autoClose ? (i - 1 + n) % n : math.max(0, i - 1)];
      final next = anchors[autoClose ? (i + 1) % n : math.min(n - 1, i + 1)];
      final t = (next - prev) * (1 / 6);
      hIn.add(-t);
      hOut.add(t);
      modes.add(1);
    }
    if (!autoClose) {
      hIn[0] = Offset.zero;
      hOut[n - 1] = Offset.zero;
    }
    final strokeColor = stroke ?? ShapeColors.primaryText;
    addObject(ShapeObject(
      type: ShapeType.path,
      center: center,
      size: Size(w, h),
      pathPoints: anchors,
      handleIn: hIn,
      handleOut: hOut,
      nodeModes: modes,
      closed: autoClose,
      fill: autoClose ? nextPastel() : const Color(0x00000000),
      stroke: strokeColor,
      strokeWidth: strokeWidth,
      // Paths carry an explicit stroke so the Strokes panel shows it (item 4).
      // Default to a taper-out profile so the line thins toward its end, like a
      // natural brush stroke (item 3).
      strokes: [StrokeSpec(color: strokeColor, width: strokeWidth, profile: 2)],
    ));
  }

  /// Ramer–Douglas–Peucker polyline simplification (iterative).
  List<Offset> _rdp(List<Offset> pts, double eps) {
    if (pts.length < 3) return List.of(pts);
    final keep = List<bool>.filled(pts.length, false);
    keep[0] = keep[pts.length - 1] = true;
    final stack = <List<int>>[
      [0, pts.length - 1]
    ];
    while (stack.isNotEmpty) {
      final seg = stack.removeLast();
      final first = seg[0], last = seg[1];
      var maxD = 0.0, idx = -1;
      for (var i = first + 1; i < last; i++) {
        final d = _distSeg2(pts[i], pts[first], pts[last]);
        if (d > maxD) {
          maxD = d;
          idx = i;
        }
      }
      if (maxD > eps && idx != -1) {
        keep[idx] = true;
        stack
          ..add([first, idx])
          ..add([idx, last]);
      }
    }
    return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
  }

  static double _distSeg2(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// One Chaikin corner-cutting pass over a closed loop — replaces each point
  /// with two points 1/4 and 3/4 along its outgoing edge, rounding sharp steps.
  static List<Offset> _chaikin(List<Offset> pts) {
    final n = pts.length;
    if (n < 3) return pts;
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = pts[i], b = pts[(i + 1) % n];
      out.add(a * 0.75 + b * 0.25);
      out.add(a * 0.25 + b * 0.75);
    }
    return out;
  }

  static Offset _centroid(List<Offset> p) {
    var sx = 0.0, sy = 0.0;
    for (final o in p) {
      sx += o.dx;
      sy += o.dy;
    }
    return Offset(sx / p.length, sy / p.length);
  }

  /// Signed polygon area (shoelace).
  static double _polyArea(List<Offset> p) {
    var a = 0.0;
    for (var i = 0; i < p.length; i++) {
      final b = p[(i + 1) % p.length];
      a += p[i].dx * b.dy - b.dx * p[i].dy;
    }
    return a / 2;
  }

  /// Ray-casting point-in-polygon test.
  static bool _pointInPoly(Offset pt, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > pt.dy) != (b.dy > pt.dy) &&
          pt.dx <
              (b.dx - a.dx) * (pt.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  // ---- Z-order: single-step forward / backward --------------------------
  void bringForward() => _stepOrder(1);
  void sendBackward() => _stepOrder(-1);
  void _stepOrder(int dir) {
    if (_selection.isEmpty) return;
    final idxs = [
      for (var i = 0; i < _objects.length; i++)
        if (_selection.contains(_objects[i].id)) i
    ];
    if (idxs.isEmpty) return;
    final order = dir > 0 ? idxs.reversed.toList() : idxs;
    for (final i in order) {
      final j = i + dir;
      if (j < 0 || j >= _objects.length) continue;
      if (_selection.contains(_objects[j].id)) continue;
      final tmp = _objects[i];
      _objects[i] = _objects[j];
      _objects[j] = tmp;
    }
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  // ---- Repeat / array (grid, radial, mirror) ----------------------------
  /// True when the source selection is itself a single group — a Repeat then
  /// produces a "group of groups": each instance is its own sub-group under one
  /// outer Repeat group (item 6a).
  bool _isGroupSource(List<ShapeObject> src) {
    if (src.length < 2) return false;
    final g = src.first.groupId;
    return g != null && src.every((o) => o.groupId == g);
  }

  /// Leaf group id for repeat instance [inst]: a fresh per-instance sub-group
  /// when nesting, otherwise the shared flat group.
  String _instanceGid(bool nested, String stamp, int inst, String? flatGid) =>
      nested ? 'grp-$stamp-$inst' : flatGid!;

  /// Clones a whole set of objects, **re-pointing any mask reference inside the
  /// set to the cloned mask** so a repeated masked group clips its OWN copy
  /// rather than every copy being clipped by the original mask (item 3).
  List<ShapeObject> _cloneSet(List<ShapeObject> src,
      {Offset offset = Offset.zero, String? groupId, String? superGroupId}) {
    final idMap = <String, String>{};
    final clones = <ShapeObject>[];
    for (final o in src) {
      final c = o.clone(
          offset: offset, groupId: groupId, superGroupId: superGroupId);
      idMap[o.id] = c.id;
      clones.add(c);
    }
    for (final c in clones) {
      final mid = c.maskId;
      if (mid != null && idMap.containsKey(mid)) c.maskId = idMap[mid];
    }
    return clones;
  }

  /// Tiles the selection into a grid of [rows]×[cols]. [gapX]/[gapY] scale the
  /// horizontal / vertical spacing between tiles (×1 = touching the bounds,
  /// item 11).
  void repeatGrid(
      {int rows = 3, int cols = 3, double gapX = 1.15, double gapY = 1.15}) {
    final src = selectedObjects;
    final r = selectionBounds;
    if (src.isEmpty || r == null) return;
    rows = rows.clamp(1, 20);
    cols = cols.clamp(1, 20);
    final stepX = r.width * gapX, stepY = r.height * gapY;
    final stamp = '${DateTime.now().microsecondsSinceEpoch}';
    final nested = _isGroupSource(src);
    final sgid = nested ? 'sgrp-$stamp' : null;
    final flatGid = nested ? null : 'grp-$stamp';
    final created = <ShapeObject>[];
    var inst = 0;
    for (var gy = 0; gy < rows; gy++) {
      for (var gx = 0; gx < cols; gx++) {
        if (gx == 0 && gy == 0) continue;
        inst++;
        final instGid = _instanceGid(nested, stamp, inst, flatGid);
        final delta = Offset(stepX * gx, stepY * gy);
        created.addAll(_cloneSet(src,
            offset: delta, groupId: instGid, superGroupId: sgid));
      }
    }
    _commitCreated(created,
        sources: src, groupId: flatGid, superGroupForSources: sgid);
  }

  /// Arranges [count] rotated copies of the selection around a ring. [radiusF]
  /// scales the ring radius relative to the selection size (item 11).
  void repeatRadial({int count = 8, double radiusF = 1.6}) {
    final src = selectedObjects;
    final r = selectionBounds;
    if (src.isEmpty || r == null) return;
    count = count.clamp(2, 60);
    final radius = math.max(r.width, r.height) * radiusF;
    final pivot = r.center + Offset(0, radius);
    final stamp = '${DateTime.now().microsecondsSinceEpoch}';
    final nested = _isGroupSource(src);
    final sgid = nested ? 'sgrp-$stamp' : null;
    final flatGid = nested ? null : 'grp-$stamp';
    final created = <ShapeObject>[];
    for (var i = 1; i < count; i++) {
      final ang = 2 * math.pi * i / count;
      final instGid = _instanceGid(nested, stamp, i, flatGid);
      final clones = _cloneSet(src, groupId: instGid, superGroupId: sgid);
      for (final c in clones) {
        final rel = c.center - pivot;
        final cos = math.cos(ang), sin = math.sin(ang);
        c.center = pivot +
            Offset(rel.dx * cos - rel.dy * sin, rel.dx * sin + rel.dy * cos);
        c.rotation += ang;
        created.add(c);
      }
    }
    _commitCreated(created,
        sources: src, groupId: flatGid, superGroupForSources: sgid);
  }

  /// Mirrors the selection across a vertical (default) or horizontal axis just
  /// beyond its bounds. Geometry is flipped by negating node x/y.
  void repeatMirror({bool horizontal = true}) {
    final src = selectedObjects;
    final r = selectionBounds;
    if (src.isEmpty || r == null) return;
    final stamp = '${DateTime.now().microsecondsSinceEpoch}';
    final nested = _isGroupSource(src);
    final sgid = nested ? 'sgrp-$stamp' : null;
    final flatGid = nested ? null : 'grp-$stamp';
    final instGid = _instanceGid(nested, stamp, 1, flatGid);
    final created = <ShapeObject>[];
    final axis = horizontal ? r.right : r.bottom;
    final clones = _cloneSet(src, groupId: instGid, superGroupId: sgid);
    for (final c in clones) {
      if (horizontal) {
        c.center = Offset(2 * axis - c.center.dx, c.center.dy);
      } else {
        c.center = Offset(c.center.dx, 2 * axis - c.center.dy);
      }
      // Flip local geometry so it's a true mirror, not just a translation.
      c.rotation = -c.rotation;
      if (c.pathPoints.isNotEmpty) {
        Offset flip(Offset p) =>
            horizontal ? Offset(-p.dx, p.dy) : Offset(p.dx, -p.dy);
        c.pathPoints = c.pathPoints.map(flip).toList();
        if (c.handleIn.length == c.pathPoints.length) {
          c.handleIn = c.handleIn.map(flip).toList();
          c.handleOut = c.handleOut.map(flip).toList();
        }
      }
      created.add(c);
    }
    _commitCreated(created,
        sources: src, groupId: flatGid, superGroupForSources: sgid);
  }

  void _commitCreated(List<ShapeObject> created,
      {String description = 'Repeat',
      List<ShapeObject> sources = const [],
      String? groupId,
      String? superGroupForSources,
      Map<String, ShapeObject>? sourcesBefore,
      List<ShapeObject> remove = const []}) {
    if (created.isEmpty) return;
    final cmds = <Command>[];
    // Objects consumed by the operation (e.g. a morph guide spline) are deleted
    // as part of the same undo step (item 9).
    if (remove.isNotEmpty) {
      cmds.add(DeleteObjectsCommand(_objects, remove));
    }
    // Fold the original shapes into the result as part of the same undo step.
    // [superGroupForSources] (nested repeat, item 6a) keeps each source's leaf
    // group and parents it under the outer group; otherwise [groupId] folds the
    // sources into one flat group (item 5). [sourcesBefore], when supplied, is a
    // snapshot taken BEFORE the caller mutated the sources (e.g. repositioning a
    // morph's start/end onto the guide path) so undo restores their state.
    if (sources.isNotEmpty &&
        (groupId != null || superGroupForSources != null)) {
      final before =
          sourcesBefore ?? {for (final o in sources) o.id: o.copyDeep()};
      for (final o in sources) {
        if (superGroupForSources != null) {
          o.superGroupId = superGroupForSources;
        } else {
          o.groupId = groupId;
        }
      }
      cmds.add(MutationCommand(
          description: 'Group',
          before: before,
          after: {for (final o in sources) o.id: o.copyDeep()}));
    }
    cmds.addAll([for (final o in created) AddObjectCommand(o)]);
    _runBatch(cmds, description);
    final ids = [...sources.map((o) => o.id), ...created.map((o) => o.id)];
    setSelection(ids);
    HapticFeedback.mediumImpact();
  }

  // ---- Expand (text → outlines, shapes → editable paths) ----------------
  Future<void> expandSelection() async {
    final targets = selectedObjects;
    if (targets.isEmpty) return;
    final newIds = <String>[];
    for (final o in targets) {
      if (o.type == ShapeType.text) {
        final ids = await _expandText(o);
        newIds.addAll(ids);
      } else if (o.type != ShapeType.image) {
        final p = _convertToPath(o); // becomes a pure vector outline
        newIds.add(p.id);
      }
    }
    if (newIds.isNotEmpty) setSelection(newIds);
  }

  /// Rasterizes a text object and traces its glyph outlines into vector paths.
  Future<List<String>> _expandText(ShapeObject o) async {
    if (o.text.trim().isEmpty) return const [];
    final weight = ui.FontWeight.values[
        (o.fontWeight ~/ 100 - 1).clamp(0, ui.FontWeight.values.length - 1)];
    final style = FontCatalog.style(
      family: o.fontFamily,
      fontSize: o.fontSize,
      weight: weight,
      color: const Color(0xFF000000),
      letterSpacing: o.letterSpacing,
      height: o.lineHeight,
      italic: o.italic,
    );
    final tp = TextPainter(
      text: TextSpan(text: o.text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: _alignFor(o.textAlignH),
    )..layout(maxWidth: o.size.width > 0 ? o.size.width : double.infinity);

    // Supersample the glyph raster so the traced outline is crisp instead of
    // jagged/wavy (item 4). Render the text scaled up into a high-res bitmap.
    final baseW = math.max(tp.width, 1.0), baseH = math.max(tp.height, 1.0);
    final ss = (1100.0 / math.max(baseW, baseH)).clamp(1.0, 8.0);
    final tw = math.max((baseW * ss).ceil(), 1);
    final th = math.max((baseH * ss).ceil(), 1);
    final recorder = ui.PictureRecorder();
    final rc = ui.Canvas(recorder)..scale(ss);
    tp.paint(rc, Offset.zero);
    final img = await recorder.endRecording().toImage(tw, th);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return const [];
    final bytes = data.buffer.asUint8List();

    final stride = math.max(1, (math.max(tw, th) / 480).floor());
    final cols = (tw / stride).floor(), rows = (th / stride).floor();
    bool ink(int x, int y) {
      final px = x * stride, py = y * stride;
      final i = (py * tw + px) * 4;
      return i + 3 < bytes.length && bytes[i + 3] > 128;
    }

    final grid =
        List.generate(cols, (x) => List.generate(rows, (y) => ink(x, y)));
    final contours = MarchingSquares.contours(grid);
    if (contours.isEmpty) return const [];

    // Grid cell → supersampled px (×stride) → base px (÷ss) → local (centred) →
    // world (rotated about the text centre).
    Offset toWorld(Offset g) {
      final local = Offset(
          g.dx * stride / ss - tp.width / 2, g.dy * stride / ss - tp.height / 2);
      return o.center + _rotate(local, o.rotation);
    }

    // Trace, corner-cut (Chaikin ×2) and simplify every contour to clean,
    // smooth vector edges (item 2/4).
    final polys = <List<Offset>>[];
    for (final contour in contours) {
      final world = _rdp(_chaikin(_chaikin(contour.map(toWorld).toList())), 0.8);
      if (world.length >= 4) polys.add(world);
    }
    if (polys.isEmpty) return const [];

    // Determine nesting: a contour whose centroid is inside an ODD number of
    // others is a hole (a letter counter), parented to its smallest container.
    // This keeps the enclosed space of o / e / a OPEN instead of filled (item 2).
    final centroids = [for (final p in polys) _centroid(p)];
    final areas = [for (final p in polys) _polyArea(p).abs()];
    final depth = List<int>.filled(polys.length, 0);
    final parent = List<int>.filled(polys.length, -1);
    for (var i = 0; i < polys.length; i++) {
      var best = -1;
      var bestArea = double.infinity;
      for (var j = 0; j < polys.length; j++) {
        if (i == j) continue;
        if (_pointInPoly(centroids[i], polys[j])) {
          depth[i]++;
          if (areas[j] < bestArea) {
            bestArea = areas[j];
            best = j;
          }
        }
      }
      parent[i] = best;
    }

    final gid = 'grp-${DateTime.now().microsecondsSinceEpoch}';
    final created = <ShapeObject>[];
    for (var i = 0; i < polys.length; i++) {
      if (depth[i].isOdd) continue; // a hole — emitted with its parent below
      final outer = polys[i];
      var minX = outer.first.dx, maxX = outer.first.dx;
      var minY = outer.first.dy, maxY = outer.first.dy;
      for (final p in outer) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      final bw = math.max(maxX - minX, 1.0), bh = math.max(maxY - minY, 1.0);
      final c = Offset((minX + maxX) / 2, (minY + maxY) / 2);
      Offset norm(Offset p) => Offset((p.dx - c.dx) / bw, (p.dy - c.dy) / bh);
      final holeContours = <List<Offset>>[];
      for (var k = 0; k < polys.length; k++) {
        if (depth[k].isOdd && parent[k] == i) {
          holeContours.add(polys[k].map(norm).toList());
        }
      }
      created.add(ShapeObject(
        type: ShapeType.path,
        center: c,
        size: Size(bw, bh),
        pathPoints: outer.map(norm).toList(),
        holes: holeContours,
        closed: true,
        fill: o.fill,
        groupId: gid,
        name: 'Letterform',
      ));
    }
    if (created.isEmpty) return const [];
    _runBatch([
      DeleteObjectsCommand(_objects, [o]),
      for (final c in created) AddObjectCommand(c),
    ], 'Expand text');
    return created.map((c) => c.id).toList();
  }

  TextAlign _alignFor(int a) => switch (a) {
        0 => TextAlign.left,
        2 => TextAlign.right,
        3 => TextAlign.justify,
        _ => TextAlign.center,
      };

  /// Create a text object at a canvas point with a measured size.
  ShapeObject addText(Offset center, {Size size = const Size(220, 60)}) {
    final o = ShapeObject(
      type: ShapeType.text,
      center: center,
      size: size,
      text: '',
      fontSize: 48,
      fill: ShapeColors.primaryText,
      name: 'Text',
    );
    addObject(o);
    return o;
  }

  void updateText(String id, String text, Size size) {
    final o = byId(id);
    if (o == null) return;
    final before = {id: o.copyDeep()};
    o.text = text;
    o.size = size;
    o.name = text.isEmpty ? 'Text' : text;
    pushApplied(MutationCommand(
        description: 'Edit text', before: before, after: {id: o.copyDeep()}));
    notifyListeners();
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    final targets = selectedObjects;
    HapticFeedback.heavyImpact();
    _run(DeleteObjectsCommand(_objects, targets));
    _selection.clear();
    notifyListeners();
  }

  // ---- Clipboard (cut / copy / paste) -----------------------------------
  final List<ShapeObject> _clipboard = [];
  bool get hasClipboard => _clipboard.isNotEmpty;

  void copySelection() {
    final sel = selectedObjects;
    if (sel.isEmpty) return;
    _clipboard
      ..clear()
      ..addAll(sel.map((o) => o.copyDeep()));
    HapticFeedback.lightImpact();
  }

  void cutSelection() {
    if (_selection.isEmpty) return;
    copySelection();
    deleteSelection();
  }

  void pasteClipboard() {
    if (_clipboard.isEmpty) return;
    // Fresh ids, nudged so the paste is visible; group mates stay grouped.
    final fresh = _clipboard
        .map((o) => o.clone(offset: const Offset(24, 24), groupId: o.groupId))
        .toList();
    _runBatch([for (final f in fresh) AddObjectCommand(f)], 'Paste');
    setSelection(fresh.map((f) => f.id));
    HapticFeedback.mediumImpact();
  }

  void duplicateSelection() {
    final originals = selectedObjects;
    if (originals.isEmpty) return;
    final fresh = originals
        .map((o) => o.clone(offset: const Offset(24, 24), groupId: o.groupId))
        .toList();
    _runBatch([for (final f in fresh) AddObjectCommand(f)], 'Duplicate');
    _selection
      ..clear()
      ..addAll(fresh.map((f) => f.id));
    notifyListeners();
  }

  // ---- Grouping (§16) ----------------------------------------------------
  void groupSelection() {
    if (_selection.length < 2) return;
    final gid = 'grp-${DateTime.now().microsecondsSinceEpoch}';
    final before = _snapshot(_selection);
    for (final o in selectedObjects) {
      o.groupId = gid;
      o.superGroupId = null; // an explicit group is a single flat level
    }
    final after = _snapshot(_selection);
    pushApplied(MutationCommand(
        description: 'Group', before: before, after: after));
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  void ungroupSelection() {
    final ids = _selection.toList();
    final before = _snapshot(ids);
    for (final o in selectedObjects) {
      o.groupId = null;
      o.superGroupId = null; // clear both levels of nesting (item 6a)
    }
    final after = _snapshot(ids);
    pushApplied(MutationCommand(
        description: 'Ungroup', before: before, after: after));
    notifyListeners();
  }

  bool get selectionHasGroup => selectedObjects.any((o) => o.groupId != null);

  // ---- Alignment / distribution (§10.3) ----------------------------------
  void alignSelection(String mode) {
    final objs = selectedObjects;
    if (objs.length < 2) return;
    final before = _snapshot(_selection);
    Rect group = objs.first.bounds;
    for (final o in objs) {
      group = group.expandToInclude(o.bounds);
    }
    for (final o in objs) {
      switch (mode) {
        case 'left':
          o.center = Offset(group.left + o.size.width / 2, o.center.dy);
        case 'hcenter':
          o.center = Offset(group.center.dx, o.center.dy);
        case 'right':
          o.center = Offset(group.right - o.size.width / 2, o.center.dy);
        case 'top':
          o.center = Offset(o.center.dx, group.top + o.size.height / 2);
        case 'vcenter':
          o.center = Offset(o.center.dx, group.center.dy);
        case 'bottom':
          o.center = Offset(o.center.dx, group.bottom - o.size.height / 2);
      }
    }
    if (mode == 'hdist' || mode == 'vdist') {
      _distribute(objs, horizontal: mode == 'hdist');
    }
    final after = _snapshot(_selection);
    pushApplied(MutationCommand(
        description: 'Align', before: before, after: after));
    notifyListeners();
  }

  void _distribute(List<ShapeObject> objs, {required bool horizontal}) {
    final sorted = objs.toList()
      ..sort((a, b) => horizontal
          ? a.center.dx.compareTo(b.center.dx)
          : a.center.dy.compareTo(b.center.dy));
    if (sorted.length < 3) return;
    final first = horizontal ? sorted.first.center.dx : sorted.first.center.dy;
    final last = horizontal ? sorted.last.center.dx : sorted.last.center.dy;
    final step = (last - first) / (sorted.length - 1);
    for (var i = 0; i < sorted.length; i++) {
      final v = first + step * i;
      sorted[i].center = horizontal
          ? Offset(v, sorted[i].center.dy)
          : Offset(sorted[i].center.dx, v);
    }
  }

  // ---- Images ------------------------------------------------------------
  /// Imports an image. The display texture is decoded (pure-Dart, alpha-safe) and
  /// downsampled by [ImageStore.decodeDisplay]; the original full-resolution
  /// [bytes] are kept on the object so export stays at native resolution.
  Future<void> addImage(Uint8List bytes, ui.Offset center) async {
    final img = await ImageStore.decodeDisplay(bytes);
    const maxDim = 360.0;
    final aspect = img.width / img.height;
    final size = aspect >= 1
        ? ui.Size(maxDim, maxDim / aspect)
        : ui.Size(maxDim * aspect, maxDim);
    final o = ShapeObject(
        type: ShapeType.image, center: center, size: size, imageBytes: bytes);
    ImageStore.instance.put(o.id, img);
    addObject(o);
  }

  /// Image trace (§18) — marching-squares contour tracing. Produces one vector
  /// path per region boundary (multiple shapes + holes), grouped, beside the
  /// source image.
  Future<void> traceSelectedImage() async {
    final o = singleSelection;
    if (o == null || o.type != ShapeType.image || o.imageBytes == null) return;
    final codec = await ui.instantiateImageCodec(o.imageBytes!);
    final img = (await codec.getNextFrame()).image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return;
    final bytes = data.buffer.asUint8List();
    final w = img.width, h = img.height;
    final stride = math.max(1, (math.max(w, h) / 160).floor());
    final cols = (w / stride).floor();
    final rows = (h / stride).floor();

    bool ink(int x, int y) {
      final px = x * stride, py = y * stride;
      final i = (py * w + px) * 4;
      if (i + 3 >= bytes.length) return false;
      final a = bytes[i + 3];
      if (a < 40) return false;
      final lum = 0.299 * bytes[i] + 0.587 * bytes[i + 1] + 0.114 * bytes[i + 2];
      return lum < 165;
    }

    final grid = List.generate(
        cols, (x) => List.generate(rows, (y) => ink(x, y)));
    final contours = MarchingSquares.contours(grid);
    if (contours.isEmpty) return;

    ui.Offset toWorld(ui.Offset g) {
      final px = g.dx * stride, py = g.dy * stride;
      final local = ui.Offset(
          (px / w - 0.5) * o.size.width, (py / h - 0.5) * o.size.height);
      return o.center + _rotate(local, o.rotation) +
          ui.Offset(o.size.width + 40, 0);
    }

    final gid = 'grp-${DateTime.now().microsecondsSinceEpoch}';
    final created = <ShapeObject>[];
    for (final contour in contours) {
      final simplified = MarchingSquares.simplify(contour, 0.6);
      if (simplified.length < 4) continue;
      final world = simplified.map(toWorld).toList();
      // Build directly so we can keep them in one undo step / group.
      var minX = world.first.dx, maxX = world.first.dx;
      var minY = world.first.dy, maxY = world.first.dy;
      for (final p in world) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      final bw = math.max(maxX - minX, 1.0), bh = math.max(maxY - minY, 1.0);
      final c = ui.Offset((minX + maxX) / 2, (minY + maxY) / 2);
      created.add(ShapeObject(
        type: ShapeType.path,
        center: c,
        size: ui.Size(bw, bh),
        pathPoints: world
            .map((p) => ui.Offset((p.dx - c.dx) / bw, (p.dy - c.dy) / bh))
            .toList(),
        closed: true,
        fill: ShapeColors.primaryText,
        groupId: gid,
        name: 'Trace',
      ));
    }
    _runBatch([for (final c in created) AddObjectCommand(c)], 'Trace');
    if (created.isNotEmpty) setSelection(created.map((c) => c.id));
  }

  /// Import vector shapes from SVG text, centered at [center].
  void importSvg(String svg, ui.Offset center) {
    final objs = SvgImporter.parse(svg);
    if (objs.isEmpty) return;
    var rect = objs.first.bounds;
    for (final o in objs) {
      rect = rect.expandToInclude(o.bounds);
    }
    final shift = center - rect.center;
    final gid = 'grp-${DateTime.now().microsecondsSinceEpoch}';
    for (final o in objs) {
      o.center += shift;
      if (objs.length > 1) o.groupId = gid;
    }
    _runBatch([for (final o in objs) AddObjectCommand(o)], 'Import SVG');
    setSelection(objs.map((o) => o.id));
  }

  void setCrop(ui.Rect crop) {
    final o = singleSelection;
    if (o == null || o.type != ShapeType.image) return;
    final before = {o.id: o.copyDeep()};
    o.crop = crop;
    pushApplied(MutationCommand(
        description: 'Crop', before: before, after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  // ---- Masking (§16.3) ---------------------------------------------------
  void maskSelection() {
    final objs = selectedObjects;
    if (objs.length < 2) return;
    // The TOP-most object (higher z, later in the list) is the clipping mask;
    // EVERYTHING below it in the selection — including whole groups (a morph or
    // normal group) — is clipped (item 4), matching Illustrator's order.
    objs.sort((a, b) => _objects.indexOf(a).compareTo(_objects.indexOf(b)));
    final mask = objs.last;
    final content = objs.where((o) => o.id != mask.id).toList();
    if (content.isEmpty) return;
    final before = {for (final o in objs) o.id: o.copyDeep()};
    final gid = 'grp-${DateTime.now().microsecondsSinceEpoch}';
    for (final o in content) {
      o.maskId = mask.id;
      o.groupId = gid;
      o.superGroupId = null; // flatten clipped content into the mask group
    }
    // The mask only defines the clip region, so its own fill is hidden (it
    // stays a real, selectable layer — re-show / release from the Layers panel).
    mask.visible = false;
    mask.groupId = gid;
    mask.superGroupId = null;
    pushApplied(MutationCommand(
        description: 'Mask',
        before: before,
        after: {for (final o in objs) o.id: o.copyDeep()}));
    selectOnly(content.first.id);
  }

  /// The masked (clipped) object within the current selection, if any. Works
  /// even when the masked pair is selected as a group.
  ShapeObject? get maskedInSelection {
    for (final o in selectedObjects) {
      if (o.maskId != null) return o;
    }
    return null;
  }

  bool get selectionHasMask => maskedInSelection != null;

  void releaseMask() {
    final o = maskedInSelection;
    if (o == null || o.maskId == null) return;
    final mask = byId(o.maskId!);
    final before = {
      o.id: o.copyDeep(),
      if (mask != null) mask.id: mask.copyDeep()
    };
    o.maskId = null;
    if (mask != null) mask.visible = true;
    pushApplied(MutationCommand(
        description: 'Release mask',
        before: before,
        after: {
          o.id: o.copyDeep(),
          if (mask != null) mask.id: mask.copyDeep()
        }));
    notifyListeners();
  }

  /// Permanently bakes the clipping mask in the current selection into a single
  /// image: the masked content is rendered clipped to the mask shape and the
  /// whole group is replaced by one cropped image layer (side-menu "Flatten
  /// Mask"). E.g. an image masked by a circle becomes one circular image.
  Future<void> flattenMask() async {
    final masked = selectedObjects.where((o) => o.maskId != null).toList();
    if (masked.isEmpty) return;
    final maskId = masked.first.maskId!;
    final mask = byId(maskId);
    if (mask == null) return;
    // All content clipped by this mask, in stacking (back-to-front) order.
    final content = _objects.where((o) => o.maskId == maskId).toList();
    if (content.isEmpty) return;

    final maskWorld = _worldPath(mask);
    final b = maskWorld.getBounds();
    if (b.width < 1 || b.height < 1) return;

    // Supersample for a crisp result — scale up so the rasterised image keeps
    // detail (vector/morph art was degrading at a flat 2×). Aim for a generous
    // pixel budget, clamped so very large masks don't blow up memory (item 5).
    final maxSide = math.max(b.width, b.height);
    final scale = (2800.0 / maxSide).clamp(3.0, 4.0);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    canvas.translate(-b.left, -b.top);
    canvas.clipPath(maskWorld);
    // Full-resolution source for any image content so the flattened result keeps
    // detail (the on-screen cache is downsampled).
    final full = <String, ui.Image>{};
    for (final o in content) {
      if (o.type == ShapeType.image && o.imageBytes != null) {
        final codec = await ui.instantiateImageCodec(o.imageBytes!);
        full[o.id] = (await codec.getNextFrame()).image;
      }
    }
    for (final o in content) {
      if (o.visible) Exporter.paintObject(canvas, o, full);
    }
    for (final im in full.values) {
      im.dispose();
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(
        (b.width * scale).ceil(), (b.height * scale).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    final bytes = data.buffer.asUint8List();

    final newObj = ShapeObject(
      type: ShapeType.image,
      center: b.center,
      size: ui.Size(b.width, b.height),
      imageBytes: bytes,
      name: 'Flattened',
    );
    ImageStore.instance.put(newObj.id, img);

    _runBatch([
      DeleteObjectsCommand(_objects, [mask, ...content]),
      AddObjectCommand(newObj),
    ], 'Flatten mask');
    setSelection([newObj.id]);
    HapticFeedback.mediumImpact();
  }

  // ---- Pathfinder / boolean ops (§18) ------------------------------------
  /// Vector-capable selection sorted back-to-front (stacking order) so the
  /// boolean ops are deterministic (front subtracts from back, etc.).
  List<ShapeObject> _pathfinderInputs() {
    final objs =
        selectedObjects.where((o) => o.type != ShapeType.image).toList();
    objs.sort((a, b) => _objects.indexOf(a).compareTo(_objects.indexOf(b)));
    return objs;
  }

  /// Splits a combined path into its separate contours as world-point lists,
  /// so multi-piece results (Exclude / Divide) become individual objects
  /// instead of being mashed into one polygon.
  List<List<Offset>> _contours(ui.Path p, {double step = 4}) {
    final out = <List<Offset>>[];
    for (final m in p.computeMetrics()) {
      final pts = <Offset>[];
      for (double d = 0; d < m.length; d += step) {
        final t = m.getTangentForOffset(d);
        if (t != null) pts.add(t.position);
      }
      if (pts.length >= 3) out.add(pts);
    }
    return out;
  }

  /// Builds one path object per [contours] entry (grouped when several),
  /// replacing [replace] in a single undo step.
  void _commitContours(List<List<Offset>> contours,
      {required Color fill,
      required String name,
      required List<ShapeObject> replace,
      bool freshFills = false}) {
    if (contours.isEmpty) return;
    final created = <ShapeObject>[];
    final gid = contours.length > 1
        ? 'grp-${DateTime.now().microsecondsSinceEpoch}'
        : null;
    for (final c in contours) {
      created.add(_pathFromWorld(c, closed: true)
        ..fill = freshFills ? nextPastel() : fill
        ..smooth = false
        ..name = name
        ..groupId = gid);
    }
    if (created.isEmpty) return;
    _runBatch([
      DeleteObjectsCommand(_objects, replace),
      for (final o in created) AddObjectCommand(o),
    ], name);
    setSelection(created.map((e) => e.id));
    HapticFeedback.mediumImpact();
  }

  void pathfinder(ui.PathOperation op, String desc) {
    final objs = _pathfinderInputs();
    if (objs.length < 2) return;
    ui.Path? acc;
    for (final o in objs) {
      final wp = _worldPath(o);
      acc = acc == null ? wp : ui.Path.combine(op, acc, wp);
    }
    if (acc == null) return;
    _commitContours(_contours(acc),
        fill: objs.first.fill, name: desc, replace: objs);
  }

  /// Subtracts everything BELOW the front-most shape from it (Illustrator's
  /// "Minus Back").
  void minusBack() {
    final objs = _pathfinderInputs();
    if (objs.length < 2) return;
    final top = _worldPath(objs.last);
    var below = _worldPath(objs.first);
    for (var i = 1; i < objs.length - 1; i++) {
      below = ui.Path.combine(ui.PathOperation.union, below, _worldPath(objs[i]));
    }
    final result = ui.Path.combine(ui.PathOperation.difference, top, below);
    _commitContours(_contours(result),
        fill: objs.last.fill, name: 'Minus Back', replace: objs);
  }

  /// Splits all overlapping shapes into their distinct, non-overlapping faces
  /// (Illustrator's "Divide"). Builds a planar subdivision incrementally.
  void divide() {
    final objs = _pathfinderInputs();
    if (objs.length < 2) return;
    var faces = <ui.Path>[_worldPath(objs.first)];
    for (var k = 1; k < objs.length; k++) {
      final s = _worldPath(objs[k]);
      final next = <ui.Path>[];
      var covered = ui.Path();
      for (final f in faces) {
        final inside = ui.Path.combine(ui.PathOperation.intersect, f, s);
        final outside = ui.Path.combine(ui.PathOperation.difference, f, s);
        if (_contours(inside).isNotEmpty) next.add(inside);
        if (_contours(outside).isNotEmpty) next.add(outside);
        covered = ui.Path.combine(ui.PathOperation.union, covered, f);
      }
      final sOutside = ui.Path.combine(ui.PathOperation.difference, s, covered);
      if (_contours(sOutside).isNotEmpty) next.add(sOutside);
      faces = next;
    }
    final pieces = <List<Offset>>[];
    for (final f in faces) {
      pieces.addAll(_contours(f));
    }
    _commitContours(pieces,
        fill: objs.first.fill,
        name: 'Divide',
        replace: objs,
        freshFills: true);
  }

  /// Converts each selected shape's boundary into an unfilled, stroked path
  /// (Illustrator's "Outline").
  void outline() {
    final objs = _pathfinderInputs();
    if (objs.isEmpty) return;
    final created = <ShapeObject>[];
    final gid = objs.length > 1
        ? 'grp-${DateTime.now().microsecondsSinceEpoch}'
        : null;
    for (final o in objs) {
      final closed = o.type != ShapeType.path || o.closed;
      for (final c in _contours(_worldPath(o))) {
        created.add(_pathFromWorld(c, closed: closed)
          ..fill = const Color(0x00000000)
          ..stroke = o.isFilled ? o.fill : o.stroke
          ..strokeWidth = o.strokeWidth > 0 ? o.strokeWidth : 2
          ..smooth = false
          ..name = 'Outline'
          ..groupId = gid);
      }
    }
    if (created.isEmpty) return;
    _runBatch([
      DeleteObjectsCommand(_objects, objs),
      for (final o in created) AddObjectCommand(o),
    ], 'Outline');
    setSelection(created.map((e) => e.id));
  }

  void flatten() => pathfinder(ui.PathOperation.union, 'Flatten');

  ui.Path _worldPath(ShapeObject o) {
    final local = o.localPath();
    return local.transform(_affine(o.center.dx, o.center.dy, o.rotation));
  }

  Float64List _affine(double tx, double ty, double rot) {
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

  // ---- Blend modes (§16.2) ----------------------------------------------
  void setBlend(int blendIndex) {
    if (_selection.isEmpty) return;
    final before = _snapshot(_selection);
    for (final o in selectedObjects) {
      o.blend = blendIndex;
    }
    pushApplied(MutationCommand(
        description: 'Blend mode',
        before: before,
        after: _snapshot(_selection)));
    notifyListeners();
  }

  // ---- Z-order -----------------------------------------------------------
  void bringToFront() => _reorder(toFront: true);
  void sendToBack() => _reorder(toFront: false);

  /// Reorders the stack from the Layers panel, where rows are listed front-most
  /// first (i.e. display index 0 == top of [_objects]). Both indices are in that
  /// display space and have already had ReorderableListView's shift applied.
  void reorderLayers(int oldDisplay, int newDisplay) {
    final n = _objects.length;
    if (oldDisplay < 0 || oldDisplay >= n) return;
    newDisplay = newDisplay.clamp(0, n - 1);
    if (oldDisplay == newDisplay) return;
    final from = n - 1 - oldDisplay;
    final to = n - 1 - newDisplay;
    final item = _objects.removeAt(from);
    _objects.insert(to, item);
    HapticFeedback.selectionClick();
    notifyListeners();
  }
  /// Group ids the user has EXPANDED in the Layers panel. Groups are collapsed
  /// by default (keeps the panel tidy), so a group shows its members only once
  /// it appears here.
  final Set<String> expandedGroups = {};
  bool isGroupCollapsed(String gid) => !expandedGroups.contains(gid);
  void toggleGroupCollapsed(String gid) {
    expandedGroups.contains(gid)
        ? expandedGroups.remove(gid)
        : expandedGroups.add(gid);
    notifyListeners();
  }

  /// Moves [ids] in the stack so they sit just IN FRONT OF (above) [anchorId] in
  /// display order; a null anchor sends them to the very back. Used by the
  /// Layers panel's drag-reorder. [detach] pulls the moved objects out of any
  /// group/mask first (dragging a layer out of a group onto open canvas-list).
  void moveLayersInFrontOf(List<String> ids,
      {String? anchorId, bool detach = false}) {
    final set = ids.toSet();
    final moving = _objects.where((o) => set.contains(o.id)).toList();
    if (moving.isEmpty) return;
    if (detach) {
      for (final o in moving) {
        o.groupId = null;
        o.superGroupId = null;
        o.maskId = null;
      }
    }
    _objects.removeWhere((o) => set.contains(o.id));
    int at;
    if (anchorId == null) {
      at = 0; // back of the stack
    } else {
      final ai = _objects.indexWhere((o) => o.id == anchorId);
      at = ai < 0 ? _objects.length : ai + 1; // just in front of the anchor
    }
    _objects.insertAll(at, moving);
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  /// Rebuilds the stacking order from a front-to-back id list (used by the
  /// hierarchical Layers panel, where whole groups move as one block).
  void setStackOrder(List<String> frontToBack) {
    final byId = {for (final o in _objects) o.id: o};
    final result = <ShapeObject>[];
    final used = <String>{};
    for (final id in frontToBack.reversed) {
      final o = byId[id];
      if (o != null && used.add(id)) result.add(o);
    }
    for (final o in _objects) {
      if (used.add(o.id)) result.add(o); // safety: keep any unlisted
    }
    _objects
      ..clear()
      ..addAll(result);
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  void _reorder({required bool toFront}) {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    _objects.removeWhere((o) => _selection.contains(o.id));
    if (toFront) {
      _objects.addAll(objs);
    } else {
      _objects.insertAll(0, objs);
    }
    notifyListeners();
  }

  // ---- Corner radius -----------------------------------------------------
  /// Live per-corner radius set (between beginGesture/commitGesture).
  void setCorner(int i, double r) {
    final o = singleSelection;
    if (o == null || o.cornerCount == 0) return;
    final v = r.clamp(0.0, double.infinity).toDouble();
    if (o.cornersLinked) {
      o.cornerRadius = v;
    } else {
      if (o.cornerRadii.length != o.cornerCount) {
        // Resync to the corner count while preserving existing per-corner
        // values, so corners never silently reset after edits.
        o.cornerRadii = List<double>.generate(
            o.cornerCount,
            (k) => k < o.cornerRadii.length
                ? o.cornerRadii[k]
                : o.cornerRadius,
            growable: true);
      }
      o.cornerRadii[i % o.cornerRadii.length] = v;
    }
    notifyListeners();
  }

  void setCornerLinked(bool linked) {
    final o = singleSelection;
    if (o == null || o.cornerCount == 0) return;
    final before = {o.id: o.copyDeep()};
    if (linked) {
      o.cornerRadius = o.radiusAt(0);
      o.cornerRadii = [];
    } else {
      o.cornerRadii =
          List<double>.filled(o.cornerCount, o.cornerRadius, growable: true);
    }
    pushApplied(MutationCommand(
        description: 'Corner link', before: before, after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  // ---- Polygon / star parameters -----------------------------------------
  /// Discrete one-shot change (pushes its own undo step).
  void setShapeParams({int? sides, double? starInner}) {
    final o = singleSelection;
    if (o == null) return;
    final before = {o.id: o.copyDeep()};
    _applyShapeParams(o, sides: sides, starInner: starInner);
    pushApplied(MutationCommand(
        description: 'Shape', before: before, after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  /// Live (gesture) variant — apply without pushing undo; pair with
  /// [beginGesture]/[commitGesture] so a slider drag is a single undo step.
  void setShapeParamsLive({int? sides, double? starInner}) {
    final o = singleSelection;
    if (o == null) return;
    _applyShapeParams(o, sides: sides, starInner: starInner);
    notifyListeners();
  }

  void _applyShapeParams(ShapeObject o, {int? sides, double? starInner}) {
    if (sides != null) o.points = sides.clamp(3, 24);
    if (starInner != null) o.starInner = starInner.clamp(0.05, 0.95);
    if (!o.cornersLinked && o.cornerRadii.length != o.cornerCount) {
      o.cornerRadii = List<double>.generate(
          o.cornerCount,
          (k) => k < o.cornerRadii.length ? o.cornerRadii[k] : o.cornerRadius,
          growable: true);
    }
  }

  // ---- Multiple strokes (appearance) ------------------------------------
  /// Copies [src]'s stroke stack (and legacy stroke) onto every other selected
  /// object, so editing strokes on a multi-selection/group applies to all.
  /// Mutates in place; the caller owns notify/undo.
  void mirrorStrokesToSelection(ShapeObject src) {
    for (final o in selectedObjects) {
      if (identical(o, src)) continue;
      o.strokes = src.strokes.map((s) => s.copy()).toList();
      o.stroke = src.stroke;
      o.strokeWidth = src.strokeWidth;
    }
  }

  void addStroke() {
    final o = styleTarget;
    if (o == null) return;
    final before = _snapshot(_selection);
    final seed = o.strokes.isEmpty && o.strokeWidth > 0
        ? StrokeSpec(color: o.stroke, width: o.strokeWidth)
        : StrokeSpec(
            color: ShapeColors.pastelFor(o.strokes.length + 2),
            width: 6.0 + o.strokes.length * 4);
    o.strokes = [...o.strokes, seed];
    mirrorStrokesToSelection(o);
    pushApplied(MutationCommand(
        description: 'Add stroke',
        before: before,
        after: _snapshot(_selection)));
    notifyListeners();
  }

  void removeStroke(int i) {
    final o = styleTarget;
    if (o == null || i >= o.strokes.length) return;
    final before = _snapshot(_selection);
    o.strokes = [...o.strokes]..removeAt(i);
    mirrorStrokesToSelection(o);
    pushApplied(MutationCommand(
        description: 'Remove stroke',
        before: before,
        after: _snapshot(_selection)));
    notifyListeners();
  }

  void reorderStroke(int from, int to) {
    final o = styleTarget;
    if (o == null) return;
    final before = _snapshot(_selection);
    final list = [...o.strokes];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    o.strokes = list;
    mirrorStrokesToSelection(o);
    pushApplied(MutationCommand(
        description: 'Reorder stroke',
        before: before,
        after: _snapshot(_selection)));
    notifyListeners();
  }

  // ---- Blend-steps: morph geometry + style between two objects ----------
  /// A selected object that can serve as the route for a blend (an open path
  /// or a line), distinct from the two shapes being morphed.
  static bool _isBlendGuide(ShapeObject o) =>
      o.type == ShapeType.line || (o.type == ShapeType.path && !o.closed);

  /// True when the current selection is blendable: exactly two shapes, plus an
  /// optional third object that is an open path/line to distribute steps along.
  bool get canBlend {
    final objs = selectedObjects;
    if (objs.length == 2) {
      // Either two closed shapes, or two open paths/lines morphed open.
      final guides = objs.where(_isBlendGuide).length;
      return guides == 0 || guides == 2;
    }
    if (objs.length == 3) {
      return objs.where(_isBlendGuide).length == 1;
    }
    return false;
  }

  void blendSteps(int steps) {
    final objs = selectedObjects;
    if (steps < 1) return;
    // Pull out an optional open-path / line guide so the steps can be laid
    // along it (item 6); the remaining two objects are the start & end shapes.
    ShapeObject? guide;
    final shapes = <ShapeObject>[];
    for (final o in objs) {
      if (objs.length == 3 && guide == null && _isBlendGuide(o)) {
        guide = o;
      } else {
        shapes.add(o);
      }
    }
    if (shapes.length != 2) return;
    shapes.sort((a, b) => _objects.indexOf(a).compareTo(_objects.indexOf(b)));
    final a = shapes.first, b = shapes.last;

    // Snapshot the originals BEFORE we (optionally) move them onto the guide so
    // undo restores their exact prior position (item 5).
    final srcBefore = {a.id: a.copyDeep(), b.id: b.copyDeep()};

    // With a guide route, the start shape snaps to the path start and the end
    // shape to the path end; intermediate steps fall in between (item 5).
    if (guide != null) {
      final pStart = _pointAlongPath(guide, 0);
      final pEnd = _pointAlongPath(guide, 1);
      if (pStart != null) a.center = pStart;
      if (pEnd != null) b.center = pEnd;
    }

    // When both shapes are open paths/lines, morph as open contours (endpoints
    // included, no wrap-around join) so intermediate steps stay open (item 1).
    final bothOpen = _isBlendGuide(a) && _isBlendGuide(b);
    const n = 72;
    final pa = _resampleContour(a, n, open: bothOpen);
    var pb = _resampleContour(b, n, open: bothOpen);
    final canMorph = pa.length == n && pb.length == n;
    if (canMorph) pb = bothOpen ? _alignOpen(pa, pb) : _alignLoop(pa, pb);

    final gid = 'grp-${DateTime.now().microsecondsSinceEpoch}';
    final created = <ShapeObject>[];
    for (var i = 1; i <= steps; i++) {
      final t = i / (steps + 1);
      late ShapeObject o;
      if (canMorph) {
        final pts = [for (var k = 0; k < n; k++) Offset.lerp(pa[k], pb[k], t)!];
        o = _pathFromWorld(pts, closed: !bothOpen);
      } else {
        // Fallback: clone shape A and interpolate transform only.
        o = a.clone();
        o.center = Offset.lerp(a.center, b.center, t)!;
        o.size = Size.lerp(a.size, b.size, t)!;
        o.rotation = a.rotation + (b.rotation - a.rotation) * t;
      }
      // Re-anchor each step onto the guide route when one is supplied.
      if (guide != null) {
        final p = _pointAlongPath(guide, t);
        if (p != null) o.center = p;
      }
      // Interpolate the ENTIRE appearance, not just a couple of fields (item 3):
      // fill / gradient, strokes (incl. the stroke stack & widths), opacity,
      // effects (shadows + glows), blur and blend mode.
      _lerpStyle(o, a, b, t);
      o.groupId = gid;
      o.name = 'Morph';
      created.add(o);
    }
    // Original start & end shapes join the generated group (items 5 & 6); the
    // guide spline, having served its purpose, is removed (item 9).
    _commitCreated(created,
        description: 'Morph',
        sources: [a, b],
        groupId: gid,
        sourcesBefore: srcBefore,
        remove: guide != null ? [guide] : const []);
  }

  /// Interpolates every visual property of [o] from [a] to [b] at fraction [t].
  void _lerpStyle(ShapeObject o, ShapeObject a, ShapeObject b, double t) {
    double ld(double x, double y) => x + (y - x) * t;
    o.opacity = ld(a.opacity, b.opacity);
    o.fill = Color.lerp(a.fill, b.fill, t)!;
    o.fillSpec = _lerpFillSpec(a.fillSpec, b.fillSpec, t);
    o.stroke = Color.lerp(a.stroke, b.stroke, t)!;
    o.strokeWidth = ld(a.strokeWidth, b.strokeWidth);
    // Interpolate against EFFECTIVE strokes (legacy width folded into a 1-item
    // stack) so a curve whose width was set via the rail (legacy strokeWidth)
    // and one set via the Strokes sheet (stack) still cross-fade in thickness.
    o.strokes = _lerpStrokes(_effectiveStrokes(a), _effectiveStrokes(b), t);
    o.blurAmount = ld(a.blurAmount, b.blurAmount);
    o.cornerRadius = ld(a.cornerRadius, b.cornerRadius);
    o.starInner = ld(a.starInner, b.starInner);
    o.shadow = _lerpShadow(a.shadow, b.shadow, t);
    o.innerShadow = _lerpShadow(a.innerShadow, b.innerShadow, t);
    o.glow = _lerpShadow(a.glow, b.glow, t);
    o.innerGlow = _lerpShadow(a.innerGlow, b.innerGlow, t);
    o.blend = t < 0.5 ? a.blend : b.blend;
  }

  /// The object's strokes as a stack, folding the legacy single stroke into a
  /// one-item stack when the stack is empty. Lets the morph treat every stroked
  /// object uniformly regardless of how its width was set.
  List<StrokeSpec> _effectiveStrokes(ShapeObject o) {
    if (o.strokes.isNotEmpty) return o.strokes;
    // Every shape is treated as carrying a stroke — even a width-0 one (item 8).
    // A 0-width stroke renders nothing but lets the morph grow a stroke from /
    // shrink it to zero, so a pure fill ↔ stroked path cross-fades cleanly.
    final w = o.strokeWidth > 0
        ? o.strokeWidth
        : (o.type == ShapeType.line ? 2.0 : 0.0);
    return [StrokeSpec(color: o.stroke, width: w)];
  }

  /// Interpolates a stroke stack. Pads the shorter stack with its last entry so
  /// widths/colours still cross-fade when the two stacks differ in length.
  List<StrokeSpec> _lerpStrokes(
      List<StrokeSpec> a, List<StrokeSpec> b, double t) {
    if (a.isEmpty && b.isEmpty) return const [];
    final count = math.max(a.length, b.length);
    final out = <StrokeSpec>[];
    for (var k = 0; k < count; k++) {
      final sa = k < a.length ? a[k] : (a.isNotEmpty ? a.last : null);
      final sb = k < b.length ? b[k] : (b.isNotEmpty ? b.last : null);
      final base = sa ?? sb!;
      final other = sb ?? sa!;
      // A side with ~zero width has no meaningful colour, so borrow the other
      // side's colour — the growing stroke then fades in its target colour
      // rather than from an arbitrary default (item 8).
      final baseColor = base.width < 0.01 ? other.color : base.color;
      final otherColor = other.width < 0.01 ? base.color : other.color;
      out.add(StrokeSpec(
        enabled: true,
        color: Color.lerp(baseColor, otherColor, t)!,
        width: base.width + (other.width - base.width) * t,
        align: base.align,
        dashed: base.dashed,
        profile: base.profile,
      ));
    }
    return out;
  }

  /// Interpolates a shadow/glow spec. Eases an effect in/out by fading the
  /// disabled side's alpha to zero so a step is enabled if either end is.
  ShadowSpec _lerpShadow(ShadowSpec a, ShadowSpec b, double t) {
    final ca = a.enabled ? a.color : a.color.withValues(alpha: 0);
    final cb = b.enabled ? b.color : b.color.withValues(alpha: 0);
    return ShadowSpec(
      enabled: a.enabled || b.enabled,
      dx: a.dx + (b.dx - a.dx) * t,
      dy: a.dy + (b.dy - a.dy) * t,
      blur: a.blur + (b.blur - a.blur) * t,
      color: Color.lerp(ca, cb, t)!,
    );
  }

  /// Interpolates fills. Cross-fades matching gradients (same kind & stop
  /// count); otherwise snaps to the nearer side so the fill stays valid.
  FillSpec _lerpFillSpec(FillSpec a, FillSpec b, double t) {
    final gradient = a.kind == b.kind &&
        (a.kind == FillKind.linearGradient ||
            a.kind == FillKind.radialGradient) &&
        a.stops.length == b.stops.length;
    if (gradient) {
      return FillSpec(
        kind: a.kind,
        angle: a.angle + (b.angle - a.angle) * t,
        stops: [
          for (var i = 0; i < a.stops.length; i++)
            GradientStop(
              a.stops[i].pos + (b.stops[i].pos - a.stops[i].pos) * t,
              Color.lerp(a.stops[i].color, b.stops[i].color, t)!,
            ),
        ],
      );
    }
    return (t < 0.5 ? a : b).copy();
  }

  /// World-space point at fraction [t] (0..1) along an object's longest contour.
  Offset? _pointAlongPath(ShapeObject o, double t) {
    final metrics = _worldPath(o).computeMetrics().toList();
    if (metrics.isEmpty) return null;
    metrics.sort((a, b) => b.length.compareTo(a.length));
    final m = metrics.first;
    final tan = m.getTangentForOffset(m.length * t.clamp(0.0, 1.0));
    return tan?.position;
  }

  /// Samples an object's outline to [n] evenly spaced world-space points.
  /// When [open], endpoints are included (`i/(n-1)`) and there is no wrap-around
  /// sample, so an open path resamples back into an open path.
  List<Offset> _resampleContour(ShapeObject o, int n, {bool open = false}) {
    final metrics = _worldPath(o).computeMetrics().toList();
    if (metrics.isEmpty) return const [];
    metrics.sort((a, b) => b.length.compareTo(a.length));
    final m = metrics.first;
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final d = open ? m.length * i / (n - 1) : m.length * i / n;
      final t = m.getTangentForOffset(d);
      if (t != null) pts.add(t.position);
    }
    return pts;
  }

  /// Aligns open contour [b] to [a] by choosing forward vs. reversed traversal
  /// (whichever matches endpoints better), without rotating — open paths have
  /// fixed ends, so only direction may need flipping.
  List<Offset> _alignOpen(List<Offset> a, List<Offset> b) {
    final rev = b.reversed.toList();
    double cost(List<Offset> cand) {
      var sum = 0.0;
      for (var k = 0; k < a.length; k++) {
        sum += (a[k] - cand[k]).distanceSquared;
      }
      return sum;
    }

    return cost(rev) < cost(b) ? rev : b;
  }

  /// Rotationally aligns loop [b] to [a] (and tries reversed winding) to
  /// minimise corresponding-point distance, reducing twist during morphs.
  List<Offset> _alignLoop(List<Offset> a, List<Offset> b) {
    final n = a.length;
    double cost(List<Offset> cand, int shift) {
      var sum = 0.0;
      for (var k = 0; k < n; k++) {
        sum += (a[k] - cand[(k + shift) % n]).distanceSquared;
      }
      return sum;
    }

    final rev = b.reversed.toList();
    var best = b;
    var bestShift = 0;
    var bestCost = double.infinity;
    for (final cand in [b, rev]) {
      for (var s = 0; s < n; s++) {
        final c = cost(cand, s);
        if (c < bestCost) {
          bestCost = c;
          best = cand;
          bestShift = s;
        }
      }
    }
    return [for (var k = 0; k < n; k++) best[(k + bestShift) % n]];
  }

  /// Builds a path object from world-space points (closed).
  ShapeObject _pathFromWorld(List<Offset> world, {required bool closed}) {
    var minX = world.first.dx, maxX = world.first.dx;
    var minY = world.first.dy, maxY = world.first.dy;
    for (final p in world) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = math.max(maxX - minX, 1.0), h = math.max(maxY - minY, 1.0);
    final c = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    return ShapeObject(
      type: ShapeType.path,
      center: c,
      size: Size(w, h),
      pathPoints:
          world.map((p) => Offset((p.dx - c.dx) / w, (p.dy - c.dy) / h)).toList(),
      closed: closed,
    );
  }

  // ---- Effects -----------------------------------------------------------
  void setShadow(void Function(ShadowSpec s) change) {
    if (_selection.isEmpty) return;
    final before = _snapshot(_selection);
    for (final o in selectedObjects) {
      change(o.shadow);
    }
    final after = _snapshot(_selection);
    pushApplied(MutationCommand(
        description: 'Effects', before: before, after: after));
    notifyListeners();
  }

  // ---- Live-gesture mutation helpers ------------------------------------
  Map<String, ShapeObject> _snapshot(Iterable<String> ids) =>
      {for (final id in ids) id: byId(id)!.copyDeep()};

  Map<String, ShapeObject>? _gestureBefore;

  /// Begin a live mutation of the current selection; pairs with [commitGesture].
  void beginGesture() => _gestureBefore = _snapshot(_selection);

  void commitGesture(String description) {
    final before = _gestureBefore;
    // Cleared up front: if anything below throws, a stale gesture must not
    // wedge the next one (and callers like the text editor must still reach
    // their cleanup).
    _gestureBefore = null;
    if (before == null) return;
    // A gesture owns the objects it BEGAN on. The selection can change while it
    // runs — tapping the canvas with the text editor open clears it — and an
    // object can even be deleted, so re-snapshot those same ids rather than
    // whatever happens to be selected now. Anything gone is dropped.
    final ids = before.keys.where((id) => byId(id) != null).toList();
    if (ids.isEmpty) return;
    final after = _snapshot(ids);
    final changed = ids.any((id) {
      final a = before[id]!, b = after[id]!;
      return a.center != b.center ||
          a.size != b.size ||
          a.rotation != b.rotation ||
          a.opacity != b.opacity ||
          a.fill != b.fill ||
          a.fillSpec.toJson().toString() != b.fillSpec.toJson().toString() ||
          a.stroke != b.stroke ||
          a.strokeWidth != b.strokeWidth ||
          a.cornerRadius != b.cornerRadius ||
          a.shadow.enabled != b.shadow.enabled ||
          a.shadow.dx != b.shadow.dx ||
          a.shadow.dy != b.shadow.dy ||
          a.shadow.blur != b.shadow.blur ||
          a.shadow.color != b.shadow.color ||
          a.fontSize != b.fontSize ||
          a.fontWeight != b.fontWeight ||
          a.fontFamily != b.fontFamily ||
          a.letterSpacing != b.letterSpacing ||
          a.lineHeight != b.lineHeight ||
          a.textAlignH != b.textAlignH ||
          a.italic != b.italic ||
          a.text != b.text ||
          a.crop != b.crop ||
          a.blend != b.blend ||
          a.starInner != b.starInner ||
          a.points != b.points ||
          !listEquals(a.cornerRadii, b.cornerRadii) ||
          !listEquals(a.pathPoints, b.pathPoints) ||
          !listEquals(a.handleIn, b.handleIn) ||
          !listEquals(a.handleOut, b.handleOut) ||
          !listEquals(a.nodeModes, b.nodeModes) ||
          a.fxSignature() != b.fxSignature();
    });
    if (changed) {
      // before is narrowed to `ids` so undo can't reference a deleted object.
      pushApplied(MutationCommand(
          description: description,
          before: {for (final id in ids) id: before[id]!},
          after: after));
    }
  }

  void mutate(void Function() change) {
    change();
    notifyListeners();
  }

  // ---- Selection ---------------------------------------------------------
  /// Expands an id to include its group mates, using the OUTERMOST container:
  /// a super-group pulls in every sub-group's members; else the leaf group;
  /// else just the object (item 6a nesting).
  Set<String> _withGroup(String id) {
    final o = byId(id);
    if (o == null) return {id};
    if (o.superGroupId != null) {
      return _objects
          .where((x) => x.superGroupId == o.superGroupId)
          .map((x) => x.id)
          .toSet();
    }
    if (o.groupId != null) {
      return _objects
          .where((x) => x.groupId == o.groupId)
          .map((x) => x.id)
          .toSet();
    }
    return {id};
  }

  void selectOnly(String id) {
    _selection
      ..clear()
      ..addAll(_withGroup(id));
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  /// Selects exactly one object, WITHOUT expanding to its group mates. Used by
  /// the Layers panel so a single member of a group can be edited on its own.
  void selectExact(String id) {
    if (byId(id) == null) return;
    _selection
      ..clear()
      ..add(id);
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  /// Selects every member of a leaf group [gid] WITHOUT expanding to an
  /// enclosing super-group — lets the Layers panel target one sub-group / one
  /// repeat instance (item 6a).
  void selectGroupMembers(String gid) {
    final ids =
        _objects.where((o) => o.groupId == gid).map((o) => o.id).toList();
    if (ids.isEmpty) return;
    _selection
      ..clear()
      ..addAll(ids);
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  /// Selects every member of a super-group [sgid] (the whole nested group).
  void selectSuperGroup(String sgid) {
    final ids = _objects
        .where((o) => o.superGroupId == sgid)
        .map((o) => o.id)
        .toList();
    if (ids.isEmpty) return;
    _selection
      ..clear()
      ..addAll(ids);
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  // ---- Layers panel: drag-into-group, masked groups, delete ---------------
  /// The id of the object acting as the clipping mask within leaf group [gid]
  /// (the member another member points at via [ShapeObject.maskId]), or null if
  /// [gid] isn't a masked group.
  String? groupMaskId(String gid) {
    final members = _objects.where((o) => o.groupId == gid).toList();
    for (final m in members) {
      if (members.any((x) => x.maskId == m.id)) return m.id;
    }
    return null;
  }

  /// Moves [id] into leaf group [gid] in one undo step (drag-drop in Layers,
  /// item 3). If [gid] is a clipping-mask group, the object also becomes clipped
  /// by the group's mask — so one mask can clip several layers. The mask object
  /// itself can't be dropped into its own masked content.
  void addToGroup(String id, String gid) {
    final o = byId(id);
    if (o == null || gid.isEmpty) return;
    final maskId = groupMaskId(gid);
    if (o.id == maskId) return;
    // Adopt the group's outer container so nesting stays consistent.
    final ref = _objects.firstWhere((x) => x.groupId == gid, orElse: () => o);
    final sgid = ref.superGroupId;
    final already = o.groupId == gid &&
        o.superGroupId == sgid &&
        (maskId == null || o.maskId == maskId);
    if (already) return;
    final before = {id: o.copyDeep()};
    o.groupId = gid;
    o.superGroupId = sgid;
    if (maskId != null) o.maskId = maskId;
    pushApplied(MutationCommand(
        description: 'Add to group',
        before: before,
        after: {id: o.copyDeep()}));
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  /// Nests leaf group [childGid] alongside [targetGid] under a common
  /// super-group, so dragging a group onto another group in the Layers panel
  /// creates a nested "group of groups" (item 5). If the target already belongs
  /// to a super-group, the child joins that one.
  void nestGroups(String childGid, String targetGid) {
    if (childGid == targetGid) return;
    final childMembers =
        _objects.where((o) => o.groupId == childGid).toList();
    final targetMembers =
        _objects.where((o) => o.groupId == targetGid).toList();
    if (childMembers.isEmpty || targetMembers.isEmpty) return;
    // Don't nest into one of the child's own descendants.
    if (childMembers.first.superGroupId != null &&
        childMembers.first.superGroupId == targetMembers.first.superGroupId &&
        targetMembers.first.superGroupId != null) {
      // already siblings under the same super — nothing to do
    }
    final existingSuper = targetMembers.first.superGroupId;
    final sgid = existingSuper ?? 'sgrp-${DateTime.now().microsecondsSinceEpoch}';
    final affected = <ShapeObject>[
      ...childMembers,
      if (existingSuper == null) ...targetMembers,
    ];
    final before = {for (final o in affected) o.id: o.copyDeep()};
    for (final o in childMembers) {
      o.superGroupId = sgid;
    }
    if (existingSuper == null) {
      for (final o in targetMembers) {
        o.superGroupId = sgid;
      }
    }
    pushApplied(MutationCommand(
        description: 'Nest group',
        before: before,
        after: {for (final o in affected) o.id: o.copyDeep()}));
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  /// Deletes [targets], first releasing any clip on survivors that one of the
  /// targets was masking (so masked content doesn't vanish with its mask).
  void deleteObjects(List<ShapeObject> targets) {
    if (targets.isEmpty) return;
    final ids = targets.map((e) => e.id).toSet();
    final cmds = <Command>[];
    final clipped = _objects
        .where((o) =>
            o.maskId != null && ids.contains(o.maskId) && !ids.contains(o.id))
        .toList();
    if (clipped.isNotEmpty) {
      final before = {for (final c in clipped) c.id: c.copyDeep()};
      for (final c in clipped) {
        c.maskId = null;
      }
      cmds.add(MutationCommand(
          description: 'Release mask',
          before: before,
          after: {for (final c in clipped) c.id: c.copyDeep()}));
    }
    cmds.add(DeleteObjectsCommand(_objects, targets));
    HapticFeedback.heavyImpact();
    _runBatch(cmds, 'Delete');
    _selection.removeAll(ids);
    notifyListeners();
  }

  /// Deletes a single object (Layers panel delete button, item 7).
  void deleteObject(String id) {
    final o = byId(id);
    if (o != null) deleteObjects([o]);
  }

  /// Deletes every member of leaf group [gid] (Layers panel).
  void deleteGroup(String gid) =>
      deleteObjects(_objects.where((o) => o.groupId == gid).toList());

  /// Deletes every member of super-group [sgid] (Layers panel).
  void deleteSuperGroup(String sgid) =>
      deleteObjects(_objects.where((o) => o.superGroupId == sgid).toList());

  void addToSelection(String id) {
    _selection.addAll(_withGroup(id));
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  void toggleSelection(String id) {
    final g = _withGroup(id);
    if (_selection.containsAll(g)) {
      _selection.removeAll(g);
    } else {
      _selection.addAll(g);
    }
    notifyListeners();
  }

  void setSelection(Iterable<String> ids) {
    final expanded = <String>{};
    for (final id in ids) {
      expanded.addAll(_withGroup(id));
    }
    _selection
      ..clear()
      ..addAll(expanded);
    notifyListeners();
  }

  /// Objects touching a canvas-space marquee rect (partial overlap counts).
  List<ShapeObject> objectsInRect(Rect rect) => _objects
      .where((o) => o.visible && !o.locked && o.bounds.overlaps(rect))
      .toList();

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  void selectAll() {
    _selection
      ..clear()
      ..addAll(_objects.where((o) => o.visible && !o.locked).map((o) => o.id));
    notifyListeners();
  }

  /// Live marquee rectangle (canvas space) while rubber-band selecting.
  Rect? marquee;
  void setMarquee(Rect? r) {
    marquee = r;
    notifyListeners();
  }

  /// Combined bounding box of the current selection (canvas space).
  Rect? get selectionBounds {
    final objs = selectedObjects;
    if (objs.isEmpty) return null;
    var r = objs.first.bounds;
    for (final o in objs) {
      r = r.expandToInclude(o.bounds);
    }
    return r;
  }

  /// Top-most object hit by a canvas-space point (last painted = on top).
  ShapeObject? hitTest(Offset canvasPoint, {double tolerance = 6}) {
    for (var i = _objects.length - 1; i >= 0; i--) {
      final o = _objects[i];
      if (!o.visible || o.locked) continue;
      if (o.hitTest(canvasPoint, tolerance: tolerance)) return o;
    }
    return null;
  }

  // ---- Viewport (§7) -----------------------------------------------------
  double zoom = 1.0;
  Offset pan = Offset.zero; // screen-space translation

  Offset screenToCanvas(Offset screen) => (screen - pan) / zoom;
  Offset canvasToScreen(Offset canvas) => canvas * zoom + pan;

  void setViewport(double newZoom, Offset newPan) {
    zoom = newZoom.clamp(0.05, 64.0);
    pan = newPan;
    notifyListeners();
  }

  /// Frames every object in [viewport]. [fill] scales the result: 1.0 fits as
  /// large as the margin allows, 0.7 leaves the content 30% smaller.
  void zoomToFit(Size viewport, {double fill = 1.0}) {
    if (_objects.isEmpty) {
      zoom = 1;
      pan = Offset(viewport.width / 2, viewport.height / 2);
      notifyListeners();
      return;
    }
    var rect = _objects.first.bounds;
    for (final o in _objects) {
      rect = rect.expandToInclude(o.bounds);
    }
    const margin = 0.8; // 20% padding
    final z = (viewport.width / rect.width * margin * fill)
        .clamp(0.05, 4.0)
        .toDouble();
    final zy = (viewport.height / rect.height * margin * fill)
        .clamp(0.05, 4.0)
        .toDouble();
    zoom = z < zy ? z : zy;
    pan = Offset(viewport.width / 2, viewport.height / 2) - rect.center * zoom;
    notifyListeners();
  }

  // ---- UI / orb / sheets -------------------------------------------------
  bool orbExpanded = false;
  String? orbBranch; // 'Create' | 'Style' | 'Edit' | 'Organize' | null
  ActiveTool tool = ActiveTool.none;
  ActiveSheet sheet = ActiveSheet.none;
  bool workspaceOpen = false;

  /// Screen-space anchor for the long-press radial context menu (§13.4),
  /// null when closed.
  Offset? contextMenuAt;

  void openContextMenu(Offset at) {
    contextMenuAt = at;
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  void closeContextMenu() {
    if (contextMenuAt == null) return;
    contextMenuAt = null;
    notifyListeners();
  }

  void toggleOrb() {
    orbExpanded = !orbExpanded;
    if (!orbExpanded) orbBranch = null;
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  /// Active creation tool (pen/draw/text). Setting a tool clears the selection
  /// and collapses the orb so the canvas is ready for input.
  void setTool(ActiveTool t) {
    tool = t;
    orbExpanded = false;
    orbBranch = null;
    if (t != ActiveTool.none) _selection.clear();
    notifyListeners();
  }

  /// Freehand draw stabilisation, 0 (off) → 1 (extreme smoothing). Higher values
  /// lag the pen behind the finger more, smoothing out jitter while sketching
  /// (item 10). Persisted for the session.
  double drawStabilization = 0.35;
  void setStabilization(double v) {
    drawStabilization = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Freehand draw: the live stroke being drawn (canvas space).
  final List<Offset> drawDraft = [];
  void drawStart(Offset p) {
    drawDraft
      ..clear()
      ..add(p);
    notifyListeners();
  }

  void drawExtend(Offset p) {
    drawDraft.add(p);
    notifyListeners();
  }

  void drawClear() {
    drawDraft.clear();
    notifyListeners();
  }

  /// Pen tool: anchor points accumulated so far (canvas space), each with an
  /// outgoing tangent handle (canvas-relative; zero = a hard corner). The in
  /// handle is the mirror of the out handle (symmetric), like a real pen.
  final List<Offset> penDraft = [];
  final List<Offset> penOut = [];

  /// Live placement preview while the finger is down (anchor + dragged handle).
  Offset? penDragAnchor;
  Offset? penDragHandle;

  void penAddPoint(Offset p) {
    penDraft.add(p);
    penOut.add(Offset.zero);
    notifyListeners();
  }

  /// Adds a smooth anchor with a dragged-out tangent (handle = drag vector).
  void penAddSmooth(Offset anchor, Offset handleOut) {
    penDraft.add(anchor);
    penOut.add(handleOut);
    notifyListeners();
  }

  void penPreview(Offset? anchor, Offset? handle) {
    penDragAnchor = anchor;
    penDragHandle = handle;
    notifyListeners();
  }

  void penFinish({required bool closed}) {
    if (penDraft.length >= 2) _buildPenPath(closed);
    penDraft.clear();
    penOut.clear();
    penDragAnchor = null;
    penDragHandle = null;
    tool = ActiveTool.none;
    notifyListeners();
  }

  void _buildPenPath(bool closed) {
    final pts = List.of(penDraft);
    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = math.max(maxX - minX, 1.0), h = math.max(maxY - minY, 1.0);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final anchors = pts
        .map((p) => Offset((p.dx - center.dx) / w, (p.dy - center.dy) / h))
        .toList();
    final hIn = <Offset>[], hOut = <Offset>[];
    final modes = <int>[];
    var anyHandle = false;
    for (var i = 0; i < pts.length; i++) {
      final rel = Offset(penOut[i].dx / w, penOut[i].dy / h);
      final smooth = penOut[i].distance > 0.5;
      if (smooth) anyHandle = true;
      hOut.add(rel);
      hIn.add(-rel);
      modes.add(smooth ? 2 : 0);
    }
    addObject(ShapeObject(
      type: ShapeType.path,
      center: center,
      size: Size(w, h),
      pathPoints: anchors,
      handleIn: anyHandle ? hIn : const [],
      handleOut: anyHandle ? hOut : const [],
      nodeModes: anyHandle ? modes : const [],
      closed: closed,
      fill: closed ? nextPastel() : const Color(0x00000000),
      stroke: ShapeColors.primaryText,
      strokeWidth: 3,
      // Paths carry an explicit stroke so the Strokes panel shows it (item 4).
      // Taper-out profile so the line thins toward its end (item 3).
      strokes: [StrokeSpec(color: ShapeColors.primaryText, width: 3, profile: 2)],
    ));
  }

  void penCancel() {
    penDraft.clear();
    penOut.clear();
    penDragAnchor = null;
    penDragHandle = null;
    notifyListeners();
  }

  /// Currently highlighted corner-radius node (for the link/single UI).
  int? selectedCorner;
  void selectCorner(int? i) {
    selectedCorner = i;
    notifyListeners();
  }

  // ---- Perspective distort (4-corner) -----------------------------------
  /// Id of the object whose perspective corners are being dragged (null = off).
  String? perspectiveEditId;

  /// Any object can be perspective-distorted — shapes, images and text.
  bool canPerspective(ShapeObject? o) => o != null;

  void enterPerspectiveEdit(String id) {
    final o = byId(id);
    if (o == null) return;
    if (!o.hasPerspective) {
      o.perspective = List.of(ShapeObject.identityPerspective);
    }
    perspectiveEditId = id;
    nodeEditId = null;
    _selection
      ..clear()
      ..add(id);
    notifyListeners();
  }

  void exitPerspectiveEdit() {
    final id = perspectiveEditId;
    if (id == null) return;
    final o = byId(id);
    // Drop an untouched (identity) distort so the object isn't flagged warped.
    if (o != null && _isIdentityPerspective(o)) o.perspective = const [];
    perspectiveEditId = null;
    notifyListeners();
  }

  bool _isIdentityPerspective(ShapeObject o) {
    if (!o.hasPerspective) return true;
    for (var i = 0; i < 4; i++) {
      if ((o.perspective[i] - ShapeObject.identityPerspective[i]).distance >
          1e-4) {
        return false;
      }
    }
    return true;
  }

  /// Moves perspective corner [i] (0 TL,1 TR,2 BR,3 BL) to a canvas point. Wrap
  /// with [beginGesture]/[commitGesture] for a single undo step.
  void setPerspectiveCorner(int i, Offset canvasPoint) {
    final o = byId(perspectiveEditId ?? '');
    if (o == null || !o.hasPerspective || i < 0 || i > 3) return;
    final local = _rotate(canvasPoint - o.center, -o.rotation);
    o.perspective[i] =
        Offset(local.dx / o.size.width, local.dy / o.size.height);
    notifyListeners();
  }

  /// Canvas-space position of perspective corner [i], for hit-testing handles.
  Offset perspectiveCornerCanvas(ShapeObject o, int i) {
    final p = o.perspective[i];
    return o.center +
        _rotate(Offset(p.dx * o.size.width, p.dy * o.size.height), o.rotation);
  }

  void resetPerspective() {
    final o = byId(perspectiveEditId ?? '');
    if (o == null) return;
    final before = {o.id: o.copyDeep()};
    o.perspective = List.of(ShapeObject.identityPerspective);
    pushApplied(MutationCommand(
        description: 'Reset perspective',
        before: before,
        after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  // ---- Node editing (path objects) --------------------------------------
  String? nodeEditId;

  // For a non-destructive "show curve nodes" peek: when node editing is entered
  // on a primitive we convert it to a path, but remember the original so we can
  // restore it (and its corner controls) if the user exits without editing.
  ShapeObject? _nodeEditOriginal;
  Command? _nodeEditConvertCmd;
  String? _nodeEditEntryDigest;

  final Set<int> selectedNodes = {};
  int? get selectedNode => selectedNodes.isEmpty ? null : selectedNodes.first;

  /// True when [o] can become an editable bezier path (everything vector).
  bool canNodeEdit(ShapeObject? o) =>
      o != null && o.type != ShapeType.text && o.type != ShapeType.image;

  void enterNodeEdit(String id) {
    var o = byId(id);
    if (!canNodeEdit(o)) return;
    _nodeEditOriginal = null;
    _nodeEditConvertCmd = null;
    // Expand any primitive into a real bezier path so every shape is editable
    // by its nodes + tangent handles (§ vector model). The original is kept so
    // a no-op peek can be reverted, restoring the shape's corner controls.
    if (o!.type != ShapeType.path) {
      _nodeEditOriginal = o.copyDeep();
      o = _convertToPath(o);
      _nodeEditConvertCmd = _undo.isNotEmpty ? _undo.last : null;
    }
    nodeEditId = o.id;
    _nodeEditEntryDigest = _nodeDigest(o);
    selectedNodes.clear();
    _selection
      ..clear()
      ..add(o.id);
    notifyListeners();
  }

  /// A signature of a path's editable geometry, used to detect whether a node
  /// edit session actually changed anything.
  String _nodeDigest(ShapeObject o) =>
      '${o.closed}|${o.pathPoints}|${o.handleIn}|${o.handleOut}|${o.nodeModes}';

  /// Replaces a primitive with an editable path of identical silhouette/style.
  ShapeObject _convertToPath(ShapeObject src) {
    final n = src.toEditableNodes();
    final path = ShapeObject(
      id: src.id,
      type: ShapeType.path,
      center: src.center,
      size: src.size,
      rotation: src.rotation,
      fill: src.fill,
      stroke: src.stroke,
      strokeWidth: src.type == ShapeType.line && src.strokeWidth == 0
          ? 2
          : src.strokeWidth,
      opacity: src.opacity,
      visible: src.visible,
      locked: src.locked,
      pathPoints: n.anchors,
      handleIn: n.hIn,
      handleOut: n.hOut,
      nodeModes: n.modes,
      closed: n.closed,
      groupId: src.groupId,
      blend: src.blend,
      strokes: src.strokes.map((s) => s.copy()).toList(),
      blurAmount: src.blurAmount,
      shadow: src.shadow.copy(),
      innerShadow: src.innerShadow.copy(),
      glow: src.glow.copy(),
      innerGlow: src.innerGlow.copy(),
      name: src.name,
    );
    _run(ReplaceObjectCommand(src, path));
    return path;
  }

  void exitNodeEdit() {
    if (nodeEditId == null) return;
    final o = byId(nodeEditId!);
    final reverted = _maybeRevertNodeEdit(o);
    if (!reverted) _renormalize(o);
    _nodeEditOriginal = null;
    _nodeEditConvertCmd = null;
    _nodeEditEntryDigest = null;
    nodeEditId = null;
    selectedNodes.clear();
    notifyListeners();
  }

  /// Restores the original primitive when a "show curve nodes" session made no
  /// edits, so the shape (and its Corners controls) comes back instead of being
  /// permanently converted to a path. Returns true if it reverted.
  bool _maybeRevertNodeEdit(ShapeObject? o) {
    if (o == null || _nodeEditOriginal == null || _nodeEditConvertCmd == null) {
      return false;
    }
    // Only revert if the conversion is still the latest action (nothing was
    // committed afterwards) and the geometry is untouched.
    if (_undo.isEmpty || !identical(_undo.last, _nodeEditConvertCmd)) {
      return false;
    }
    if (_nodeDigest(o) != _nodeEditEntryDigest) return false;
    final i = _objects.indexWhere((x) => x.id == o.id);
    if (i < 0) return false;
    _objects[i] = _nodeEditOriginal!;
    _undo.removeLast(); // drop the now-cancelled conversion from history
    return true;
  }

  void selectNode(int? i, {bool add = false}) {
    if (i == null) {
      selectedNodes.clear();
    } else if (add) {
      selectedNodes.contains(i)
          ? selectedNodes.remove(i)
          : selectedNodes.add(i);
    } else {
      selectedNodes
        ..clear()
        ..add(i);
    }
    notifyListeners();
  }

  /// Select all nodes whose canvas position lies inside [rect].
  void selectNodesInRect(Rect rect) {
    final o = byId(nodeEditId ?? '');
    if (o == null) return;
    selectedNodes.clear();
    for (var i = 0; i < o.pathPoints.length; i++) {
      final local =
          Offset(o.pathPoints[i].dx * o.size.width, o.pathPoints[i].dy * o.size.height);
      final world = o.center + _rotate(local, o.rotation);
      if (rect.contains(world)) selectedNodes.add(i);
    }
    notifyListeners();
  }

  /// Move all selected nodes (or [index] if none selected) by a canvas delta.
  void moveNode(int index, Offset canvasDelta) {
    final o = byId(nodeEditId ?? '');
    if (o == null) return;
    final local = _rotate(canvasDelta, -o.rotation);
    final dn = Offset(local.dx / o.size.width, local.dy / o.size.height);
    final targets =
        selectedNodes.isNotEmpty ? selectedNodes : <int>{index};
    for (final i in targets) {
      if (i < o.pathPoints.length) o.pathPoints[i] += dn;
    }
    notifyListeners();
  }

  void addNodeNear(Offset canvasPoint) {
    final o = byId(nodeEditId ?? '');
    if (o == null) return;
    // Convert to normalized local space.
    final local = _rotate(canvasPoint - o.center, -o.rotation);
    final target = Offset(local.dx / o.size.width, local.dy / o.size.height);
    var bestSeg = 0;
    var bestDist = double.infinity;
    final n = o.pathPoints.length;
    final segs = o.closed ? n : n - 1;
    for (var i = 0; i < segs; i++) {
      final a = o.pathPoints[i];
      final b = o.pathPoints[(i + 1) % n];
      final d = _distSeg(target, a, b);
      if (d < bestDist) {
        bestDist = d;
        bestSeg = i;
      }
    }
    final before = {o.id: o.copyDeep()};
    o.pathPoints.insert(bestSeg + 1, target);
    if (o.hasHandles || o.handleIn.isNotEmpty) {
      o.handleIn.insert(bestSeg + 1, Offset.zero);
      o.handleOut.insert(bestSeg + 1, Offset.zero);
    }
    if (o.nodeModes.isNotEmpty) o.nodeModes.insert(bestSeg + 1, 0);
    pushApplied(MutationCommand(
        description: 'Add node', before: before, after: {o.id: o.copyDeep()}));
    selectedNodes
      ..clear()
      ..add(bestSeg + 1);
    notifyListeners();
  }

  void deleteSelectedNode() {
    final o = byId(nodeEditId ?? '');
    if (o == null || selectedNodes.isEmpty) return;
    final before = {o.id: o.copyDeep()};
    final sorted = selectedNodes.toList()..sort((a, b) => b.compareTo(a));
    for (final i in sorted) {
      if (o.pathPoints.length > 2 && i < o.pathPoints.length) {
        o.pathPoints.removeAt(i);
        if (i < o.handleIn.length) o.handleIn.removeAt(i);
        if (i < o.handleOut.length) o.handleOut.removeAt(i);
        if (i < o.nodeModes.length) o.nodeModes.removeAt(i);
        // Re-fit the tangents of the two nodes that close the gap so the curve
        // doesn't bulge toward the removed point (item 1). Hard corners keep
        // their handles; only smooth nodes are refitted.
        final n = o.pathPoints.length;
        if (n > 0) {
          _retangentNode(o, o.closed ? (i - 1 + n) % n : i - 1);
          _retangentNode(o, i < n ? i : (o.closed ? 0 : n - 1));
        }
      }
    }
    pushApplied(MutationCommand(
        description: 'Delete node',
        before: before,
        after: {o.id: o.copyDeep()}));
    selectedNodes.clear();
    notifyListeners();
  }

  /// Recomputes a smooth node's tangent handles from its current neighbours
  /// (Catmull-Rom), respecting open-path endpoints. Leaves hard corners (mode 0)
  /// untouched. Used after a node deletion so the surviving curve stays clean.
  void _retangentNode(ShapeObject o, int i) {
    final n = o.pathPoints.length;
    if (i < 0 || i >= n || !o.hasHandles || o.nodeModeAt(i) == 0) return;
    final prev =
        o.pathPoints[o.closed ? (i - 1 + n) % n : math.max(0, i - 1)];
    final next =
        o.pathPoints[o.closed ? (i + 1) % n : math.min(n - 1, i + 1)];
    final t = (next - prev) * (1 / 6);
    o.handleOut[i] = (!o.closed && i == n - 1) ? Offset.zero : t;
    o.handleIn[i] = (!o.closed && i == 0) ? Offset.zero : -t;
  }

  void toggleSmooth() {
    final o = byId(nodeEditId ?? (singleSelection?.id ?? ''));
    if (o == null || o.type != ShapeType.path) return;
    final before = {o.id: o.copyDeep()};
    o.smooth = !o.smooth;
    pushApplied(MutationCommand(
        description: 'Curve', before: before, after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  void toggleClosed() {
    final o = byId(nodeEditId ?? (singleSelection?.id ?? ''));
    if (o == null || o.type != ShapeType.path) return;
    final before = {o.id: o.copyDeep()};
    o.closed = !o.closed;
    pushApplied(MutationCommand(
        description: 'Close path', before: before, after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  /// Re-fit a path's bounding box to its nodes (called when exiting node edit).
  void _renormalize(ShapeObject? o) {
    if (o == null || o.type != ShapeType.path || o.pathPoints.isEmpty) return;
    final local =
        o.pathPoints.map((p) => Offset(p.dx * o.size.width, p.dy * o.size.height));
    var minX = local.first.dx, maxX = local.first.dx;
    var minY = local.first.dy, maxY = local.first.dy;
    for (final p in local) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = math.max(maxX - minX, 1.0);
    final h = math.max(maxY - minY, 1.0);
    final localCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final oldW = o.size.width, oldH = o.size.height;
    o.center += _rotate(localCenter, o.rotation);
    o.size = Size(w, h);
    o.pathPoints = local
        .map((p) => Offset((p.dx - localCenter.dx) / w,
            (p.dy - localCenter.dy) / h))
        .toList();
    // Handles are stored normalized & relative — rescale so they keep the same
    // absolute (local-pixel) length under the new bounding box.
    Offset rescale(Offset hn) => Offset(hn.dx * oldW / w, hn.dy * oldH / h);
    if (o.handleIn.length == o.pathPoints.length) {
      o.handleIn = o.handleIn.map(rescale).toList();
    }
    if (o.handleOut.length == o.pathPoints.length) {
      o.handleOut = o.handleOut.map(rescale).toList();
    }
  }

  // ---- Tangent handles (bezier) -----------------------------------------
  /// Drags a node's tangent handle (canvas-space delta). Mirrors the opposite
  /// handle for smooth (1) / symmetric (2) nodes; corner (0) moves freely.
  void moveHandle(int node, bool isOut, Offset canvasDelta) {
    final o = byId(nodeEditId ?? '');
    if (o == null || !o.hasHandles || node >= o.pathPoints.length) return;
    final local = _rotate(canvasDelta, -o.rotation);
    final dn = Offset(local.dx / o.size.width, local.dy / o.size.height);
    final mode = o.nodeModeAt(node);
    final moved = (isOut ? o.handleOut[node] : o.handleIn[node]) + dn;
    if (isOut) {
      o.handleOut[node] = moved;
    } else {
      o.handleIn[node] = moved;
    }
    if (mode != 0) {
      final other = isOut ? o.handleIn[node] : o.handleOut[node];
      final otherLen = mode == 2 ? moved.distance : other.distance;
      final dir = moved.distance == 0 ? Offset.zero : moved / moved.distance;
      final mirrored = -dir * otherLen;
      if (isOut) {
        o.handleIn[node] = mirrored;
      } else {
        o.handleOut[node] = mirrored;
      }
    }
    notifyListeners();
  }

  /// Sets the handle mode of all selected nodes, synthesizing tangents when
  /// switching a hard corner to smooth so handles appear to grab.
  void setNodeMode(int mode) {
    final o = byId(nodeEditId ?? '');
    if (o == null || o.type != ShapeType.path || selectedNodes.isEmpty) return;
    final before = {o.id: o.copyDeep()};
    _ensureHandles(o);
    final n = o.pathPoints.length;
    bool zero(Offset h) => h.dx.abs() < 1e-6 && h.dy.abs() < 1e-6;
    for (final i in selectedNodes) {
      if (i >= n) continue;
      o.nodeModes[i] = mode;
      if (mode != 0 && zero(o.handleIn[i]) && zero(o.handleOut[i])) {
        // Auto-tangent along the neighbours so the node visibly rounds. On an
        // OPEN path the ends clamp (no wrap) so endpoint handles don't blow out.
        final prev = o.pathPoints[
            o.closed ? (i - 1 + n) % n : math.max(0, i - 1)];
        final next = o.pathPoints[
            o.closed ? (i + 1) % n : math.min(n - 1, i + 1)];
        final t = (next - prev) * (1 / 6);
        o.handleOut[i] = (!o.closed && i == n - 1) ? Offset.zero : t;
        o.handleIn[i] = (!o.closed && i == 0) ? Offset.zero : -t;
      } else if (mode == 0) {
        o.handleIn[i] = Offset.zero;
        o.handleOut[i] = Offset.zero;
      }
    }
    pushApplied(MutationCommand(
        description: mode == 0 ? 'Corner node' : 'Smooth node',
        before: before,
        after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  /// Breaks the tangent link on the selected nodes (Illustrator "cusp") so each
  /// handle can be dragged independently instead of moving as a mirrored pair.
  /// Keeps the existing handle vectors — synthesizing a pair first if the node
  /// is a bare corner so there is something to pull on either side.
  void breakNodeHandles() {
    final o = byId(nodeEditId ?? '');
    if (o == null || o.type != ShapeType.path || selectedNodes.isEmpty) return;
    final before = {o.id: o.copyDeep()};
    _ensureHandles(o);
    final n = o.pathPoints.length;
    bool zero(Offset h) => h.dx.abs() < 1e-6 && h.dy.abs() < 1e-6;
    for (final i in selectedNodes) {
      if (i >= n) continue;
      if (zero(o.handleIn[i]) && zero(o.handleOut[i])) {
        final prev =
            o.pathPoints[o.closed ? (i - 1 + n) % n : math.max(0, i - 1)];
        final next =
            o.pathPoints[o.closed ? (i + 1) % n : math.min(n - 1, i + 1)];
        final t = (next - prev) * (1 / 6);
        o.handleOut[i] = (!o.closed && i == n - 1) ? Offset.zero : t;
        o.handleIn[i] = (!o.closed && i == 0) ? Offset.zero : -t;
      }
      o.nodeModes[i] = 0; // corner mode → handles move independently
    }
    pushApplied(MutationCommand(
        description: 'Break handles',
        before: before,
        after: {o.id: o.copyDeep()}));
    notifyListeners();
  }

  /// Ensures a path has handle arrays sized to its anchors (zeros = corners).
  void _ensureHandles(ShapeObject o) {
    final n = o.pathPoints.length;
    if (o.handleIn.length != n) {
      o.handleIn = List.filled(n, Offset.zero, growable: true);
    }
    if (o.handleOut.length != n) {
      o.handleOut = List.filled(n, Offset.zero, growable: true);
    }
    if (o.nodeModes.length != n) {
      o.nodeModes = List.filled(n, 0, growable: true);
    }
  }

  Offset _rotate(Offset v, double a) {
    final c = math.cos(a), s = math.sin(a);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  static double _distSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
        (ab.distanceSquared == 0 ? 1 : ab.distanceSquared);
    final proj = a + ab * t.clamp(0.0, 1.0);
    return (p - proj).distance;
  }

  /// The id of a text object currently being edited (keyboard overlay shown).
  String? editingTextId;
  void beginTextEdit(String id) {
    editingTextId = id;
    notifyListeners();
  }

  void endTextEdit() {
    if (editingTextId == null) return;
    editingTextId = null;
    notifyListeners();
  }

  void openOrbBranch(String? branch) {
    orbBranch = branch;
    notifyListeners();
  }

  void collapseOrb() {
    if (!orbExpanded && orbBranch == null) return;
    orbExpanded = false;
    orbBranch = null;
    notifyListeners();
  }

  void openSheet(ActiveSheet s) {
    sheet = s;
    notifyListeners();
  }

  /// Seed mode for the Repeat sheet (0 = grid, 1 = radial, 2 = mirror) so the
  /// orb's Grid/Radial/Mirror entries open the same sheet preselected.
  int repeatModeSeed = 0;
  void openRepeatSheet(int mode) {
    repeatModeSeed = mode;
    openSheet(ActiveSheet.repeat);
  }

  void closeSheet() {
    if (sheet == ActiveSheet.none) return;
    sheet = ActiveSheet.none;
    notifyListeners();
  }

  /// Quick Command Search overlay (§18).
  bool commandOpen = false;
  void openCommand() {
    commandOpen = true;
    orbExpanded = false;
    notifyListeners();
  }

  void closeCommand() {
    if (!commandOpen) return;
    commandOpen = false;
    notifyListeners();
  }

  void setWorkspace(bool open) {
    workspaceOpen = open;
    notifyListeners();
  }
}
