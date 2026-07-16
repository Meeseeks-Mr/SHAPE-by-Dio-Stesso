import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import '../glass.dart';

/// A floating indicator shown while a creation tool (pen/draw/text) is active,
/// with quick actions to finish or cancel. Animated in/out.
class ToolHud extends StatelessWidget {
  const ToolHud({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final active = m.tool != ActiveTool.none;
    final pad = MediaQuery.of(context).padding;

    final label = switch (m.tool) {
      ActiveTool.pen => 'Pen — tap to add points',
      ActiveTool.draw => 'Draw — drag to sketch',
      ActiveTool.text => 'Text — tap to place',
      ActiveTool.none => '',
    };

    return Positioned(
      top: pad.top + 70,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          offset: active ? Offset.zero : const Offset(0, -0.6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: active ? 1 : 0,
            child: Center(
              child: Glass(
                layer: GlassLayer.orbMenu,
                borderRadius: BorderRadius.circular(22),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon(m.tool),
                        size: 16, color: ShapeColors.shapeBlue),
                    const SizedBox(width: 8),
                    Text(label,
                        style: ShapeText.labelMD
                            .copyWith(color: ShapeColors.primaryText)),
                    if (m.tool == ActiveTool.pen) ...[
                      const SizedBox(width: 10),
                      _Chip(
                          label: 'Finish',
                          onTap: () => m.penFinish(closed: false)),
                    ],
                    if (m.tool == ActiveTool.draw) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.auto_graph,
                          size: 15, color: ShapeColors.secondaryText),
                      SizedBox(
                        width: 120,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            overlayShape: SliderComponentShape.noOverlay,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7),
                          ),
                          child: Slider(
                            value: m.drawStabilization,
                            activeColor: ShapeColors.shapeBlue,
                            inactiveColor: ShapeColors.glassBorderDark,
                            onChanged: m.setStabilization,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text('${(m.drawStabilization * 100).round()}%',
                            style: ShapeText.labelSM
                                .copyWith(color: ShapeColors.secondaryText)),
                      ),
                    ],
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        m.penCancel();
                        m.setTool(ActiveTool.none);
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: ShapeColors.secondaryText),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(ActiveTool t) => switch (t) {
        ActiveTool.pen => Icons.gesture,
        ActiveTool.draw => Icons.draw_outlined,
        ActiveTool.text => Icons.title,
        ActiveTool.none => Icons.circle,
      };
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: ShapeColors.shapeBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: ShapeText.labelSM.copyWith(color: Colors.white)),
        ),
      );
}
