import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shape_object.dart';

/// A saved Shape document.
class Project {
  Project({
    required this.id,
    required this.name,
    required this.objects,
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  List<ShapeObject> objects;
  double zoom;
  double panX;
  double panY;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'zoom': zoom,
        'panX': panX,
        'panY': panY,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'objects': objects.map((o) => o.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        zoom: (j['zoom'] as num?)?.toDouble() ?? 1.0,
        panX: (j['panX'] as num?)?.toDouble() ?? 0.0,
        panY: (j['panY'] as num?)?.toDouble() ?? 0.0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int? ?? 0),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int? ?? 0),
        objects: (j['objects'] as List)
            .map((e) => ShapeObject.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Lightweight listing entry for the projects history (no object payload).
class ProjectMeta {
  ProjectMeta(this.id, this.name, this.updatedAt, this.count);
  final String id;
  final String name;
  final DateTime updatedAt;
  final int count;

  String get relativeTime {
    final d = DateTime.now().difference(updatedAt);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')}';
  }
}

/// Cross-platform project persistence backed by [SharedPreferences].
/// Keeps a project history index and the id of the last-opened project so the
/// app can auto-restore after a normal exit or a crash (§25.5).
class ProjectStore {
  ProjectStore._();
  static final ProjectStore instance = ProjectStore._();

  static const _kIndex = 'shape.index';
  static const _kLast = 'shape.lastId';
  static const _kProject = 'shape.project.';
  static const _kPalette = 'shape.palette';
  static const _kScratch = 'shape.scratch';

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> init() async {
    await _p;
  }

  String? get lastId => _prefs?.getString(_kLast);

  Future<void> setLast(String id) async {
    (await _p).setString(_kLast, id);
  }

  /// Saved color palette (ARGB ints).
  Future<List<int>> palette() async {
    final raw = (await _p).getString(_kPalette);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<int>();
  }

  Future<void> setPalette(List<int> colors) async {
    (await _p).setString(_kPalette, jsonEncode(colors));
  }

  Future<List<ProjectMeta>> index() async {
    final raw = (await _p).getString(_kIndex);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final metas = list
        .map((m) => ProjectMeta(
              m['id'] as String,
              m['name'] as String,
              DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int),
              m['count'] as int? ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return metas;
  }

  /// Crash-recovery "scratch" slot: the exact current canvas, written on every
  /// change regardless of whether the document has been explicitly saved. This
  /// is what lets an unsaved Untitled draft survive a crash. Stored outside the
  /// project index so it never litters the history list. The caller controls the
  /// JSON payload (it wraps the project plus a saved-state flag).
  Future<void> saveScratch(String json) async {
    (await _p).setString(_kScratch, json);
  }

  Future<String?> loadScratch() async => (await _p).getString(_kScratch);

  Future<void> clearScratch() async {
    (await _p).remove(_kScratch);
  }

  Future<Project?> load(String id) async {
    final raw = (await _p).getString('$_kProject$id');
    if (raw == null) return null;
    return Project.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(Project project) async {
    project.updatedAt = DateTime.now();
    final p = await _p;
    await p.setString(
        '$_kProject${project.id}', jsonEncode(project.toJson()));
    await p.setString(_kLast, project.id);

    // Update the index.
    final metas = await index();
    final filtered = metas.where((m) => m.id != project.id).toList();
    filtered.insert(
        0,
        ProjectMeta(project.id, project.name, project.updatedAt,
            project.objects.length));
    await p.setString(
        _kIndex,
        jsonEncode(filtered
            .map((m) => {
                  'id': m.id,
                  'name': m.name,
                  'updatedAt': m.updatedAt.millisecondsSinceEpoch,
                  'count': m.count,
                })
            .toList()));
  }

  Future<void> delete(String id) async {
    final p = await _p;
    await p.remove('$_kProject$id');
    final metas = (await index()).where((m) => m.id != id).toList();
    await p.setString(
        _kIndex,
        jsonEncode(metas
            .map((m) => {
                  'id': m.id,
                  'name': m.name,
                  'updatedAt': m.updatedAt.millisecondsSinceEpoch,
                  'count': m.count,
                })
            .toList()));
    if (p.getString(_kLast) == id) await p.remove(_kLast);
  }
}
