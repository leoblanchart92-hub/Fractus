// Le journal d'activité de Fractus : tout ce qu'il a fait sur la machine
// (fichiers écrits ou modifiés, commandes lancées, actions PC, mémoire), avec
// une copie de chaque fichier AVANT modification pour pouvoir Annuler.
//   %APPDATA%\fractus\journal.json      — les entrées
//   %APPDATA%\fractus\backups\<id>-nom  — les copies d'avant

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/settings.dart';

enum JournalKind { write, edit, command, action, memory, restore }

class JournalEntry {
  JournalEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.label,
    this.detail,
    this.path,
    this.backup,
    this.created = false,
    this.undone = false,
  });

  final String id;
  final DateTime at;
  final JournalKind kind;
  /// « Modifié main.dart », « Lancé npm test »…
  final String label;
  final String? detail;
  /// Le fichier touché, s'il y en a un.
  final String? path;
  /// La copie du fichier avant l'action (null si le fichier n'existait pas).
  final String? backup;
  /// Le fichier a été créé par cette action (annuler = le retirer).
  final bool created;
  bool undone;

  bool get canUndo => !undone && path != null && (backup != null || created);

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'kind': kind.name,
        'label': label,
        if (detail != null) 'detail': detail,
        if (path != null) 'path': path,
        if (backup != null) 'backup': backup,
        'created': created,
        'undone': undone,
      };

  static JournalEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String) return null;
    return JournalEntry(
      id: id,
      at: DateTime.tryParse((j['at'] ?? '').toString()) ?? DateTime.now(),
      kind: JournalKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => JournalKind.action),
      label: (j['label'] ?? '').toString(),
      detail: j['detail'] as String?,
      path: j['path'] as String?,
      backup: j['backup'] as String?,
      created: j['created'] == true,
      undone: j['undone'] == true,
    );
  }
}

class Journal extends ChangeNotifier {
  static const int maxEntries = 300;

  /// Les entrées, la plus ancienne d'abord.
  final List<JournalEntry> entries = [];
  Timer? _timer;
  bool _loaded = false;

  List<JournalEntry> get newestFirst => entries.reversed.toList();

  Future<Directory> _backupsDir() async {
    final base = await Settings.dir();
    final d = Directory('${base.path}${Platform.pathSeparator}backups');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file() async {
    final d = await Settings.dir();
    return File('${d.path}${Platform.pathSeparator}journal.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is List) {
        entries
          ..clear()
          ..addAll(j.map(JournalEntry.fromJson).whereType<JournalEntry>());
      }
    } catch (_) {}
    notifyListeners();
  }

  void _saveSoon() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), flush);
    notifyListeners();
  }

  Future<void> flush() async {
    _timer?.cancel();
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static String _baseName(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  /// Copie un fichier dans le dossier des sauvegardes. Null s'il n'existe pas.
  Future<String?> backupOf(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final d = await _backupsDir();
      final safe = _baseName(path).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final dest = '${d.path}${Platform.pathSeparator}${_newId()}-$safe';
      await f.copy(dest);
      return dest;
    } catch (_) {
      return null;
    }
  }

  /// Note une action. À appeler une fois qu'elle a réussi.
  JournalEntry record({
    required JournalKind kind,
    required String label,
    String? detail,
    String? path,
    String? backup,
    bool created = false,
  }) {
    final e = JournalEntry(
      id: _newId(),
      at: DateTime.now(),
      kind: kind,
      label: label,
      detail: detail,
      path: path,
      backup: backup,
      created: created,
    );
    entries.add(e);
    _prune();
    _saveSoon();
    return e;
  }

  /// Annule une écriture : remet la copie d'avant (ou retire le fichier créé).
  /// L'état actuel est lui aussi sauvegardé, pour pouvoir revenir en arrière.
  Future<String?> undo(JournalEntry e) async {
    if (!e.canUndo) return 'Rien à annuler.';
    final path = e.path!;
    try {
      final current = await backupOf(path);
      final f = File(path);
      if (e.backup != null) {
        final b = File(e.backup!);
        if (!await b.exists()) return 'La copie de sauvegarde a disparu.';
        await f.parent.create(recursive: true);
        await b.copy(path);
        e.undone = true;
        record(
          kind: JournalKind.restore,
          label: 'Restauré ${_baseName(path)}',
          detail: 'version d\'avant « ${e.label} »',
          path: path,
          backup: current,
          created: current == null,
        );
      } else {
        if (await f.exists()) await f.delete();
        e.undone = true;
        record(
          kind: JournalKind.restore,
          label: 'Retiré ${_baseName(path)}',
          detail: 'fichier créé par « ${e.label} »',
          path: path,
          backup: current,
        );
      }
      _saveSoon();
      return null;
    } catch (err) {
      return 'Impossible d\'annuler : $err';
    }
  }

  Future<void> clear() async {
    entries.clear();
    await flush();
    try {
      final d = await _backupsDir();
      await for (final f in d.list()) {
        if (f is File) await f.delete();
      }
    } catch (_) {}
    notifyListeners();
  }

  void _prune() {
    if (entries.length <= maxEntries) return;
    final dropped = entries.sublist(0, entries.length - maxEntries);
    entries.removeRange(0, dropped.length);
    for (final e in dropped) {
      final b = e.backup;
      if (b != null) File(b).delete().ignore();
    }
  }
}
