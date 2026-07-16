import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../theme/shape_theme.dart';
import '../color/wheel_picker.dart';
import 'controls.dart';
import 'fill_sheet.dart' show recentFillColors;
import 'sheet_host.dart';

/// Multiple-strokes appearance module (item 13) — add / remove / edit a stack
/// of strokes per object, like Illustrator's Appearance panel. Each stroke now
/// has the full HSV colour picker AND optional gradient paint (item 2).
class StrokesSheet extends StatefulWidget {
  const StrokesSheet({super.key});

  @override
  State<StrokesSheet> createState() => _StrokesSheetState();
}

class _StrokesSheetState extends State<StrokesSheet> {
  // Which stroke row currently has its colour editor open (-1 = none), and the
  // active gradient stop within that editor.
  int _expanded = -1;
  int _editStop = 0;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final o = m.styleTarget;
    if (o == null) return const SheetTitle('Strokes');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const SheetTitle('Strokes'),
          const Spacer(),
          GestureDetector(
            onTap: m.addStroke,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: ShapeColors.shapeBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.add, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Text('Add',
                    style: ShapeText.labelSM.copyWith(color: Colors.white)),
              ]),
            ),
          ),
        ]),
        if (o.strokes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No strokes yet. Add one to start stacking.',
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.secondaryText)),
          ),
        for (var i = 0; i < o.strokes.length; i++) _strokeRow(m, o, i),
      ],
    );
  }

  // ---- One stroke row ----------------------------------------------------
  Widget _strokeRow(EditorModel m, ShapeObject o, int index) {
    final s = o.strokes[index];
    final expanded = _expanded == index;

    void edit(void Function() change) {
      m.beginGesture();
      m.mutate(() {
        change();
        m.mirrorStrokesToSelection(o);
      });
      m.commitGesture('Stroke');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ShapeColors.fieldBase,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(children: [
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: s.enabled,
                activeThumbColor: ShapeColors.shapeBlue,
                onChanged: (v) => edit(() => s.enabled = v),
              ),
            ),
            // Colour swatch — tap to open the full picker for this stroke.
            GestureDetector(
              onTap: () => setState(() {
                _expanded = expanded ? -1 : index;
                _editStop = 0;
              }),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: s.hasGradient
                      ? LinearGradient(
                          colors: [
                            for (final st in s.paintFill!.stops) st.color
                          ],
                        )
                      : null,
                  color: s.hasGradient ? null : s.color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: expanded
                          ? ShapeColors.shapeBlue
                          : ShapeColors.glassBorderDark,
                      width: expanded ? 2 : 0.5),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(s.hasGradient ? 'Gradient' : 'Colour',
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.secondaryText)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                if (_expanded == index) setState(() => _expanded = -1);
                m.removeStroke(index);
              },
              child: const Icon(Icons.delete_outline,
                  size: 18, color: ShapeColors.destructive),
            ),
          ]),
          if (expanded) _colorEditor(m, o, s),
          LabeledSlider(
            label: 'Width',
            value: s.width,
            min: 0,
            max: 60,
            display: s.width.toStringAsFixed(1),
            onStart: m.beginGesture,
            onChanged: (v) => m.mutate(() {
              s.width = v;
              m.mirrorStrokesToSelection(o);
            }),
            onEnd: () => m.commitGesture('Stroke'),
          ),
          IconChoiceRow(
            label: 'Align',
            icons: const [
              Icons.vertical_align_center,
              Icons.format_indent_increase,
              Icons.format_indent_decrease
            ],
            selected: s.align,
            onChanged: (i) => edit(() => s.align = i),
          ),
          // Width profile (taper) only applies to outlined paths, not glyphs.
          if (o.type != ShapeType.text)
            IconChoiceRow(
              label: 'Width profile',
              icons: const [
                Icons.horizontal_rule, // uniform
                Icons.play_arrow, // taper in (thin → thick)
                Icons.play_arrow_outlined, // taper out (thick → thin)
                Icons.change_history, // pointed ends
                Icons.diamond_outlined, // pinch (thick ends)
              ],
              selected: s.profile,
              onChanged: (i) => edit(() => s.profile = i),
            ),
        ],
      ),
    );
  }

  // ---- Expanded colour / gradient editor --------------------------------
  Widget _colorEditor(EditorModel m, ShapeObject o, StrokeSpec s) {
    final isGradient = s.hasGradient;

    void mirror() => m.mirrorStrokesToSelection(o);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Segmented(
            options: const ['Solid', 'Gradient'],
            selected: isGradient ? 1 : 0,
            onChanged: (i) {
              m.beginGesture();
              m.mutate(() {
                if (i == 0) {
                  s.paintFill = null;
                } else {
                  // Seed a 2-stop linear gradient from the current colour.
                  s.paintFill = FillSpec(
                    kind: FillKind.linearGradient,
                    stops: [
                      GradientStop(0, s.color),
                      GradientStop(1, ShapeColors.sky),
                    ],
                  );
                }
                mirror();
              });
              m.commitGesture('Stroke paint');
              setState(() => _editStop = 0);
            },
          ),
          const SizedBox(height: 10),
          if (!isGradient)
            _solidEditor(m, o, s, mirror)
          else
            _gradientEditor(m, o, s, mirror),
        ],
      ),
    );
  }

  Widget _solidEditor(
      EditorModel m, ShapeObject o, StrokeSpec s, VoidCallback mirror) {
    final hsv = HSVColor.fromColor(s.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: WheelColorPicker(
            size: 168,
            color: hsv,
            onStart: m.beginGesture,
            onChanged: (v) => m.mutate(() {
              s.color = v.toColor();
              mirror();
            }),
            onEnd: () => m.commitGesture('Stroke colour'),
          ),
        ),
        const SizedBox(height: 8),
        _RecentRow(
          onPick: (c) {
            m.beginGesture();
            m.mutate(() {
              s.color = c;
              mirror();
            });
            m.commitGesture('Stroke colour');
          },
        ),
      ],
    );
  }

  Widget _gradientEditor(
      EditorModel m, ShapeObject o, StrokeSpec s, VoidCallback mirror) {
    final spec = s.paintFill!;
    final stops = spec.stops;
    _editStop = _editStop.clamp(0, stops.length - 1);
    final active = stops[_editStop];
    final hsv = HSVColor.fromColor(active.color);

    void editSpec(void Function() change, {bool commit = true}) {
      if (commit) m.beginGesture();
      m.mutate(() {
        change();
        mirror();
      });
      if (commit) m.commitGesture('Stroke gradient');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Segmented(
          options: const ['Linear', 'Radial'],
          selected: spec.kind == FillKind.radialGradient ? 1 : 0,
          onChanged: (i) => editSpec(() => spec.kind =
              i == 1 ? FillKind.radialGradient : FillKind.linearGradient),
        ),
        const SizedBox(height: 10),
        // Gradient preview (stops must be ascending for the LinearGradient).
        Builder(builder: (_) {
          final sorted = [...stops]..sort((a, b) => a.pos.compareTo(b.pos));
          return Container(
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: ShapeColors.glassBorderDark, width: 0.5),
              gradient: LinearGradient(
                colors: [for (final st in sorted) st.color],
                stops: [for (final st in sorted) st.pos.clamp(0.0, 1.0)],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        // Stop selector chips.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < stops.length; i++)
              GestureDetector(
                onTap: () => setState(() => _editStop = i),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: stops[i].color,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: i == _editStop
                            ? ShapeColors.shapeBlue
                            : ShapeColors.glassBorderDark,
                        width: i == _editStop ? 2 : 0.5),
                  ),
                ),
              ),
            // Add stop.
            GestureDetector(
              onTap: () {
                editSpec(() {
                  spec.stops.add(GradientStop(0.5, active.color));
                  spec.stops.sort((a, b) => a.pos.compareTo(b.pos));
                });
                setState(() {});
              },
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: ShapeColors.fieldBase,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: ShapeColors.glassBorderDark, width: 0.5),
                ),
                child: const Icon(Icons.add,
                    size: 16, color: ShapeColors.shapeBlue),
              ),
            ),
            if (stops.length > 2)
              GestureDetector(
                onTap: () {
                  editSpec(() =>
                      spec.stops.removeAt(_editStop.clamp(0, stops.length - 1)));
                  setState(() => _editStop = 0);
                },
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: ShapeColors.fieldBase,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: ShapeColors.glassBorderDark, width: 0.5),
                  ),
                  child: const Icon(Icons.remove,
                      size: 16, color: ShapeColors.destructive),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: WheelColorPicker(
            size: 160,
            color: hsv,
            onStart: m.beginGesture,
            onChanged: (v) =>
                editSpec(() => active.color = v.toColor(), commit: false),
            onEnd: () => m.commitGesture('Stroke gradient'),
          ),
        ),
        const SizedBox(height: 6),
        LabeledSlider(
          label: 'Position',
          value: active.pos.clamp(0.0, 1.0),
          min: 0,
          max: 1,
          display: '${(active.pos * 100).round()}%',
          onStart: m.beginGesture,
          onChanged: (v) =>
              editSpec(() => active.pos = v.clamp(0.0, 1.0), commit: false),
          onEnd: () => m.commitGesture('Stroke gradient'),
        ),
        if (spec.kind == FillKind.linearGradient)
          LabeledSlider(
            label: 'Angle',
            value: (spec.angle * 180 / math.pi) % 360,
            min: 0,
            max: 360,
            display: '${((spec.angle * 180 / math.pi) % 360).round()}°',
            onStart: m.beginGesture,
            onChanged: (v) =>
                editSpec(() => spec.angle = v * math.pi / 180, commit: false),
            onEnd: () => m.commitGesture('Stroke gradient'),
          ),
      ],
    );
  }
}

/// A compact recent-colours strip shared with the Fill sheet's store.
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.onPick});
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recentFillColors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => onPick(recentFillColors[i]),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: recentFillColors[i],
              shape: BoxShape.circle,
              border:
                  Border.all(color: ShapeColors.glassBorderDark, width: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
