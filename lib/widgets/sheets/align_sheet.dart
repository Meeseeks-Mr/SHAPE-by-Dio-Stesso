import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import 'sheet_host.dart';

/// Alignment sheet for multi-selection (§10.3) — a pictographic grid.
class AlignSheet extends StatelessWidget {
  const AlignSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    Widget btn(IconData icon, String mode, String tip) => _AlignButton(
        icon: icon, onTap: () => m.alignSelection(mode), tip: tip);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Align'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            btn(Icons.align_horizontal_left, 'left', 'Left'),
            btn(Icons.align_horizontal_center, 'hcenter', 'Center'),
            btn(Icons.align_horizontal_right, 'right', 'Right'),
            btn(Icons.align_vertical_top, 'top', 'Top'),
            btn(Icons.align_vertical_center, 'vcenter', 'Middle'),
            btn(Icons.align_vertical_bottom, 'bottom', 'Bottom'),
          ],
        ),
        const SizedBox(height: 16),
        Text('Distribute',
            style:
                ShapeText.labelSM.copyWith(color: ShapeColors.secondaryText)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          children: [
            btn(Icons.horizontal_distribute, 'hdist', 'Horizontal'),
            btn(Icons.vertical_distribute, 'vdist', 'Vertical'),
          ],
        ),
      ],
    );
  }
}

class _AlignButton extends StatelessWidget {
  const _AlignButton(
      {required this.icon, required this.onTap, required this.tip});
  final IconData icon;
  final VoidCallback onTap;
  final String tip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 48,
          decoration: BoxDecoration(
            color: ShapeColors.fieldBase,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: ShapeColors.glassBorderDark, width: 0.5),
          ),
          child: Icon(icon, size: 22, color: ShapeColors.primaryText),
        ),
      ),
    );
  }
}
