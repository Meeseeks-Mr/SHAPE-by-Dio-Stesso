import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shape/models/shape_object.dart';
import 'package:shape/state/editor_model.dart';

/// `commitGesture` used to re-snapshot whatever was selected at commit time and
/// index it with `after[id]!`. If the selection changed after `beginGesture`
/// (e.g. tapping the canvas while the text editor is open clears it), that `!`
/// threw "Unexpected null value" — and because `_gestureBefore` was only
/// cleared on the last line, the throw also stranded `editingTextId`, killing
/// every keyboard shortcut for the rest of the session.
void main() {
  // selectOnly fires HapticFeedback, which needs a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  ShapeObject rect([Offset c = const Offset(50, 50)]) => ShapeObject(
        type: ShapeType.rectangle,
        center: c,
        size: const Size(40, 40),
      );

  test('commit survives the selection being cleared mid-gesture', () {
    final m = EditorModel();
    addTearDown(m.dispose);
    final o = rect();
    m.addObject(o);
    m.beginGesture();
    o.center = const Offset(80, 80);
    m.clearSelection(); // what a canvas tap does
    expect(() => m.commitGesture('Move'), returnsNormally);
  });

  test('commit survives the object being deleted mid-gesture', () {
    final m = EditorModel();
    addTearDown(m.dispose);
    m.addObject(rect());
    m.beginGesture();
    m.deleteSelection();
    expect(() => m.commitGesture('Move'), returnsNormally);
  });

  test('commit survives the selection changing to a different object', () {
    final m = EditorModel();
    addTearDown(m.dispose);
    final a = rect();
    final b = rect(const Offset(300, 300));
    m.addObject(a);
    m.beginGesture();
    a.center = const Offset(90, 90);
    m.addObject(b); // selects b, dropping a from the selection
    expect(() => m.commitGesture('Move'), returnsNormally);
  });

  test('a real edit still lands on the undo stack', () {
    final m = EditorModel();
    addTearDown(m.dispose);
    final o = rect();
    m.addObject(o);
    final before = o.center;
    m.beginGesture();
    o.center = const Offset(123, 45);
    m.commitGesture('Move');
    expect(m.canUndo, isTrue);
    m.undo();
    expect(m.byId(o.id)!.center, before, reason: 'undo must restore the move');
  });

  test('a no-op gesture does not litter the undo stack', () {
    final m = EditorModel();
    addTearDown(m.dispose);
    // The welcome composition is seeded in the constructor and is deliberately
    // not part of undo history, so measure against it rather than zero.
    final seeded = m.objects.length;
    m.addObject(rect());
    m.beginGesture();
    m.commitGesture('Nothing changed');
    m.undo(); // undoes the add — the no-op gesture must not have pushed
    expect(m.objects.length, seeded);
    expect(m.canUndo, isFalse);
  });

  test('a throw cannot strand the gesture and wedge the next one', () {
    final m = EditorModel();
    addTearDown(m.dispose);
    m.addObject(rect());
    m.beginGesture();
    m.deleteSelection();
    m.commitGesture('Move'); // previously threw and left _gestureBefore set
    // A fresh gesture on a new object must still record normally.
    final o = rect(const Offset(10, 10));
    m.addObject(o);
    m.beginGesture();
    o.center = const Offset(200, 200);
    m.commitGesture('Move again');
    expect(m.canUndo, isTrue);
  });
}
