// Les outils que le modèle peut appeler pendant le chat (function calling).
// Tous en LECTURE SEULE : voir les sessions, lire un fichier, lister un dossier,
// chercher du texte. Fractus n'exécute jamais de commande et n'écrit jamais
// rien pour le compte du modèle — et il n'approuve jamais une permission à sa place.

import 'dart:convert';
import 'dart:io';

import '../core/state.dart';

class ChatTools {
  ChatTools(this.state);
  final AppState state;

  static const int maxFileBytes = 60 * 1024;
  static const int maxEntries = 300;
  static const int maxMatches = 60;

  /// Déclaration des outils, au format OpenAI/Groq.
  List<Map<String, dynamic>> get definitions => [
        _tool('get_sessions', 'Détail des sessions d\'agents suivies par Fractus : projet, agent, dossier, état, '
            'dernières étapes, dernier message, demande de permission en attente.', {}),
        _tool('read_file', 'Lit un fichier texte (jusqu\'à 60 Ko). Chemin absolu, ou relatif au dossier du projet en avant.', {
          'path': {'type': 'string', 'description': 'Chemin du fichier.'},
          'start_line': {'type': 'integer', 'description': 'Première ligne (1 par défaut).'},
          'max_lines': {'type': 'integer', 'description': 'Nombre maximal de lignes (400 par défaut).'},
        }, required: ['path']),
        _tool('list_directory', 'Liste les fichiers et dossiers d\'un répertoire (jusqu\'à 300 entrées).', {
          'path': {'type': 'string', 'description': 'Chemin du dossier (vide = dossier du projet en avant).'},
        }),
        _tool('search_text', 'Cherche une expression régulière dans les fichiers texte d\'un dossier (récursif, 60 résultats max).', {
          'pattern': {'type': 'string', 'description': 'Expression régulière (insensible à la casse).'},
          'path': {'type': 'string', 'description': 'Dossier de départ (vide = dossier du projet en avant).'},
          'glob': {'type': 'string', 'description': 'Filtre sur le nom de fichier, ex. "*.dart" (facultatif).'},
        }, required: ['pattern']),
        _tool('get_datetime', 'Date et heure locales actuelles.', {}),
      ];

  Map<String, dynamic> _tool(String name, String description, Map<String, dynamic> props, {List<String> required = const []}) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {'type': 'object', 'properties': props, 'required': required},
      },
    };
  }

  /// Une ligne pour l'interface pendant que l'outil tourne.
  String describe(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'read_file':
        return 'lit ${_short(args['path'])}';
      case 'list_directory':
        return 'parcourt ${_short(args['path'] ?? _frontCwd())}';
      case 'search_text':
        return 'cherche « ${args['pattern']} »';
      case 'get_sessions':
        return 'regarde les sessions';
      default:
        return name;
    }
  }

  String _short(Object? p) {
    final s = (p ?? '').toString();
    final i = s.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? s : s.substring(i + 1);
  }

  Future<String> call(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'get_sessions':
          return sessionsJson();
        case 'read_file':
          return _readFile(args);
        case 'list_directory':
          return _listDirectory(args);
        case 'search_text':
          return _searchText(args);
        case 'get_datetime':
          return jsonEncode({'now': DateTime.now().toIso8601String(), 'timezone': DateTime.now().timeZoneName});
        default:
          return jsonEncode({'error': 'Outil inconnu : $name'});
      }
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  // ── Sessions ─────────────────────────────────────────────────────────────

  String _frontCwd() => state.frontSession?.cwd ?? '';

  /// Résumé compact, pour le prompt système.
  String sessionsSummary() {
    if (state.sessions.isEmpty) return 'Aucune session d\'agent en cours.';
    final b = StringBuffer();
    for (final s in state.orderedSessions.take(6)) {
      b.writeln('- ${s.project} (${s.agent}) : ${s.state.name}'
          '${s.cwd.isNotEmpty ? ' — ${s.cwd}' : ''}'
          '${s.steps.isNotEmpty ? ' — dernière étape : ${s.steps.last.text}' : ''}');
    }
    final a = state.pendingApproval;
    if (a != null) {
      b.writeln(a.isQuestion
          ? '- Question en attente de ${a.project} : ${a.questions!.first.question}'
          : '- Permission en attente de ${a.project} : ${a.toolName} ${a.summary} (seul l\'humain peut cliquer Autoriser/Refuser).');
    }
    return b.toString();
  }

  String sessionsJson() {
    final list = state.orderedSessions.map((s) => {
          'project': s.project,
          'agent': s.agent,
          'cwd': s.cwd,
          'state': s.state.name,
          'prompt': s.prompt,
          'lastMessage': s.lastMessage,
          'updated': s.updated.toIso8601String(),
          'steps': s.steps.reversed.take(12).map((st) => {'kind': st.kind.name, 'text': st.text, if (st.detail != null) 'detail': st.detail}).toList(),
        });
    final a = state.pendingApproval;
    return jsonEncode({
      'sessions': list.toList(),
      'pending': a == null
          ? null
          : {
              'project': a.project,
              'tool': a.toolName,
              'summary': a.summary,
              'isQuestion': a.isQuestion,
              if (a.isQuestion) 'questions': a.questions!.map((q) => {'question': q.question, 'options': q.options}).toList(),
              'note': 'Seul l\'utilisateur peut répondre, via la carte de l\'île.',
            },
    });
  }

  // ── Fichiers ─────────────────────────────────────────────────────────────

  String _resolve(Object? raw) {
    var p = (raw ?? '').toString().trim();
    if (p.startsWith('~')) p = (Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '') + p.substring(1);
    final base = _frontCwd();
    if (p.isEmpty) return base;
    final absolute = RegExp(r'^([a-zA-Z]:[\\/]|[\\/]{1,2})').hasMatch(p);
    if (absolute || base.isEmpty) return p;
    return '$base${Platform.pathSeparator}$p';
  }

  Future<String> _readFile(Map<String, dynamic> args) async {
    final path = _resolve(args['path']);
    final f = File(path);
    if (!await f.exists()) return jsonEncode({'error': 'Fichier introuvable : $path'});
    final len = await f.length();
    final raw = await f.openRead(0, len > maxFileBytes ? maxFileBytes : len).fold<List<int>>([], (a, b) => a..addAll(b));
    if (raw.contains(0)) return jsonEncode({'error': 'Fichier binaire', 'bytes': len});
    final text = utf8.decode(raw, allowMalformed: true);
    final lines = const LineSplitter().convert(text);
    final start = ((args['start_line'] is num) ? (args['start_line'] as num).toInt() : 1).clamp(1, lines.isEmpty ? 1 : lines.length);
    final max = ((args['max_lines'] is num) ? (args['max_lines'] as num).toInt() : 400).clamp(1, 2000);
    final slice = lines.skip(start - 1).take(max).toList();
    final numbered = StringBuffer();
    for (var i = 0; i < slice.length; i++) {
      numbered.writeln('${start + i}: ${slice[i]}');
    }
    return jsonEncode({
      'path': path,
      'total_lines': lines.length,
      'truncated': len > maxFileBytes || start - 1 + slice.length < lines.length,
      'content': numbered.toString(),
    });
  }

  Future<String> _listDirectory(Map<String, dynamic> args) async {
    final path = _resolve(args['path']);
    if (path.isEmpty) return jsonEncode({'error': 'Aucun dossier : précise un chemin (aucune session en cours).'});
    final d = Directory(path);
    if (!await d.exists()) return jsonEncode({'error': 'Dossier introuvable : $path'});
    final entries = <Map<String, dynamic>>[];
    await for (final e in d.list(followLinks: false)) {
      final name = e.path.substring(e.path.lastIndexOf(RegExp(r'[\\/]')) + 1);
      if (name == 'node_modules' || name == '.git') {
        entries.add({'name': name, 'type': 'dir', 'skipped': true});
        continue;
      }
      final isDir = e is Directory;
      entries.add({
        'name': name,
        'type': isDir ? 'dir' : 'file',
        if (!isDir) 'size': (await (e as File).length()),
      });
      if (entries.length >= maxEntries) break;
    }
    // Dossiers d'abord, puis ordre alphabétique.
    entries.sort((a, b) {
      final t = (a['type'] as String).compareTo(b['type'] as String);
      if (t != 0) return t;
      return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
    });
    return jsonEncode({'path': path, 'entries': entries});
  }

  Future<String> _searchText(Map<String, dynamic> args) async {
    final path = _resolve(args['path']);
    if (path.isEmpty) return jsonEncode({'error': 'Aucun dossier : précise un chemin.'});
    final RegExp re;
    try {
      re = RegExp((args['pattern'] ?? '').toString(), caseSensitive: false);
    } catch (e) {
      return jsonEncode({'error': 'Expression invalide : $e'});
    }
    final glob = (args['glob'] ?? '').toString().trim();
    final globRe = glob.isEmpty ? null : RegExp('^${RegExp.escape(glob).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$', caseSensitive: false);
    final d = Directory(path);
    if (!await d.exists()) return jsonEncode({'error': 'Dossier introuvable : $path'});
    final matches = <Map<String, dynamic>>[];
    var scanned = 0;
    const skip = {'node_modules', '.git', 'build', 'dist', '.dart_tool', 'target', '.next', 'out'};
    Future<void> walk(Directory dir, int depth) async {
      if (depth > 8 || matches.length >= maxMatches) return;
      await for (final e in dir.list(followLinks: false)) {
        if (matches.length >= maxMatches) return;
        final name = e.path.substring(e.path.lastIndexOf(RegExp(r'[\\/]')) + 1);
        if (e is Directory) {
          if (!skip.contains(name)) await walk(e, depth + 1);
        } else if (e is File) {
          if (globRe != null && !globRe.hasMatch(name)) continue;
          if (await e.length() > 2 * 1024 * 1024 || scanned > 4000) continue;
          scanned++;
          List<int> bytes;
          try {
            bytes = await e.readAsBytes();
          } catch (_) {
            continue;
          }
          if (bytes.take(4096).contains(0)) continue;
          final lines = const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true));
          for (var i = 0; i < lines.length; i++) {
            if (re.hasMatch(lines[i])) {
              matches.add({'file': e.path, 'line': i + 1, 'text': lines[i].trim().length > 240 ? '${lines[i].trim().substring(0, 240)}…' : lines[i].trim()});
              if (matches.length >= maxMatches) break;
            }
          }
        }
      }
    }

    await walk(d, 0);
    return jsonEncode({'path': path, 'files_scanned': scanned, 'matches': matches, 'truncated': matches.length >= maxMatches});
  }
}
