import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// Crop sheet for image objects — adjusts the normalized source rect (§ images).
class CropSheet extends StatelessWidget {
  const CropSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final o = m.singleSelection;
    if (o == null || o.type.name != 'image') {
      return const SheetTitle('Crop');
    }
    final c = o.crop;

    void apply(Rect r) {
      m.mutate(() => o.crop = r);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Crop'),
        LabeledSlider(
          label: 'Left',
          value: c.left,
          min: 0,
          max: 0.9,
          display: '${(c.left * 100).round()}%',
          onStart: m.beginGesture,
          onChanged: (v) =>
              apply(Rect.fromLTRB(v, c.top, c.right.clamp(v + 0.05, 1), c.bottom)),
          onEnd: () => m.commitGesture('Crop'),
        ),
        LabeledSlider(
          label: 'Right',
          value: c.right,
          min: 0.1,
          max: 1,
          display: '${(c.right * 100).round()}%',
          onStart: m.beginGesture,
          onChanged: (v) => apply(
              Rect.fromLTRB(c.left.clamp(0, v - 0.05), c.top, v, c.bottom)),
          onEnd: () => m.commitGesture('Crop'),
        ),
        LabeledSlider(
          label: 'Top',
          value: c.top,
          min: 0,
          max: 0.9,
          display: '${(c.top * 100).round()}%',
          onStart: m.beginGesture,
          onChanged: (v) => apply(
              Rect.fromLTRB(c.left, v, c.right, c.bottom.clamp(v + 0.05, 1))),
          onEnd: () => m.commitGesture('Crop'),
        ),
        LabeledSlider(
          label: 'Bottom',
          value: c.bottom,
          min: 0.1,
          max: 1,
          display: '${(c.bottom * 100).round()}%',
          onStart: m.beginGesture,
          onChanged: (v) => apply(
              Rect.fromLTRB(c.left, c.top.clamp(0, v - 0.05), c.right, v)),
          onEnd: () => m.commitGesture('Crop'),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {
              m.beginGesture();
              m.mutate(() => o.crop = const Rect.fromLTRB(0, 0, 1, 1));
              m.commitGesture('Crop');
            },
            child: Text('Reset',
                style:
                    ShapeText.labelMD.copyWith(color: ShapeColors.shapeBlue)),
          ),
        ),
      ],
    );
  }
}
