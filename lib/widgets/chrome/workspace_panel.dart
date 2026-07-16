import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../state/editor_model.dart';
import '../../state/project_store.dart';
import '../../theme/shape_theme.dart';
import '../brand.dart';
import 'save_dialog.dart';

/// Workspace / file menu — §19. Slides in from the left as a frosted panel.
/// Hosts New / Save plus the persisted project history (open & delete).
class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final open = m.workspaceOpen;
    final width = (MediaQuery.of(context).size.width * 0.78).clamp(0.0, 360.0);

    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      ignoring: !open,
      child: Stack(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: open ? 1 : 0,
            child: GestureDetector(
              onTap: () => m.setWorkspace(false),
              child: Container(
                  color: ShapeColors.primaryText.withValues(alpha: 0.10)),
            ),
          ),
          // Compact floating modal (not a full-height drawer).
          Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              scale: open ? 1 : 0.92,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: open ? 1 : 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: width.clamp(0.0, 380.0),
                      maxHeight: size.height * 0.7),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: GlassLayer.workspace.sigma,
                          sigmaY: GlassLayer.workspace.sigma),
                      child: Container(
                        decoration: BoxDecoration(
                          color: ShapeColors.glassTint.withValues(
                              alpha: GlassLayer.workspace.tintOpacity),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: ShapeColors.softShadow,
                          border: Border.all(
                              color: ShapeColors.glassBorderDark, width: 0.6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: open ? _Body(m) : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.m);
  final EditorModel m;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Row(children: [
          ShapeMark(size: 26),
          SizedBox(width: 10),
          Wordmark(large: true),
        ]),
        const SizedBox(height: 4),
        const Divider(color: ShapeColors.glassBorderDark, height: 18),
        _Row(
          icon: Icons.add_box_outlined,
          label: 'New Document',
          onTap: () async {
            await m.newProject();
            m.setWorkspace(false);
          },
        ),
        _Row(
          icon: Icons.save_outlined,
          label: 'Save As…',
          onTap: () async {
            final didSave = await promptSaveAs(context, m);
            if (!context.mounted || !didSave) return;
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(content: Text('Saved "${m.projectName}"')));
            m.setWorkspace(false);
          },
        ),
        // Disk documents — durable across cleared site data, unlike the
        // browser-storage projects listed below.
        _Row(
          icon: Icons.download_outlined,
          label: 'Save to Disk…',
          onTap: () => _saveToDisk(context, m),
        ),
        _Row(
          icon: Icons.folder_open_outlined,
          label: 'Open from Disk…',
          onTap: () => _openFromDisk(context, m),
        ),
        const Divider(color: ShapeColors.glassBorderDark, height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('PROJECTS',
              style: ShapeText.labelXS.copyWith(
                  color: ShapeColors.tertiaryText,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600)),
        ),
        Flexible(child: _ProjectList(m)),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Writes the open document to the user's downloads as a `.shape` file.
Future<void> _saveToDisk(BuildContext context, EditorModel m) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = Uint8List.fromList(utf8.encode(m.toDocumentJson()));
    await FileSaver.instance.saveFile(
      name: m.projectName.replaceAll(' ', '_'),
      bytes: bytes,
      ext: 'shape',
      mimeType: MimeType.other,
    );
    m.setWorkspace(false);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
          SnackBar(content: Text('Saved "${m.projectName}.shape" to disk')));
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Save failed: $e')));
  }
}

/// Loads a `.shape` file from disk, replacing the open document.
Future<void> _openFromDisk(BuildContext context, EditorModel m) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['shape'],
      withData: true, // web hands back bytes, never a path
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return; // cancelled
    await m.openDocumentJson(utf8.decode(bytes));
    m.setWorkspace(false);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Opened "${m.projectName}"')));
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
          const SnackBar(content: Text("That file isn't a Shape document")));
  }
}

class _ProjectList extends StatefulWidget {
  const _ProjectList(this.m);
  final EditorModel m;
  @override
  State<_ProjectList> createState() => _ProjectListState();
}

class _ProjectListState extends State<_ProjectList> {
  late Future<List<ProjectMeta>> _future;

  @override
  void initState() {
    super.initState();
    _future = ProjectStore.instance.index();
  }

  void _refresh() => setState(() => _future = ProjectStore.instance.index());

  Future<void> _confirmDelete(BuildContext context, ProjectMeta p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ShapeColors.paper,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete project?',
            style: ShapeText.labelLG
                .copyWith(color: ShapeColors.primaryText)),
        content: Text(
            'This permanently removes "${p.name}". This can\'t be undone.',
            style: ShapeText.labelMD
                .copyWith(color: ShapeColors.secondaryText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.secondaryText)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.destructive)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ProjectStore.instance.delete(p.id);
    // If we just deleted the document that's open, start a fresh untitled one.
    if (p.id == widget.m.projectId) await widget.m.newProject();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProjectMeta>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data ?? const <ProjectMeta>[];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text('No saved projects yet.',
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.secondaryText)),
          );
        }
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: items.length,
          itemBuilder: (context, i) {
            final p = items[i];
            final isCurrent = p.id == widget.m.projectId;
            return Dismissible(
              key: ValueKey(p.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete_outline,
                    color: ShapeColors.destructive),
              ),
              onDismissed: (_) async {
                await ProjectStore.instance.delete(p.id);
                _refresh();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await widget.m.openProject(p.id);
                  widget.m.setWorkspace(false);
                },
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? ShapeColors.shapeBlue.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCurrent ? Icons.folder_open : Icons.folder_outlined,
                        size: 22,
                        color: isCurrent
                            ? ShapeColors.shapeBlue
                            : ShapeColors.secondaryText,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ShapeText.labelLG.copyWith(
                                    color: ShapeColors.primaryText,
                                    fontWeight: FontWeight.w500)),
                            Text('${p.count} objects · ${p.relativeTime}',
                                style: ShapeText.labelXS.copyWith(
                                    color: ShapeColors.tertiaryText)),
                          ],
                        ),
                      ),
                      // Explicit delete button next to the name (item 1).
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _confirmDelete(context, p),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.delete_outline,
                              size: 20, color: ShapeColors.destructive),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Icon(icon, size: 20, color: ShapeColors.secondaryText),
            const SizedBox(width: 16),
            Text(label,
                style: ShapeText.labelLG.copyWith(
                    color: ShapeColors.primaryText,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
