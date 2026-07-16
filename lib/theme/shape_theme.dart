import 'package:flutter/widgets.dart';

/// Central design tokens for Shape. The interface is a **light, pleasant,
/// pastel matte** material system: frosted-white glass floating over a soft
/// multi-pastel canvas, with a single muted periwinkle accent. Chrome stays
/// quiet so the artwork leads (spec §4 philosophy), now in a warmer key.
class ShapeColors {
  ShapeColors._();

  // ---- Surfaces ----------------------------------------------------------
  /// App / scaffold fallback base (the canvas paints a pastel gradient over it).
  static const paper = Color(0xFFF7F4FC);
  /// Frosted-glass tint base — clean white, used at the GlassLayer opacities.
  static const glassTint = Color(0xFFFFFFFF);
  static const surfaceCarbon = Color(0xFFFFFFFF); // colorScheme surface
  static const offBlack = Color(0xFFFFFFFF); // elevated surface (light)

  /// Soft pastel gradient stops for the canvas backdrop ("light & fun").
  static const bgTop = Color(0xFFFBEFF4); // rose mist
  static const bgMid = Color(0xFFF4F0FB); // lavender haze
  static const bgBottom = Color(0xFFEAF3F7); // sky / mint whisper

  /// Back-compat alias (older refs); now the paper base.
  static const deepCarbon = paper;

  // ---- Text (dark ink on light) -----------------------------------------
  static const primaryText = Color(0xFF3A3742);
  static const secondaryText = Color(0xFF7C7689);
  static const tertiaryText = Color(0xFFAEA9BA);

  // ---- Accent (muted periwinkle) ----------------------------------------
  static const shapeBlue = Color(0xFF6C63D6);
  static const shapeBlueDim = Color(0x406C63D6);
  static const shapeBlueGhost = Color(0x1A6C63D6);

  // ---- State colors (softened, matte) -----------------------------------
  static const destructive = Color(0xFFE8746C);
  static const warning = Color(0xFFE6AE4D);
  static const success = Color(0xFF6FC18A);

  // ---- Glass hairline & controls ----------------------------------------
  static const glassBorderDark = Color(0x16000000); // ink @ ~9% — glass edge
  static const glassBorderLight = Color(0x0F000000);
  static const trackBase = Color(0x1F3A3742); // slider inactive track
  static const fieldBase = Color(0x0F3A3742); // segmented / field fills
  static const handle = Color(0x453A3742); // sheet grab handle

  // ---- Checkerboard (transparent canvas) --------------------------------
  static const checkerDark = Color(0xFFE3DEEC);
  static const checkerLight = Color(0xFFF1ECF7);

  // ---- Pastel palette (shape fills, recents, accents) -------------------
  static const lavender = Color(0xFFC9B8F0);
  static const mint = Color(0xFFA9E0C9);
  static const peach = Color(0xFFF7C9A6);
  static const rose = Color(0xFFF4B6CC);
  static const sky = Color(0xFFA9CBEE);
  static const butter = Color(0xFFF2DEA0);

  static const pastels = <Color>[lavender, mint, peach, rose, sky, butter];

  /// Cycles through the pastel palette for each new object.
  static Color pastelFor(int i) => pastels[i % pastels.length];

  /// Soft elevation shadow for glass on the light backdrop.
  static const softShadow = [
    BoxShadow(color: Color(0x14302B45), offset: Offset(0, 2), blurRadius: 10),
    BoxShadow(color: Color(0x0D302B45), offset: Offset(0, 8), blurRadius: 24),
  ];
}

/// Material stack tint/blur levels — §5 Transparency & Blur System.
/// `sigma` feeds `ImageFilter.blur`; `tintOpacity` is applied over the white
/// glass tint to produce frosted panels of increasing opacity.
class GlassLayer {
  const GlassLayer(this.sigma, this.tintOpacity);
  final double sigma;
  final double tintOpacity;

  static const halo = GlassLayer(14, 0.32); // Layer 1
  static const orbMenu = GlassLayer(20, 0.48); // Layer 2
  static const sheet = GlassLayer(28, 0.64); // Layer 3
  static const workspace = GlassLayer(36, 0.76); // Layer 4
  static const command = GlassLayer(48, 0.82); // Layer 5
}

/// Type scale — §3. Font families are referenced by name; if the bundled
/// fonts (see pubspec) are absent, Flutter falls back to the platform default
/// while preserving size/weight. Numeric/measurement styles use [mono].
class ShapeText {
  ShapeText._();

  static const _ui = 'InstrumentSans';
  // A bundled monospace face (registered in pubspec) so numeric/measurement
  // labels are truly monospaced offline — the old 'DMMono' was never bundled
  // and silently fell back to the platform sans.
  static const _monoFamily = 'JetBrains Mono';

  static const labelXS = TextStyle(
      fontFamily: _ui, fontSize: 10, fontWeight: FontWeight.w400, height: 1.2);
  static const labelSM = TextStyle(
      fontFamily: _ui, fontSize: 12, fontWeight: FontWeight.w400, height: 1.2);
  static const labelMD = TextStyle(
      fontFamily: _ui, fontSize: 14, fontWeight: FontWeight.w500, height: 1.2);
  static const labelLG = TextStyle(
      fontFamily: _ui, fontSize: 16, fontWeight: FontWeight.w600, height: 1.2);
  static const titleSM = TextStyle(
      fontFamily: _ui, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2);
  static const titleLG = TextStyle(
      fontFamily: _ui, fontSize: 28, fontWeight: FontWeight.w700, height: 1.1);

  /// DM Mono — coordinates, measurements, values. Always for numerics.
  static const TextStyle mono = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 22,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.1,
  );

  static TextStyle monoSize(double size,
          {Color color = ShapeColors.primaryText}) =>
      mono.copyWith(fontSize: size, color: color);
}
