import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import '../glass.dart';

/// Controls shown while perspective-distorting an object: drag the four corner
/// handles on the canvas; Reset restores the rectangle; Done finishes.
class PerspectiveHud extends StatelessWidget {
  const PerspectiveHud({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final active = m.perspectiveEditId != null;
    final pad = MediaQuery.of(context).padding;
    final w = MediaQuery.of(context).size.width;

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
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: w - 24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.crop_rotate,
                          size: 16, color: ShapeColors.shapeBlue),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('Drag the corners',
                            style: ShapeText.labelMD.copyWith(
                                color: ShapeColors.primaryText)),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: m.resetPerspective,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text('Reset',
                              style: ShapeText.labelSM.copyWith(
                                  color: ShapeColors.secondaryText)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: m.exitPerspectiveEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: ShapeColors.shapeBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('Done',
                              style: ShapeText.labelSM
                                  .copyWith(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
