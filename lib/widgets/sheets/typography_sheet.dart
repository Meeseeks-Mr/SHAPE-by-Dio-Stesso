import 'package:flutter/material.dart';

import '../../canvas/canvas_painter.dart';
import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../theme/fonts.dart';
import '../../theme/shape_theme.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// Typography sheet (§15) — a comprehensive type panel: a large free-font
/// catalog with live previews, size, weight, italic, alignment, and horizontal
/// (letter) + vertical (line-height) spacing.
class TypographySheet extends StatelessWidget {
  const TypographySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final o = m.singleSelection;
    if (o == null || o.type != ShapeType.text) {
      return const SheetTitle('Typography');
    }

    void resizeToFit() {
      final tp = textPainterFor(o);
      o.size = Size(o.size.width, tp.height);
    }

    void set(String desc, void Function() change) {
      m.beginGesture();
      m.mutate(() {
        change();
        resizeToFit();
      });
      m.commitGesture(desc);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Typography'),

        // ---- Font family catalog (grouped, live preview) ----
        _FontPicker(o: o, onPick: (f) => set('Font', () => o.fontFamily = f)),
        const SizedBox(height: 10),

        // ---- Size ----
        LabeledSlider(
          label: 'Size',
          value: o.fontSize,
          min: 8,
          max: 240,
          display: o.fontSize.toStringAsFixed(0),
          onStart: m.beginGesture,
          onChanged: (v) => m.mutate(() {
            o.fontSize = v;
            resizeToFit();
          }),
          onEnd: () => m.commitGesture('Font size'),
        ),
        // ---- Letter spacing (horizontal) ----
        LabeledSlider(
          label: 'Letter',
          value: o.letterSpacing,
          min: -4,
          max: 24,
          display: o.letterSpacing.toStringAsFixed(1),
          onStart: m.beginGesture,
          onChanged: (v) => m.mutate(() {
            o.letterSpacing = v;
            resizeToFit();
          }),
          onEnd: () => m.commitGesture('Letter spacing'),
        ),
        // ---- Line height (vertical) ----
        LabeledSlider(
          label: 'Line',
          value: o.lineHeight,
          min: 0.8,
          max: 3.0,
          display: o.lineHeight.toStringAsFixed(2),
          onStart: m.beginGesture,
          onChanged: (v) => m.mutate(() {
            o.lineHeight = v;
            resizeToFit();
          }),
          onEnd: () => m.commitGesture('Line height'),
        ),
        const SizedBox(height: 6),

        // ---- Alignment ----
        IconChoiceRow(
          label: 'Align',
          icons: const [
            Icons.format_align_left,
            Icons.format_align_center,
            Icons.format_align_right,
            Icons.format_align_justify,
          ],
          selected: o.textAlignH,
          onChanged: (i) => set('Align', () => o.textAlignH = i),
        ),
        const SizedBox(height: 10),

        // ---- Weight + Italic ----
        Text('Weight',
            style:
                ShapeText.labelSM.copyWith(color: ShapeColors.secondaryText)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [300, 400, 500, 600, 700, 800, 900].map((w) {
                  final selected = o.fontWeight == w;
                  return GestureDetector(
                    onTap: () => set('Font weight', () => o.fontWeight = w),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? ShapeColors.shapeBlue.withValues(alpha: 0.18)
                            : ShapeColors.fieldBase,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selected
                                ? ShapeColors.shapeBlue
                                : Colors.transparent,
                            width: 1),
                      ),
                      child: Text('$w',
                          style: ShapeText.labelMD.copyWith(
                              color: ShapeColors.primaryText,
                              fontWeight: FontWeight.values[(w ~/ 100 - 1)])),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => set('Italic', () => o.italic = !o.italic),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 40,
                height: 36,
                decoration: BoxDecoration(
                  color: o.italic
                      ? ShapeColors.shapeBlue.withValues(alpha: 0.18)
                      : ShapeColors.fieldBase,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: o.italic
                          ? ShapeColors.shapeBlue
                          : Colors.transparent,
                      width: 1),
                ),
                child: Icon(Icons.format_italic,
                    size: 18,
                    color: o.italic
                        ? ShapeColors.shapeBlue
                        : ShapeColors.secondaryText),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Horizontal, grouped font catalog. Each chip previews its own typeface.
class _FontPicker extends StatelessWidget {
  const _FontPicker({required this.o, required this.onPick});
  final ShapeObject o;
  final void Function(String?) onPick;

  TextStyle _preview(String family) => FontCatalog.preview(family);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Font',
            style:
                ShapeText.labelSM.copyWith(color: ShapeColors.secondaryText)),
        const SizedBox(height: 6),
        SizedBox(
          height: 116,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: [
              for (final entry in FontCatalog.groups.entries) ...[
                _CategoryColumn(
                  label: entry.key,
                  families: entry.key == FontCatalog.groups.keys.first
                      ? [FontCatalog.defaultFamily, ...entry.value]
                      : entry.value,
                  current: o.fontFamily ?? FontCatalog.defaultFamily,
                  preview: _preview,
                  onPick: onPick,
                ),
                const SizedBox(width: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({
    required this.label,
    required this.families,
    required this.current,
    required this.preview,
    required this.onPick,
  });
  final String label;
  final List<String> families;
  final String current;
  final TextStyle Function(String) preview;
  final void Function(String?) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: ShapeText.labelXS.copyWith(
                color: ShapeColors.tertiaryText,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final f in families)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () =>
                        onPick(f == FontCatalog.defaultFamily ? null : f),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 96),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: current == f
                            ? ShapeColors.shapeBlue.withValues(alpha: 0.16)
                            : ShapeColors.fieldBase,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: current == f
                                ? ShapeColors.shapeBlue
                                : Colors.transparent,
                            width: 1),
                      ),
                      child: Text(
                        f == FontCatalog.defaultFamily ? 'Default' : f,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: preview(f),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
