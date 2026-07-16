import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import '../brand.dart';
import '../glass.dart';
import 'exit_flow.dart';

/// The permanent top chrome: workspace button + branding wordmark (left),
/// undo/redo pill and a subtle exit button (right). (§8.2–8.3)
class TopChrome extends StatelessWidget {
  const TopChrome({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final pad = MediaQuery.of(context).padding;

    return Padding(
      padding: EdgeInsets.only(top: pad.top + 16, left: 16, right: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Workspace / file menu.
          _PressScale(
            onTap: () => m.setWorkspace(true),
            child: const Glass(
              layer: GlassLayer.halo,
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.home_outlined,
                    size: 20, color: ShapeColors.primaryText),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Branding wordmark.
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Row(
              children: [
                ShapeMark(size: 22),
                SizedBox(width: 8),
                Wordmark(subtleCredit: true),
              ],
            ),
          ),
          const Spacer(),
          // Undo / redo pill.
          Glass(
            layer: GlassLayer.halo,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                _HistoryButton(
                  icon: Icons.undo,
                  enabled: m.canUndo,
                  onTap: m.undo,
                ),
                Container(
                    width: 0.5, height: 22, color: ShapeColors.glassBorderDark),
                _HistoryButton(
                  icon: Icons.redo,
                  enabled: m.canRedo,
                  onTap: m.redo,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Subtle exit button.
          _PressScale(
            onTap: () => ExitFlow.attempt(context),
            child: Glass(
              layer: GlassLayer.halo,
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.close_rounded,
                    size: 18, color: ShapeColors.secondaryText),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton(
      {required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 40,
        height: 36,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Icon(icon, size: 18, color: ShapeColors.primaryText),
        ),
      ),
    );
  }
}

/// Small press-scale wrapper used by chrome buttons (§8 states).
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  double _scale = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _scale = 0.9),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      child: AnimatedScale(
        scale: widget.onTap == null ? 1 : _scale,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}
