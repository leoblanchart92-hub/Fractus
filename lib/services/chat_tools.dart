// Les outils que le modèle appelle pendant le chat (function calling) — ce qui
// fait de Fractus un agent, comme Claude Code :
//   - lecture libre : sessions, lire un fichier, lister un dossier, chercher du texte ;
//   - actions sous permission : écrire ou modifier un fichier, lancer une commande,
//     aller chercher une URL. Chacune passe par la carte Autoriser / Refuser /
//     Toujours de l'île : rien ne s'exécute sans un clic humain (ou une règle
//     « Toujours autoriser » donnée plus tôt pour ce type d'action).
// Le travail de Fractus apparaît comme une session à part entière dans l'île.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/layout.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../island/controller.dart';

class ChatTools {
  ChatTools(this.state, {required this.controller});
  final AppState state;
  final IslandController controller;

  /// Dossier de travail imposé dans les réglages (vide = projet en avant, sinon le profil).
  String workspace = '';

  static const String sessionId = 'fractus';
  static const int maxCommandOutput = 30 * 1024;

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
        _tool('write_file', 'Crée ou remplace un fichier texte (les dossiers parents sont créés). Demande la permission à l\'utilisateur.', {
          'path': {'type': 'string', 'description': 'Chemin du fichier.'},
          'content': {'type': 'string', 'description': 'Contenu complet du fichier.'},
        }, required: ['path', 'content']),
        _tool('edit_file', 'Remplace un passage exact d\'un fichier par un autre (old_text doit apparaître une seule fois). Demande la permission.', {
          'path': {'type': 'string', 'description': 'Chemin du fichier.'},
          'old_text': {'type': 'string', 'description': 'Texte existant, exact.'},
          'new_text': {'type': 'string', 'description': 'Texte de remplacement.'},
        }, required: ['path', 'old_text', 'new_text']),
        _tool('run_command', 'Exécute une commande PowerShell dans le dossier de travail et renvoie sa sortie (stdout+stderr, code de retour). Demande la permission. Pas de commande interactive.', {
          'command': {'type': 'string', 'description': 'La commande PowerShell.'},
          'description': {'type': 'string', 'description': 'Ce qu\'elle fait, en quelques mots (montré à l\'utilisateur).'},
          'timeout_seconds': {'type': 'integer', 'description': 'Délai maximal (120 par défaut, 600 max).'},
        }, required: ['command']),
        _tool('fetch_url', 'Télécharge le texte d\'une URL (HTTP GET, 80 Ko max). Demande la permission.', {
          'url': {'type': 'string', 'description': 'URL complète.'},
        }, required: ['url']),
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
      case 'write_file':
        return 'écrit ${_short(args['path'])}';
      case 'edit_file':
        return 'modifie ${_short(args['path'])}';
      case 'run_command':
        return 'lance « ${_oneLine(args['command'])} »';
      case 'fetch_url':
        return 'consulte ${args['url']}';
      default:
        return name;
    }
  }

  String _oneLine(Object? v) {
    final s = (v ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
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
          return await _readFile(args);
        case 'list_directory':
          return await _listDirectory(args);
        case 'search_text':
          return await _searchText(args);
        case 'get_datetime':
          return jsonEncode({'now': DateTime.now().toIso8601String(), 'timezone': DateTime.now().timeZoneName});
        case 'write_file':
          return await _writeFile(args);
        case 'edit_file':
          return await _editFile(args);
        case 'run_command':
          return await _runCommand(args);
        case 'fetch_url':
          return await _fetchUrl(args);
        default:
          return jsonEncode({'error': 'Outil inconnu : $name'});
      }
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  // ── Sessions ─────────────────────────────────────────────────────────────

  /// Le dossier de travail de Fractus : réglage, sinon le projet d'un agent en
  /// cours, sinon le profil de l'utilisateur.
  String baseDir() {
    if (workspace.trim().isNotEmpty) return workspace.trim();
    for (final s in state.orderedSessions) {
      if (s.id != sessionId && s.cwd.isNotEmpty) return s.cwd;
    }
    return Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
  }

  String _frontCwd() => baseDir();

  String _projectName() {
    final cleaned = baseDir().replaceAll(RegExp(r'[\\/]+$'), '');
    final i = cleaned.lastIndexOf(RegExp(r'[\\/]'));
    final name = i < 0 ? cleaned : cleaned.substring(i + 1);
    return name.isEmpty ? 'Fractus' : name;
  }

  // ── La session « Fractus » dans l'île ─────────────────────────────────────

  Session session() => state.upsertSession(sessionId, _projectName(), 'Fractus', cwd: baseDir());

  /// Au début d'une réponse : Fractus réfléchit.
  void begin(String prompt) {
    final s = session();
    s.state = BotState.thinking;
    s.prompt = prompt;
    s.lastMessage = null;
    s.addStep(SessionStep(StepKind.prompt, prompt));
    state.touch();
  }

  /// Une étape visible dans la pastille à chaque outil.
  void step(String name, Map<String, dynamic> args) {
    final s = session();
    final kind = switch (name) {
      'read_file' || 'list_directory' || 'get_sessions' => StepKind.read,
      'write_file' || 'edit_file' => StepKind.edit,
      'run_command' => StepKind.run,
      'search_text' || 'fetch_url' => StepKind.search,
      _ => StepKind.note,
    };
    s.addStep(SessionStep(kind, describe(name, args)));
    s.state = name == 'run_command' ? BotState.working : (name == 'search_text' || name == 'fetch_url' ? BotState.searching : BotState.working);
    state.touch();
  }

  /// À la fin : la réponse est le dernier message, Fractus se repose.
  void end(String answer, {bool error = false}) {
    final s = state.sessions[sessionId];
    if (s == null) return;
    s.lastMessage = answer;
    s.state = error ? BotState.error : BotState.idle;
    s.updated = DateTime.now();
    state.touch();
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  /// Demande l'accord de l'utilisateur via la carte de l'île. Renvoie null si
  /// c'est accordé, sinon le JSON d'erreur à rendre au modèle.
  Future<String?> _permission(String tool, Map<String, dynamic> input) async {
    final s = session();
    s.state = BotState.approval;
    state.touch();
    final reply = await controller.requestPermission({
      'session_id': sessionId,
      'cwd': baseDir(),
      'fractus_agent': 'fractus',
      'tool_name': tool,
      'tool_input': input,
      'request_id': 'fractus-${DateTime.now().microsecondsSinceEpoch}',
    });
    final decision = reply?['hookSpecificOutput']?['decision'];
    final allowed = decision is Map && decision['behavior'] == 'allow';
    s.state = BotState.working;
    state.touch();
    if (allowed) return null;
    if (reply == null) {
      return jsonEncode({'error': 'Pas de réponse de l\'utilisateur dans le temps imparti : action annulée. Demande-lui avant de réessayer.'});
    }
    return jsonEncode({'error': 'Refusé par l\'utilisateur. N\'insiste pas : propose une alternative ou demande ce qu\'il souhaite.'});
  }

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

  // ── Actions (sous permission) ─────────────────────────────────────────────

  Future<String> _writeFile(Map<String, dynamic> args) async {
    final path = _resolve(args['path']);
    final content = (args['content'] ?? '').toString();
    final denied = await _permission('Write', {'file_path': path, 'content': content});
    if (denied != null) return denied;
    final f = File(path);
    final existed = await f.exists();
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
    return jsonEncode({'ok': true, 'path': path, 'created': !existed, 'bytes': utf8.encode(content).length});
  }

  Future<String> _editFile(Map<String, dynamic> args) async {
    final path = _resolve(args['path']);
    final oldText = (args['old_text'] ?? '').toString();
    final newText = (args['new_text'] ?? '').toString();
    final f = File(path);
    if (!await f.exists()) return jsonEncode({'error': 'Fichier introuvable : $path'});
    if (oldText.isEmpty) return jsonEncode({'error': 'old_text est vide.'});
    final text = await f.readAsString();
    final count = oldText.allMatches(text).length;
    if (count == 0) return jsonEncode({'error': 'old_text introuvable dans le fichier (relis-le : read_file).'});
    if (count > 1) return jsonEncode({'error': 'old_text apparaît $count fois : donne plus de contexte pour qu\'il soit unique.'});
    final denied = await _permission('Edit', {'file_path': path, 'old_string': oldText, 'new_string': newText});
    if (denied != null) return denied;
    await f.writeAsString(text.replaceFirst(oldText, newText));
    return jsonEncode({'ok': true, 'path': path});
  }

  Future<String> _runCommand(Map<String, dynamic> args) async {
    final command = (args['command'] ?? '').toString().trim();
    if (command.isEmpty) return jsonEncode({'error': 'Commande vide.'});
    final timeout = ((args['timeout_seconds'] is num) ? (args['timeout_seconds'] as num).toInt() : 120).clamp(5, 600);
    final denied = await _permission('Bash', {'command': command, if (args['description'] != null) 'description': args['description']});
    if (denied != null) return denied;
    final cwd = baseDir();
    final sw = Stopwatch()..start();
    final proc = await Process.start(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', '[Console]::OutputEncoding=[Text.Encoding]::UTF8; \$ProgressPreference=\'SilentlyContinue\'; $command'],
      workingDirectory: Directory(cwd).existsSync() ? cwd : null,
      runInShell: false,
    );
    final out = StringBuffer();
    var truncated = false;
    void collect(String chunk) {
      if (out.length >= maxCommandOutput) {
        truncated = true;
        return;
      }
      out.write(chunk);
    }

    final done = Future.wait([
      proc.stdout.transform(utf8.decoder).forEach(collect),
      proc.stderr.transform(utf8.decoder).forEach(collect),
    ]);
    int code;
    var timedOut = false;
    try {
      code = await proc.exitCode.timeout(Duration(seconds: timeout));
      await done.timeout(const Duration(seconds: 5), onTimeout: () => []);
    } on TimeoutException {
      timedOut = true;
      proc.kill(ProcessSignal.sigkill);
      code = -1;
    }
    sw.stop();
    return jsonEncode({
      'exit_code': code,
      'timed_out': timedOut,
      'duration_ms': sw.elapsedMilliseconds,
      'cwd': cwd,
      'output': out.toString(),
      'truncated': truncated,
    });
  }

  Future<String> _fetchUrl(Map<String, dynamic> args) async {
    final url = (args['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return jsonEncode({'error': 'URL invalide : $url'});
    final denied = await _permission('WebFetch', {'url': url});
    if (denied != null) return denied;
    final res = await http.get(uri, headers: {'User-Agent': 'Fractus (Windows)', 'Accept': 'text/html,text/plain,application/json;q=0.9,*/*;q=0.5'}).timeout(const Duration(seconds: 30));
    var body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final type = res.headers['content-type'] ?? '';
    if (type.contains('html')) {
      body = body
          .replaceAll(RegExp(r'<(script|style|noscript)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<br\s*/?>|</(p|div|li|h[1-6]|tr)>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n+'), '\n');
    }
    const max = 80 * 1024;
    return jsonEncode({
      'status': res.statusCode,
      'content_type': type,
      'truncated': body.length > max,
      'text': body.length > max ? body.substring(0, max) : body,
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
