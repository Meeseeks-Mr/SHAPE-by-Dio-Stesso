import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../models/tool.dart';
import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../theme/shape_theme.dart';
import '../glass.dart';

/// The Property Rail - #11. A vertical column of property pills pinned to the
/// right edge of the screen whenever a single object is selected, replacing the
/// inspector panel (and the older orbital halo). It stays clear of the canvas
/// centre so it never interferes with the artwork. Tap a pill to open its
/// sheet; drag Rotate / Opacity / Stroke for direct manipulation with a live
/// value label shown over the object.
class PropertyHaloLayer extends StatefulWidget {
  const PropertyHaloLayer({super.key});

  @override
  State<PropertyHaloLayer> createState() => _PropertyHaloLayerState();
}

class _PropertyHaloLayerState extends State<PropertyHaloLayer> {
  String? _centerLabel; // shown during active drag (#11.5)
  double _startRotation = 0;
  double _startAngle = 0;
  double _startStroke = 0;
  double _startDist = 0;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final single = m.singleSelection;
    final multi = single == null && m.selectedObjects.length >= 2;
    final empty = single == null && !multi;
    // Rail yields to other UI to keep the canvas calm (#1 Law 1).
    if (m.orbExpanded ||
        m.sheet != ActiveSheet.none ||
        m.contextMenuAt != null ||
        m.nodeEditId != null ||
        m.perspectiveEditId != null ||
        m.editingTextId != null ||
        m.tool != ActiveTool.none) {
      return const SizedBox.shrink();
    }

    // For a multi-selection / group, use the first object as the representative
    // for labels; the options apply to the whole selection. With nothing
    // selected, the rail still offers canvas-level options like Layers (item 7).
    final o = empty ? null : (single ?? m.selectedObjects.first);

    // Contextual option set, laid out flat top-to-bottom. Only properties that
    // apply appear, so there are no dead buttons. Drag-to-edit pills are only
    // offered for a single object.
    final defs = empty
        ? _defsForEmpty(m)
        : (single != null ? _defsFor(m, o!) : _defsForMulti(m));
    if (defs.isEmpty) return const SizedBox.shrink();

    final railChildren = [
      for (final def in defs)
        _railButton(context, m, o, def, allowDrag: single != null),
    ];

    final widgets = <Widget>[
      // The rail itself — pinned right, vertically centred so it never crosses
      // the artwork in the middle of the canvas. Scrolls if it would overflow.
      Positioned.fill(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: railChildren,
              ),
            ),
          ),
        ),
      ),
    ];

    // Live value readout over the object centre during a drag (single only).
    if (_centerLabel != null && o != null) {
      final center = m.canvasToScreen(o.center);
      widgets.add(Positioned(
        left: center.dx - 60,
        top: center.dy - 18,
        child: SizedBox(
          width: 120,
          child: Center(
            child: Glass(
              layer: GlassLayer.halo,
              borderRadius: BorderRadius.circular(10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(_centerLabel!,
                  style: ShapeText.monoSize(20), textAlign: TextAlign.center),
            ),
          ),
        ),
      ));
    }

    return SizedBox.expand(
      child: Stack(clipBehavior: Clip.none, children: widgets),
    );
  }

  /// Full, flat option set for the selection laid out top-to-bottom. Only
  /// properties that apply to this object appear, so there are no dead buttons.
  List<_HaloDef> _defsFor(EditorModel m, ShapeObject o) {
    _HaloDef d(String label, IconData icon, String value, _Mode mode,
            {Color? swatch}) =>
        _HaloDef(label, icon, value, mode, swatch: swatch);

    return [
      if (o.isFilled)
        d('Fill', Icons.circle, '', _Mode.fill, swatch: _fillSwatch(o)),
      if (o.type != ShapeType.image)
        d('Stroke', Icons.line_weight, o.strokeWidth.toStringAsFixed(0),
            _Mode.stroke),
      d('Opacity', Icons.opacity, '${(o.opacity * 100).round()}%',
          _Mode.opacity),
      d('Blend', Icons.gradient, '', _Mode.blend),
      if (m.canNodeEdit(o)) d('Nodes', Icons.timeline, '', _Mode.nodes),
      // Label by what the control actually does for this shape so it's findable:
      // a star edits Points, a polygon edits Sides, everything else rounds Corners.
      if (o.type == ShapeType.star)
        d('Points', Icons.star_border, '${o.points}', _Mode.shape)
      else if (o.type == ShapeType.polygon)
        d('Sides', Icons.pentagon_outlined, '${o.points}', _Mode.shape)
      else if (o.cornerCount > 0)
        d('Corners', Icons.rounded_corner, '', _Mode.shape),
      if (o.type == ShapeType.text)
        d('Type', Icons.text_fields, '', _Mode.type),
      if (o.type == ShapeType.image) d('Crop', Icons.crop, '', _Mode.crop),
      d('Effects', Icons.auto_awesome, '', _Mode.effects),
      // 4-corner perspective distort — for shapes, images and text.
      d('Perspective', Icons.crop_rotate, '', _Mode.perspective),
      d('Layers', Icons.layers_outlined, '', _Mode.layer),
      d('Front', Icons.flip_to_front, '', _Mode.front),
      d('Back', Icons.flip_to_back, '', _Mode.toBack),
    ];
  }

  /// Options shown when a group / multiple objects are selected. Everything here
  /// applies to the WHOLE selection (Fill, Stroke, Effects are collective).
  List<_HaloDef> _defsForMulti(EditorModel m) {
    final objs = m.selectedObjects;
    _HaloDef d(String label, IconData icon, _Mode mode, {Color? swatch}) =>
        _HaloDef(label, icon, '', mode, swatch: swatch);
    final anyFill = objs.any((o) => o.isFilled);
    final anyStroke = objs.any((o) => o.type != ShapeType.image);
    return [
      d(m.selectionHasGroup ? 'Ungroup' : 'Group', Icons.workspaces_outline,
          _Mode.group),
      d('Align', Icons.align_horizontal_center, _Mode.align),
      if (anyFill) d('Fill', Icons.format_color_fill, _Mode.fill),
      if (anyStroke) d('Stroke', Icons.line_weight, _Mode.stroke),
      d('Effects', Icons.auto_awesome, _Mode.effects),
      d('Front', Icons.flip_to_front, _Mode.front),
      d('Back', Icons.flip_to_back, _Mode.toBack),
      d('Layers', Icons.layers_outlined, _Mode.layer),
      // Masked group → bake the clip into the artwork (appears last).
      if (m.selectionHasMask)
        d('Flatten Mask', Icons.layers_clear, _Mode.flattenMask),
    ];
  }

  /// Canvas-level options shown when nothing is selected (item 7).
  List<_HaloDef> _defsForEmpty(EditorModel m) {
    _HaloDef d(String label, IconData icon, _Mode mode) =>
        _HaloDef(label, icon, '', mode);
    return [
      d('Layers', Icons.layers_outlined, _Mode.layer),
      if (m.objects.isNotEmpty)
        d('Select All', Icons.select_all, _Mode.selectAll),
      if (m.hasClipboard) d('Paste', Icons.content_paste, _Mode.paste),
    ];
  }

  Widget _railButton(
      BuildContext context, EditorModel m, ShapeObject? o, _HaloDef def,
      {bool allowDrag = true}) {
    void onTap() {
      switch (def.mode) {
        case _Mode.fill:
          m.openSheet(ActiveSheet.fill);
        case _Mode.crop:
          m.openSheet(ActiveSheet.crop);
        case _Mode.stroke:
          m.openSheet(ActiveSheet.strokes);
        case _Mode.layer:
          m.openSheet(ActiveSheet.layers);
        case _Mode.effects:
          m.openSheet(ActiveSheet.effects);
        case _Mode.shape:
          m.openSheet(ActiveSheet.shapeParams);
        case _Mode.nodes:
          if (o != null) m.enterNodeEdit(o.id);
        case _Mode.perspective:
          if (o != null) m.enterPerspectiveEdit(o.id);
        case _Mode.type:
          m.openSheet(ActiveSheet.typography);
        case _Mode.blend:
          m.openSheet(ActiveSheet.blendModes);
        case _Mode.front:
          m.bringToFront();
        case _Mode.toBack:
          m.sendToBack();
        case _Mode.align:
          m.openSheet(ActiveSheet.align);
        case _Mode.group:
          m.selectionHasGroup ? m.ungroupSelection() : m.groupSelection();
        case _Mode.selectAll:
          m.selectAll();
        case _Mode.paste:
          m.pasteClipboard();
        case _Mode.flattenMask:
          m.flattenMask();
        case _Mode.rotate:
        case _Mode.opacity:
          break; // drag-only
      }
    }

    void onStart(DragStartDetails d) {
      if (o == null) return;
      final ob = o;
      m.beginGesture();
      final c = m.canvasToScreen(ob.center);
      final p = _globalToOverlay(context, d.globalPosition);
      _startRotation = ob.rotation;
      // Curves/paths keep their real width in the stroke stack, so seed the drag
      // from there when present (item 7).
      _startStroke =
          ob.strokes.isNotEmpty ? ob.strokes.first.width : ob.strokeWidth;
      _startAngle = math.atan2((p - c).dy, (p - c).dx);
      _startDist = (p - c).distance;
    }

    void onUpdate(DragUpdateDetails d) {
      if (o == null) return;
      final ob = o;
      final c = m.canvasToScreen(ob.center);
      final p = _globalToOverlay(context, d.globalPosition);
      switch (def.mode) {
        case _Mode.rotate:
          final ang = math.atan2((p - c).dy, (p - c).dx);
          m.mutate(() => ob.rotation = _startRotation + (ang - _startAngle));
          setState(() => _centerLabel = '${ob.rotationDegrees.round()}°');
        case _Mode.opacity:
          m.mutate(() =>
              ob.opacity = (ob.opacity - d.delta.dy / 200).clamp(0.0, 1.0));
          setState(() => _centerLabel = '${(ob.opacity * 100).round()}%');
        case _Mode.stroke:
          final dist = (p - c).distance;
          final w = (_startStroke + (dist - _startDist) / m.zoom * 0.4)
              .clamp(0.0, 100.0);
          m.mutate(() {
            // Apply to every selected object so dragging the Stroke pill works
            // on a whole group, not just the representative (item 7). Curves /
            // paths render from the stroke stack, so keep it in sync too.
            for (final t in m.selectedObjects) {
              t.strokeWidth = w;
              for (final s in t.strokes) {
                s.width = w;
              }
            }
          });
          setState(() => _centerLabel = w.toStringAsFixed(1));
        default:
          break;
      }
    }

    void onEnd(DragEndDetails d) {
      final desc = switch (def.mode) {
        _Mode.rotate => 'Rotate',
        _Mode.opacity => 'Opacity',
        _Mode.stroke => 'Stroke width',
        _ => 'Edit',
      };
      m.commitGesture(desc);
      setState(() => _centerLabel = null);
    }

    // Stroke is draggable for a group/multi-selection too (applies to all),
    // while Rotate/Opacity stay single-object drags (item 7).
    final draggable = (def.mode == _Mode.stroke && o != null) ||
        (allowDrag &&
            (def.mode == _Mode.rotate || def.mode == _Mode.opacity));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        onPanStart: draggable ? onStart : null,
        onPanUpdate: draggable ? onUpdate : null,
        onPanEnd: draggable ? onEnd : null,
        child: Glass(
          layer: GlassLayer.halo,
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label (+ live value) to the left of the icon so the icon sits
              // nearest the screen edge.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(def.label,
                      style: ShapeText.labelSM
                          .copyWith(color: ShapeColors.primaryText)),
                  if (def.value.isNotEmpty)
                    Text(def.value,
                        style: ShapeText.monoSize(9)
                            .copyWith(color: ShapeColors.tertiaryText)),
                ],
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: def.swatch != null
                      ? Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: def.swatch,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: ShapeColors.glassBorderDark, width: 0.5),
                          ),
                        )
                      : Icon(def.icon,
                          size: 18, color: ShapeColors.primaryText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Converts a global pointer position into the overlay/local coordinate space
/// used for screen<->canvas math. The rail fills the same full-screen Stack as
/// the canvas, so its own render box shares the canvas coordinate origin.
Offset _globalToOverlay(BuildContext context, Offset global) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return global;
  return box.globalToLocal(global);
}

enum _Mode {
  rotate,
  stroke,
  layer,
  effects,
  fill,
  crop,
  opacity,
  shape,
  nodes,
  type,
  blend,
  front,
  toBack,
  align,
  group,
  selectAll,
  paste,
  flattenMask,
  perspective,
}

/// A representative swatch color for the Fill pill — the solid color, or the
/// first gradient stop / pattern ink for non-solid fills.
Color _fillSwatch(ShapeObject o) {
  final s = o.fillSpec;
  return switch (s.kind) {
    FillKind.solid => o.fill,
    FillKind.linearGradient ||
    FillKind.radialGradient =>
      s.stops.isEmpty ? o.fill : s.stops.first.color,
    FillKind.pattern => s.patternFg,
  };
}

class _HaloDef {
  _HaloDef(this.label, this.icon, this.value, this.mode, {this.swatch});
  final String label;
  final IconData icon;
  final String value;
  final _Mode mode;
  final Color? swatch;
}
