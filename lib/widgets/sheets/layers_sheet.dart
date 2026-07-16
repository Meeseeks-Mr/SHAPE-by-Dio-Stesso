import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../theme/shape_theme.dart';
import 'sheet_host.dart';

/// Layer manager (#12.6). Objects are listed front-most first.
///
/// Drag-and-drop (custom, so it works inside the sheet's scroll view):
///  • Long-press a layer row and drop it ON a group header to **add it to that
///    group** — onto a masked group it also becomes clipped by that mask
///    (item 3). Drop it on an insertion bar to reorder it (and pull it out of
///    its group). Long-press a group header to move the whole block.
///  • A masked group shows the **mask as the parent row** with its clipped
///    content as sub-layers; a Repeat shows an outer group of per-instance
///    sub-groups (item 6a).
///  • Every row / group has a delete button (item 7).
class LayersSheet extends StatelessWidget {
  const LayersSheet({super.key});

  static const _groupColors = [
    Color(0xFF6C63D6),
    Color(0xFF4C9AFF),
    Color(0xFFE6739F),
    Color(0xFF49C5B6),
    Color(0xFFE8A13C),
    Color(0xFF8E7CC3),
  ];

  static Color groupColor(String gid) =>
      _groupColors[gid.hashCode.abs() % _groupColors.length];

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final ordered = m.objects.reversed.toList(); // front-most first
    final entries = _topEntries(ordered);

    final children = <Widget>[const SheetTitle('Layers')];
    if (entries.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No layers yet - create a shape.',
            style:
                ShapeText.labelMD.copyWith(color: ShapeColors.secondaryText)),
      ));
    } else {
      for (final e in entries) {
        children.add(_InsertBar(anchorId: e.frontmostId));
        switch (e.kind) {
          case _Kind.superGroup:
            children.add(_SuperGroupTile(entry: e));
          case _Kind.group:
            children.add(_GroupTile(entry: e));
          case _Kind.single:
            children.add(_LayerRow(e.object!));
        }
      }
      children.add(const _InsertBar(anchorId: null)); // drop here → send to back
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<_Entry> _topEntries(List<ShapeObject> ordered) {
    final entries = <_Entry>[];
    final seen = <String>{};
    for (final o in ordered) {
      final sg = o.superGroupId;
      final g = o.groupId;
      if (sg != null) {
        if (seen.add('s:$sg')) {
          entries.add(_Entry.superGroup(
              sg, ordered.where((x) => x.superGroupId == sg).toList()));
        }
      } else if (g != null) {
        if (seen.add('g:$g')) {
          entries.add(_Entry.group(
              g,
              ordered
                  .where((x) => x.groupId == g && x.superGroupId == null)
                  .toList()));
        }
      } else {
        entries.add(_Entry.single(o));
      }
    }
    return entries;
  }
}

enum _Kind { single, group, superGroup }

class _Entry {
  _Entry.single(this.object)
      : kind = _Kind.single,
        id = null,
        members = const [];
  _Entry.group(this.id, this.members)
      : kind = _Kind.group,
        object = null;
  _Entry.superGroup(this.id, this.members)
      : kind = _Kind.superGroup,
        object = null;

  final _Kind kind;
  final ShapeObject? object;
  final String? id;
  final List<ShapeObject> members;

  String get frontmostId =>
      kind == _Kind.single ? object!.id : members.first.id;
}

// ---- Drag payloads -------------------------------------------------------
// 'o:<id>'  a single object   |  'g:<gid>' a leaf group  |  's:<sgid>' a super.
String _objPayload(String id) => 'o:$id';
String _groupPayload(String gid) => 'g:$gid';
String _superPayload(String sgid) => 's:$sgid';

/// Handles a payload dropped onto a group header [gid]: a single object joins
/// the group; another group nests under a shared super-group (item 5).
void _dropOnGroup(EditorModel m, String payload, String gid) {
  if (payload.startsWith('o:')) {
    m.addToGroup(payload.substring(2), gid);
  } else if (payload.startsWith('g:')) {
    m.nestGroups(payload.substring(2), gid);
  }
}

void _dropOnBar(EditorModel m, String payload, String? anchorId) {
  if (payload.startsWith('o:')) {
    m.moveLayersInFrontOf([payload.substring(2)],
        anchorId: anchorId, detach: true);
  } else if (payload.startsWith('g:')) {
    final gid = payload.substring(2);
    m.moveLayersInFrontOf(
        m.objects.where((o) => o.groupId == gid).map((o) => o.id).toList(),
        anchorId: anchorId);
  } else if (payload.startsWith('s:')) {
    final sgid = payload.substring(2);
    m.moveLayersInFrontOf(
        m.objects
            .where((o) => o.superGroupId == sgid)
            .map((o) => o.id)
            .toList(),
        anchorId: anchorId);
  }
}

/// Thin reorder drop-zone between entries; swells and highlights on hover.
class _InsertBar extends StatelessWidget {
  const _InsertBar({required this.anchorId});
  final String? anchorId;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _dropOnBar(m, d.data, anchorId),
      builder: (ctx, cand, rej) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: cand.isEmpty ? 6 : 20,
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: cand.isEmpty
              ? Colors.transparent
              : ShapeColors.shapeBlue.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

/// Header for group / sub-group / super-group rows. It's a [DragTarget] (a layer
/// dropped on it joins via [onDropObject]) and a [LongPressDraggable] (drag the
/// whole block to reorder) when [dragPayload] is supplied.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.color,
    required this.icon,
    required this.title,
    required this.collapsed,
    required this.indent,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
    this.onDrop,
    this.acceptsGroups = false,
    this.selfGid,
    this.dragPayload,
    this.trailing,
  });

  final Color color;
  final IconData icon;
  final String title;
  final bool collapsed;
  final double indent;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  // Receives the raw drag payload ('o:<id>', 'g:<gid>', 's:<sgid>').
  final void Function(String payload)? onDrop;
  final bool acceptsGroups;
  final String? selfGid;
  final String? dragPayload;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Widget content(bool highlight) => Container(
          height: 44,
          decoration: BoxDecoration(
            color: highlight
                ? ShapeColors.shapeBlue.withValues(alpha: 0.18)
                : (selected
                    ? ShapeColors.shapeBlue.withValues(alpha: 0.08)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(width: indent + 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                      collapsed
                          ? Icons.chevron_right
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: ShapeColors.secondaryText),
                ),
              ),
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: ShapeText.labelMD
                        .copyWith(color: ShapeColors.primaryText),
                    overflow: TextOverflow.ellipsis),
              ),
              if (trailing != null) trailing!,
              _DeleteButton(onTap: onDelete),
            ],
          ),
        );

    // The tappable + draggable header body.
    Widget body = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content(false),
    );
    if (dragPayload != null) {
      body = LongPressDraggable<String>(
        data: dragPayload!,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragFeedback(name: title),
        childWhenDragging: Opacity(opacity: 0.4, child: content(false)),
        child: body,
      );
    }

    if (onDrop == null) return body;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        if (d.data.startsWith('o:')) return true;
        // A group can be dropped onto another group to nest them (item 5),
        // but not onto itself.
        if (acceptsGroups && d.data.startsWith('g:')) {
          return d.data.substring(2) != selfGid;
        }
        return false;
      },
      onAcceptWithDetails: (d) => onDrop!(d.data),
      builder: (ctx, cand, rej) =>
          cand.isEmpty ? body : Stack(children: [body, _DropGlow(content)]),
    );
  }
}

/// Highlights a header when a layer is hovering to be dropped into it.
class _DropGlow extends StatelessWidget {
  const _DropGlow(this.content);
  final Widget Function(bool) content;
  @override
  Widget build(BuildContext context) =>
      Positioned.fill(child: IgnorePointer(child: content(true)));
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.entry});
  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final gid = entry.id!;
    final color = LayersSheet.groupColor(gid);
    final collapsed = m.isGroupCollapsed(gid);
    final allSelected = entry.members.every((o) => m.selection.contains(o.id));
    final maskId = m.groupMaskId(gid);
    final mask = maskId == null ? null : m.byId(maskId);
    final content = maskId == null
        ? entry.members
        : entry.members.where((o) => o.id != maskId).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        children: [
          _GroupHeader(
            color: color,
            icon: mask != null ? Icons.crop_free : Icons.workspaces_outline,
            title: mask != null
                ? '${mask.name}  (mask)'
                : 'Group · ${entry.members.length}',
            collapsed: collapsed,
            indent: 0,
            selected: allSelected,
            dragPayload: _groupPayload(gid),
            onToggle: () => m.toggleGroupCollapsed(gid),
            onTap: () => m.selectOnly(entry.members.first.id),
            onDelete: () => m.deleteGroup(gid),
            acceptsGroups: true,
            selfGid: gid,
            onDrop: (payload) => _dropOnGroup(m, payload, gid),
            trailing: mask != null
                ? _IconToggle(
                    icon: mask.visible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    active: mask.visible,
                    onTap: () => m.mutate(() => mask.visible = !mask.visible),
                  )
                : null,
          ),
          if (!collapsed)
            for (final o in content) _LayerRow(o, indent: 1),
        ],
      ),
    );
  }
}

class _SuperGroupTile extends StatelessWidget {
  const _SuperGroupTile({required this.entry});
  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final sgid = entry.id!;
    final color = LayersSheet.groupColor(sgid);
    final collapsed = m.isGroupCollapsed(sgid);
    final allSelected = entry.members.every((o) => m.selection.contains(o.id));

    final subIds = <String>[];
    for (final o in entry.members) {
      final g = o.groupId;
      if (g != null && !subIds.contains(g)) subIds.add(g);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        children: [
          _GroupHeader(
            color: color,
            icon: Icons.grid_view_rounded,
            title: 'Repeat · ${subIds.length}',
            collapsed: collapsed,
            indent: 0,
            selected: allSelected,
            dragPayload: _superPayload(sgid),
            onToggle: () => m.toggleGroupCollapsed(sgid),
            onTap: () => m.selectSuperGroup(sgid),
            onDelete: () => m.deleteSuperGroup(sgid),
          ),
          if (!collapsed)
            for (final g in subIds)
              _SubGroup(
                  gid: g,
                  members:
                      entry.members.where((o) => o.groupId == g).toList()),
        ],
      ),
    );
  }
}

class _SubGroup extends StatelessWidget {
  const _SubGroup({required this.gid, required this.members});
  final String gid;
  final List<ShapeObject> members;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final color = LayersSheet.groupColor(gid);
    final collapsed = m.isGroupCollapsed(gid);
    final selected = members.every((o) => m.selection.contains(o.id));
    return Column(
      children: [
        _GroupHeader(
          color: color,
          icon: Icons.workspaces_outline,
          title: 'Group · ${members.length}',
          collapsed: collapsed,
          indent: 14,
          selected: selected,
          dragPayload: _groupPayload(gid),
          onToggle: () => m.toggleGroupCollapsed(gid),
          onTap: () => m.selectGroupMembers(gid),
          onDelete: () => m.deleteGroup(gid),
          onDrop: (payload) => _dropOnGroup(m, payload, gid),
        ),
        if (!collapsed)
          for (final o in members) _LayerRow(o, indent: 2),
      ],
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow(this.object, {this.indent = 0});
  final ShapeObject object;
  final int indent;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final selected = m.selection.contains(object.id);
    final isMasked = object.maskId != null;
    final isMask = m.objects.any((x) => x.maskId == object.id);

    Widget rowContent(bool dim) => Container(
          height: 48,
          margin: EdgeInsets.only(bottom: 4, left: indent * 14.0),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? ShapeColors.shapeBlue.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Opacity(
            opacity: dim ? 0.4 : 1,
            child: Row(
              children: [
                const Icon(Icons.drag_indicator,
                    size: 16, color: ShapeColors.tertiaryText),
                const SizedBox(width: 4),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: ShapeColors.fieldBase,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: ShapeColors.glassBorderDark, width: 0.5),
                  ),
                  child: CustomPaint(painter: _Thumb(object)),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(object.name,
                      style: ShapeText.labelMD
                          .copyWith(color: ShapeColors.primaryText),
                      overflow: TextOverflow.ellipsis),
                ),
                if (isMask || isMasked)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(isMask ? Icons.crop_free : Icons.crop,
                        size: 14, color: ShapeColors.shapeBlue),
                  ),
                const Spacer(),
                _IconToggle(
                  icon:
                      object.visible ? Icons.visibility : Icons.visibility_off,
                  active: object.visible,
                  onTap: () =>
                      m.mutate(() => object.visible = !object.visible),
                ),
                _IconToggle(
                  icon: object.locked ? Icons.lock : Icons.lock_open,
                  active: object.locked,
                  onTap: () => m.mutate(() => object.locked = !object.locked),
                ),
                _DeleteButton(onTap: () => m.deleteObject(object.id)),
              ],
            ),
          ),
        );

    return LongPressDraggable<String>(
      data: _objPayload(object.id),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(name: object.name),
      childWhenDragging: rowContent(true),
      child: GestureDetector(
        onTap: () => m.selectExact(object.id),
        behavior: HitTestBehavior.opaque,
        child: rowContent(false),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(Icons.delete_outline,
              size: 18, color: ShapeColors.destructive),
        ),
      );
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ShapeColors.shapeBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(name,
                  style: ShapeText.labelSM.copyWith(color: Colors.white)),
            ],
          ),
        ),
      );
}

class _IconToggle extends StatelessWidget {
  const _IconToggle(
      {required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(icon,
              size: 18,
              color: active
                  ? ShapeColors.secondaryText
                  : ShapeColors.tertiaryText),
        ),
      );
}

class _Thumb extends CustomPainter {
  _Thumb(this.object);
  final ShapeObject object;
  @override
  void paint(Canvas canvas, Size size) {
    final scale =
        (size.width / (object.size.width.abs() + 1)).clamp(0.0, 1.0) * 0.7;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    final paint = Paint()
      ..color = object.fill
      ..style = object.type == ShapeType.line
          ? PaintingStyle.stroke
          : PaintingStyle.fill
      ..strokeWidth = 6;
    canvas.drawPath(object.localPath(), paint);
  }

  @override
  bool shouldRepaint(covariant _Thumb old) => true;
}
