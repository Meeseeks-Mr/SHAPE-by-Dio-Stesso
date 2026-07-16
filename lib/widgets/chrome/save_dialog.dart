import 'package:flutter/material.dart';

import '../../state/editor_model.dart';
import '../../theme/shape_theme.dart';

/// "Save As" — names an Untitled draft (or renames the current document) and
/// persists it. Untitled drafts are never auto-saved, so this is the only way
/// they become a saved project. Returns true if the user saved.
Future<bool> promptSaveAs(BuildContext context, EditorModel m) async {
  final controller = TextEditingController(
      text: m.projectName == 'Untitled' ? '' : m.projectName);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ShapeColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Save project',
          style: ShapeText.labelLG.copyWith(color: ShapeColors.primaryText)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: ShapeText.labelLG.copyWith(color: ShapeColors.primaryText),
        decoration: InputDecoration(
          hintText: 'Project name',
          hintStyle: ShapeText.labelMD
              .copyWith(color: ShapeColors.tertiaryText),
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: ShapeColors.glassBorderDark)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: ShapeColors.shapeBlue, width: 2)),
        ),
        onSubmitted: (_) => Navigator.of(ctx).pop(true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel',
              style: ShapeText.labelMD
                  .copyWith(color: ShapeColors.secondaryText)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Save',
              style: ShapeText.labelMD.copyWith(color: ShapeColors.shapeBlue)),
        ),
      ],
    ),
  );
  if (saved != true) return false;
  await m.saveAs(controller.text);
  return true;
}
