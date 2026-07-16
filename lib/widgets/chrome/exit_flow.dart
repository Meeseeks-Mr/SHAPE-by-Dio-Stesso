import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_scope.dart';
import '../../theme/shape_theme.dart';
import '../brand.dart';

/// The exit flow (§ requested): on exit, ask whether to save the project (which
/// is kept within the app and listed in history), let the user name it, then
/// leave. Because Shape also autosaves, this is a graceful confirmation rather
/// than a last line of defense.
class ExitFlow {
  static Future<void> attempt(BuildContext context) async {
    final model = AppScope.read(context);
    final controller = TextEditingController(text: model.projectName);

    final action = await showDialog<String>(
      context: context,
      barrierColor: ShapeColors.primaryText.withValues(alpha: 0.18),
      builder: (context) => Dialog(
        backgroundColor: ShapeColors.glassTint,
        surfaceTintColor: Colors.transparent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                ShapeMark(size: 26),
                SizedBox(width: 10),
                Text('Leaving so soon?',
                    style: ShapeText.titleSM, textAlign: TextAlign.start),
              ]),
              const SizedBox(height: 8),
              Text(
                'Name this project to keep it in your history. '
                'Shape autosaves, so nothing is lost either way.',
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.secondaryText, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                style: ShapeText.labelLG
                    .copyWith(color: ShapeColors.primaryText),
                cursorColor: ShapeColors.shapeBlue,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: ShapeColors.fieldBase,
                  hintText: 'Project name',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: ShapeColors.glassBorderDark, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: ShapeColors.shapeBlue, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => Navigator.pop(context, 'save'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'cancel'),
                    child: Text('Stay',
                        style: ShapeText.labelMD
                            .copyWith(color: ShapeColors.secondaryText)),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'leave'),
                    child: Text('Leave',
                        style: ShapeText.labelMD
                            .copyWith(color: ShapeColors.secondaryText)),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ShapeColors.shapeBlue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context, 'save'),
                    child: Text('Save & exit',
                        style: ShapeText.labelMD
                            .copyWith(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || action == 'cancel') return;
    if (action == 'save') {
      model.renameProject(controller.text);
      await model.saveNow();
    }
    // 'leave' relies on the most recent autosave.
    await SystemNavigator.pop();
  }
}
