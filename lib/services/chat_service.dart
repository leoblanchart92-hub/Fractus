// Le chat de l'île : l'API Messages d'Anthropic avec votre propre clé.
// Rien n'est envoyé tant que vous n'avez pas tapé Entrée.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';

class ChatService {
  ChatService({required this.apiKey, required this.model});

  String apiKey;
  String model;

  bool get configured => apiKey.trim().isNotEmpty;

  Future<String> send(List<ChatMessage> history, {String? context}) async {
    if (!configured) {
      return 'Ajoute ta clé Anthropic dans Réglages → Chat pour parler à Claude.';
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
    final res = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 600,
            'system': system.toString(),
            'messages': messages,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      String detail = res.body;
      try {
        final j = jsonDecode(res.body);
        detail = j['error']?['message']?.toString() ?? detail;
      } catch (_) {}
      return 'Erreur ${res.statusCode} : $detail';
    }
    final j = jsonDecode(res.body);
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
}
