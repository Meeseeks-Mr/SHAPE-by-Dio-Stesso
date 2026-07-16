import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../state/exporter.dart';
import '../../theme/shape_theme.dart';
import 'controls.dart';
import 'sheet_host.dart';

/// Compact export wizard (§17): scope · format · scale · export.
class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key});
  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  int _scope = 0; // 0 = selection, 1 = whole project
  int _format = 1; // 0 SVG, 1 PNG, 2 JPG-ish(PNG opaque)
  int _scale = 1; // index into [1,2,3,4]
  bool _busy = false;

  static const _scales = [1, 2, 3, 4];

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Export'),
        Segmented(
          options: const ['Selection', 'Project'],
          selected: _scope,
          onChanged: (i) => setState(() => _scope = i),
        ),
        const SizedBox(height: 12),
        Segmented(
          options: const ['SVG', 'PNG', 'JPG'],
          selected: _format,
          onChanged: (i) => setState(() => _format = i),
        ),
        if (_format != 0) ...[
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
                width: 60,
                child: Text('Scale',
                    style: ShapeText.labelMD
                        .copyWith(color: ShapeColors.secondaryText))),
            for (var i = 0; i < _scales.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _scale = i),
                  child: Container(
                    width: 44,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == _scale
                          ? ShapeColors.shapeBlue.withValues(alpha: 0.18)
                          : ShapeColors.fieldBase,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: i == _scale
                              ? ShapeColors.shapeBlue
                              : Colors.transparent),
                    ),
                    child: Text('${_scales[i]}×',
                        style: ShapeText.labelMD
                            .copyWith(color: ShapeColors.primaryText)),
                  ),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ShapeColors.shapeBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _busy ? null : () => _export(m),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('Export ${_label()}',
                    style: ShapeText.labelLG.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  String _label() => switch (_format) { 0 => 'SVG', 1 => 'PNG', _ => 'JPG' };

  /// Shown when Export is tapped under "Selection" scope with nothing selected.
  Future<bool?> _confirmExportProject() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ShapeColors.surfaceCarbon,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Nothing selected',
              style: ShapeText.titleSM
                  .copyWith(color: ShapeColors.primaryText)),
          content: Text(
            'No objects are selected. Export the whole project instead?',
            style:
                ShapeText.labelMD.copyWith(color: ShapeColors.secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: ShapeText.labelLG
                      .copyWith(color: ShapeColors.secondaryText)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: ShapeColors.shapeBlue),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Export project',
                  style: ShapeText.labelLG.copyWith(color: Colors.white)),
            ),
          ],
        ),
      );

  Future<void> _export(EditorModel m) async {
    var scope = _scope;
    // Selection scope with nothing selected: ask before falling back to the
    // whole project instead of silently switching.
    if (scope == 0 && m.selectedObjects.isEmpty) {
      final exportProject = await _confirmExportProject();
      if (exportProject != true) return;
      scope = 1;
    }
    final objs = scope == 0 ? m.selectedObjects : m.objects;
    if (objs.isEmpty) return;
    setState(() => _busy = true);
    try {
      final name = m.projectName.replaceAll(' ', '_');
      String? where;
      if (_format == 0) {
        final svg = Exporter.svg(objs);
        where = await _saveToDownloads(
            name, 'svg', 'image/svg+xml', Uint8List.fromList(utf8.encode(svg)));
      } else {
        final bytes = await Exporter.png(objs,
            scale: _scales[_scale].toDouble(),
            background:
                _format == 2 ? const Color(0xFFFFFFFF) : null);
        if (bytes != null) {
          where = await _saveToDownloads(name, 'png', 'image/png', bytes);
        }
      }
      if (mounted) {
        m.closeSheet();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(where == null
                  ? 'Exported'
                  : 'Saved to $where')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves [bytes] to the device Downloads folder via the native MediaStore
  /// channel (Android). Falls back to the platform file-saver elsewhere or if
  /// the channel is unavailable. Returns a human-readable location.
  static const _exportChannel = MethodChannel('shape/export');

  Future<String> _saveToDownloads(
      String name, String ext, String mime, Uint8List bytes) async {
    try {
      final res = await _exportChannel.invokeMethod<String>('saveToDownloads', {
        'name': name,
        'ext': ext,
        'mime': mime,
        'bytes': bytes,
      });
      if (res != null) return res;
    } on MissingPluginException {
      // Not Android (web/desktop) — fall through to the cross-platform saver.
    } on PlatformException {
      // Native save failed — fall through to the cross-platform saver.
    }
    await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        ext: ext,
        mimeType: ext == 'svg' ? MimeType.other : MimeType.png);
    return 'Downloads';
  }
}
