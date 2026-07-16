import 'package:flutter_test/flutter_test.dart';
import 'package:shape/state/shortcuts.dart';

/// Guards the deconfliction contract documented on [kShortcuts]. A collision
/// here means two commands fire on one keypress — the exact failure the table
/// exists to prevent.
void main() {
  String combo(ShapeShortcut s) =>
      '${s.ctrl ? 'ctrl+' : ''}${s.shift ? 'shift+' : ''}${s.key.keyLabel}';

  test('no two commands share the same key combination', () {
    final seen = <String, String>{};
    final clashes = <String>[];
    kShortcuts.forEach((label, s) {
      final c = combo(s);
      if (seen.containsKey(c)) {
        clashes.add('$c is bound to both "${seen[c]}" and "$label"');
      }
      seen[c] = label;
    });
    expect(clashes, isEmpty, reason: clashes.join('\n'));
  });

  test('display string matches the actual modifiers', () {
    kShortcuts.forEach((label, s) {
      expect(s.display.contains('Ctrl'), s.ctrl,
          reason: '"$label" display "${s.display}" disagrees with ctrl=${s.ctrl}');
      expect(s.display.contains('Shift'), s.shift,
          reason:
              '"$label" display "${s.display}" disagrees with shift=${s.shift}');
    });
  });

  test('a bare letter and its Ctrl twin stay distinct commands', () {
    // V=Select vs Ctrl+V=Paste, C=Crop vs Ctrl+C=Copy, and friends: matches()
    // must compare modifiers exactly, not ignore extra ones.
    final select = kShortcuts['Select']!;
    expect(select.matches(select.key, ctrlDown: false, shiftDown: false), isTrue);
    expect(select.matches(select.key, ctrlDown: true, shiftDown: false), isFalse);

    final paste = kShortcuts['Paste']!;
    expect(paste.matches(paste.key, ctrlDown: true, shiftDown: false), isTrue);
    expect(paste.matches(paste.key, ctrlDown: false, shiftDown: false), isFalse);
  });

  test('shift-qualified order commands do not swallow their bare twins', () {
    final forward = kShortcuts['Forward']!;
    final toFront = kShortcuts['To Front']!;
    expect(forward.key, toFront.key); // same physical key...
    // ...told apart purely by Shift.
    expect(forward.matches(forward.key, ctrlDown: false, shiftDown: true), isFalse);
    expect(toFront.matches(toFront.key, ctrlDown: false, shiftDown: true), isTrue);
  });

  test('every shortcut has a non-empty hint', () {
    for (final label in kShortcuts.keys) {
      expect(shortcutHint(label), isNotEmpty);
    }
    expect(shortcutHint('NotACommand'), isNull);
  });
}
