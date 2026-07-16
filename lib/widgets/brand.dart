import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/shape_theme.dart';

/// The Shape app mark (§2 Visual Identity): a filled circle intersecting a
/// slightly rotated square. Re-themed for light/pastel — a pastel-filled circle
/// over an ink hairline square. [progress] (0..1) draws it on for the splash.
class ShapeMark extends StatelessWidget {
  const ShapeMark({
    super.key,
    this.size = 28,
    this.progress = 1,
    this.circleColor = ShapeColors.shapeBlue,
  });

  final double size;
  final double progress;
  final Color circleColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(progress, circleColor),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.progress, this.circleColor);
  final double progress;
  final Color circleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.rotate(-0.18 * progress); // slight rotation, eased in by progress

    // Larger, brighter mark: a mint-filled rounded square with an ink outline,
    // overlapped by a vivid periwinkle circle — two pastel shapes intersecting,
    // a more playful read than a hairline outline.
    final squareSide = s * 0.72;
    final square = RRect.fromRectXY(
      Rect.fromCenter(
          center: Offset(-s * 0.08, s * 0.08),
          width: squareSide,
          height: squareSide),
      s * 0.10,
      s * 0.10,
    );
    canvas.drawRRect(
      square,
      Paint()..color = ShapeColors.mint.withValues(alpha: 0.95 * progress),
    );
    canvas.drawRRect(
      square,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, s * 0.05)
        ..color = ShapeColors.primaryText.withValues(alpha: 0.9 * progress),
    );

    canvas.drawCircle(
      Offset(s * 0.12, -s * 0.07),
      s * 0.37 * (0.6 + 0.4 * progress),
      Paint()..color = circleColor.withValues(alpha: progress),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.progress != progress || old.circleColor != circleColor;
}

/// "Shape" wordmark with the "by dio.stesso" credit, set artistically.
/// [showCredit] hides the credit entirely (used on the splash). [subtleCredit]
/// keeps it but greatly dialed back, for the always-on main canvas chrome.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.large = false,
    this.color,
    this.showCredit = true,
    this.subtleCredit = false,
  });
  final bool large;
  final Color? color;
  final bool showCredit;
  final bool subtleCredit;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? ShapeColors.primaryText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shape',
          style: (large ? ShapeText.titleLG : ShapeText.titleSM).copyWith(
            color: ink,
            fontWeight: FontWeight.w700,
            letterSpacing: large ? -0.5 : -0.2,
            height: 1.0,
          ),
        ),
        if (showCredit)
          Padding(
            padding: const EdgeInsets.only(top: 1, left: 1),
            child: Text(
              'by dio.stesso',
              style: ShapeText.labelXS.copyWith(
                color: (subtleCredit
                        ? ShapeColors.tertiaryText
                        : ShapeColors.shapeBlue)
                    .withValues(alpha: subtleCredit ? 0.4 : 0.9),
                fontStyle: FontStyle.italic,
                letterSpacing: 0.4,
                fontSize: subtleCredit ? 8 : (large ? 12 : 9.5),
              ),
            ),
          ),
      ],
    );
  }
}
