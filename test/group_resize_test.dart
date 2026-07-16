import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shape/models/shape_object.dart';
import 'package:shape/screens/editor_screen.dart';
import 'package:shape/state/app_scope.dart';
import 'package:shape/state/editor_model.dart';

/// The group bounding box painted around a multi-selection had corner handles
/// drawn but never hit-tested (`_hitHandle` bails on `singleSelection == null`),
/// so grabbing them did nothing. These drive the real canvas to prove the
/// handles resize the whole selection, and that the maths is right.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewport = Size(1000, 800);

  /// Mounts the editor with [objects] selected and the viewport identity-mapped
  /// (zoom 1, no pan) so canvas coords == screen coords and drag maths is
  /// checkable by hand.
  Future<EditorModel> pumpWith(
      WidgetTester tester, List<ShapeObject> objects) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final m = EditorModel();
    addTearDown(m.dispose);
    await tester.pumpWidget(MaterialApp(
      home: AppScope(model: m, child: const EditorScreen()),
    ));
    await tester.pump();

    m.newProject(); // drop the welcome composition
    await tester.pump();
    for (final o in objects) {
      m.addObject(o);
    }
    m.selectAll();
    m.setViewport(1.0, Offset.zero);
    await tester.pump();
    return m;
  }

  ShapeObject rect(Offset c, [Size s = const Size(100, 100), double rot = 0]) =>
      ShapeObject(
          type: ShapeType.rectangle, center: c, size: s, rotation: rot);

  /// Drags [from] by [delta] in two steps.
  ///
  /// A single big `moveBy` would clear touch-slop and fire `onScaleStart` only
  /// once the pointer was already far from the handle — which is what a real
  /// finger does too, and precisely why the grab tests the pointer-down
  /// position rather than the scale focal point.
  Future<void> dragHandle(WidgetTester tester, Offset from, Offset delta) async {
    final g = await tester.startGesture(from);
    await tester.pump();
    await g.moveBy(const Offset(20, 20)); // past slop
    await tester.pump();
    await g.moveBy(delta - const Offset(20, 20));
    await tester.pump();
    await g.up();
    // Outlive the double-tap recogniser's timer, or teardown fails on it.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('dragging a group corner scales the whole selection',
      (tester) async {
    // Two 100×100 squares → group bounds (100,100)-(400,300), i.e. 300×200.
    final a = rect(const Offset(150, 150));
    final b = rect(const Offset(350, 250));
    final m = await pumpWith(tester, [a, b]);

    final gb = m.selectionBounds!;
    expect(gb, const Rect.fromLTRB(100, 100, 400, 300));

    // The handle sits on the padded box (inflate 8 at zoom 1) → (408, 308).
    final handle = gb.inflate(8).bottomRight;
    // Anchor is topLeft (100,100). Land the pointer on (700,500) so both axes
    // give exactly 2×: (700-100)/300 = 2 and (500-100)/200 = 2.
    await dragHandle(tester, handle, const Offset(292, 192));

    expect(m.byId(a.id)!.size.width, closeTo(200, 0.5));
    expect(m.byId(b.id)!.size.width, closeTo(200, 0.5));
    expect(m.byId(a.id)!.center.dx, closeTo(200, 0.5)); // 100 + (150-100)*2
    expect(m.byId(b.id)!.center.dx, closeTo(600, 0.5)); // 100 + (350-100)*2
  });

  testWidgets('the anchored corner stays put', (tester) async {
    final a = rect(const Offset(150, 150));
    final b = rect(const Offset(350, 250));
    final m = await pumpWith(tester, [a, b]);
    final gb = m.selectionBounds!;

    await dragHandle(tester, gb.inflate(8).bottomRight, const Offset(150, 100));

    // Grabbing bottom-right anchors top-left: it must not move.
    final after = m.selectionBounds!;
    expect(after.left, closeTo(gb.left, 1.5));
    expect(after.top, closeTo(gb.top, 1.5));
    expect(after.width, greaterThan(gb.width), reason: 'should have grown');
  });

  testWidgets('dragging the top-left corner anchors the bottom-right',
      (tester) async {
    final a = rect(const Offset(150, 150));
    final b = rect(const Offset(350, 250));
    final m = await pumpWith(tester, [a, b]);
    final gb = m.selectionBounds!;

    await dragHandle(tester, gb.inflate(8).topLeft, const Offset(75, 50));

    final after = m.selectionBounds!;
    expect(after.right, closeTo(gb.right, 1.5));
    expect(after.bottom, closeTo(gb.bottom, 1.5));
    expect(after.width, lessThan(gb.width), reason: 'should have shrunk');
  });

  testWidgets('rotation is preserved (uniform scale must not shear)',
      (tester) async {
    final a = rect(const Offset(150, 150), const Size(100, 100), math.pi / 5);
    final b = rect(const Offset(350, 250));
    final m = await pumpWith(tester, [a, b]);

    await dragHandle(
        tester, m.selectionBounds!.inflate(8).bottomRight, const Offset(200, 150));

    expect(m.byId(a.id)!.rotation, closeTo(math.pi / 5, 1e-9));
    // ...and it must actually stay square, not become a parallelogram.
    final s = m.byId(a.id)!.size;
    expect(s.width, closeTo(s.height, 0.01));
  });

  testWidgets('a group resize is one undoable step', (tester) async {
    final a = rect(const Offset(150, 150));
    final b = rect(const Offset(350, 250));
    final m = await pumpWith(tester, [a, b]);
    final size0 = a.size;

    await dragHandle(
        tester, m.selectionBounds!.inflate(8).bottomRight, const Offset(300, 200));
    expect(m.byId(a.id)!.size.width, isNot(closeTo(size0.width, 1)));

    m.undo();
    // undo() kicks off a highlight-pulse timer; outlive it before teardown.
    await tester.pump(const Duration(milliseconds: 400));
    expect(m.byId(a.id)!.size.width, closeTo(size0.width, 0.01));
    expect(m.byId(b.id)!.size.width, closeTo(size0.width, 0.01),
        reason: 'both objects must revert together');
  });

  testWidgets('dragging inside the box still moves rather than resizes',
      (tester) async {
    final a = rect(const Offset(150, 150));
    final b = rect(const Offset(350, 250));
    final m = await pumpWith(tester, [a, b]);
    final size0 = a.size;

    // Grab the middle of object a, well away from any corner.
    await dragHandle(tester, const Offset(150, 150), const Offset(40, 0));

    expect(m.byId(a.id)!.size, size0, reason: 'move must not scale');
    // Move tracks focalPointDelta, so the slop leg is consumed rather than
    // applied: the object follows the post-slop travel of (+20, -20).
    expect(m.byId(a.id)!.center.dx, closeTo(170, 2));
    expect(m.byId(a.id)!.center.dy, closeTo(130, 2));
  });
}
