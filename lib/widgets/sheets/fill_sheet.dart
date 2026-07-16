import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../theme/shape_theme.dart';
import '../color/wheel_picker.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// Fill sheet — §12.3. Three tabs: Solid (the Affinity-style wheel picker with
/// hex, opacity, recents + saved palette), Gradient (linear/radial with a stop
/// editor + angle), and Pattern (built-in tiling motifs with two colors).
class FillSheet extends StatefulWidget {
  const FillSheet({super.key});
  @override
  State<FillSheet> createState() => _FillSheetState();
}

class _FillSheetState extends State<FillSheet> {
  HSVColor? _hsv;
  // Which gradient stop / pattern color is currently being edited by the wheel.
  int _editStop = 0;
  int _patternTarget = 0; // 0 foreground, 1 background

  ShapeObject? _obj(EditorModel m) =>
      m.selectedObjects.isEmpty ? null : m.selectedObjects.first;

  FillKind _kind(EditorModel m) => _obj(m)?.fillSpec.kind ?? FillKind.solid;

  // ---- Solid color helpers ----------------------------------------------
  HSVColor _current(EditorModel m) {
    if (_hsv != null) return _hsv!;
    final o = _obj(m);
    return HSVColor.fromColor(o != null ? o.fill : ShapeColors.lavender);
  }

  void _apply(EditorModel m, HSVColor c, {bool commit = false}) {
    final color = c.toColor();
    m.mutate(() {
      for (final o in m.selectedObjects) {
        o.fill = color;
      }
    });
    setState(() => _hsv = c);
    if (commit) m.commitGesture('Fill');
  }

  // ---- Fill-type switching ----------------------------------------------
  void _setKind(EditorModel m, FillKind kind) {
    m.beginGesture();
    m.mutate(() {
      for (final o in m.selectedObjects) {
        // Tapping the Gradient tab keeps an existing radial gradient as radial.
        if (kind == FillKind.linearGradient &&
            o.fillSpec.kind == FillKind.radialGradient) {
          continue;
        }
        o.fillSpec.kind = kind;
        // Seed a sensible gradient from the current solid color the first time.
        if ((kind == FillKind.linearGradient ||
                kind == FillKind.radialGradient) &&
            o.fillSpec.stops.length < 2) {
          o.fillSpec.stops = [
            GradientStop(0, o.fill),
            GradientStop(1, ShapeColors.sky),
          ];
        }
      }
    });
    m.commitGesture('Fill type');
    setState(() {
      _hsv = null;
      _editStop = 0;
    });
  }

  /// Live-edit a fill spec across the whole selection.
  void _editSpec(EditorModel m, void Function(FillSpec s) change,
      {bool commit = true}) {
    if (commit) m.beginGesture();
    m.mutate(() {
      for (final o in m.selectedObjects) {
        change(o.fillSpec);
      }
    });
    if (commit) m.commitGesture('Fill');
  }

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final kind = _kind(m);
    final selected = switch (kind) {
      FillKind.solid => 0,
      FillKind.linearGradient || FillKind.radialGradient => 1,
      FillKind.pattern => 2,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Fill'),
        Segmented(
          options: const ['Solid', 'Gradient', 'Pattern'],
          selected: selected,
          onChanged: (i) => _setKind(
              m,
              switch (i) {
                0 => FillKind.solid,
                1 => FillKind.linearGradient,
                _ => FillKind.pattern,
              }),
        ),
        const SizedBox(height: 12),
        switch (selected) {
          0 => _buildSolid(m),
          1 => _buildGradient(m),
          _ => _buildPattern(m),
        },
      ],
    );
  }

  // ---- Solid tab --------------------------------------------------------
  Widget _buildSolid(EditorModel m) {
    final c = _current(m);
    final hex =
        '#${c.toColor().toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: WheelColorPicker(
            size: 184,
            color: c,
            onStart: m.beginGesture,
            onChanged: (v) => _apply(m, v),
            onEnd: () => _apply(m, _current(m), commit: true),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.toColor(),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: ShapeColors.glassBorderDark, width: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          Text(hex, style: ShapeText.monoSize(16)),
          const Spacer(),
          GestureDetector(
            onTap: () => m.saveColor(c.toColor()),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ShapeColors.fieldBase,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.bookmark_add_outlined,
                    size: 16, color: ShapeColors.shapeBlue),
                const SizedBox(width: 6),
                Text('Save',
                    style: ShapeText.labelMD
                        .copyWith(color: ShapeColors.shapeBlue)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        LabeledSlider(
          label: 'Opacity',
          value: c.alpha,
          min: 0,
          max: 1,
          display: '${(c.alpha * 100).round()}%',
          onStart: m.beginGesture,
          onChanged: (v) => _apply(m, c.withAlpha(v)),
          onEnd: () => _apply(m, _current(m), commit: true),
        ),
        const SizedBox(height: 8),
        _Swatches(
          label: 'Recent',
          colors: recentFillColors,
          onPick: (color) {
            m.beginGesture();
            _apply(m, HSVColor.fromColor(color), commit: true);
            _remember(color);
          },
        ),
        if (m.savedColors.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Swatches(
            label: 'Palette',
            colors: m.savedColors,
            onPick: (color) {
              m.beginGesture();
              _apply(m, HSVColor.fromColor(color), commit: true);
            },
            onLongPress: m.removeSavedColor,
          ),
        ],
      ],
    );
  }

  // ---- Gradient tab -----------------------------------------------------
  Widget _buildGradient(EditorModel m) {
    final o = _obj(m);
    if (o == null) return const SizedBox.shrink();
    final spec = o.fillSpec;
    final stops = spec.stops;
    _editStop = _editStop.clamp(0, stops.length - 1);
    final active = stops[_editStop];
    final hsv = HSVColor.fromColor(active.color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Linear / radial toggle.
        Segmented(
          options: const ['Linear', 'Radial'],
          selected: spec.kind == FillKind.radialGradient ? 1 : 0,
          onChanged: (i) => _editSpec(
              m,
              (s) => s.kind = i == 1
                  ? FillKind.radialGradient
                  : FillKind.linearGradient),
        ),
        const SizedBox(height: 12),

        // Live gradient preview bar with tappable stop handles.
        _GradientBar(
          spec: spec,
          activeIndex: _editStop,
          onSelect: (i) => setState(() => _editStop = i),
          onMove: (i, pos) => _editSpec(
              m, (s) => s.stops[i].pos = pos.clamp(0.0, 1.0),
              commit: false),
          onCommit: () => m.commitGesture('Gradient'),
          onBegin: m.beginGesture,
        ),
        const SizedBox(height: 10),

        Row(children: [
          _MiniButton(
            icon: Icons.add,
            label: 'Add stop',
            onTap: () {
              final mid = stops.length < 2
                  ? 0.5
                  : ((stops[stops.length - 1].pos + stops[0].pos) / 2);
              _editSpec(m, (s) {
                s.stops.add(GradientStop(mid, active.color));
                s.stops.sort((a, b) => a.pos.compareTo(b.pos));
              });
              setState(() {});
            },
          ),
          const SizedBox(width: 8),
          _MiniButton(
            icon: Icons.remove,
            label: 'Remove',
            enabled: stops.length > 2,
            onTap: stops.length > 2
                ? () {
                    _editSpec(m, (s) => s.stops.removeAt(
                        _editStop.clamp(0, s.stops.length - 1)));
                    setState(() => _editStop = 0);
                  }
                : null,
          ),
        ]),
        const SizedBox(height: 10),

        // Per-stop color picker (reuses the wheel picker).
        Center(
          child: WheelColorPicker(
            size: 168,
            color: hsv,
            onStart: m.beginGesture,
            onChanged: (v) => _editSpec(
                m, (s) => s.stops[_editStop].color = v.toColor(),
                commit: false),
            onEnd: () => m.commitGesture('Gradient'),
          ),
        ),
        const SizedBox(height: 10),

        if (spec.kind == FillKind.linearGradient)
          LabeledSlider(
            label: 'Angle',
            value: (spec.angle * 180 / math.pi) % 360,
            min: 0,
            max: 360,
            display: '${((spec.angle * 180 / math.pi) % 360).round()}°',
            onStart: m.beginGesture,
            onChanged: (v) => _editSpec(
                m, (s) => s.angle = v * math.pi / 180,
                commit: false),
            onEnd: () => m.commitGesture('Gradient angle'),
          ),
      ],
    );
  }

  // ---- Pattern tab ------------------------------------------------------
  Widget _buildPattern(EditorModel m) {
    final o = _obj(m);
    if (o == null) return const SizedBox.shrink();
    final spec = o.fillSpec;
    final target =
        _patternTarget == 0 ? spec.patternFg : spec.patternBg;
    final hsv = HSVColor.fromColor(target);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pattern',
            style:
                ShapeText.labelSM.copyWith(color: ShapeColors.secondaryText)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final p in PatternId.values)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => _editSpec(m, (s) => s.pattern = p),
                  child: _PatternSwatch(
                    pattern: p,
                    fg: spec.patternFg,
                    bg: spec.patternBg,
                    selected: spec.pattern == p,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // Foreground / background color target toggle.
        Segmented(
          options: const ['Ink', 'Paper'],
          selected: _patternTarget,
          onChanged: (i) => setState(() => _patternTarget = i),
        ),
        const SizedBox(height: 12),
        Center(
          child: WheelColorPicker(
            size: 168,
            color: hsv,
            onStart: m.beginGesture,
            onChanged: (v) => _editSpec(m, (s) {
              if (_patternTarget == 0) {
                s.patternFg = v.toColor();
              } else {
                s.patternBg = v.toColor();
              }
            }, commit: false),
            onEnd: () => m.commitGesture('Pattern'),
          ),
        ),
        const SizedBox(height: 10),
        LabeledSlider(
          label: 'Scale',
          value: spec.patternScale.clamp(0.4, 4.0),
          min: 0.4,
          max: 4.0,
          display: '${(spec.patternScale * 100).round()}%',
          onStart: m.beginGesture,
          onChanged: (v) =>
              _editSpec(m, (s) => s.patternScale = v, commit: false),
          onEnd: () => m.commitGesture('Pattern scale'),
        ),
      ],
    );
  }

  void _remember(Color color) {
    recentFillColors.removeWhere((x) => x.toARGB32() == color.toARGB32());
    recentFillColors.insert(0, color);
    if (recentFillColors.length > 16) recentFillColors.removeLast();
  }
}

/// Module-level recent-colors store (§12.3 Section 3).
final List<Color> recentFillColors = <Color>[
  ShapeColors.lavender,
  ShapeColors.mint,
  ShapeColors.peach,
  ShapeColors.rose,
  ShapeColors.sky,
  ShapeColors.butter,
];

/// Small labeled pill button used by the gradient stop controls.
class _MiniButton extends StatelessWidget {
  const _MiniButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.enabled = true});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ShapeColors.fieldBase,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: ShapeColors.shapeBlue),
            const SizedBox(width: 6),
            Text(label,
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.shapeBlue)),
          ]),
        ),
      ),
    );
  }
}

/// Interactive linear preview of the gradient with draggable stop handles.
class _GradientBar extends StatelessWidget {
  const _GradientBar({
    required this.spec,
    required this.activeIndex,
    required this.onSelect,
    required this.onMove,
    required this.onBegin,
    required this.onCommit,
  });
  final FillSpec spec;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final void Function(int index, double pos) onMove;
  final VoidCallback onBegin;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final sorted = [...spec.stops]..sort((a, b) => a.pos.compareTo(b.pos));
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Gradient track.
            Positioned.fill(
              bottom: 16,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: ShapeColors.glassBorderDark, width: 0.5),
                  gradient: LinearGradient(
                    colors: [for (final s in sorted) s.color],
                    stops: [for (final s in sorted) s.pos.clamp(0.0, 1.0)],
                  ),
                ),
              ),
            ),
            // Stop handles.
            for (var i = 0; i < spec.stops.length; i++)
              Positioned(
                left: (spec.stops[i].pos.clamp(0.0, 1.0) * w - 9)
                    .clamp(0.0, w - 18),
                bottom: 0,
                child: GestureDetector(
                  onTapDown: (_) => onSelect(i),
                  onHorizontalDragStart: (_) {
                    onSelect(i);
                    onBegin();
                  },
                  onHorizontalDragUpdate: (d) => onMove(
                      i, spec.stops[i].pos + d.delta.dx / (w == 0 ? 1 : w)),
                  onHorizontalDragEnd: (_) => onCommit(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_drop_up,
                          size: 18,
                          color: i == activeIndex
                              ? ShapeColors.shapeBlue
                              : ShapeColors.tertiaryText),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: spec.stops[i].color,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: i == activeIndex
                                  ? ShapeColors.shapeBlue
                                  : Colors.white,
                              width: 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// A small preview tile rendering a built-in pattern.
class _PatternSwatch extends StatelessWidget {
  const _PatternSwatch({
    required this.pattern,
    required this.fg,
    required this.bg,
    required this.selected,
  });
  final PatternId pattern;
  final Color fg;
  final Color bg;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected ? ShapeColors.shapeBlue : ShapeColors.glassBorderDark,
            width: selected ? 2 : 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _PatternPainter(pattern, fg, bg)),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.pattern, this.fg, this.bg);
  final PatternId pattern;
  final Color fg;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = bg);
    final p = Paint()
      ..color = fg
      ..isAntiAlias = true;
    const step = 12.0;
    switch (pattern) {
      case PatternId.dots:
        for (var y = 0.0; y <= size.height + step; y += step) {
          for (var x = 0.0; x <= size.width + step; x += step) {
            canvas.drawCircle(Offset(x, y), step * 0.22, p);
          }
        }
      case PatternId.stripes:
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = step * 0.4;
        for (var d = -size.height; d <= size.width + size.height; d += step) {
          canvas.drawLine(
              Offset(d, 0), Offset(d - size.height, size.height), p);
        }
      case PatternId.grid:
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (var x = 0.0; x <= size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (var y = 0.0; y <= size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case PatternId.checker:
        var row = 0;
        for (var y = 0.0; y <= size.height; y += step) {
          for (var x = 0.0; x <= size.width; x += step) {
            final col = (x / step).floor();
            if ((col + row).isEven) {
              canvas.drawRect(Rect.fromLTWH(x, y, step, step), p);
            }
          }
          row++;
        }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.pattern != pattern || old.fg != fg || old.bg != bg;
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.label,
    required this.colors,
    required this.onPick,
    this.onLongPress,
  });
  final String label;
  final List<Color> colors;
  final ValueChanged<Color> onPick;
  final ValueChanged<Color>? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                ShapeText.labelSM.copyWith(color: ShapeColors.secondaryText)),
        const SizedBox(height: 8),
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: colors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => onPick(colors[i]),
              onLongPress:
                  onLongPress == null ? null : () => onLongPress!(colors[i]),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: ShapeColors.glassBorderDark, width: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
