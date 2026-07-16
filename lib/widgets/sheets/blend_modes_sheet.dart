import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import 'sheet_host.dart';

/// Layer blend-mode picker (§16.2) as a compact chip grid — the halo's Blend
/// node and the orb both open this. Applies to the whole selection.
class BlendModesSheet extends StatelessWidget {
  const BlendModesSheet({super.key});

  static const _modes = <(String, BlendMode)>[
    ('Normal', BlendMode.srcOver),
    ('Multiply', BlendMode.multiply),
    ('Screen', BlendMode.screen),
    ('Overlay', BlendMode.overlay),
    ('Darken', BlendMode.darken),
    ('Lighten', BlendMode.lighten),
    ('Color Dodge', BlendMode.colorDodge),
    ('Color Burn', BlendMode.colorBurn),
    ('Hard Light', BlendMode.hardLight),
    ('Soft Light', BlendMode.softLight),
    ('Difference', BlendMode.difference),
    ('Exclusion', BlendMode.exclusion),
    ('Hue', BlendMode.hue),
    ('Saturation', BlendMode.saturation),
    ('Color', BlendMode.color),
    ('Luminosity', BlendMode.luminosity),
  ];

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final o = m.singleSelection ?? m.selectedObjects.firstOrNull;
    final current = o?.blend ?? BlendMode.srcOver.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Blend Mode'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, mode) in _modes)
              GestureDetector(
                onTap: () => m.setBlend(mode.index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: current == mode.index
                        ? ShapeColors.shapeBlue.withValues(alpha: 0.18)
                        : ShapeColors.fieldBase,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: current == mode.index
                            ? ShapeColors.shapeBlue
                            : Colors.transparent,
                        width: 1),
                  ),
                  child: Text(label,
                      style: ShapeText.labelMD
                          .copyWith(color: ShapeColors.primaryText)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
