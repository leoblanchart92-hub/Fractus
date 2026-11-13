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
        // ── Le PC ──
        _tool('open', 'Ouvre une application, un fichier, un dossier ou une URL avec Windows (Start-Process). Ex. "notepad", "code .", "https://…", "C:\\Users\\…\\doc.pdf". Demande la permission.', {
          'target': {'type': 'string', 'description': 'Programme, chemin ou URL.'},
          'arguments': {'type': 'string', 'description': 'Arguments éventuels.'},
        }, required: ['target']),
        _tool('system_info', 'Système : nom de machine, utilisateur, Windows, CPU, RAM, disques, batterie, uptime, écran(s).', {}),
        _tool('list_processes', 'Processus en cours (nom, PID, mémoire, titre de fenêtre), triés par mémoire ; filtre facultatif.', {
          'filter': {'type': 'string', 'description': 'Sous-chaîne du nom (facultatif).'},
        }),
        _tool('kill_process', 'Ferme un processus (par PID ou nom). Demande la permission.', {
          'pid': {'type': 'integer', 'description': 'PID.'},
          'name': {'type': 'string', 'description': 'Nom du processus (ex. "notepad").'},
        }),
        _tool('list_windows', 'Fenêtres ouvertes (titre, processus, PID), pour savoir ce qui est à l\'écran.', {}),
        _tool('focus_window', 'Met une fenêtre au premier plan (par morceau de titre ou PID). Demande la permission.', {
          'title': {'type': 'string', 'description': 'Morceau du titre.'},
          'pid': {'type': 'integer', 'description': 'PID.'},
        }),
        _tool('send_keys', 'Tape du texte / des touches dans la fenêtre active (syntaxe SendKeys : {ENTER}, ^c, %{F4}, {TAB}…). Demande la permission. Utilise focus_window avant.', {
          'keys': {'type': 'string', 'description': 'Texte ou séquence SendKeys.'},
          'delay_ms': {'type': 'integer', 'description': 'Attente avant d\'envoyer (300 par défaut).'},
        }, required: ['keys']),
        _tool('clipboard_get', 'Lit le presse-papiers (texte). Demande la permission.', {}),
        _tool('clipboard_set', 'Écrit du texte dans le presse-papiers. Demande la permission.', {
          'text': {'type': 'string', 'description': 'Texte.'},
        }, required: ['text']),
        _tool('screenshot', 'Capture l\'écran dans un fichier PNG (chemin renvoyé) — utile pour l\'ouvrir ou le montrer à l\'utilisateur. Demande la permission.', {
          'path': {'type': 'string', 'description': 'Chemin du PNG (facultatif : %TEMP%).'},
        }),
        _tool('notify', 'Affiche une notification Windows (titre + message).', {
          'title': {'type': 'string', 'description': 'Titre.'},
          'message': {'type': 'string', 'description': 'Message.'},
        }, required: ['message']),
        _tool('set_volume', 'Règle le volume principal (0-100) ou coupe/rétablit le son. Demande la permission.', {
          'level': {'type': 'integer', 'description': '0 à 100.'},
          'mute': {'type': 'boolean', 'description': 'Couper (true) / rétablir (false).'},
        }),
        _tool('power', 'Verrouille, met en veille, redémarre ou éteint le PC. Demande la permission.', {
          'action': {'type': 'string', 'enum': ['lock', 'sleep', 'restart', 'shutdown'], 'description': 'Action.'},
        }, required: ['action']),
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
      case 'open':
        return 'ouvre ${_oneLine(args['target'])}';
      case 'system_info':
        return 'regarde le système';
      case 'list_processes':
        return 'liste les processus';
      case 'kill_process':
        return 'ferme ${args['name'] ?? args['pid']}';
      case 'list_windows':
        return 'regarde les fenêtres';
      case 'focus_window':
        return 'passe sur ${args['title'] ?? args['pid']}';
      case 'send_keys':
        return 'tape « ${_oneLine(args['keys'])} »';
      case 'clipboard_get':
        return 'lit le presse-papiers';
      case 'clipboard_set':
        return 'copie dans le presse-papiers';
      case 'screenshot':
        return 'capture l\'écran';
      case 'notify':
        return 'te notifie';
      case 'set_volume':
        return 'règle le volume';
      case 'power':
        return '${args['action']} le PC';
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
        case 'open':
          return await _open(args);
        case 'system_info':
          return await _ps(_systemInfoScript);
        case 'list_processes':
          return await _ps(_processesScript((args['filter'] ?? '').toString()));
        case 'kill_process':
          return await _killProcess(args);
        case 'list_windows':
          return await _ps(_windowsScript);
        case 'focus_window':
          return await _focusWindow(args);
        case 'send_keys':
          return await _sendKeys(args);
        case 'clipboard_get':
          return await _gated('Fractus', {'action': 'Lire le presse-papiers'}, () => _ps('Get-Clipboard -Raw | ConvertTo-Json -Compress'));
        case 'clipboard_set':
          return await _gated('Fractus', {'action': 'Copier dans le presse-papiers', 'text': args['text']},
              () => _ps('Set-Clipboard -Value ${_q((args['text'] ?? '').toString())}; \'{"ok":true}\''));
        case 'screenshot':
          return await _screenshot(args);
        case 'notify':
          return await _notify(args);
        case 'set_volume':
          return await _setVolume(args);
        case 'power':
          return await _power(args);
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
      'run_command' || 'open' || 'kill_process' || 'focus_window' || 'send_keys' || 'power' || 'set_volume' || 'screenshot' => StepKind.run,
      'search_text' || 'fetch_url' || 'list_windows' || 'list_processes' || 'system_info' => StepKind.search,
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

  // ── Le PC ─────────────────────────────────────────────────────────────────

  /// Une action quelconque gardée par la carte de permission.
  Future<String> _gated(String tool, Map<String, dynamic> input, Future<String> Function() run) async {
    final denied = await _permission(tool, input);
    if (denied != null) return denied;
    return run();
  }

  /// Chaîne PowerShell entre apostrophes simples.
  static String _q(String s) => "'${s.replaceAll("'", "''")}'";

  /// Exécute un script PowerShell (sans carte : réservé aux lectures et aux
  /// actions déjà autorisées) et renvoie sa sortie texte, ou un JSON d'erreur.
  Future<String> _ps(String script, {int timeoutSeconds = 60}) async {
    try {
      final r = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', '[Console]::OutputEncoding=[Text.Encoding]::UTF8; \$ProgressPreference=\'SilentlyContinue\'; $script'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(Duration(seconds: timeoutSeconds));
      final out = (r.stdout as String).trim();
      final err = (r.stderr as String).trim();
      if (r.exitCode != 0 && out.isEmpty) return jsonEncode({'error': err.isEmpty ? 'code ${r.exitCode}' : err});
      if (out.isEmpty) return jsonEncode({'ok': true, if (err.isNotEmpty) 'stderr': err});
      return out.length > maxCommandOutput ? '${out.substring(0, maxCommandOutput)}\n…[tronqué]' : out;
    } on TimeoutException {
      return jsonEncode({'error': 'Délai dépassé ($timeoutSeconds s).'});
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  Future<String> _open(Map<String, dynamic> args) async {
    final target = (args['target'] ?? '').toString().trim();
    final arguments = (args['arguments'] ?? '').toString().trim();
    if (target.isEmpty) return jsonEncode({'error': 'Cible vide.'});
    return _gated('Fractus', {'action': 'Ouvrir', 'target': target, if (arguments.isNotEmpty) 'arguments': arguments}, () async {
      final cwd = baseDir();
      final script = arguments.isEmpty
          ? 'Set-Location ${_q(cwd)}; Start-Process ${_q(target)}; \'{"ok":true}\''
          : 'Set-Location ${_q(cwd)}; Start-Process ${_q(target)} -ArgumentList ${_q(arguments)}; \'{"ok":true}\'';
      return _ps(script);
    });
  }

  Future<String> _killProcess(Map<String, dynamic> args) async {
    final pid = args['pid'];
    final name = (args['name'] ?? '').toString().trim();
    if (pid is! num && name.isEmpty) return jsonEncode({'error': 'Donne un pid ou un name.'});
    return _gated('Fractus', {'action': 'Fermer le processus', 'target': pid is num ? 'PID ${pid.toInt()}' : name}, () {
      final sel = pid is num ? 'Get-Process -Id ${pid.toInt()}' : 'Get-Process -Name ${_q(name.replaceAll(RegExp(r'\.exe\$', caseSensitive: false), ''))}';
      return _ps('\$p = $sel -ErrorAction Stop; \$p | Stop-Process -Force -ErrorAction Stop; @{ok=\$true; closed=@(\$p | ForEach-Object { \$_.ProcessName })} | ConvertTo-Json -Compress');
    });
  }

  Future<String> _focusWindow(Map<String, dynamic> args) async {
    final title = (args['title'] ?? '').toString().trim();
    final pid = args['pid'];
    if (title.isEmpty && pid is! num) return jsonEncode({'error': 'Donne un title ou un pid.'});
    return _gated('Fractus', {'action': 'Mettre au premier plan', 'target': title.isNotEmpty ? title : 'PID ${(pid as num).toInt()}'}, () {
      final sel = pid is num
          ? 'Get-Process -Id ${pid.toInt()} -ErrorAction Stop'
          : 'Get-Process | Where-Object { \$_.MainWindowHandle -ne 0 -and \$_.MainWindowTitle -like (\'*\' + ${_q(title)} + \'*\') } | Select-Object -First 1';
      return _ps('''
\$p = $sel
if (-not \$p -or \$p.MainWindowHandle -eq 0) { '{"error":"Fenêtre introuvable"}'; exit 0 }
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FxWin { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n); }
"@
[FxWin]::ShowWindowAsync(\$p.MainWindowHandle, 9) | Out-Null
[FxWin]::SetForegroundWindow(\$p.MainWindowHandle) | Out-Null
@{ok=\$true; title=\$p.MainWindowTitle; pid=\$p.Id} | ConvertTo-Json -Compress
''');
    });
  }

  Future<String> _sendKeys(Map<String, dynamic> args) async {
    final keys = (args['keys'] ?? '').toString();
    if (keys.isEmpty) return jsonEncode({'error': 'keys vide.'});
    final delay = ((args['delay_ms'] is num) ? (args['delay_ms'] as num).toInt() : 300).clamp(0, 5000);
    return _gated('Fractus', {'action': 'Taper au clavier', 'keys': keys}, () {
      return _ps('Start-Sleep -Milliseconds $delay; \$w = New-Object -ComObject WScript.Shell; \$w.SendKeys(${_q(keys)}); \'{"ok":true}\'');
    });
  }

  Future<String> _screenshot(Map<String, dynamic> args) async {
    var path = (args['path'] ?? '').toString().trim();
    if (path.isEmpty) path = '${Directory.systemTemp.path}${Platform.pathSeparator}fractus-${DateTime.now().millisecondsSinceEpoch}.png';
    return _gated('Fractus', {'action': 'Capturer l\'écran', 'target': path}, () {
      return _ps('''
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
\$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
\$bmp = New-Object System.Drawing.Bitmap \$b.Width, \$b.Height
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen(\$b.Left, \$b.Top, 0, 0, \$bmp.Size)
\$bmp.Save(${_q(path)}, [System.Drawing.Imaging.ImageFormat]::Png)
\$g.Dispose(); \$bmp.Dispose()
@{ok=\$true; path=${_q(path)}; width=\$b.Width; height=\$b.Height} | ConvertTo-Json -Compress
''');
    });
  }

  Future<String> _notify(Map<String, dynamic> args) async {
    final title = (args['title'] ?? 'Fractus').toString();
    final message = (args['message'] ?? '').toString();
    return _ps('''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
\$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$t = \$x.GetElementsByTagName('text'); \$t.Item(0).AppendChild(\$x.CreateTextNode(${_q(title)})) | Out-Null; \$t.Item(1).AppendChild(\$x.CreateTextNode(${_q(message)})) | Out-Null
\$n = [Windows.UI.Notifications.ToastNotification]::new(\$x)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Fractus').Show(\$n)
'{"ok":true}'
''');
  }

  Future<String> _setVolume(Map<String, dynamic> args) async {
    final level = args['level'];
    final mute = args['mute'];
    if (level is! num && mute is! bool) return jsonEncode({'error': 'Donne level (0-100) ou mute.'});
    final what = mute is bool ? (mute ? 'Couper le son' : 'Rétablir le son') : 'Volume ${(level as num).toInt().clamp(0, 100)} %';
    return _gated('Fractus', {'action': what}, () {
      // Via les touches multimédia : VK_VOLUME_MUTE 0xAD, DOWN 0xAE, UP 0xAF (2 % par appui).
      final sb = StringBuffer('''
\$c = Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);' -Name FxKey -Namespace Fx -PassThru
function Tap(\$k) { \$c::keybd_event(\$k, 0, 0, [UIntPtr]::Zero); \$c::keybd_event(\$k, 0, 2, [UIntPtr]::Zero) }
''');
      if (mute is bool) {
        sb.writeln('Tap 0xAD');
      } else {
        final target = (level as num).toInt().clamp(0, 100);
        sb.writeln('1..50 | ForEach-Object { Tap 0xAE }');
        sb.writeln('1..${(target / 2).round()} | ForEach-Object { Tap 0xAF }');
      }
      sb.writeln("'{\"ok\":true}'");
      return _ps(sb.toString());
    });
  }

  Future<String> _power(Map<String, dynamic> args) async {
    final action = (args['action'] ?? '').toString();
    final cmd = switch (action) {
      'lock' => 'rundll32.exe user32.dll,LockWorkStation',
      'sleep' => 'rundll32.exe powrprof.dll,SetSuspendState 0,1,0',
      'restart' => 'shutdown.exe /r /t 5',
      'shutdown' => 'shutdown.exe /s /t 5',
      _ => '',
    };
    if (cmd.isEmpty) return jsonEncode({'error': 'Action inconnue : $action'});
    final label = switch (action) { 'lock' => 'Verrouiller', 'sleep' => 'Mettre en veille', 'restart' => 'Redémarrer', _ => 'Éteindre' };
    return _gated('Fractus', {'action': '$label le PC'}, () => _ps('$cmd; \'{"ok":true}\''));
  }

  static const String _systemInfoScript = '''
\$os = Get-CimInstance Win32_OperatingSystem
\$cs = Get-CimInstance Win32_ComputerSystem
\$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
\$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
\$disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { @{ drive=\$_.DeviceID; free_gb=[math]::Round(\$_.FreeSpace/1GB,1); total_gb=[math]::Round(\$_.Size/1GB,1) } }
Add-Type -AssemblyName System.Windows.Forms
\$screens = [System.Windows.Forms.Screen]::AllScreens | ForEach-Object { @{ device=\$_.DeviceName; width=\$_.Bounds.Width; height=\$_.Bounds.Height; primary=\$_.Primary } }
@{
  computer=\$env:COMPUTERNAME; user=\$env:USERNAME; os=\$os.Caption; version=\$os.Version
  cpu=\$cpu.Name; cores=\$cpu.NumberOfLogicalProcessors
  ram_total_gb=[math]::Round(\$cs.TotalPhysicalMemory/1GB,1); ram_free_gb=[math]::Round(\$os.FreePhysicalMemory/1MB,1)
  uptime_hours=[math]::Round(((Get-Date) - \$os.LastBootUpTime).TotalHours,1)
  battery_percent=\$(if (\$bat) { \$bat.EstimatedChargeRemaining } else { \$null })
  disks=\$disks; screens=\$screens
  home=\$env:USERPROFILE
} | ConvertTo-Json -Compress -Depth 4
''';

  static String _processesScript(String filter) => '''
Get-Process | Where-Object { ${filter.isEmpty ? '\$true' : '\$_.ProcessName -like (\'*\' + ${_q(filter)} + \'*\')'} } |
  Sort-Object WorkingSet64 -Descending | Select-Object -First 60 |
  ForEach-Object { @{ name=\$_.ProcessName; pid=\$_.Id; mem_mb=[math]::Round(\$_.WorkingSet64/1MB); title=\$_.MainWindowTitle } } |
  ConvertTo-Json -Compress
''';

  static const String _windowsScript = '''
Get-Process | Where-Object { \$_.MainWindowHandle -ne 0 -and \$_.MainWindowTitle } |
  ForEach-Object { @{ title=\$_.MainWindowTitle; process=\$_.ProcessName; pid=\$_.Id } } | ConvertTo-Json -Compress
''';

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
