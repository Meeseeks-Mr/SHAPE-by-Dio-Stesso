import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// Repeat / array sheet (#item 4): pick a mode and the number of repetitions.
/// The generated copies — together with the originals — land in one group.
class RepeatSheet extends StatefulWidget {
  const RepeatSheet({super.key});
  @override
  State<RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<RepeatSheet> {
  late int _mode = AppScope.read(context).repeatModeSeed; // 0 grid 1 radial 2 mirror
  int _rows = 3;
  int _cols = 3;
  int _count = 8;
  int _axis = 0; // 0 horizontal, 1 vertical (mirror)
  double _gapX = 1.15; // grid horizontal spacing factor
  double _gapY = 1.15; // grid vertical spacing factor
  double _radiusF = 1.6; // radial ring radius factor

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final has = m.selection.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Repeat'),
        Segmented(
          options: const ['Grid', 'Radial', 'Mirror'],
          selected: _mode,
          onChanged: (i) => setState(() => _mode = i),
        ),
        const SizedBox(height: 12),
        if (_mode == 0) ...[
          LabeledSlider(
            label: 'Rows',
            value: _rows.toDouble(),
            min: 1,
            max: 50,
            display: '$_rows',
            onChanged: (v) => setState(() => _rows = v.round()),
          ),
          LabeledSlider(
            label: 'Columns',
            value: _cols.toDouble(),
            min: 1,
            max: 50,
            display: '$_cols',
            onChanged: (v) => setState(() => _cols = v.round()),
          ),
          LabeledSlider(
            label: 'Spacing X',
            value: _gapX,
            min: 0.2,
            max: 3,
            display: '${_gapX.toStringAsFixed(2)}×',
            onChanged: (v) => setState(() => _gapX = v),
          ),
          LabeledSlider(
            label: 'Spacing Y',
            value: _gapY,
            min: 0.2,
            max: 3,
            display: '${_gapY.toStringAsFixed(2)}×',
            onChanged: (v) => setState(() => _gapY = v),
          ),
          Text('$_rows × $_cols = ${_rows * _cols} tiles',
              style: ShapeText.labelMD
                  .copyWith(color: ShapeColors.secondaryText)),
        ] else if (_mode == 1) ...[
          LabeledSlider(
            label: 'Count',
            value: _count.toDouble(),
            min: 2,
            max: 500,
            display: '$_count',
            onChanged: (v) => setState(() => _count = v.round()),
          ),
          LabeledSlider(
            label: 'Radius',
            value: _radiusF,
            min: 0.5,
            max: 5,
            display: '${_radiusF.toStringAsFixed(2)}×',
            onChanged: (v) => setState(() => _radiusF = v),
          ),
          Text('$_count copies around a ring',
              style: ShapeText.labelMD
                  .copyWith(color: ShapeColors.secondaryText)),
        ] else ...[
          IconChoiceRow(
            label: 'Axis',
            icons: const [Icons.swap_horiz, Icons.swap_vert],
            selected: _axis,
            onChanged: (i) => setState(() => _axis = i),
          ),
          Text(_axis == 0 ? 'Mirror left ↔ right' : 'Mirror top ↕ bottom',
              style: ShapeText.labelMD
                  .copyWith(color: ShapeColors.secondaryText)),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ShapeColors.shapeBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: has
                ? () {
                    switch (_mode) {
                      case 0:
                        m.repeatGrid(
                            rows: _rows,
                            cols: _cols,
                            gapX: _gapX,
                            gapY: _gapY);
                      case 1:
                        m.repeatRadial(count: _count, radiusF: _radiusF);
                      default:
                        m.repeatMirror(horizontal: _axis == 0);
                    }
                    m.closeSheet();
                  }
                : null,
            child: Text('Apply Repeat',
                style: ShapeText.labelLG.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
