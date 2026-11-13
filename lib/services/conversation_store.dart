// Les conversations du chat, gardées sur disque :
//   %APPDATA%\fractus\conversations\<id>.json
// La dernière est rouverte au lancement ; les plus vieilles sont élaguées
// au-delà de [maxConversations]. Rien ne quitte la machine.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import '../core/settings.dart';

class ConversationStore {
  static const int maxConversations = 60;

  Directory? _dir;
  Timer? _timer;
  Conversation? _dirty;

  /// La liste des conversations connues, la plus récente d'abord.
  List<ConversationMeta> index = const [];

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final base = await Settings.dir();
    final d = Directory('${base.path}${Platform.pathSeparator}conversations');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> _fileFor(String id) async {
    final d = await _directory();
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return File('${d.path}${Platform.pathSeparator}$safe.json');
  }

  /// Relit l'index depuis le disque.
  Future<List<ConversationMeta>> refresh() async {
    final out = <ConversationMeta>[];
    try {
      final d = await _directory();
      await for (final e in d.list()) {
        if (e is! File || !e.path.endsWith('.json')) continue;
        try {
          final j = jsonDecode(await e.readAsString());
          if (j is! Map) continue;
          final id = (j['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final msgs = j['messages'];
          out.add(ConversationMeta(
            id: id,
            title: (j['title'] ?? '').toString(),
            updated: DateTime.tryParse((j['updated'] ?? '').toString()) ?? (await e.lastModified()),
            count: msgs is List ? msgs.length : 0,
          ));
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => b.updated.compareTo(a.updated));
    // Élagage : au-delà du maximum, les plus anciennes disparaissent.
    while (out.length > maxConversations) {
      final old = out.removeLast();
      try {
        await (await _fileFor(old.id)).delete();
      } catch (_) {}
    }
    index = out;
    return out;
  }

  Future<Conversation?> load(String id) async {
    try {
      final f = await _fileFor(id);
      if (!await f.exists()) return null;
      return Conversation.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// La conversation la plus récente, si elle existe.
  Future<Conversation?> loadLatest() async {
    if (index.isEmpty) await refresh();
    for (final m in index) {
      final c = await load(m.id);
      if (c != null) return c;
    }
    return null;
  }

  Future<void> save(Conversation c) async {
    if (c.isEmpty) return;
    try {
      final f = await _fileFor(c.id);
      await f.writeAsString(jsonEncode(c.toJson()));
      final meta = ConversationMeta(id: c.id, title: c.title, updated: c.updated, count: c.messages.length);
      final list = index.where((m) => m.id != c.id).toList()..insert(0, meta);
      list.sort((a, b) => b.updated.compareTo(a.updated));
      index = list;
    } catch (_) {}
  }

  /// Enregistre un peu plus tard (regroupe les écritures pendant le streaming).
  void saveSoon(Conversation c) {
    _dirty = c;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    final c = _dirty;
    _dirty = null;
    if (c != null) await save(c);
  }

  Future<void> delete(String id) async {
    try {
      final f = await _fileFor(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    index = index.where((m) => m.id != id).toList();
  }
}
