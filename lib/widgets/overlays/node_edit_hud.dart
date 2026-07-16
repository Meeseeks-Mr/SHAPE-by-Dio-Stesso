import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../theme/shape_theme.dart';
import '../glass.dart';

/// The shared handle mode of the selected nodes (-1 if mixed/none).
int _selMode(EditorModel m, ShapeObject? o) {
  if (o == null || m.selectedNodes.isEmpty) return -1;
  final modes = m.selectedNodes
      .where((i) => i < o.pathPoints.length)
      .map(o.nodeModeAt)
      .toSet();
  return modes.length == 1 ? modes.first : -1;
}

/// True when every selected node is a "broken" cusp: corner mode (0) but with
/// at least one non-zero tangent handle, i.e. handles that move independently.
bool _hasBrokenHandles(EditorModel m, ShapeObject? o) {
  if (o == null || !o.hasHandles || m.selectedNodes.isEmpty) return false;
  bool zero(Offset h) => h.dx.abs() < 1e-6 && h.dy.abs() < 1e-6;
  final sel = m.selectedNodes.where((i) => i < o.pathPoints.length);
  if (sel.isEmpty) return false;
  return sel.every((i) =>
      o.nodeModeAt(i) == 0 && !(zero(o.handleIn[i]) && zero(o.handleOut[i])));
}

/// Controls shown while editing a path's nodes: curve/close toggles, delete the
/// selected node, and finish. Tap a segment to add a node, drag a node to move,
/// tap empty canvas to exit.
class NodeEditHud extends StatelessWidget {
  const NodeEditHud({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final active = m.nodeEditId != null;
    final o = active ? m.byId(m.nodeEditId!) : null;
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
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: w - 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Btn(
                      icon: Icons.gesture,
                      label: 'Smooth',
                      active: _selMode(m, o) == 1,
                      enabled: m.selectedNodes.isNotEmpty,
                      onTap: () => m.setNodeMode(1),
                    ),
                    _Btn(
                      icon: Icons.share_outlined,
                      label: 'Corner',
                      active: _selMode(m, o) == 0 &&
                          m.selectedNodes.isNotEmpty &&
                          !_hasBrokenHandles(m, o),
                      enabled: m.selectedNodes.isNotEmpty,
                      onTap: () => m.setNodeMode(0),
                    ),
                    _Btn(
                      icon: Icons.call_split,
                      label: 'Break',
                      active: _hasBrokenHandles(m, o),
                      enabled: m.selectedNodes.isNotEmpty,
                      onTap: m.breakNodeHandles,
                    ),
                    _Btn(
                      icon: Icons.link,
                      label: 'Close',
                      active: o?.closed ?? false,
                      onTap: m.toggleClosed,
                    ),
                    _Btn(
                      icon: Icons.remove_circle_outline,
                      label: 'Delete',
                      active: false,
                      enabled: m.selectedNodes.isNotEmpty,
                      onTap: m.deleteSelectedNode,
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: m.exitNodeEdit,
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
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? ShapeColors.shapeBlue.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 16,
                color: active
                    ? ShapeColors.shapeBlue
                    : ShapeColors.secondaryText),
            const SizedBox(width: 5),
            Text(label,
                style: ShapeText.labelSM
                    .copyWith(color: ShapeColors.primaryText)),
          ]),
        ),
      ),
    );
  }
}
