import 'package:flutter/services.dart';

/// One keyboard shortcut: how it reads on screen, and how it matches a key.
///
/// [ctrl] means the platform's command modifier — Ctrl on Windows/Linux, ⌘ on
/// macOS — so the same table serves both.
class ShapeShortcut {
  const ShapeShortcut(this.key, this.display,
      {this.ctrl = false, this.shift = false});

  final LogicalKeyboardKey key;

  /// Shown in the hover hint, e.g. `V` or `Ctrl+Shift+S`.
  final String display;
  final bool ctrl;
  final bool shift;

  bool matches(LogicalKeyboardKey pressed,
          {required bool ctrlDown, required bool shiftDown}) =>
      pressed == key && ctrlDown == ctrl && shiftDown == shift;
}

/// Every editor shortcut, keyed by the command's menu label.
///
/// This is the single source of truth for key bindings: the orb menu reads it
/// to render hover hints, and [EditorScreen] reads it to dispatch — so a hint
/// can never disagree with what the key actually does.
///
/// Deconfliction rules, enforced by `shortcuts_test.dart`:
///  * A bare letter never collides with another bare letter.
///  * A bare letter and the same letter under Ctrl are different commands
///    (`V` = Select vs `Ctrl+V` = Paste), which is why [matches] compares the
///    modifier state exactly rather than ignoring extra modifiers.
///  * Bare letters are suppressed entirely while text is being typed, so they
///    can never steal a character from the canvas text editor.
const Map<String, ShapeShortcut> kShortcuts = {
  // ---- Tools ----
  'Select': ShapeShortcut(LogicalKeyboardKey.keyV, 'V'),
  'Pen': ShapeShortcut(LogicalKeyboardKey.keyP, 'P'),
  'Draw': ShapeShortcut(LogicalKeyboardKey.keyB, 'B'),
  'Text': ShapeShortcut(LogicalKeyboardKey.keyT, 'T'),
  'Shapes': ShapeShortcut(LogicalKeyboardKey.keyS, 'S'),

  // ---- Style panels ----
  'Fill': ShapeShortcut(LogicalKeyboardKey.keyF, 'F'),
  'Strokes': ShapeShortcut(LogicalKeyboardKey.keyK, 'K'),
  'Effects': ShapeShortcut(LogicalKeyboardKey.keyE, 'E'),
  'Type': ShapeShortcut(LogicalKeyboardKey.keyY, 'Y'),
  'Shape': ShapeShortcut(LogicalKeyboardKey.keyU, 'U'),

  // ---- Arrange ----
  'Align': ShapeShortcut(LogicalKeyboardKey.keyA, 'A'),
  'Layers': ShapeShortcut(LogicalKeyboardKey.keyL, 'L'),
  'Repeat': ShapeShortcut(LogicalKeyboardKey.keyR, 'R'),
  // Bracket keys for stacking order — the cross-industry standard.
  'Forward': ShapeShortcut(LogicalKeyboardKey.bracketRight, ']'),
  'Backward': ShapeShortcut(LogicalKeyboardKey.bracketLeft, '['),
  'To Front':
      ShapeShortcut(LogicalKeyboardKey.bracketRight, 'Shift+]', shift: true),
  'To Back':
      ShapeShortcut(LogicalKeyboardKey.bracketLeft, 'Shift+[', shift: true),

  // ---- Combine ----
  'Nodes': ShapeShortcut(LogicalKeyboardKey.keyN, 'N'),
  'Mask': ShapeShortcut(LogicalKeyboardKey.keyM, 'M'),
  'Crop': ShapeShortcut(LogicalKeyboardKey.keyC, 'C'),

  // ---- File ----
  'New': ShapeShortcut(LogicalKeyboardKey.keyN, 'Ctrl+N', ctrl: true),
  'Save': ShapeShortcut(LogicalKeyboardKey.keyS, 'Ctrl+S', ctrl: true),
  'Projects':
      ShapeShortcut(LogicalKeyboardKey.keyO, 'Ctrl+O', ctrl: true),
  'Export': ShapeShortcut(LogicalKeyboardKey.keyE, 'Ctrl+E', ctrl: true),
  'Duplicate':
      ShapeShortcut(LogicalKeyboardKey.keyD, 'Ctrl+D', ctrl: true),

  // ---- Edit ----
  'Undo': ShapeShortcut(LogicalKeyboardKey.keyZ, 'Ctrl+Z', ctrl: true),
  'Redo': ShapeShortcut(LogicalKeyboardKey.keyY, 'Ctrl+Y', ctrl: true),
  'Select All': ShapeShortcut(LogicalKeyboardKey.keyA, 'Ctrl+A', ctrl: true),
  'Group': ShapeShortcut(LogicalKeyboardKey.keyG, 'Ctrl+G', ctrl: true),
  'Ungroup':
      ShapeShortcut(LogicalKeyboardKey.keyG, 'Ctrl+Shift+G', ctrl: true, shift: true),
  'Copy': ShapeShortcut(LogicalKeyboardKey.keyC, 'Ctrl+C', ctrl: true),
  'Cut': ShapeShortcut(LogicalKeyboardKey.keyX, 'Ctrl+X', ctrl: true),
  'Paste': ShapeShortcut(LogicalKeyboardKey.keyV, 'Ctrl+V', ctrl: true),

  // ---- View ----
  'Zoom to Fit': ShapeShortcut(LogicalKeyboardKey.digit0, '0'),
};

/// Menu labels that flip with state but fire the same toggle command, so the
/// hint follows the button rather than vanishing when it changes caption.
const Map<String, String> _labelAliases = {'Unmask': 'Mask', 'Ungroup': 'Group'};

/// The hint shown next to [label] in menus, or null when it has no shortcut.
String? shortcutHint(String label) =>
    kShortcuts[_labelAliases[label] ?? label]?.display;

/// What the orb's submenu branches contain. Branches open a level rather than
/// running a command, so they have no key — without this they'd be the only
/// things on screen with no hover text, and they're the *first* thing you see.
const Map<String, String> _branchBlurbs = {
  'Create': 'Shapes, pen, draw, text, place',
  'Style': 'Fill, strokes, effects, blend',
  'Arrange': 'Align, order, group, repeat, layers',
  'Combine': 'Pathfinder, nodes, mask, morph',
  'File': 'New, save, export, projects',
  'Place': 'Import an image or an SVG',
  'Blend': 'Blend modes',
  'Order': 'Move through the stack',
  'Repeat': 'Grid, radial or mirror array',
  'Pathfind': 'Union, minus, intersect, exclude',
  'More': 'Further options',
};

/// Hover text for any menu entry.
///
/// Every node gets one: `Pen · P` where a key exists, the blurb for a branch,
/// and the bare label otherwise — so hovering always tells you something.
String tooltipFor(String label) {
  final hint = shortcutHint(label);
  if (hint != null) return '$label · $hint';
  final blurb = _branchBlurbs[label];
  return blurb == null ? label : '$label · $blurb';
}
