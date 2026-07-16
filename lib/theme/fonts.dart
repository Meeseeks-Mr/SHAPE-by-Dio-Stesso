import 'package:flutter/material.dart';

/// The Typography panel's font catalog. Every family here is BUNDLED as an OFL
/// `.ttf` in assets/fonts and declared in pubspec.yaml, so type works fully
/// offline with no network fetch. Most are variable fonts, so the weight axis
/// is driven live via [FontVariation] in [style]. `null`/'Default' uses the
/// app's default face (Instrument Sans).
class FontCatalog {
  static const String defaultFamily = 'Default';
  static const String _default = 'InstrumentSans';

  static const Map<String, List<String>> groups = {
    'Sans': [
      'Inter',
      'Open Sans',
      'Montserrat',
      'Poppins',
      'Nunito',
      'Work Sans',
      'Raleway',
      'Rubik',
      'DM Sans',
      'Manrope',
      'Oswald',
      'Lato',
    ],
    'Serif': [
      'Playfair Display',
      'Lora',
      'EB Garamond',
    ],
    'Mono': [
      'JetBrains Mono',
      'Source Code Pro',
      'Space Mono',
    ],
    'Display': [
      'Bebas Neue',
      'Anton',
      'Comfortaa',
      'Lobster',
    ],
    'Handwriting': [
      'Pacifico',
      'Caveat',
      'Dancing Script',
    ],
    // Devanagari (Hindi) — bundled OFL faces with full Devanagari + Latin.
    'Hindi (Devanagari)': [
      'Mukta',
      'Hind',
      'Baloo 2',
      'Tillana',
    ],
  };

  /// Flat list of every family (with the Default sentinel first).
  static final List<String> all = [
    defaultFamily,
    for (final list in groups.values) ...list,
  ];

  /// Resolves a catalog family to its bundled font-family name.
  static String resolve(String? family) =>
      (family == null || family == defaultFamily) ? _default : family;

  /// Builds a [TextStyle] for the given family using only bundled fonts. The
  /// weight axis is applied via [FontVariation] so variable fonts respond to
  /// the weight slider; static fonts simply ignore the axis.
  static TextStyle style({
    required String? family,
    required double fontSize,
    required FontWeight weight,
    required Color color,
    double letterSpacing = 0,
    double height = 1.2,
    bool italic = false,
  }) {
    return TextStyle(
      fontFamily: resolve(family),
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
    );
  }

  /// A lightweight preview style (for the font-picker chips).
  static TextStyle preview(String family, {double size = 17}) => TextStyle(
        fontFamily: resolve(family == defaultFamily ? null : family),
        fontSize: size,
        color: const Color(0xFF2A2733),
      );
}
