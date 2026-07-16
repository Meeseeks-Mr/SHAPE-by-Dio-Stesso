import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import 'sheet_host.dart';

/// Shapes sub-menu gallery (#9.3). Tapping a shape places it at the center of
/// the current viewport and drops straight into selection state (halo appears).
class ShapesSheet extends StatelessWidget {
  const ShapesSheet({super.key});

  // Only the primitive shapes are placeable from the gallery; path/text/image
  // are created via their dedicated tools (Pen/Draw, Text, Place) and would be
  // empty/broken if instantiated here.
  static const _items = [
    ShapeType.rectangle,
    ShapeType.ellipse,
    ShapeType.triangle,
    ShapeType.star,
    ShapeType.polygon,
    ShapeType.line,
  ];

  void _place(BuildContext context, ShapeType type) {
    final m = AppScope.read(context);
    final media = MediaQuery.of(context).size;
    final center = m.screenToCanvas(Offset(media.width / 2, media.height / 2));
    final size = switch (type) {
      ShapeType.line => const Size(180, 180),
      ShapeType.triangle => const Size(160, 140),
      _ => const Size(160, 120),
    };
    m.addObject(ShapeObject(
      type: type,
      center: center,
      size: size,
      fill: type == ShapeType.line ? const Color(0x00000000) : m.nextPastel(),
      stroke: ShapeColors.primaryText,
      strokeWidth: type == ShapeType.line ? 3 : 0,
    ));
    m.closeSheet();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Shapes'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final t in _items)
              GestureDetector(
                onTap: () => _place(context, t),
                child: Container(
                  decoration: BoxDecoration(
                    color: ShapeColors.fieldBase,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: ShapeColors.glassBorderDark, width: 0.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(48, 40),
                        painter: _ShapePreview(t),
                      ),
                      const SizedBox(height: 8),
                      Text(t.label,
                          style: ShapeText.labelSM
                              .copyWith(color: ShapeColors.secondaryText)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ShapePreview extends CustomPainter {
  _ShapePreview(this.type);
  final ShapeType type;

  @override
  void paint(Canvas canvas, Size size) {
    final o = ShapeObject(
      type: type,
      center: Offset.zero,
      size: Size(size.width, size.height),
    );
    canvas.translate(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = ShapeColors.primaryText
      ..style = type == ShapeType.line
          ? PaintingStyle.stroke
          : PaintingStyle.fill
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(o.localPath(), paint);
  }

  @override
  bool shouldRepaint(covariant _ShapePreview old) => old.type != type;
}

