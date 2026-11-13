// Le chef d'orchestre de l'île : reçoit les événements des agents, décide de
// la vue, de l'état de Mochi, des alertes ; répond aux clics des cartes.
// Pendant de windows/src/island/hooks.ts + island.ts (la partie logique).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/layout.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../mochi/bot_engine.dart';
import '../services/sound.dart';

class IslandController extends ChangeNotifier {
  IslandController(this.state) : bot = BotEngine() {
    bot.onSound = (name) => Sound.play(name, muted: state.settings.muted);
    bot.onDizzy = _onDizzy;
    state.addListener(_syncBot);
  }

  final AppState state;
  final BotEngine bot;

  /// Appelé quand l'île doit être visible (ouverture d'une alerte) : la couche
  /// fenêtre s'assure alors que la souris n'est plus ignorée.
  VoidCallback? onWake;

  Timer? _closeTimer;
  Timer? _hideTimer;
  final Map<String, Timer> _stopTimers = {};
  final Map<String, Timer> _requestTimers = {};

  // ── Mode ───────────────────────────────────────────────────────────────────

  bool get isOpen => state.mode == IslandMode.expanded;

  void peek() {
    _hideTimer?.cancel();
    if (state.mode == IslandMode.hidden) state.setMode(IslandMode.compact);
  }

  void open([IslandView? v]) {
    _closeTimer?.cancel();
    _hideTimer?.cancel();
    if (v != null) state.setView(v);
    if (state.view == IslandView.overview && state.sessions.isEmpty) state.setView(IslandView.empty);
    state.setMode(IslandMode.expanded);
    onWake?.call();
  }

  /// Replie l'île (le ✕ ou le pointeur qui s'en va).
  void close() {
    _closeTimer?.cancel();
    if (state.mode != IslandMode.expanded) return;
    state.setMode(IslandMode.compact);
    _scheduleHide();
  }

  void hide() {
    _closeTimer?.cancel();
    _hideTimer?.cancel();
    if (state.pinned) return;
    state.setMode(IslandMode.hidden);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 900), () {
      if (!_pointerInside && !state.pinned) hide();
    });
  }

  bool _pointerInside = false;

  /// La couche fenêtre dit où est le pointeur par rapport à l'île.
  void pointerInside(bool inside) {
    if (inside == _pointerInside) return;
    _pointerInside = inside;
    if (inside) {
      _closeTimer?.cancel();
      _hideTimer?.cancel();
      if (state.mode == IslandMode.hidden) state.setMode(IslandMode.compact);
      if (state.mode == IslandMode.compact && state.settings.openOnHover) open();
    } else {
      if (state.pinned) return;
      if (state.mode == IslandMode.expanded) {
        _closeTimer?.cancel();
        _closeTimer = Timer(const Duration(milliseconds: 1400), () {
          if (!_pointerInside && !state.pinned) close();
        });
      } else if (state.mode == IslandMode.compact) {
        _scheduleHide();
      }
    }
  }

  /// Un clic sur l'île compacte l'ouvre ; sur l'île ouverte, la garde ouverte.
  void tapIsland() {
    if (state.mode == IslandMode.compact) {
      open();
    } else {
      _closeTimer?.cancel();
    }
  }

  /// Ouvre l'île sur une vue d'alerte (permission, question, erreur, fin).
  void alert(IslandView v) {
    open(v);
    Sound.play(v.name, muted: state.settings.muted);
  }

  // ── Mochi ──────────────────────────────────────────────────────────────────

  void _syncBot() {
    final target = state.botState;
    if (state.view == IslandView.confused) return;
    if (bot.state != target) bot.setState(target);
  }

  void slapBot() {
    bot.slap();
  }

  void _onDizzy() {
    bot.setState(BotState.dizzy);
    open(IslandView.confused);
    Timer(const Duration(milliseconds: 2600), () {
      if (state.view == IslandView.confused) {
        state.setView(state.pendingApproval != null
            ? (state.pendingApproval!.isQuestion ? IslandView.question : IslandView.approval)
            : state.defaultView());
      }
      bot.setState(state.botState, force: true);
    });
  }

  void hoverBot(bool on) {
    _hoverTimer?.cancel();
    if (on) {
      _hoverTimer = Timer(const Duration(seconds: 2), () => bot.triggerEmote(BotEmote.love));
    }
  }

  Timer? _hoverTimer;

  /// Le regard : coordonnées normalisées (−1…1) par rapport au centre de Mochi.
  void look(double x, double y) {
    bot.lookX = x.clamp(-1, 1);
    bot.lookY = y.clamp(-1, 1);
  }

  // ── Événements des agents ──────────────────────────────────────────────────

  static const _claudeAgent = 'Claude Code';

  String _projectOf(Map<String, dynamic> p) {
    final cwd = (p['cwd'] ?? '') as String;
    final cleaned = cwd.replaceAll(RegExp(r'[\\/]+$'), '');
    final idx = cleaned.lastIndexOf(RegExp(r'[\\/]'));
    final name = idx < 0 ? cleaned : cleaned.substring(idx + 1);
    return name.isEmpty ? 'Session' : name;
  }

  String _agentOf(Map<String, dynamic> p) {
    final a = p['fractus_agent'] ?? p['coucou_agent'];
    if (a is String && a.isNotEmpty) {
      return a.split(RegExp(r'[-_ ]')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    }
    return _claudeAgent;
  }

  String _sessionIdOf(Map<String, dynamic> p) {
    final id = p['session_id'];
    if (id is String && id.isNotEmpty) return id;
    return 'cwd:${p['cwd'] ?? ''}';
  }

  /// Un événement de hook (Claude Code ou un autre agent) → l'état de l'île.
  void handleHook(Map<String, dynamic> p) {
    final name = (p['hook_event_name'] ?? '') as String;
    final id = _sessionIdOf(p);
    final project = _projectOf(p);
    final agent = _agentOf(p);

    switch (name) {
      case 'SessionStart':
        final s = state.upsertSession(id, project, agent);
        s.state = BotState.idle;
        state.touch();
        break;

      case 'UserPromptSubmit':
        final s = state.upsertSession(id, project, agent);
        _cancelStop(id);
        s.prompt = (p['prompt'] ?? p['message'] ?? '') as String;
        s.lastMessage = null;
        s.state = BotState.thinking;
        if (s.prompt!.isNotEmpty) s.addStep(SessionStep(StepKind.prompt, s.prompt!));
        state.focus(id);
        if (state.view == IslandView.empty) state.setView(IslandView.overview);
        state.touch();
        break;

      case 'PreToolUse':
        final s = state.upsertSession(id, project, agent);
        _cancelStop(id);
        final tool = (p['tool_name'] ?? '') as String;
        final input = _map(p['tool_input']);
        final step = _stepFor(tool, input);
        if (step != null) s.addStep(step);
        s.state = _stateForTool(tool);
        if (state.view == IslandView.empty) state.setView(IslandView.overview);
        state.touch();
        break;

      case 'PostToolUse':
        final s = state.upsertSession(id, project, agent);
        if (s.state != BotState.thinking) s.state = BotState.thinking;
        state.touch();
        break;

      case 'SubagentStart':
        final s = state.upsertSession(id, project, agent);
        final kind = (p['agent_type'] ?? '') as String;
        s.addStep(SessionStep(StepKind.note, kind.isEmpty ? 'Sous-agent lancé' : 'Sous-agent $kind'));
        s.state = BotState.searching;
        state.touch();
        break;

      case 'Notification':
        final s = state.upsertSession(id, project, agent);
        final msg = (p['message'] ?? '') as String;
        final lower = msg.toLowerCase();
        if (lower.contains('permission')) {
          // La vraie demande arrive par PermissionRequest ; on ne fait que signaler.
          s.state = BotState.approval;
        } else if (lower.contains('rate limit') || lower.contains('usage limit')) {
          s.state = BotState.ratelimit;
        } else if (lower.contains('waiting for your input')) {
          s.state = BotState.question;
        }
        if (msg.isNotEmpty) s.addStep(SessionStep(StepKind.note, msg));
        state.touch();
        break;

      case 'Stop':
      case 'SubagentStop':
        final s = state.upsertSession(id, project, agent);
        if (name == 'SubagentStop') {
          s.state = BotState.thinking;
          state.touch();
          break;
        }
        final last = p['last_assistant_message'];
        if (last is String && last.trim().isNotEmpty) s.lastMessage = last.trim();
        s.state = BotState.finished;
        s.updated = DateTime.now();
        state.focus(id);
        state.touch();
        if (state.pendingApproval == null) alert(IslandView.finished);
        _cancelStop(id);
        _stopTimers[id] = Timer(const Duration(seconds: 12), () {
          _stopTimers.remove(id);
          final ss = state.sessions[id];
          if (ss == null || ss.state != BotState.finished) return;
          ss.state = BotState.idle;
          if (state.view == IslandView.finished && state.pendingApproval == null) {
            state.setView(state.defaultView());
            if (state.mode == IslandMode.expanded && !_pointerInside) close();
          }
          state.touch();
        });
        break;

      case 'SessionEnd':
        _cancelStop(id);
        state.removeSession(id);
        break;

      case 'PermissionRequest':
        // Traité par requestPermission (il attend la réponse) ; rien ici.
        break;

      default:
        break;
    }
  }

  void _cancelStop(String id) {
    _stopTimers.remove(id)?.cancel();
  }

  Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  BotState _stateForTool(String tool) {
    switch (tool) {
      case 'Grep':
      case 'Glob':
      case 'WebSearch':
      case 'WebFetch':
      case 'LS':
        return BotState.searching;
      case 'Task':
        return BotState.thinking;
      default:
        return BotState.working;
    }
  }

  static String fileName(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  SessionStep? _stepFor(String tool, Map<String, dynamic> input) {
    switch (tool) {
      case 'Bash':
        final c = (input['command'] ?? '') as String;
        final d = input['description'];
        return SessionStep(StepKind.run, _oneLine(c), detail: d is String ? d : null);
      case 'Edit':
      case 'MultiEdit':
      case 'Write':
      case 'NotebookEdit':
        final f = (input['file_path'] ?? input['notebook_path'] ?? '') as String;
        return SessionStep(StepKind.edit, '${tool == 'Write' ? 'Écriture de' : 'Modification de'} ${fileName(f)}',
            detail: f);
      case 'Read':
        final f = (input['file_path'] ?? '') as String;
        return SessionStep(StepKind.read, 'Lecture de ${fileName(f)}', detail: f);
      case 'Grep':
        return SessionStep(StepKind.search, 'Recherche « ${input['pattern'] ?? ''} »');
      case 'Glob':
        return SessionStep(StepKind.search, 'Fichiers ${input['pattern'] ?? ''}');
      case 'WebSearch':
        return SessionStep(StepKind.search, 'Recherche web « ${input['query'] ?? ''} »');
      case 'WebFetch':
        return SessionStep(StepKind.search, 'Lecture de ${input['url'] ?? ''}');
      case 'Task':
        final d = input['description'];
        return SessionStep(StepKind.note, d is String && d.isNotEmpty ? d : 'Sous-tâche');
      case 'AskUserQuestion':
      case 'ExitPlanMode':
        return null;
      default:
        return SessionStep(StepKind.note, tool);
    }
  }

  String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Résumé montré sur la carte de permission.
  String _summaryFor(String tool, Map<String, dynamic> input) {
    switch (tool) {
      case 'Bash':
        return _oneLine((input['command'] ?? '') as String);
      case 'Edit':
      case 'MultiEdit':
      case 'Write':
      case 'NotebookEdit':
      case 'Read':
        return (input['file_path'] ?? input['notebook_path'] ?? '') as String;
      case 'WebFetch':
        return (input['url'] ?? '') as String;
      case 'WebSearch':
        return (input['query'] ?? '') as String;
      default:
        return input.isEmpty ? tool : _oneLine(input.toString());
    }
  }

  String _titleFor(String tool) {
    switch (tool) {
      case 'Bash':
        return 'veut lancer une commande';
      case 'Edit':
      case 'MultiEdit':
      case 'NotebookEdit':
        return 'veut modifier un fichier';
      case 'Write':
        return 'veut écrire un fichier';
      case 'Read':
        return 'veut lire un fichier';
      case 'WebFetch':
      case 'WebSearch':
        return 'veut aller sur le web';
      default:
        return 'veut utiliser $tool';
    }
  }

  String alwaysKey(ApprovalInfo a) {
    final cmd = a.toolName == 'Bash' ? a.summary.split(' ').first : '';
    return '${a.toolName}|$cmd';
  }

  /// Une demande de permission : la carte s'affiche, la réponse est rendue à
  /// l'agent quand l'utilisateur clique (ou `null` s'il ne clique pas).
  Future<Map<String, dynamic>?> requestPermission(Map<String, dynamic> p) {
    final id = _sessionIdOf(p);
    final project = _projectOf(p);
    final agent = _agentOf(p);
    final tool = (p['tool_name'] ?? '') as String;
    final input = _map(p['tool_input']);
    final requestId = (p['request_id'] ?? '${DateTime.now().microsecondsSinceEpoch}') as String;

    final s = state.upsertSession(id, project, agent);
    _cancelStop(id);

    List<AskedQuestion>? questions;
    if (tool == 'AskUserQuestion') {
      final qs = input['questions'];
      if (qs is List) {
        questions = qs.whereType<Map>().take(4).map((q) {
          final opts = q['options'];
          final labels = opts is List
              ? opts.map((o) => o is Map ? (o['label'] ?? '').toString() : o.toString()).where((l) => l.isNotEmpty).toList()
              : <String>[];
          return AskedQuestion(
            question: (q['question'] ?? '').toString(),
            options: labels,
            header: q['header']?.toString(),
            multi: q['multiSelect'] == true,
          );
        }).toList();
      }
      if (questions == null || questions.isEmpty) return Future.value(null);
    }

    final info = ApprovalInfo(
      requestId: requestId,
      sessionId: id,
      project: project,
      toolName: tool,
      summary: questions != null ? questions.first.question : _summaryFor(tool, input),
      toolInput: input,
      questions: questions,
    );

    // « Toujours autoriser » déjà donné pour cet outil / cette commande : on répond sans carte.
    if (questions == null && state.settings.alwaysAllow.contains(alwaysKey(info))) {
      s.addStep(SessionStep(StepKind.note, 'Autorisé automatiquement : ${info.summary}'));
      state.touch();
      return Future.value(_allowReply());
    }

    s.state = questions != null ? BotState.question : BotState.approval;
    state.focus(id);
    final onCard = state.enqueueApproval(info);
    if (onCard) alert(questions != null ? IslandView.question : IslandView.approval);

    // Chaque demande renonce sur sa propre horloge : 110 s, carte ou file.
    _requestTimers[requestId] = Timer(const Duration(seconds: 110), () {
      _requestTimers.remove(requestId);
      expire(requestId);
    });

    return info.completer.future;
  }

  void expire(String requestId) {
    _requestTimers.remove(requestId)?.cancel();
    state.expireApproval(requestId);
    _afterCard();
  }

  Map<String, dynamic> _allowReply() => {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {'behavior': 'allow'},
        }
      };

  Map<String, dynamic> _denyReply() => {
        'hookSpecificOutput': {
          'hookEventName': 'PermissionRequest',
          'decision': {'behavior': 'deny', 'message': 'Refusé depuis Fractus'},
        }
      };

  /// Le clic sur Autoriser / Toujours / Refuser.
  void decide(Decision d) {
    final a = state.pendingApproval;
    if (a == null) return;
    _requestTimers.remove(a.requestId)?.cancel();
    final s = state.sessions[a.sessionId];
    switch (d) {
      case Decision.allow:
        a.finish(_allowReply());
        s?.addStep(SessionStep(StepKind.note, 'Autorisé : ${a.summary}'));
        break;
      case Decision.always:
        state.settings.alwaysAllow.add(alwaysKey(a));
        state.saveSettingsSoon();
        a.finish(_allowReply());
        s?.addStep(SessionStep(StepKind.note, 'Toujours autorisé : ${a.summary}'));
        break;
      case Decision.deny:
        a.finish(_denyReply());
        s?.addStep(SessionStep(StepKind.note, 'Refusé : ${a.summary}'));
        break;
    }
    if (s != null) s.state = BotState.working;
    Sound.play(d == Decision.deny ? 'deny' : 'allow', muted: state.settings.muted);
    final next = state.endApproval();
    if (next != null) {
      alert(next.isQuestion ? IslandView.question : IslandView.approval);
    } else {
      _afterCard();
    }
  }

  /// « Répondre dans le terminal » : on rend la main sans décision.
  void deferToTerminal() {
    final a = state.pendingApproval;
    if (a == null) return;
    _requestTimers.remove(a.requestId)?.cancel();
    a.finish(null);
    final s = state.sessions[a.sessionId];
    if (s != null) s.state = BotState.working;
    final next = state.endApproval();
    if (next != null) {
      alert(next.isQuestion ? IslandView.question : IslandView.approval);
    } else {
      _afterCard();
    }
  }

  /// Les réponses à AskUserQuestion : la même entrée, avec `answers` en plus.
  void answerQuestion(Map<String, String> answers) {
    final a = state.pendingApproval;
    if (a == null || !a.isQuestion) return;
    _requestTimers.remove(a.requestId)?.cancel();
    final input = Map<String, dynamic>.from(a.toolInput)..['answers'] = answers;
    a.finish({
      'hookSpecificOutput': {
        'hookEventName': 'PermissionRequest',
        'decision': {'behavior': 'allow', 'updatedInput': input},
      }
    });
    final s = state.sessions[a.sessionId];
    if (s != null) {
      s.state = BotState.working;
      s.addStep(SessionStep(StepKind.note, 'Répondu : ${answers.values.join(', ')}'));
    }
    Sound.play('allow', muted: state.settings.muted);
    final next = state.endApproval();
    if (next != null) {
      alert(next.isQuestion ? IslandView.question : IslandView.approval);
    } else {
      _afterCard();
    }
  }

  void _afterCard() {
    if (state.pendingApproval != null) return;
    state.pinned = false;
    if (state.mode == IslandMode.expanded && !_pointerInside) close();
    state.touch();
  }

  /// Fermer la carte « terminé » / « erreur » avec OK.
  void dismissCard() {
    final s = state.frontSession;
    if (s != null && (s.state == BotState.finished || s.state == BotState.error)) {
      s.state = BotState.idle;
    }
    state.setView(state.defaultView());
    if (!_pointerInside) close();
    state.touch();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _hideTimer?.cancel();
    _hoverTimer?.cancel();
    for (final t in _stopTimers.values) {
      t.cancel();
    }
    for (final t in _requestTimers.values) {
      t.cancel();
    }
    state.removeListener(_syncBot);
    bot.dispose();
    super.dispose();
  }
}
