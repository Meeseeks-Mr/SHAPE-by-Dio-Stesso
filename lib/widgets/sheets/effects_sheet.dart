import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../theme/shape_theme.dart';
import '../color/wheel_picker.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// Effects sheet (§12.5) — Drop Shadow, Inner Shadow, Outer Glow, Inner Glow,
/// Blur. Every control applies to the WHOLE selection so effects can be set on
/// a group collectively.
class EffectsSheet extends StatelessWidget {
  const EffectsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final o = m.singleSelection ?? m.selectedObjects.firstOrNull;
    if (o == null) return const SheetTitle('Effects');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Effects'),
        _ShadowBlock(o: o, get: (x) => x.shadow, label: 'Drop Shadow'),
        _ShadowBlock(
            o: o, get: (x) => x.innerShadow, label: 'Inner Shadow', offset: false),
        _ShadowBlock(
            o: o,
            get: (x) => x.glow,
            label: 'Outer Glow',
            offset: false,
            color: true),
        _ShadowBlock(
            o: o,
            get: (x) => x.innerGlow,
            label: 'Inner Glow',
            offset: false,
            color: true),
        _BlurBlock(o: o),
      ],
    );
  }
}

class _ShadowBlock extends StatefulWidget {
  const _ShadowBlock(
      {required this.o,
      required this.get,
      required this.label,
      this.offset = true,
      this.color = false});

  /// Display target (the spec shown by the sliders). Edits apply to all.
  final ShapeObject o;
  final ShadowSpec Function(ShapeObject) get;
  final String label;
  final bool offset;

  /// When true, shows the colour picker (used by the glow effects).
  final bool color;

  @override
  State<_ShadowBlock> createState() => _ShadowBlockState();
}

class _ShadowBlockState extends State<_ShadowBlock> {
  bool _pickerOpen = false;

  static const _palette = [
    Color(0xFF6C63D6),
    Color(0xFFFFE08A),
    ShapeColors.shapeBlue,
    ShapeColors.rose,
    ShapeColors.mint,
    Color(0xFFFFFFFF),
  ];

  ShadowSpec _get(ShapeObject o) => widget.get(o);

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final s = _get(widget.o);

    // Apply a change to the matching spec on EVERY selected object as a single
    // undo step.
    void editAll(void Function(ShadowSpec s) change) {
      m.beginGesture();
      m.mutate(() {
        for (final obj in m.selectedObjects) {
          change(_get(obj));
        }
      });
      m.commitGesture('Effects');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(widget.label,
              style:
                  ShapeText.labelMD.copyWith(color: ShapeColors.primaryText)),
          const Spacer(),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: s.enabled,
              activeThumbColor: ShapeColors.shapeBlue,
              onChanged: (v) => editAll((sp) => sp.enabled = v),
            ),
          ),
        ]),
        if (s.enabled)
          Column(children: [
            if (widget.offset) ...[
              _slim(m, 'X', s.dx, -60, 60, (sp, v) => sp.dx = v),
              _slim(m, 'Y', s.dy, -60, 60, (sp, v) => sp.dy = v),
            ],
            _slim(m, 'Blur', s.blur, 0, 80, (sp, v) => sp.blur = v),
            _slim(m, 'Opacity', s.color.a, 0, 1,
                (sp, v) => sp.color = sp.color.withValues(alpha: v),
                pct: true),
            if (widget.color) _colorSection(m, s, editAll),
          ]),
        const Divider(height: 14, color: ShapeColors.glassBorderDark),
      ],
    );
  }

  /// Full colour picker for glow colour — the same wheel template used by Fill
  /// and Stroke, tucked behind a swatch so the sheet stays compact. The wheel
  /// changes hue/sat/value; each object keeps its own opacity.
  Widget _colorSection(
      EditorModel m, ShadowSpec s, void Function(void Function(ShadowSpec)) editAll) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
              width: 60,
              child: Text('Colour',
                  style: ShapeText.labelMD
                      .copyWith(color: ShapeColors.secondaryText)),
            ),
            for (final c in _palette)
              GestureDetector(
                onTap: () => editAll(
                    (sp) => sp.color = c.withValues(alpha: sp.color.a)),
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: s.color.toARGB32() ==
                                c.withValues(alpha: s.color.a).toARGB32()
                            ? ShapeColors.shapeBlue
                            : ShapeColors.glassBorderDark,
                        width: s.color.toARGB32() ==
                                c.withValues(alpha: s.color.a).toARGB32()
                            ? 2
                            : 0.5),
                  ),
                ),
              ),
            const Spacer(),
            // Toggle the full wheel picker.
            GestureDetector(
              onTap: () => setState(() => _pickerOpen = !_pickerOpen),
              child: Container(
                width: 30,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _pickerOpen
                      ? ShapeColors.shapeBlue.withValues(alpha: 0.18)
                      : ShapeColors.fieldBase,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune,
                    size: 16,
                    color: _pickerOpen
                        ? ShapeColors.shapeBlue
                        : ShapeColors.secondaryText),
              ),
            ),
          ]),
          if (_pickerOpen)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: WheelColorPicker(
                  size: 168,
                  color: HSVColor.fromColor(s.color.withValues(alpha: 1)),
                  onStart: m.beginGesture,
                  onChanged: (v) => m.mutate(() {
                    final rgb = v.toColor();
                    for (final obj in m.selectedObjects) {
                      final sp = _get(obj);
                      sp.color = rgb.withValues(alpha: sp.color.a);
                    }
                  }),
                  onEnd: () => m.commitGesture('Glow colour'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slim(EditorModel m, String l, double v, double min, double max,
          void Function(ShadowSpec s, double v) set,
          {bool pct = false}) =>
      LabeledSlider(
        label: l,
        value: v.clamp(min, max),
        min: min,
        max: max,
        display: pct ? '${(v * 100).round()}%' : v.toStringAsFixed(0),
        onStart: m.beginGesture,
        onChanged: (x) => m.mutate(() {
          for (final obj in m.selectedObjects) {
            set(_get(obj), x);
          }
        }),
        onEnd: () => m.commitGesture('Effects'),
      );
}

class _BlurBlock extends StatelessWidget {
  const _BlurBlock({required this.o});
  final ShapeObject o;
  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    return LabeledSlider(
      label: 'Blur',
      value: o.blurAmount,
      min: 0,
      max: 40,
      display: o.blurAmount.toStringAsFixed(0),
      onStart: m.beginGesture,
      onChanged: (v) => m.mutate(() {
        for (final obj in m.selectedObjects) {
          obj.blurAmount = v;
        }
      }),
      onEnd: () => m.commitGesture('Blur'),
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
