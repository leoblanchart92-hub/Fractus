// Le chat de l'île, avec votre propre clé. Trois fournisseurs :
//   - Groq (par défaut)   : API compatible OpenAI, https://api.groq.com/openai/v1
//   - OpenAI / compatible : n'importe quel serveur /v1/chat/completions (OpenAI, Mistral, Ollama…)
//   - Anthropic           : API Messages
// Rien n'est envoyé tant que vous n'avez pas tapé Entrée.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';

enum ChatProvider { groq, openai, anthropic }

extension ChatProviderInfo on ChatProvider {
  String get label => switch (this) {
        ChatProvider.groq => 'Groq',
        ChatProvider.openai => 'OpenAI / compatible',
        ChatProvider.anthropic => 'Anthropic',
      };

  /// Modèle proposé quand le champ est vide.
  String get defaultModel => switch (this) {
        ChatProvider.groq => 'llama-3.3-70b-versatile',
        ChatProvider.openai => 'gpt-4o-mini',
        ChatProvider.anthropic => 'claude-sonnet-4-5',
      };

  String get defaultBaseUrl => switch (this) {
        ChatProvider.groq => 'https://api.groq.com/openai/v1',
        ChatProvider.openai => 'https://api.openai.com/v1',
        ChatProvider.anthropic => 'https://api.anthropic.com/v1',
      };

  String get keyHint => switch (this) {
        ChatProvider.groq => 'Clé API Groq (gsk_…)',
        ChatProvider.openai => 'Clé API (sk-…)',
        ChatProvider.anthropic => 'Clé API Anthropic (sk-ant-…)',
      };

  /// Le nom qu'on donne à l'interlocuteur dans l'interface.
  String get assistantName => switch (this) {
        ChatProvider.groq => 'Groq',
        ChatProvider.openai => 'le modèle',
        ChatProvider.anthropic => 'Claude',
      };

  static ChatProvider parse(String? s) {
    for (final p in ChatProvider.values) {
      if (p.name == s) return p;
    }
    return ChatProvider.groq;
  }
}

class ChatService {
  ChatService({
    required this.apiKey,
    required this.model,
    this.provider = ChatProvider.groq,
    this.baseUrl = '',
  });

  String apiKey;
  String model;
  ChatProvider provider;
  /// URL de base personnalisée (OpenAI compatible) ; vide = celle du fournisseur.
  String baseUrl;

  bool get configured => apiKey.trim().isNotEmpty;

  String get _model => model.trim().isEmpty ? provider.defaultModel : model.trim();
  String get _base => (baseUrl.trim().isEmpty ? provider.defaultBaseUrl : baseUrl.trim()).replaceAll(RegExp(r'/+$'), '');

  Future<String> send(List<ChatMessage> history, {String? context}) async {
    if (!configured) {
      return 'Ajoute ta clé ${provider.label} dans Réglages → Chat pour discuter.';
    }
    final messages = history
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();
    final system = StringBuffer(
      'Tu es Fractus, un petit compagnon qui vit en haut de l\'écran et surveille les agents de code. '
      'Réponds court, en français, sans Markdown lourd.',
    );
    if (context != null && context.isNotEmpty) {
      system.write('\n\nContexte de l\'île :\n$context');
    }
    try {
      return provider == ChatProvider.anthropic
          ? await _sendAnthropic(system.toString(), messages)
          : await _sendOpenAi(system.toString(), messages);
    } catch (e) {
      return 'Impossible de joindre ${provider.label} : ${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  /// OpenAI, Groq et compatibles : POST {base}/chat/completions.
  Future<String> _sendOpenAi(String system, List<Map<String, String>> messages) async {
    final res = await http
        .post(
          Uri.parse('$_base/chat/completions'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer ${apiKey.trim()}',
          },
          body: jsonEncode({
            'model': _model,
            'max_tokens': 600,
            'temperature': 0.6,
            'messages': [
              {'role': 'system', 'content': system},
              ...messages,
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) return _error(res);
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty) {
      final content = choices.first['message']?['content'];
      if (content is String) return content.trim();
      if (content is List) {
        return content.whereType<Map>().map((b) => b['text']?.toString() ?? '').join('\n').trim();
      }
    }
    return '';
  }

  /// Anthropic : POST {base}/messages.
  Future<String> _sendAnthropic(String system, List<Map<String, String>> messages) async {
    final res = await http
        .post(
          Uri.parse('$_base/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': _model,
            'max_tokens': 600,
            'system': system,
            'messages': messages,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) return _error(res);
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final content = j['content'];
    if (content is List) {
      return content
          .where((b) => b is Map && b['type'] == 'text')
          .map((b) => b['text'].toString())
          .join('\n')
          .trim();
    }
    return '';
  }

  String _error(http.Response res) {
    String detail = res.body;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final err = j['error'];
      detail = (err is Map ? err['message'] : err)?.toString() ?? detail;
    } catch (_) {}
    if (res.statusCode == 401) detail = 'clé refusée — vérifie-la dans Réglages → Chat.';
    if (res.statusCode == 429) detail = 'limite de débit atteinte, réessaie dans un instant.';
    return 'Erreur ${res.statusCode} : $detail';
  }
}
