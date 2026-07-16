import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// The Corners sheet: polygon sides, star points + inner ratio, a shortcut to
/// reveal the curve nodes, and corner rounding with a combined/independent
/// toggle.
class ShapeParamsSheet extends StatelessWidget {
  const ShapeParamsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final o = m.singleSelection;
    if (o == null) return const SheetTitle('Corners');
    final isPolyStar =
        o.type == ShapeType.polygon || o.type == ShapeType.star;
    final title = o.type == ShapeType.star
        ? 'Points'
        : o.type == ShapeType.polygon
            ? 'Sides'
            : 'Corners';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetTitle(title),
        // Option 1: reveal/edit the curve (path) nodes for this shape.
        if (m.canNodeEdit(o))
          GestureDetector(
            onTap: () {
              final id = o.id;
              m.closeSheet();
              m.enterNodeEdit(id);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: ShapeColors.fieldBase,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.timeline,
                    size: 18, color: ShapeColors.shapeBlue),
                const SizedBox(width: 10),
                Text('Show curve nodes',
                    style: ShapeText.labelMD
                        .copyWith(color: ShapeColors.primaryText)),
                const Spacer(),
                const Icon(Icons.chevron_right,
                    size: 18, color: ShapeColors.tertiaryText),
              ]),
            ),
          ),
        if (isPolyStar)
          LabeledSlider(
            label: o.type == ShapeType.star ? 'Points' : 'Sides',
            value: o.points.toDouble().clamp(3, 100),
            min: 3,
            max: 100,
            display: '${o.points}',
            onStart: m.beginGesture,
            onChanged: (v) => m.setShapeParamsLive(sides: v.round()),
            onEnd: () => m.commitGesture('Shape'),
          ),
        if (o.type == ShapeType.star)
          LabeledSlider(
            label: 'Inner',
            value: o.starInner,
            min: 0.05,
            max: 0.95,
            display: '${(o.starInner * 100).round()}%',
            onStart: m.beginGesture,
            onChanged: (v) => m.setShapeParamsLive(starInner: v),
            onEnd: () => m.commitGesture('Shape'),
          ),
        if (o.cornerCount > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Rounding',
                  style: ShapeText.labelMD
                      .copyWith(color: ShapeColors.secondaryText)),
              const Spacer(),
              Text(o.cornersLinked ? 'Combined' : 'Independent',
                  style: ShapeText.labelSM
                      .copyWith(color: ShapeColors.tertiaryText)),
              const SizedBox(width: 8),
              Switch(
                value: !o.cornersLinked,
                activeThumbColor: ShapeColors.shapeBlue,
                onChanged: (v) => m.setCornerLinked(!v),
              ),
            ],
          ),
          if (o.cornersLinked)
            LabeledSlider(
              label: 'Radius',
              value: o.cornerRadius,
              min: 0,
              max: (o.size.shortestSide / 2),
              display: o.cornerRadius.toStringAsFixed(0),
              onStart: m.beginGesture,
              onChanged: (v) => m.setCorner(0, v),
              onEnd: () => m.commitGesture('Corner radius'),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Drag the amber node on each corner to round it.',
                  style: ShapeText.labelSM
                      .copyWith(color: ShapeColors.tertiaryText)),
            ),
        ],
      ],
    );
  }
}
