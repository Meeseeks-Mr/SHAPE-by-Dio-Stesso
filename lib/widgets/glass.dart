import 'dart:ui';
import 'package:flutter/widgets.dart';

import '../theme/shape_theme.dart';

/// A frosted-glass surface — the single material primitive behind orbs, halos,
/// sheets and chrome (§5 Transparency & Blur System). Renders a [BackdropFilter]
/// blur, a tint over deep carbon, and the defining 0.5dp hairline border.
///
/// Performance rule from the spec: keep ≤2 active backdrop filters on screen.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.layer,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.child,
    this.shadows,
    this.elevate = true,
  });

  final GlassLayer layer;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Widget? child;
  final List<BoxShadow>? shadows;

  /// On the light backdrop, panels get a soft default shadow to read as
  /// floating glass. Pass [shadows] to override, or `elevate: false` for flat.
  final bool elevate;

  @override
  Widget build(BuildContext context) {
    final surface = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: layer.sigma, sigmaY: layer.sigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: ShapeColors.glassTint.withValues(alpha: layer.tintOpacity),
            borderRadius: borderRadius,
            border: Border.all(color: ShapeColors.glassBorderDark, width: 0.5),
          ),
          child: child,
        ),
      ),
    );

    final effectiveShadows =
        shadows ?? (elevate ? ShapeColors.softShadow : null);
    if (effectiveShadows == null) return surface;
    return DecoratedBox(
      decoration:
          BoxDecoration(borderRadius: borderRadius, boxShadow: effectiveShadows),
      child: surface,
    );
  }

  /// The orb's two-layer drop shadow (§8.1), tuned matte for the light theme.
  static const orbShadows = [
    BoxShadow(color: Color(0x22302B45), offset: Offset(0, 3), blurRadius: 12),
    BoxShadow(color: Color(0x14302B45), offset: Offset(0, 10), blurRadius: 30),
  ];
}
