import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import '../glass.dart';

/// Radial context menu shown on long-press of an object (#13.4, #24.6).
/// Items bloom from the finger position.
class ContextMenuLayer extends StatelessWidget {
  const ContextMenuLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final at = m.contextMenuAt;
    if (at == null) return const SizedBox.shrink();

    final canGroup = m.selection.length >= 2;
    final hasGroup = m.selectionHasGroup;
    final actions = <_CtxItem>[
      _CtxItem('Cut', Icons.content_cut, m.cutSelection),
      _CtxItem('Copy', Icons.copy, m.copySelection),
      if (m.hasClipboard) _CtxItem('Paste', Icons.content_paste, m.pasteClipboard),
      _CtxItem('Duplicate', Icons.copy_all, m.duplicateSelection),
      if (canGroup || hasGroup)
        _CtxItem(hasGroup ? 'Ungroup' : 'Group', Icons.workspaces_outline,
            hasGroup ? m.ungroupSelection : m.groupSelection),
      _CtxItem('Delete', Icons.delete_outline, m.deleteSelection),
      _CtxItem('Front', Icons.flip_to_front, m.bringToFront),
    ];

    final widgets = <Widget>[
      // Backdrop dimming objects beneath (#24.6).
      GestureDetector(
        onTap: m.closeContextMenu,
        child: Container(
            color: ShapeColors.primaryText.withValues(alpha: 0.10)),
      ),
    ];

    const radius = 76.0;
    for (var i = 0; i < actions.length; i++) {
      final a = -math.pi / 2 + (2 * math.pi * i / actions.length);
      final pos = at + Offset(math.cos(a), math.sin(a)) * radius;
      widgets.add(Positioned(
        left: pos.dx - 24,
        top: pos.dy - 24,
        child: _CtxButton(item: actions[i], onDone: m.closeContextMenu),
      ));
    }

    return SizedBox.expand(
      child: Stack(clipBehavior: Clip.none, children: widgets),
    );
  }
}

class _CtxItem {
  _CtxItem(this.label, this.icon, this.action);
  final String label;
  final IconData icon;
  final VoidCallback action;
}

class _CtxButton extends StatelessWidget {
  const _CtxButton({required this.item, required this.onDone});
  final _CtxItem item;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        item.action();
        onDone();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glass(
            layer: GlassLayer.orbMenu,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 48,
              height: 36,
              child: Icon(item.icon,
                  size: 18, color: ShapeColors.primaryText),
            ),
          ),
          const SizedBox(height: 2),
          Text(item.label,
              style: ShapeText.labelXS
                  .copyWith(color: ShapeColors.secondaryText)),
        ],
      ),
    );
  }
}
