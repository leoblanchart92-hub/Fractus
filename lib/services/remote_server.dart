// Le serveur « téléphone » : l'appli Android de Fractus s'y connecte sur le
// réseau local (ou via Tailscale) pour voir l'état, autoriser les demandes,
// discuter avec Fractus, voir l'écran et déclencher des actions rapides.
//
//   Toutes les routes sauf /api/ping exigent le code d'appairage :
//   en-tête `Authorization: Bearer XXXX-XXXX` (ou `?token=` pour les images).
//
//   GET  /api/ping                      { app, version, host }   (sans code)
//   GET  /api/status                    l'état complet (voir _status)
//   GET  /api/events                    SSE : « data: <status> » à chaque changement
//   POST /api/approvals/decide          { requestId, decision: allow|always|deny }
//   POST /api/approvals/answer          { requestId, answers: { question: réponse } }
//   POST /api/chat                      { text }  → 202 (la réponse arrive par /events)
//   POST /api/chat/new                  nouvelle conversation
//   POST /api/action                    { action: lock|sleep|mute|volume_up|volume_down|play_pause|next|prev }
//   GET  /api/screen.jpg?w=1100         capture de l'écran

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/layout.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/state.dart';
import '../island/controller.dart';
import 'chat_runner.dart';
import 'chat_service.dart';
import 'chat_tools.dart';

class RemoteServer {
  RemoteServer({
    required this.state,
    required this.controller,
    required this.chat,
    required this.tools,
    required this.version,
  });

  final AppState state;
  final IslandController controller;
  final ChatService chat;
  final ChatTools tools;
  final String Function() version;

  HttpServer? _server;
  int? port;
  String? error;
  final Set<HttpResponse> _streams = {};
  Timer? _push;
  Timer? _heartbeat;
  bool _listening = false;

  bool get running => _server != null;

  Future<void> start(int wantedPort) async {
    await stop();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, wantedPort, shared: true);
      port = _server!.port;
      error = null;
      _server!.listen(_handle, onError: (_) {});
      if (!_listening) {
        state.addListener(_onState);
        _listening = true;
      }
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _broadcast(': ping\n\n'));
    } catch (e) {
      error = 'Port $wantedPort indisponible : $e';
      port = null;
    }
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _push?.cancel();
    for (final s in _streams.toList()) {
      try {
        await s.close();
      } catch (_) {}
    }
    _streams.clear();
    await _server?.close(force: true);
    _server = null;
    port = null;
  }

  void dispose() {
    if (_listening) state.removeListener(_onState);
    stop();
  }

  /// Les adresses IPv4 locales (pour afficher « 192.168.1.20:7790 »).
  static Future<List<String>> localAddresses() async {
    final out = <String>[];
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false)) {
        for (final a in i.addresses) {
          if (a.isLoopback) continue;
          out.add(a.address);
        }
      }
    } catch (_) {}
    int rank(String a) => a.startsWith('192.168.') ? 0 : (a.startsWith('10.') ? 1 : (a.startsWith('100.') ? 2 : 3));
    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  }

  // ── État ──────────────────────────────────────────────────────────────────

  void _onState() {
    if (_streams.isEmpty) return;
    _push ??= Timer(const Duration(milliseconds: 250), () {
      _push = null;
      _broadcast('data: ${jsonEncode(_status())}\n\n');
    });
  }

  void _broadcast(String chunk) {
    for (final s in _streams.toList()) {
      try {
        s.write(chunk);
        s.flush();
      } catch (_) {
        _streams.remove(s);
      }
    }
  }

  Map<String, dynamic> _status() {
    final a = state.pendingApproval;
    final c = state.conversation;
    return {
      'app': 'fractus',
      'version': version(),
      'host': Platform.localHostname,
      'time': DateTime.now().toIso8601String(),
      'botState': state.botState.name,
      'chatBusy': state.chatBusy,
      'sessions': [
        for (final s in state.orderedSessions.take(8))
          {
            'id': s.id,
            'project': s.project,
            'agent': s.agent,
            'state': s.state.name,
            'active': s.isActive,
            'cwd': s.cwd,
            'lastStep': s.steps.isEmpty ? null : s.steps.last.text,
            'lastMessage': s.lastMessage,
            'updated': s.updated.toIso8601String(),
          },
      ],
      'pending': a == null
          ? null
          : {
              'requestId': a.requestId,
              'sessionId': a.sessionId,
              'project': a.project,
              'tool': a.toolName,
              'summary': a.summary,
              'label': _label(a),
              'isQuestion': a.isQuestion,
              'alwaysKey': controller.alwaysKey(a),
              'createdAt': a.createdAt.toIso8601String(),
              if (a.isQuestion)
                'questions': [
                  for (final q in a.questions!)
                    {'question': q.question, 'options': q.options, 'header': q.header, 'multi': q.multi},
                ],
              if (a.toolName == 'Write' || a.toolName == 'Edit')
                'preview': _preview(a.toolInput),
            },
      'queue': state.approvalQueue.length,
      'conversation': {
        'id': c.id,
        'title': c.title,
        'count': c.messages.length,
        'messages': [
          for (final m in c.messages.reversed.take(40).toList().reversed)
            {'role': m.role, 'text': m.text, 'at': m.at.toIso8601String()},
        ],
      },
      'quickActions': ChatTools.quickLabels,
    };
  }

  static String _label(ApprovalInfo a) {
    switch (a.toolName) {
      case 'Bash':
        return 'Lancer une commande';
      case 'Write':
        return 'Écrire un fichier';
      case 'Edit':
      case 'MultiEdit':
        return 'Modifier un fichier';
      case 'WebFetch':
        return 'Consulter une URL';
      case 'Fractus':
        return 'Agir sur le PC';
      default:
        return a.toolName;
    }
  }

  static String? _preview(Map<String, dynamic> input) {
    final s = (input['new_string'] ?? input['content'])?.toString();
    if (s == null) return null;
    return s.length > 600 ? '${s.substring(0, 600)}…' : s;
  }

  // ── Requêtes ──────────────────────────────────────────────────────────────

  bool _authorized(HttpRequest req) {
    final want = Settings.normalizeToken(state.settings.remoteToken);
    if (want.isEmpty) return false;
    var given = '';
    final h = req.headers.value('authorization');
    if (h != null && h.toLowerCase().startsWith('bearer ')) given = h.substring(7);
    given = given.isEmpty ? (req.uri.queryParameters['token'] ?? '') : given;
    final got = Settings.normalizeToken(given);
    if (got.length != want.length) return false;
    var diff = 0;
    for (var i = 0; i < want.length; i++) {
      diff |= want.codeUnitAt(i) ^ got.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    try {
      final raw = jsonDecode(await utf8.decoder.bind(req).join());
      return raw is Map<String, dynamic> ? raw : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _json(HttpResponse res, Object body, {int status = 200}) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final path = req.uri.path;
    try {
      if (req.method == 'GET' && path == '/api/ping') {
        return await _json(res, {'app': 'fractus', 'version': version(), 'host': Platform.localHostname});
      }
      if (!path.startsWith('/api/')) return await _json(res, {'error': 'not found'}, status: 404);
      if (!_authorized(req)) return await _json(res, {'error': 'code d\'appairage incorrect'}, status: 401);

      if (req.method == 'GET' && path == '/api/status') return await _json(res, _status());

      if (req.method == 'GET' && path == '/api/events') {
        res.statusCode = 200;
        res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
        res.headers.set('cache-control', 'no-cache');
        res.headers.set('connection', 'keep-alive');
        res.bufferOutput = false;
        res.write('retry: 2000\n\n');
        res.write('data: ${jsonEncode(_status())}\n\n');
        await res.flush();
        _streams.add(res);
        res.done.then((_) => _streams.remove(res), onError: (_) => _streams.remove(res));
        return;
      }

      if (req.method == 'POST' && path == '/api/approvals/decide') {
        final b = await _body(req);
        final a = state.pendingApproval;
        if (a == null || a.requestId != b['requestId']) return await _json(res, {'error': 'Cette demande n\'est plus en attente.', 'status': _status()}, status: 409);
        final d = switch (b['decision']) { 'allow' => Decision.allow, 'always' => Decision.always, _ => Decision.deny };
        controller.decide(d);
        return await _json(res, {'ok': true, 'status': _status()});
      }

      if (req.method == 'POST' && path == '/api/approvals/answer') {
        final b = await _body(req);
        final a = state.pendingApproval;
        if (a == null || a.requestId != b['requestId'] || !a.isQuestion) return await _json(res, {'error': 'Cette question n\'est plus en attente.'}, status: 409);
        final raw = b['answers'];
        final answers = <String, String>{};
        if (raw is Map) raw.forEach((k, v) => answers['$k'] = '$v');
        if (answers.isEmpty) return await _json(res, {'error': 'answers manquant'}, status: 400);
        controller.answerQuestion(answers);
        return await _json(res, {'ok': true, 'status': _status()});
      }

      if (req.method == 'POST' && path == '/api/chat') {
        final b = await _body(req);
        final text = (b['text'] ?? '').toString().trim();
        if (text.isEmpty) return await _json(res, {'error': 'text manquant'}, status: 400);
        if (state.chatBusy) return await _json(res, {'error': 'Fractus est déjà occupé.'}, status: 409);
        if (!chat.configured) return await _json(res, {'error': 'Pas de clé Groq sur le PC (Réglages → Chat).'}, status: 409);
        // L'île s'ouvre sur le chat pour que l'écran du PC montre ce qui se passe.
        controller.open(IslandView.prompt);
        unawaited(ChatRunner.send(state, chat, text));
        return await _json(res, {'ok': true}, status: 202);
      }

      if (req.method == 'POST' && path == '/api/chat/new') {
        await state.newConversation();
        return await _json(res, {'ok': true, 'status': _status()});
      }

      if (req.method == 'POST' && path == '/api/action') {
        final b = await _body(req);
        final out = await tools.quick((b['action'] ?? '').toString());
        Object parsed;
        try {
          parsed = jsonDecode(out);
        } catch (_) {
          parsed = {'ok': true, 'output': out};
        }
        return await _json(res, parsed, status: out.startsWith('{"error"') ? 400 : 200);
      }

      if (req.method == 'GET' && path == '/api/screen.jpg') {
        final w = int.tryParse(req.uri.queryParameters['w'] ?? '') ?? 1100;
        final bytes = await tools.screenJpeg(maxWidth: w.clamp(320, 2400));
        if (bytes == null) return await _json(res, {'error': 'capture impossible'}, status: 500);
        res.statusCode = 200;
        res.headers.contentType = ContentType('image', 'jpeg');
        res.headers.set('cache-control', 'no-store');
        res.add(bytes);
        await res.close();
        return;
      }

      return await _json(res, {'error': 'not found'}, status: 404);
    } catch (e) {
      try {
        await _json(res, {'error': e.toString()}, status: 500);
      } catch (_) {}
    }
  }
}
