import 'package:flutter/material.dart';

import '../../canvas/canvas_painter.dart';
import '../../state/app_scope.dart';
import '../../state/hindi.dart';
import '../../theme/fonts.dart';
import '../../theme/shape_theme.dart';
import '../glass.dart';

/// Inline text editor (§14.4). Shown while a text object is being edited; typing
/// updates the on-canvas object live and resizes its bounds. The input is
/// rendered in the object's CHOSEN font so non-Latin scripts (e.g. Devanagari)
/// are visible as you type, and a font strip lets you switch fonts mid-typing.
class TextEditOverlay extends StatefulWidget {
  const TextEditOverlay({super.key});

  @override
  State<TextEditOverlay> createState() => _TextEditOverlayState();
}

class _TextEditOverlayState extends State<TextEditOverlay> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _boundId;
  // Phonetic Hindi input: the field holds romanised Latin; the object shows the
  // transliterated Devanagari (item: Hindi typing).
  bool _hindi = false;

  static const _devanagariFonts = ['Mukta', 'Hind', 'Baloo 2', 'Tillana'];

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _bind(String id) {
    final m = AppScope.read(context);
    final o = m.byId(id);
    if (o == null) return;
    _boundId = id;
    _controller.text = o.text;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    m.beginGesture();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _onChanged(String value) {
    final m = AppScope.read(context);
    final o = m.byId(_boundId!);
    if (o == null) return;
    // In Hindi mode the canvas text is the Devanagari transliteration of what
    // was typed; otherwise it's the literal text.
    final text = _hindi ? transliterateHindi(value) : value;
    m.mutate(() {
      o.text = text;
      final tp = textPainterFor(o);
      o.size = Size(o.size.width, tp.height);
      o.name = text.isEmpty ? 'Text' : text;
    });
  }

  void _toggleHindi() {
    final m = AppScope.read(context);
    final o = m.byId(_boundId ?? '');
    setState(() => _hindi = !_hindi);
    if (_hindi && o != null) {
      // Ensure a Devanagari-capable font so the result actually renders (the
      // default face has no Devanagari glyphs).
      if (!_devanagariFonts.contains(o.fontFamily)) _applyFont('Mukta');
    }
    // Re-run the conversion on whatever is currently typed.
    _onChanged(_controller.text);
  }

  /// Live Devanagari preview of the romanised text the user is typing.
  Widget _hindiPreview(String? family) {
    final deva = transliterateHindi(_controller.text);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ShapeColors.shapeBlueGhost,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          deva.isEmpty ? 'Type Hinglish — e.g. "namaste" → नमस्ते' : deva,
          style: FontCatalog.style(
            family: _devanagariFonts.contains(family) ? family : 'Mukta',
            fontSize: 20,
            weight: FontWeight.w600,
            color: deva.isEmpty
                ? ShapeColors.tertiaryText
                : ShapeColors.primaryText,
          ),
        ),
      ),
    );
  }

  void _applyFont(String family) {
    final m = AppScope.read(context);
    final o = m.byId(_boundId!);
    if (o == null) return;
    m.mutate(() {
      o.fontFamily = family;
      final tp = textPainterFor(o);
      o.size = Size(o.size.width, tp.height);
    });
    setState(() {});
  }

  void _done() {
    final m = AppScope.read(context);
    m.commitGesture('Edit text');
    m.endTextEdit();
    _boundId = null;
    _hindi = false;
  }

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context);
    final id = m.editingTextId;
    if (id == null) {
      _boundId = null;
      return const SizedBox.shrink();
    }
    if (_boundId != id) _bind(id);
    final o = m.byId(id);
    final family = o?.fontFamily;

    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + pad,
      child: Glass(
        layer: GlassLayer.sheet,
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hindi (phonetic) toggle + font strip — switch on Hindi typing and
            // pick a font while you type (item 8).
            Row(children: [
              _HindiToggle(active: _hindi, onTap: _toggleHindi),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: FontCatalog.all.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final fam = FontCatalog.all[i];
                  final selected = (family ?? FontCatalog.defaultFamily) == fam;
                  return GestureDetector(
                    onTap: () => _applyFont(fam),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? ShapeColors.shapeBlue.withValues(alpha: 0.16)
                            : ShapeColors.fieldBase,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selected
                                ? ShapeColors.shapeBlue
                                : Colors.transparent),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        fam == FontCatalog.defaultFamily ? 'Default' : fam,
                        style: FontCatalog.preview(fam, size: 15).copyWith(
                            color: ShapeColors.primaryText),
                      ),
                    ),
                  );
                },
              ),
                ),
              ),
            ]),
            if (_hindi) _hindiPreview(family),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    maxLines: null,
                    // Render the input in the object's own font so the script is
                    // visible as you type (Devanagari, etc.) — item 8.
                    style: FontCatalog.style(
                      family: family,
                      fontSize: 20,
                      weight: FontWeight.w500,
                      color: ShapeColors.primaryText,
                    ),
                    cursorColor: ShapeColors.shapeBlue,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Type something…',
                      hintStyle: ShapeText.labelLG
                          .copyWith(color: ShapeColors.tertiaryText),
                    ),
                    onChanged: _onChanged,
                    onSubmitted: (_) => _done(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _done,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: ShapeColors.shapeBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Done',
                        style:
                            ShapeText.labelMD.copyWith(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The "हिं" toggle that switches phonetic Hindi typing on/off.
class _HindiToggle extends StatelessWidget {
  const _HindiToggle({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? ShapeColors.shapeBlue
              : ShapeColors.fieldBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? ShapeColors.shapeBlue : Colors.transparent),
        ),
        child: Text(
          'हिं',
          style: FontCatalog.style(
            family: 'Mukta',
            fontSize: 17,
            weight: FontWeight.w700,
            color: active ? Colors.white : ShapeColors.secondaryText,
          ),
        ),
      ),
    );
  }
}
