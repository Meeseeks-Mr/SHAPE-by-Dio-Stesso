import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shape/screens/editor_screen.dart';
import 'package:shape/state/app_scope.dart';
import 'package:shape/state/editor_model.dart';
import 'package:shape/state/shortcuts.dart';

/// The orb's hover hints must be reachable in the running app, not merely wired
/// in source. This caught the real bug: the root level is all branches, none of
/// which have shortcuts, so the first screen of the menu had zero tooltips —
/// "no hover text anywhere".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<EditorModel> pumpEditor(WidgetTester tester) async {
    final m = EditorModel();
    addTearDown(m.dispose);
    await tester.pumpWidget(MaterialApp(
      home: AppScope(model: m, child: const EditorScreen()),
    ));
    await tester.pump();
    return m;
  }

  testWidgets('every node on the orb root level has hover text',
      (tester) async {
    final m = await pumpEditor(tester);
    m.toggleOrb();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Create'), findsOneWidget, reason: 'orb did not open');

    final tips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message)
        .toList();
    // Five branches on the root level, each must carry a hint.
    expect(tips.length, greaterThanOrEqualTo(5),
        reason: 'root level is missing tooltips: $tips');
    expect(tips, contains('Create · Shapes, pen, draw, text, place'));
    expect(tips, contains('File · New, save, export, projects'));
  });

  group('tooltipFor', () {
    test('a command shows its key', () {
      expect(tooltipFor('Pen'), 'Pen · P');
      expect(tooltipFor('Export'), 'Export · Ctrl+E');
      expect(tooltipFor('To Front'), 'To Front · Shift+]');
    });

    test('a branch shows what it contains', () {
      expect(tooltipFor('Style'), 'Style · Fill, strokes, effects, blend');
    });

    test('state-flipped labels keep their key', () {
      expect(tooltipFor('Unmask'), 'Unmask · M');
      expect(tooltipFor('Ungroup'), 'Ungroup · Ctrl+G');
    });

    test('anything else still returns its label rather than nothing', () {
      expect(tooltipFor('Union'), 'Union');
      expect(tooltipFor(''), '');
    });
  });
}
