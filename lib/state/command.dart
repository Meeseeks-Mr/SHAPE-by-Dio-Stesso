import '../models/shape_object.dart';

/// Command pattern for undo/redo — §25.3. Every user action is encapsulated as
/// a [Command] with execute/undo/description. The model owns the stacks.
abstract class Command {
  String get description;
  void execute(List<ShapeObject> objects);
  void undo(List<ShapeObject> objects);

  /// Ids the command affected — used to drive the Shape Blue "what changed"
  /// pulse on undo/redo (§6 Undo/Redo).
  Iterable<String> get affectedIds;
}

/// Adds a new object to the top of the stack.
class AddObjectCommand extends Command {
  AddObjectCommand(this.object);
  final ShapeObject object;

  @override
  String get description => 'Add ${object.name}';
  @override
  Iterable<String> get affectedIds => [object.id];

  @override
  void execute(List<ShapeObject> objects) => objects.add(object);
  @override
  void undo(List<ShapeObject> objects) =>
      objects.removeWhere((o) => o.id == object.id);
}

/// Removes one or more objects, preserving their stack indices for undo.
class DeleteObjectsCommand extends Command {
  DeleteObjectsCommand(List<ShapeObject> all, this.targets)
      : _indices = {for (final o in targets) o.id: all.indexOf(o)};
  final List<ShapeObject> targets;
  final Map<String, int> _indices;

  @override
  String get description =>
      targets.length == 1 ? 'Delete ${targets.first.name}' : 'Delete ${targets.length} objects';
  @override
  Iterable<String> get affectedIds => targets.map((o) => o.id);

  @override
  void execute(List<ShapeObject> objects) {
    final ids = targets.map((o) => o.id).toSet();
    objects.removeWhere((o) => ids.contains(o.id));
  }

  @override
  void undo(List<ShapeObject> objects) {
    final ordered = targets.toList()
      ..sort((a, b) => _indices[a.id]!.compareTo(_indices[b.id]!));
    for (final o in ordered) {
      final i = _indices[o.id]!.clamp(0, objects.length);
      objects.insert(i, o);
    }
  }
}

/// Replaces an object instance in place (same stack index) — used when an
/// object's immutable [ShapeObject.type] must change, e.g. expanding a
/// primitive into an editable bezier path for node editing.
class ReplaceObjectCommand extends Command {
  ReplaceObjectCommand(this.before, this.after);
  final ShapeObject before;
  final ShapeObject after;

  @override
  String get description => 'Convert to path';
  @override
  Iterable<String> get affectedIds => [after.id];

  void _swap(List<ShapeObject> objects, ShapeObject from, ShapeObject to) {
    final i = objects.indexWhere((o) => o.id == from.id);
    if (i >= 0) objects[i] = to;
  }

  @override
  void execute(List<ShapeObject> objects) => _swap(objects, before, after);
  @override
  void undo(List<ShapeObject> objects) => _swap(objects, after, before);
}

/// Groups several commands into a single undo step (e.g. a Repeat that adds
/// many objects, or Expand that deletes the source then adds its outlines).
class CompositeCommand extends Command {
  CompositeCommand(this.commands, [this._description = 'Edit']);
  final List<Command> commands;
  final String _description;

  @override
  String get description => _description;
  @override
  Iterable<String> get affectedIds => commands.expand((c) => c.affectedIds);

  @override
  void execute(List<ShapeObject> objects) {
    for (final c in commands) {
      c.execute(objects);
    }
  }

  @override
  void undo(List<ShapeObject> objects) {
    for (final c in commands.reversed) {
      c.undo(objects);
    }
  }
}

/// Captures before/after snapshots of a set of objects (move, rotate, resize,
/// property changes). For live gestures the mutation is applied directly during
/// the drag and this command is pushed already-applied at gesture end.
class MutationCommand extends Command {
  MutationCommand({
    required this.description,
    required Map<String, ShapeObject> before,
    required Map<String, ShapeObject> after,
  })  : _before = before,
        _after = after;

  @override
  final String description;
  final Map<String, ShapeObject> _before;
  final Map<String, ShapeObject> _after;

  @override
  Iterable<String> get affectedIds => _after.keys;

  void _apply(List<ShapeObject> objects, Map<String, ShapeObject> snap) {
    for (final o in objects) {
      final s = snap[o.id];
      if (s != null) _restore(o, s);
    }
  }

  static void _restore(ShapeObject o, ShapeObject s) {
    o
      ..center = s.center
      ..size = s.size
      ..rotation = s.rotation
      ..fill = s.fill
      ..fillSpec = s.fillSpec.copy()
      ..stroke = s.stroke
      ..strokeWidth = s.strokeWidth
      ..opacity = s.opacity
      ..cornerRadius = s.cornerRadius
      ..cornerRadii = List.of(s.cornerRadii)
      ..starInner = s.starInner
      ..points = s.points
      ..visible = s.visible
      ..locked = s.locked
      ..pathPoints = List.of(s.pathPoints)
      ..handleIn = List.of(s.handleIn)
      ..handleOut = List.of(s.handleOut)
      ..nodeModes = List.of(s.nodeModes)
      ..holes = s.holes.map((h) => List.of(h)).toList()
      ..perspective = List.of(s.perspective)
      ..closed = s.closed
      ..smooth = s.smooth
      ..text = s.text
      ..fontSize = s.fontSize
      ..fontWeight = s.fontWeight
      ..fontFamily = s.fontFamily
      ..letterSpacing = s.letterSpacing
      ..lineHeight = s.lineHeight
      ..textAlignH = s.textAlignH
      ..italic = s.italic
      ..groupId = s.groupId
      ..superGroupId = s.superGroupId
      ..imageBytes = s.imageBytes
      ..crop = s.crop
      ..maskId = s.maskId
      ..blend = s.blend
      ..strokes = s.strokes.map((x) => x.copy()).toList()
      ..blurAmount = s.blurAmount
      ..shadow = s.shadow.copy()
      ..innerShadow = s.innerShadow.copy()
      ..glow = s.glow.copy()
      ..innerGlow = s.innerGlow.copy()
      ..name = s.name;
  }

  @override
  void execute(List<ShapeObject> objects) => _apply(objects, _after);
  @override
  void undo(List<ShapeObject> objects) => _apply(objects, _before);
}
