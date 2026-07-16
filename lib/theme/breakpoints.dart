import 'package:flutter/widgets.dart';

/// Layout thresholds for the web build.
///
/// Below [desktopMinWidth] the editor is pixel-identical to the touch build:
/// bottom drawers, orb, full-bleed canvas. At or above it the drawers dock to a
/// side rail so a mouse never has to travel to the bottom of a wide screen.
/// Everything else — the canvas, the orb, every sheet's contents — is shared.
class Breakpoints {
  const Breakpoints._();

  /// Chosen so phones and portrait tablets keep the touch layout, while
  /// landscape tablets and desktop windows get the docked rail.
  static const double desktopMinWidth = 900;

  /// Width of the docked drawer rail on desktop.
  static const double railWidth = 380;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopMinWidth;
}
