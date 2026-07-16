import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shape/app.dart';
import 'package:shape/models/shape_object.dart';
import 'package:shape/screens/editor_screen.dart';
import 'package:shape/state/app_scope.dart';
import 'package:shape/state/editor_model.dart';

void main() {
  testWidgets('Shape boots to the editor scaffold',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Scaffold), findsOneWidget);
  });

  // The editor's Stack mixes self-positioning overlays with Positioned.fill
  // wrappers. Getting that wrong makes two ParentDataWidgets write the same
  // RenderObject, which throws on every single build — so assert the editor
  // mounts clean rather than only that *a* Scaffold exists.
  testWidgets('the editor builds without widget exceptions',
      (WidgetTester tester) async {
    final model = EditorModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(MaterialApp(
      home: AppScope(model: model, child: const EditorScreen()),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(EditorScreen), findsOneWidget);
  });

  test('hit testing respects an object\'s bounds', () {
    final o = ShapeObject(
      type: ShapeType.rectangle,
      center: const Offset(100, 100),
      size: const Size(80, 40),
    );
    expect(o.hitTest(const Offset(100, 100)), isTrue);
    expect(o.hitTest(const Offset(400, 400)), isFalse);
  });
}
