import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/shape_object.dart';
import '../../models/tool.dart';
import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../state/shortcuts.dart';
import '../../theme/shape_theme.dart';
import '../chrome/save_dialog.dart';
import '../glass.dart';

/// One node in a radial orb level: either a branch (drills deeper) or a leaf
/// (performs an action and closes the orb).
/// Hover text for an orb entry: its shortcut where it has one, otherwise what
/// the branch contains. Every node gets one, so hovering anywhere tells you
/// something — branches are the first thing the orb shows, and leaving them
/// bare made the whole menu look like it had no hints at all.
class _WithShortcutHint extends StatelessWidget {
  const _WithShortcutHint({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltipFor(label),
        waitDuration: const Duration(milliseconds: 300),
        preferBelow: false,
        child: child,
      );
}

class _Node {
  const _Node(this.label, this.icon,
      {this.branch, this.action, this.enabled = true});
  final String label;
  final IconData icon;
  final String? branch;
  final VoidCallback? action;
  final bool enabled;
  bool get isBranch => branch != null;
}

enum _Kind { open, push, pop }

/// The Main Orb and its **animated drill-down** radial menu (§8.1, §9).
///
/// Navigation is a breadcrumb stack: tapping a branch animates the chosen
/// option up into a header crumb above the orb while its siblings dissolve and
/// the next level blooms in. Crumbs are tappable to pop back. The orb stays
/// anchored bottom-center; levels fan across the upper hemisphere.
class MainOrbLayer extends StatefulWidget {
  const MainOrbLayer({super.key});

  @override
  State<MainOrbLayer> createState() => _MainOrbLayerState();
}

class _MainOrbLayerState extends State<MainOrbLayer>
    with TickerProviderStateMixin {
  static const _gap = 72.0; // vertical spacing between breadcrumb levels
  static const _radius = 120.0; // fan radius
  static const _childSize = 46.0;

  late final AnimationController _nav = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _breathe = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);

  bool _open = false;
  final List<String> _path = []; // branch keys, deepest last

  // Transition bookkeeping.
  _Kind _kind = _Kind.open;
  List<_Node> _prevNodes = const [];
  int _chosenIndex = -1;
  _Node? _chosenNode;
  int _prevDepth = 0;

  @override
  void dispose() {
    _nav.dispose();
    _breathe.dispose();
    super.dispose();
  }

  // ---- Menu definition ---------------------------------------------------
  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// The complete menu tree. ≤5 nodes per level, nested as deep as needed, with
  /// each node disabled when it can't apply to the current selection.
  List<_Node> _levelFor(List<String> path, EditorModel m) {
    final hasSel = m.selection.isNotEmpty;
    final multi = m.selection.length >= 2;
    final single = m.singleSelection;
    final isText = single?.type == ShapeType.text;
    final canNodes = m.canNodeEdit(single);
    final isGeo = single != null &&
        (single.cornerCount > 0 ||
            single.type == ShapeType.polygon ||
            single.type == ShapeType.star);
    // Fill doesn't apply to lines / open paths; stroke needs expanding on text.
    final fillOn = hasSel &&
        !(single != null &&
            (single.type == ShapeType.line ||
                (single.type == ShapeType.path && !single.closed)));
    final strokeOn = hasSel; // text supports outline strokes too now

    void sheet(ActiveSheet s) => m.openSheet(s);
    _Node leaf(String l, IconData i, VoidCallback a, {bool on = true}) =>
        _Node(l, i, action: a, enabled: on);
    _Node branch(String l, IconData i, {bool on = true}) =>
        _Node(l, i, branch: l, enabled: on);
    void blend(BlendMode b) => m.setBlend(b.index);

    switch (path.join('/')) {
      case '':
        return [
          branch('Create', Icons.add),
          branch('Style', Icons.palette_outlined, on: hasSel),
          branch('Arrange', Icons.dashboard_customize_outlined, on: hasSel),
          branch('Combine', Icons.account_tree_outlined, on: hasSel),
          branch('File', Icons.folder_outlined),
        ];

      // ---- Create ----
      case 'Create':
        return [
          leaf('Shapes', Icons.category_outlined,
              () => m.openSheet(ActiveSheet.shapes)),
          leaf('Pen', Icons.gesture, () => m.setTool(ActiveTool.pen)),
          leaf('Draw', Icons.draw_outlined, () => m.setTool(ActiveTool.draw)),
          leaf('Text', Icons.title, () => m.setTool(ActiveTool.text)),
          branch('Place', Icons.add_photo_alternate_outlined),
        ];
      case 'Create/Place':
        return [
          leaf('Image', Icons.image_outlined, () => _pickImage(m)),
          leaf('Vector', Icons.polyline_outlined, () => _pickSvg(m)),
        ];

      // ---- Style ----
      case 'Style':
        return [
          leaf('Fill', Icons.format_color_fill, () => sheet(ActiveSheet.fill),
              on: fillOn),
          leaf('Strokes', Icons.line_weight, () => sheet(ActiveSheet.strokes),
              on: strokeOn),
          leaf('Effects', Icons.auto_awesome, () => sheet(ActiveSheet.effects),
              on: hasSel),
          branch('Blend', Icons.gradient, on: hasSel),
          if (isText)
            leaf('Type', Icons.text_fields,
                () => sheet(ActiveSheet.typography))
          else
            leaf('Shape', Icons.tune, () => sheet(ActiveSheet.shapeParams),
                on: isGeo),
        ];
      case 'Style/Blend':
        return [
          leaf('Normal', Icons.circle_outlined, () => blend(BlendMode.srcOver)),
          leaf('Multiply', Icons.brightness_3, () => blend(BlendMode.multiply)),
          leaf('Screen', Icons.brightness_5, () => blend(BlendMode.screen)),
          leaf('Overlay', Icons.gradient, () => blend(BlendMode.overlay)),
          branch('More', Icons.more_horiz),
        ];
      case 'Style/Blend/More':
        return [
          leaf('Darken', Icons.brightness_2, () => blend(BlendMode.darken)),
          leaf('Lighten', Icons.brightness_7, () => blend(BlendMode.lighten)),
          leaf('Diff', Icons.difference, () => blend(BlendMode.difference)),
          leaf('Hue', Icons.colorize, () => blend(BlendMode.hue)),
          leaf('Lumin', Icons.tonality, () => blend(BlendMode.luminosity)),
        ];

      // ---- Arrange ----
      case 'Arrange':
        return [
          leaf('Align', Icons.align_horizontal_center,
              () => m.openSheet(ActiveSheet.align),
              on: multi),
          branch('Order', Icons.layers_outlined, on: hasSel),
          leaf(m.selectionHasGroup ? 'Ungroup' : 'Group',
              Icons.workspaces_outline,
              m.selectionHasGroup ? m.ungroupSelection : m.groupSelection,
              on: multi || m.selectionHasGroup),
          branch('Repeat', Icons.grid_view_outlined, on: hasSel),
          leaf('Layers', Icons.dashboard_outlined,
              () => m.openSheet(ActiveSheet.layers)),
        ];
      case 'Arrange/Order':
        return [
          leaf('To Front', Icons.flip_to_front, m.bringToFront, on: hasSel),
          leaf('Forward', Icons.keyboard_arrow_up, m.bringForward, on: hasSel),
          leaf('Backward', Icons.keyboard_arrow_down, m.sendBackward,
              on: hasSel),
          leaf('To Back', Icons.flip_to_back, m.sendToBack, on: hasSel),
        ];
      case 'Arrange/Repeat':
        return [
          leaf('Grid', Icons.grid_on, () => m.openRepeatSheet(0), on: hasSel),
          leaf('Radial', Icons.blur_circular, () => m.openRepeatSheet(1),
              on: hasSel),
          leaf('Mirror', Icons.flip, () => m.openRepeatSheet(2), on: hasSel),
        ];

      // ---- Combine ----
      case 'Combine':
        return [
          branch('Pathfind', Icons.join_full, on: multi),
          leaf('Nodes', Icons.timeline,
              () => m.enterNodeEdit(single!.id),
              on: canNodes),
          leaf(m.selectionHasMask ? 'Unmask' : 'Mask', Icons.crop_outlined,
              m.selectionHasMask ? m.releaseMask : m.maskSelection,
              on: m.selection.length >= 2 || m.selectionHasMask),
          leaf('Morph', Icons.blur_linear,
              () => m.openSheet(ActiveSheet.blendSteps),
              on: m.canBlend),
          // Expand (text → outlines, shapes → editable paths). Never offered
          // when an image is selected — an image stays an image (item 5).
          if (hasSel &&
              !m.selectedObjects.any((o) => o.type == ShapeType.image))
            leaf('Expand', Icons.call_split, m.expandSelection),
        ];
      case 'Combine/Pathfind':
        return [
          leaf('Union', Icons.join_full,
              () => m.pathfinder(PathOperation.union, 'Union')),
          leaf('Minus Front', Icons.join_inner,
              () => m.pathfinder(PathOperation.difference, 'Minus Front')),
          leaf('Minus Back', Icons.flip_to_back, m.minusBack),
          leaf('Intersect', Icons.join_left,
              () => m.pathfinder(PathOperation.intersect, 'Intersect')),
          branch('More', Icons.more_horiz),
        ];
      case 'Combine/Pathfind/More':
        return [
          leaf('Exclude', Icons.layers_clear,
              () => m.pathfinder(PathOperation.xor, 'Exclude')),
          leaf('Divide', Icons.grid_on, m.divide),
          leaf('Outline', Icons.format_shapes, m.outline),
          leaf('Flatten', Icons.compress, m.flatten),
        ];

      // ---- File ----
      case 'File':
        return [
          leaf('New', Icons.note_add_outlined, m.newProject),
          leaf('Save', Icons.save_outlined, () async {
            final ok = await promptSaveAs(context, m);
            if (ok && mounted) _toast('Saved "${m.projectName}"');
          }),
          leaf('Export', Icons.ios_share, () => m.openSheet(ActiveSheet.export)),
          leaf('Projects', Icons.folder_open_outlined,
              () => m.setWorkspace(true)),
          leaf('Duplicate', Icons.copy_all_outlined, m.duplicateSelection,
              on: hasSel),
        ];

      default:
        return const [];
    }
  }

  Future<void> _pickImage(EditorModel m) async {
    // Use FileType.custom with explicit extensions (the document/SAF picker)
    // rather than FileType.image. Android's photo picker frequently TRANSCODES
    // a picked PNG to JPEG, flattening its alpha channel to black before the
    // bytes ever reach the app — the document picker returns the original file
    // bytes untouched, preserving transparency.
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      withData: true,
    );
    final bytes = res?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final size = MediaQuery.of(context).size;
    await m.addImage(bytes, m.screenToCanvas(size.center(Offset.zero)));
  }

  Future<void> _pickSvg(EditorModel m) async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['svg'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final size = MediaQuery.of(context).size;
    m.importSvg(utf8.decode(bytes, allowMalformed: true),
        m.screenToCanvas(size.center(Offset.zero)));
  }

  // ---- Navigation --------------------------------------------------------
  void _onNodeTap(List<_Node> level, int i, EditorModel m) {
    final node = level[i];
    if (!node.enabled) return;
    if (node.isBranch) {
      setState(() {
        _kind = _Kind.push;
        _prevNodes = level;
        _chosenIndex = i;
        _chosenNode = node;
        _prevDepth = _path.length;
        _path.add(node.branch!);
      });
      _nav.forward(from: 0);
    } else {
      node.action?.call();
      m.collapseOrb();
    }
  }

  void _popTo(int depth) {
    if (depth >= _path.length) return;
    setState(() {
      _kind = _Kind.pop;
      _path.removeRange(depth, _path.length);
    });
    _nav.forward(from: 0);
  }

  // ---- Geometry ----------------------------------------------------------
  Offset _anchor(Offset orbCenter, int depth) =>
      orbCenter - Offset(0, depth * _gap);

  Offset _radial(Offset anchor, int i, int count) {
    final frac = count <= 1 ? 0.5 : i / (count - 1);
    // Wider fan (172°) so up to 5 nodes don't feel crowded.
    final deg = -176 + frac * 172;
    final a = deg * math.pi / 180;
    return anchor + Offset(math.cos(a), math.sin(a)) * _radius;
  }

  // ---- Build -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);

    // Sync open/close with the model.
    if (m.orbExpanded && !_open) {
      _open = true;
      _path.clear();
      _kind = _Kind.open;
      _nav.forward(from: 0);
    } else if (!m.orbExpanded && _open) {
      _open = false;
      _path.clear();
      _nav.value = 0;
    }

    final media = MediaQuery.of(context);
    final orbCenter = Offset(
      media.size.width / 2,
      media.size.height - media.padding.bottom - 24 - 28,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_nav, _breathe]),
      builder: (context, _) {
        final children = <Widget>[];
        if (_open) {
          _composeLevels(children, m, orbCenter);
        }
        children.add(_orb(m, orbCenter));
        return SizedBox.expand(
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      },
    );
  }

  void _composeLevels(List<Widget> out, EditorModel m, Offset orbCenter) {
    final depth = _path.length;
    final current = _levelFor(_path, m);
    final t = Curves.easeOutCubic.transform(_nav.value);
    final animating = _nav.isAnimating || _nav.value < 1;

    // Breadcrumb header orbs (tappable to pop). During a push the freshly
    // chosen crumb is drawn by the flying orb instead.
    final crumbCount =
        (_kind == _Kind.push && animating) ? _prevDepth : depth;
    for (var k = 0; k < crumbCount; k++) {
      out.add(_crumb(k, _anchor(orbCenter, k + 1)));
    }

    if (_kind == _Kind.push && animating) {
      final fromAnchor = _anchor(orbCenter, _prevDepth);
      // Outgoing siblings dissolve.
      for (var i = 0; i < _prevNodes.length; i++) {
        if (i == _chosenIndex) continue;
        out.add(_childWidget(_prevNodes[i],
            _radial(fromAnchor, i, _prevNodes.length),
            opacity: (1 - t * 1.5).clamp(0.0, 1.0),
            scale: 1 - 0.3 * t,
            interactive: false));
      }
      // Flying chosen → header crumb position.
      final from = _radial(fromAnchor, _chosenIndex, _prevNodes.length);
      final to = _anchor(orbCenter, depth);
      out.add(_headerOrb(_chosenNode!, Offset.lerp(from, to, t)!,
          scale: 1 - 0.1 * t, onTap: null));
      // Incoming level blooms.
      final toAnchor = _anchor(orbCenter, depth);
      for (var i = 0; i < current.length; i++) {
        final ct = ((t - 0.35) / 0.65 - i * 0.08).clamp(0.0, 1.0);
        if (ct <= 0) continue;
        final full = _radial(toAnchor, i, current.length);
        out.add(_childWidget(current[i], Offset.lerp(toAnchor, full, ct)!,
            opacity: ct,
            scale: 0.4 + 0.6 * ct,
            interactive: ct > 0.6,
            onTap: () => _onNodeTap(current, i, m)));
      }
    } else {
      // Steady, or open/pop bloom: fan the current level around the anchor.
      final anchor = _anchor(orbCenter, depth);
      final bloom = animating ? t : 1.0;
      for (var i = 0; i < current.length; i++) {
        final ct = (bloom - i * 0.06).clamp(0.0, 1.0);
        final full = _radial(anchor, i, current.length);
        out.add(_childWidget(current[i], Offset.lerp(anchor, full, ct)!,
            opacity: ct,
            scale: 0.4 + 0.6 * ct,
            interactive: ct > 0.6,
            onTap: () => _onNodeTap(current, i, m)));
      }
    }
  }

  // ---- Pieces ------------------------------------------------------------
  Widget _childWidget(_Node node, Offset pos,
      {required double opacity,
      required double scale,
      required bool interactive,
      VoidCallback? onTap}) {
    return Positioned(
      left: pos.dx - _childSize / 2,
      top: pos.dy - _childSize / 2,
      child: IgnorePointer(
        // A disabled node is fully inert — it can never fire, no matter where it
        // is in the bloom animation (item 6).
        ignoring: !interactive || !node.enabled,
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WithShortcutHint(
                  label: node.label,
                  child: GestureDetector(
                    onTap: node.enabled ? onTap : null,
                    child: Opacity(
                      opacity: node.enabled ? 1 : 0.32,
                      child: Glass(
                        layer: GlassLayer.orbMenu,
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: _childSize,
                          height: _childSize,
                          child: Icon(node.icon,
                              size: 20, color: ShapeColors.primaryText),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Opacity(
                  opacity: node.enabled ? 1 : 0.32,
                  child: Text(node.label,
                      style: ShapeText.labelXS
                          .copyWith(color: ShapeColors.secondaryText)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _crumb(int k, Offset pos) {
    final label = _path[k];
    return _headerOrb(
      _Node(label, _iconForBranch(label), branch: label),
      pos,
      scale: 1,
      onTap: () => _popTo(k),
    );
  }

  Widget _headerOrb(_Node node, Offset pos,
      {required double scale, VoidCallback? onTap}) {
    return Positioned(
      left: pos.dx - 22,
      top: pos.dy - 22,
      child: Transform.scale(
        scale: scale,
        child: GestureDetector(
          onTap: onTap,
          child: Glass(
            layer: GlassLayer.orbMenu,
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(node.icon, size: 19, color: ShapeColors.shapeBlue),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForBranch(String branch) => switch (branch) {
        'Create' => Icons.add,
        'Style' => Icons.palette_outlined,
        'Arrange' => Icons.dashboard_customize_outlined,
        'Combine' => Icons.account_tree_outlined,
        'Pathfind' => Icons.join_full,
        'Order' => Icons.layers_outlined,
        'Repeat' => Icons.grid_view_outlined,
        'File' => Icons.folder_outlined,
        'Place' => Icons.add_photo_alternate_outlined,
        'Blend' => Icons.gradient,
        'More' => Icons.more_horiz,
        _ => Icons.circle,
      };

  Widget _orb(EditorModel m, Offset center) {
    final selecting = m.selection.isNotEmpty;
    final pulse = 1 + 0.015 * math.sin(_breathe.value * math.pi * 2);
    return Positioned(
      left: center.dx - 28,
      top: center.dy - 28,
      child: GestureDetector(
        onTap: m.toggleOrb,
        child: Transform.scale(
          scale: pulse,
          child: Glass(
            layer: GlassLayer.halo,
            borderRadius: BorderRadius.circular(28),
            shadows: Glass.orbShadows,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [ShapeColors.lavender, ShapeColors.sky],
                    ),
                    border: Border.all(
                        color: selecting
                            ? ShapeColors.shapeBlue
                            : Colors.transparent,
                        width: 2),
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
