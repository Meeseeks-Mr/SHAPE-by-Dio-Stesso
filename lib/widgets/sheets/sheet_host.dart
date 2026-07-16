import 'dart:ui';
import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../state/app_scope.dart';
import '../../theme/breakpoints.dart';
import '../../theme/shape_theme.dart';
import 'align_sheet.dart';
import 'blend_modes_sheet.dart';
import 'blend_steps_sheet.dart';
import 'crop_sheet.dart';
import 'effects_sheet.dart';
import 'export_sheet.dart';
import 'fill_sheet.dart';
import 'repeat_sheet.dart';
import 'shape_params_sheet.dart';
import 'strokes_sheet.dart';
import 'layers_sheet.dart';
import 'shapes_sheet.dart';
import 'typography_sheet.dart';

/// Hosts the active drawer as a **floating glassmorphic modal** (§12): a frosted
/// card detached from every edge, translucent so the artwork stays visible
/// underneath, animated in with a spring slide + scale + fade, and cross-fading
/// between drawers.
class SheetHost extends StatelessWidget {
  const SheetHost({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final active = m.sheet;
    final visible = active != ActiveSheet.none;
    final media = MediaQuery.of(context);
    // Wide windows dock the drawer to a right-hand rail; narrow ones keep the
    // touch build's bottom sheet exactly as it is.
    final desktop = Breakpoints.isDesktop(context);

    return IgnorePointer(
      ignoring: !visible,
      child: Stack(
        children: [
          // Tap-outside barrier — barely tints so the canvas reads through.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: visible ? 1 : 0,
            child: GestureDetector(
              onTap: m.closeSheet,
              child: Container(
                  color: ShapeColors.primaryText.withValues(alpha: 0.04)),
            ),
          ),
          Align(
            alignment:
                desktop ? Alignment.centerRight : Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: desktop ? 16 : 0,
                bottom: desktop ? 16 : media.padding.bottom + 16,
              ),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                // Slides in from the edge it's docked to.
                offset: visible
                    ? Offset.zero
                    : (desktop ? const Offset(0.18, 0) : const Offset(0, 0.18)),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutBack,
                  scale: visible ? 1 : 0.94,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    opacity: visible ? 1 : 0,
                    child: _FloatingCard(active: active, desktop: desktop),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingCard extends StatelessWidget {
  const _FloatingCard({required this.active, this.desktop = false});
  final ActiveSheet active;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.read(context);
    // Docked: a tall rail using the window height. Bottom sheet: half the
    // screen, so the artwork stays visible underneath.
    final maxH = MediaQuery.of(context).size.height * (desktop ? 0.86 : 0.5);
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: desktop ? Breakpoints.railWidth : 460, maxHeight: maxH),
      child: PhysicalShape(
        clipper: const ShapeBorderClipper(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(26)))),
        color: Colors.transparent,
        shadowColor: const Color(0x33302B45),
        elevation: 18,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                // Translucent so the artwork shows through (glassmorphism).
                color: ShapeColors.glassTint.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55), width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) > 200) m.closeSheet();
                    },
                    child: const _GrabHandle(),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(
                              scale: Tween(begin: 0.98, end: 1.0)
                                  .animate(anim),
                              child: child),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(active),
                          child: _content(active),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(ActiveSheet active) => switch (active) {
        ActiveSheet.fill => const FillSheet(),
        ActiveSheet.shapes => const ShapesSheet(),
        ActiveSheet.layers => const LayersSheet(),
        ActiveSheet.effects => const EffectsSheet(),
        ActiveSheet.align => const AlignSheet(),
        ActiveSheet.typography => const TypographySheet(),
        ActiveSheet.crop => const CropSheet(),
        ActiveSheet.shapeParams => const ShapeParamsSheet(),
        ActiveSheet.strokes => const StrokesSheet(),
        ActiveSheet.blendSteps => const BlendStepsSheet(),
        ActiveSheet.blendModes => const BlendModesSheet(),
        ActiveSheet.repeat => const RepeatSheet(),
        ActiveSheet.export => const ExportSheet(),
        _ => const SizedBox.shrink(),
      };
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: ShapeColors.handle,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// Shared section header used across sheets (§12.3 etc.).
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title,
              style:
                  ShapeText.labelLG.copyWith(color: ShapeColors.primaryText)),
        ),
      );
}
