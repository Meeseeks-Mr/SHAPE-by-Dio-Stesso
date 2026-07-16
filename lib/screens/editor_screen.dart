import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/canvas_view.dart';
import '../models/shape_object.dart';
import '../models/tool.dart';
import '../state/app_scope.dart';
import '../state/editor_model.dart';
import '../state/shortcuts.dart';
import '../theme/shape_theme.dart';
import '../widgets/chrome/context_menu.dart';
import '../widgets/chrome/save_dialog.dart';
import '../widgets/chrome/top_chrome.dart';
import '../widgets/chrome/workspace_panel.dart';
import '../widgets/halo/property_halo.dart';
import '../widgets/orb/main_orb.dart';
import '../widgets/overlays/node_edit_hud.dart';
import '../widgets/overlays/perspective_hud.dart';
import '../widgets/overlays/text_edit_overlay.dart';
import '../widgets/overlays/tool_hud.dart';
import '../widgets/sheets/sheet_host.dart';

/// The single editor surface. Everything is layered above the canvas in a
/// Stack (§25.2) — the canvas never rebuilds when chrome changes and vice
/// versa, thanks to the RepaintBoundary in [CanvasView]. Also persists the
/// project when the app is backgrounded (§25.5).
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  EditorModel? _model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _model?.saveNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = AppScope.read(context);
    _model = m;
    return Scaffold(
      backgroundColor: ShapeColors.paper,
      resizeToAvoidBottomInset: false,
      body: _Shortcuts(
        model: m,
        child: const Stack(
          children: [
            // Layer 0 — canvas (user content).
            Positioned.fill(child: CanvasView()),
            // Property halo (Layer 1) around the single selection.
            Positioned.fill(child: PropertyHaloLayer()),
            // Permanent top chrome.
            Align(alignment: Alignment.topCenter, child: TopChrome()),
            // These four place themselves with their own Positioned, so they
            // must be direct Stack children — wrapping them in Positioned.fill
            // makes two ParentDataWidgets fight over one RenderObject, which
            // throws on every build.
            ToolHud(),
            NodeEditHud(),
            PerspectiveHud(),
            // The orb + radial menus.
            Positioned.fill(child: MainOrbLayer()),
            // Contextual floating drawers (Layer 3).
            Positioned.fill(child: SheetHost()),
            // Inline text editor.
            TextEditOverlay(),
            // Long-press radial context menu.
            Positioned.fill(child: ContextMenuLayer()),
            // Workspace slide-in (Layer 4).
            Positioned.fill(child: WorkspacePanel()),
          ],
        ),
      ),
    );
  }
}

/// Hardware keyboard shortcuts for tablets/desktop (§21.6).
///
/// Bindings live in [kShortcuts] and actions in [_actions], joined by label —
/// so the hint the orb shows on hover and the key that fires here can't drift.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.model, required this.child});
  final EditorModel model;
  final Widget child;

  /// True when a text input owns the keyboard. Bare-letter shortcuts must stay
  /// out of its way, or typing "s" into a name field would open the Shapes
  /// drawer instead of inserting a character.
  bool get _typing {
    if (model.editingTextId != null) return true;
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    return focused is EditableText;
  }

  /// What each labelled command does. Guards mirror the orb's own enablement,
  /// so a key can never reach a command the menu would have shown greyed out.
  Map<String, VoidCallback> _actions(BuildContext context) {
    final m = model;
    final hasSel = m.selection.isNotEmpty;
    final single = m.singleSelection;
    void sheet(ActiveSheet s) => m.openSheet(s);

    return {
      // Tools
      'Select': () => m.setTool(ActiveTool.none),
      'Pen': () => m.setTool(ActiveTool.pen),
      'Draw': () => m.setTool(ActiveTool.draw),
      'Text': () => m.setTool(ActiveTool.text),
      'Shapes': () => sheet(ActiveSheet.shapes),

      // Style — all need something to style.
      if (hasSel) 'Fill': () => sheet(ActiveSheet.fill),
      if (hasSel) 'Strokes': () => sheet(ActiveSheet.strokes),
      if (hasSel) 'Effects': () => sheet(ActiveSheet.effects),
      if (single?.type == ShapeType.text) 'Type': () => sheet(ActiveSheet.typography),
      if (single != null && single.type != ShapeType.text)
        'Shape': () => sheet(ActiveSheet.shapeParams),
      if (hasSel) 'Crop': () => sheet(ActiveSheet.crop),

      // Arrange
      if (m.selection.length >= 2) 'Align': () => sheet(ActiveSheet.align),
      'Layers': () => sheet(ActiveSheet.layers),
      if (hasSel) 'Repeat': () => m.openRepeatSheet(0),
      if (hasSel) 'Forward': m.bringForward,
      if (hasSel) 'Backward': m.sendBackward,
      if (hasSel) 'To Front': m.bringToFront,
      if (hasSel) 'To Back': m.sendToBack,

      // Combine
      if (m.canNodeEdit(single)) 'Nodes': () => m.enterNodeEdit(single!.id),
      if (m.selection.length >= 2 || m.selectionHasMask)
        'Mask': m.selectionHasMask ? m.releaseMask : m.maskSelection,

      // File
      'New': m.newProject,
      'Save': () => promptSaveAs(context, model),
      'Projects': () => m.setWorkspace(true),
      'Export': () => sheet(ActiveSheet.export),
      if (hasSel) 'Duplicate': m.duplicateSelection,

      // Edit
      'Undo': m.undo,
      'Redo': m.redo,
      'Select All': m.selectAll,
      if (m.selection.length >= 2) 'Group': m.groupSelection,
      if (m.selectionHasGroup) 'Ungroup': m.ungroupSelection,
      if (hasSel) 'Copy': m.copySelection,
      if (hasSel) 'Cut': m.cutSelection,
      'Paste': m.pasteClipboard,

      // View
      'Zoom to Fit': () => m.zoomToFit(MediaQuery.sizeOf(context)),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // While editing text the keyboard belongs to the text field. Especially
        // Backspace/Delete, which would otherwise delete the very object being
        // edited (leaving the editor with no target, appearing to hang).
        if (_typing) return KeyEventResult.ignored;

        final ctrl = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        final key = event.logicalKey;

        // Keys with no menu entry of their own.
        if (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) {
          model.deleteSelection();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          model.closeSheet();
          model.collapseOrb();
          model.clearSelection();
          return KeyEventResult.handled;
        }

        final actions = _actions(context);
        for (final entry in kShortcuts.entries) {
          if (!entry.value.matches(key, ctrlDown: ctrl, shiftDown: shift)) {
            continue;
          }
          final action = actions[entry.key];
          // Bound but currently unavailable (e.g. Fill with nothing selected):
          // swallow it rather than let it fall through to another binding.
          if (action == null) return KeyEventResult.handled;
          action();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
