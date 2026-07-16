import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// Illustrator-style Blend (morph): N interpolated steps between two objects.
class BlendStepsSheet extends StatefulWidget {
  const BlendStepsSheet({super.key});
  @override
  State<BlendStepsSheet> createState() => _BlendStepsSheetState();
}

class _BlendStepsSheetState extends State<BlendStepsSheet> {
  int _steps = 5;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final ok = m.canBlend;
    final alongPath = m.selection.length == 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Morph'),
        Text(
          ok
              ? (alongPath
                  ? 'Creates $_steps shapes morphing between the two shapes, '
                      'distributed along the selected path (start & end shapes '
                      'snap to the path ends).'
                  : 'Creates $_steps shapes morphing between your two selections. '
                      'Tip: also select an open path/line to lay the steps along it.')
              : 'Select two shapes to morph — optionally add an open path or '
                  'line as the route for the steps.',
          style:
              ShapeText.labelMD.copyWith(color: ShapeColors.secondaryText),
        ),
        const SizedBox(height: 8),
        LabeledSlider(
          label: 'Steps',
          value: _steps.toDouble(),
          min: 1,
          max: 500,
          display: '$_steps',
          onChanged: (v) => setState(() => _steps = v.round()),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ShapeColors.shapeBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: ok
                ? () {
                    m.blendSteps(_steps);
                    m.closeSheet();
                  }
                : null,
            child: Text('Create Morph',
                style: ShapeText.labelLG.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
