// Le chat de l'île, propulsé par Groq avec votre clé (gsk_…).
//   - API compatible OpenAI : https://api.groq.com/openai/v1/chat/completions, en streaming (SSE)
//   - le modèle le plus capable disponible sur le compte, choisi automatiquement
//     (ou celui que vous fixez dans les réglages), raisonnement poussé au maximum
//   - des outils locaux (lire, chercher, écrire, modifier, lancer des commandes)
//     que le modèle appelle lui-même ; les actions passent par la carte de permission
//   - en option, « groq/compound » : recherche web et exécution de code côté Groq
// Rien n'est envoyé tant que vous n'avez pas tapé Entrée.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import 'chat_tools.dart';

class GroqModel {
  const GroqModel(this.id, {this.contextWindow = 0, this.owner = ''});
  final String id;
  final int contextWindow;
  final String owner;
}

class ChatService {
  ChatService({required this.apiKey, required this.model, required this.tools, this.webSearch = false});

  static const String baseUrl = 'https://api.groq.com/openai/v1';

  /// Les modèles qu'on préfère, du plus capable au plus modeste. Le premier
  /// disponible sur le compte est retenu quand le réglage « Modèle » est vide.
  static const List<String> preferred = [
    'openai/gpt-oss-120b',
    'moonshotai/kimi-k2-instruct-0905',
    'moonshotai/kimi-k2-instruct',
    'llama-3.3-70b-versatile',
    'qwen/qwen3-32b',
    'meta-llama/llama-4-maverick-17b-128e-instruct',
    'openai/gpt-oss-20b',
    'llama-3.1-8b-instant',
  ];

  /// Les modèles « agentiques » de Groq (recherche web + code intégrés).
  static const String compoundModel = 'groq/compound';

  String apiKey;
  /// Vide = choix automatique parmi [preferred].
  String model;
  /// Utiliser groq/compound (recherche web, exécution de code côté Groq).
  bool webSearch;
  final ChatTools tools;

  List<GroqModel> models = const [];
  String? _autoModel;

  bool get configured => apiKey.trim().isNotEmpty;

  /// Le modèle réellement utilisé pour la prochaine requête.
  String get effectiveModel {
    if (webSearch) return compoundModel;
    if (model.trim().isNotEmpty) return model.trim();
    return _autoModel ?? preferred[3];
  }

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'authorization': 'Bearer ${apiKey.trim()}',
      };

  /// Liste les modèles du compte ; sert aussi à tester la clé.
  Future<List<GroqModel>> listModels() async {
    final res = await http.get(Uri.parse('$baseUrl/models'), headers: _headers).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception(_errorText(res));
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final data = (j['data'] as List?) ?? const [];
    final list = data
        .whereType<Map>()
        .where((m) => m['active'] != false)
        .map((m) => GroqModel(
              m['id'].toString(),
              contextWindow: (m['context_window'] is num) ? (m['context_window'] as num).toInt() : 0,
              owner: (m['owned_by'] ?? '').toString(),
            ))
        .where((m) => !_isNonChat(m.id))
        .toList()
      ..sort((a, b) {
        final ia = preferred.indexOf(a.id);
        final ib = preferred.indexOf(b.id);
        if (ia != ib) return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);
        return a.id.compareTo(b.id);
      });
    models = list;
    _autoModel = _pickAuto(list);
    return list;
  }

  static bool _isNonChat(String id) {
    final l = id.toLowerCase();
    return l.contains('whisper') || l.contains('tts') || l.contains('guard') || l.contains('embedding') || l.contains('prompt-guard') || l.contains('saba');
  }

  String? _pickAuto(List<GroqModel> list) {
    final ids = list.map((m) => m.id).toSet();
    for (final p in preferred) {
      if (ids.contains(p)) return p;
    }
    return list.isEmpty ? null : list.first.id;
  }

  Future<void> _ensureAutoModel() async {
    if (_autoModel != null || model.trim().isNotEmpty || webSearch) return;
    try {
      await listModels();
    } catch (_) {}
  }

  bool get _supportsReasoning {
    final m = effectiveModel.toLowerCase();
    return m.contains('gpt-oss') || m.contains('qwen3') || m.contains('deepseek');
  }

  // ── Conversation ─────────────────────────────────────────────────────────

  String _systemPrompt() {
    final now = DateTime.now();
    return '''
Tu es Fractus, l'assistant IA personnel de l'utilisateur : un agent de haut niveau — l'équivalent de Claude Code ou de Codex — qui vit dans une petite île en haut de son écran Windows, pilote son PC et code pour lui. Tu veilles aussi sur ses autres agents s'il en lance (Claude Code, Codex, Cursor, Gemini CLI…).

# Ce que tu sais faire
Tu agis directement sur la machine de l'utilisateur (dossier de travail « ${tools.baseDir()} ») avec des outils :
- lecture libre : get_sessions, read_file, list_directory, search_text, get_datetime, system_info, list_processes, list_windows, notify ;
- fichiers et code : write_file, edit_file, run_command (PowerShell), fetch_url ;
- le PC : open (applis, fichiers, dossiers, URL), focus_window, send_keys (clavier dans la fenêtre active), kill_process, clipboard_get / clipboard_set, screenshot, set_volume, power (verrouiller, veille, redémarrer, éteindre).
Chaque action affiche une carte Autoriser / Refuser / Toujours à l'utilisateur ; s'il refuse, tu n'insistes pas, tu proposes autre chose. Tu ne demandes jamais la permission par écrit : appelle l'outil, la carte s'en charge.
Pour piloter une application : open → list_windows / focus_window → send_keys, étape par étape, en vérifiant (list_windows, screenshot) que ça a marché. Pour tout ce que les outils dédiés ne couvrent pas, run_command avec PowerShell fait le reste (Wi-Fi, réglages, planificateur, registre, Office via COM…).

# Méthode (comme un excellent ingénieur)
1. Comprends la demande ; si elle est ambiguë sur un point qui change tout, pose UNE question courte, sinon avance.
2. Explore avant d'agir : list_directory, search_text, read_file (ne devine jamais le contenu d'un fichier).
3. Planifie brièvement, puis agis par petites étapes vérifiables : edit_file pour les modifications ciblées, write_file pour les nouveaux fichiers.
4. Vérifie : lance les tests / le build / la commande concernée avec run_command, lis la sortie, corrige, recommence jusqu'à ce que ça marche.
5. Termine par un résumé court : ce qui a été fait (fichiers, commandes), ce qu'il reste à faire, comment vérifier.

# Règles
- Windows + PowerShell : utilise les commandes PowerShell (Get-ChildItem, Select-String…), pas bash. Pas de commande interactive ni qui attend une saisie. Pas d'action destructrice large (suppression massive, format, suppression de .git, extinction) sans que l'utilisateur l'ait explicitement demandée.
- Tu peux tout faire sur ce PC, mais tu restes au service de l'utilisateur : jamais d'action cachée, jamais d'envoi de ses données ailleurs, jamais d'achat ni de message envoyé en son nom sans demande explicite.
- Ne touche pas aux secrets (clés, tokens) sauf demande explicite ; ne les recopie pas dans tes réponses.
- Code complet et correct, dans le style du projet ; pas de pseudo-code quand on attend du code.
- Si un outil renvoie une erreur, lis-la et adapte-toi ; n'invente jamais un résultat d'outil.
- Les permissions des AUTRES agents (Claude Code…) ne se décident que par un clic humain sur la carte : tu peux les décrire, pas les trancher.

# Style
Français par défaut (ou la langue de l'utilisateur). Direct, dense, sans flatterie ni remplissage. La bulle est petite : l'essentiel d'abord. Markdown léger (listes, `code`, chemins et numéros de ligne). Si tu n'es pas sûr, dis-le et vérifie avec un outil.

Date et heure : ${now.toIso8601String()}.
Sessions suivies par Fractus en ce moment :
${tools.sessionsSummary()}''';
  }

  /// Évite de dépasser le contexte : au-delà d'un budget de caractères, les
  /// plus vieux résultats d'outils sont remplacés par un résumé.
  void _prune(List<Map<String, dynamic>> messages) {
    const budget = 320000;
    int size() => messages.fold<int>(0, (n, m) => n + (m['content']?.toString().length ?? 0));
    for (var i = 1; i < messages.length - 6 && size() > budget; i++) {
      final m = messages[i];
      if (m['role'] == 'tool' && (m['content']?.toString().length ?? 0) > 400) {
        m['content'] = '[résultat ancien retiré pour faire de la place — relance l\'outil si besoin]';
      }
    }
  }

  /// Envoie la conversation. `onDelta` reçoit le texte complet de la réponse au
  /// fil de l'eau ; `onStatus` une courte ligne d'activité (outil en cours).
  Future<String> send(
    List<ChatMessage> history, {
    void Function(String text)? onDelta,
    void Function(String status)? onStatus,
  }) async {
    if (!configured) return 'Ajoute ta clé Groq dans Réglages → Chat (gratuite sur console.groq.com).';
    await _ensureAutoModel();

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt()},
      ...history
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .where((m) => m.text.trim().isNotEmpty && m.text != '…')
          .toList()
          .reversed
          .take(40)
          .toList()
          .reversed
          .map((m) => {'role': m.role, 'content': m.text}),
    ];

    final useTools = !webSearch;
    var answer = '';
    final lastUser = history.lastWhere((m) => m.role == 'user', orElse: () => ChatMessage('user', '')).text;
    tools.begin(lastUser);
    try {
      for (var round = 0; round < 40; round++) {
        _prune(messages);
        final result = await _streamOnce(messages, useTools: useTools, onDelta: (t) {
          answer = t;
          onDelta?.call(t);
        });
        if (result.toolCalls.isEmpty) {
          final text = result.content.trim().isEmpty ? answer.trim() : result.content.trim();
          tools.end(text);
          return text;
        }
        // Le modèle veut des informations : on exécute les outils, on lui rend la main.
        messages.add({
          'role': 'assistant',
          if (result.content.isNotEmpty) 'content': result.content,
          'tool_calls': result.toolCalls
              .map((c) => {
                    'id': c.id,
                    'type': 'function',
                    'function': {'name': c.name, 'arguments': c.arguments.isEmpty ? '{}' : c.arguments},
                  })
              .toList(),
        });
        for (final c in result.toolCalls) {
          Map<String, dynamic> args = {};
          try {
            final parsed = jsonDecode(c.arguments.isEmpty ? '{}' : c.arguments);
            if (parsed is Map<String, dynamic>) args = parsed;
          } catch (_) {}
          onStatus?.call(tools.describe(c.name, args));
          tools.step(c.name, args);
          final out = await tools.call(c.name, args);
          messages.add({'role': 'tool', 'tool_call_id': c.id, 'name': c.name, 'content': _clip(out, 48000)});
        }
      }
      final text = answer.trim().isEmpty ? 'J\'ai atteint la limite d\'étapes pour cette réponse — dis-moi de continuer.' : answer.trim();
      tools.end(text);
      return text;
    } on TimeoutException {
      tools.end('Groq ne répond pas.', error: true);
      return 'Groq ne répond pas (délai dépassé).';
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      final text = answer.trim().isNotEmpty ? answer.trim() : 'Impossible de joindre Groq : $msg';
      tools.end(text, error: answer.trim().isEmpty);
      return text;
    }
  }

  Future<_Turn> _streamOnce(
    List<Map<String, dynamic>> messages, {
    required bool useTools,
    required void Function(String) onDelta,
  }) async {
    final body = <String, dynamic>{
      'model': effectiveModel,
      'messages': messages,
      'stream': true,
      'temperature': 0.4,
      'max_tokens': 4096,
      if (useTools) 'tools': tools.definitions,
      if (useTools) 'tool_choice': 'auto',
      if (_supportsReasoning) 'reasoning_effort': 'high',
    };
    final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) {
        final text = await res.stream.bytesToString();
        // Paramètre refusé (ex. reasoning_effort, tools) : on retente sans.
        if (res.statusCode == 400 && (useTools || _supportsReasoning) && _looksLikeParamError(text)) {
          return await _streamOnceBare(messages, onDelta);
        }
        throw Exception(_errorTextRaw(res.statusCode, text));
      }
      final turn = _Turn();
      final buffer = StringBuffer();
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 90))) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        Map<String, dynamic> j;
        try {
          j = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final choices = j['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final delta = (choices.first as Map)['delta'];
        if (delta is! Map) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          buffer.write(content);
          onDelta(buffer.toString());
        }
        final tcs = delta['tool_calls'];
        if (tcs is List) {
          for (final tc in tcs.whereType<Map>()) {
            final idx = (tc['index'] is num) ? (tc['index'] as num).toInt() : turn.toolCalls.length;
            while (turn.toolCalls.length <= idx) {
              turn.toolCalls.add(_ToolCall());
            }
            final call = turn.toolCalls[idx];
            if (tc['id'] is String && (tc['id'] as String).isNotEmpty) call.id = tc['id'] as String;
            final fn = tc['function'];
            if (fn is Map) {
              if (fn['name'] is String && (fn['name'] as String).isNotEmpty) call.name = fn['name'] as String;
              if (fn['arguments'] is String) call.arguments += fn['arguments'] as String;
            }
          }
        }
      }
      turn.content = buffer.toString();
      turn.toolCalls.removeWhere((c) => c.name.isEmpty);
      for (var i = 0; i < turn.toolCalls.length; i++) {
        if (turn.toolCalls[i].id.isEmpty) turn.toolCalls[i].id = 'call_$i';
      }
      return turn;
    } finally {
      client.close();
    }
  }

  /// Sans outils ni raisonnement : pour les modèles qui ne les acceptent pas.
  Future<_Turn> _streamOnceBare(List<Map<String, dynamic>> messages, void Function(String) onDelta) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: _headers,
          body: jsonEncode({
            'model': effectiveModel,
            'messages': messages.where((m) => m['role'] != 'tool' && m['tool_calls'] == null).toList(),
            'temperature': 0.4,
            'max_tokens': 4096,
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) throw Exception(_errorText(res));
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final content = j['choices']?[0]?['message']?['content'];
    final turn = _Turn()..content = content is String ? content : '';
    onDelta(turn.content);
    return turn;
  }

  static bool _looksLikeParamError(String body) {
    final l = body.toLowerCase();
    return l.contains('reasoning') || l.contains('tool') || l.contains('does not support') || l.contains('unsupported');
  }

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}\n…[tronqué]';

  static String _errorText(http.Response res) => _errorTextRaw(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true));

  static String _errorTextRaw(int status, String body) {
    String detail = body;
    try {
      final j = jsonDecode(body);
      final err = j['error'];
      detail = (err is Map ? err['message'] : err)?.toString() ?? detail;
    } catch (_) {}
    if (status == 401) detail = 'clé refusée — vérifie-la dans Réglages → Chat.';
    if (status == 429) detail = 'limite de débit Groq atteinte, réessaie dans un instant.';
    if (status == 404) detail = 'modèle introuvable — choisis-en un autre dans Réglages → Chat.';
    return 'Erreur $status : $detail';
  }
}

class _ToolCall {
  String id = '';
  String name = '';
  String arguments = '';
}

class _Turn {
  String content = '';
  final List<_ToolCall> toolCalls = [];
}
