// Envoyer un message à Fractus : le même chemin pour l'île et pour le téléphone.
// Ajoute le message, fait réfléchir le modèle (outils compris), met la réponse
// à jour au fil de l'eau dans la conversation de l'état.

import '../core/models.dart';
import '../core/state.dart';
import 'chat_service.dart';

class ChatRunner {
  ChatRunner._();

  /// Renvoie faux si Fractus était déjà occupé (ou le texte vide).
  static Future<bool> send(AppState state, ChatService chat, String text, {void Function()? onUpdate}) async {
    final t = text.trim();
    if (t.isEmpty || state.chatBusy) return false;
    state.addChat(ChatMessage('user', t));
    final reply = ChatMessage('assistant', '…');
    state.addChat(reply);
    state.chatBusy = true;
    state.touch();
    onUpdate?.call();
    try {
      final answer = await chat.send(
        state.chat.where((m) => !identical(m, reply)).toList(),
        onDelta: (partial) {
          reply.text = partial;
          state.touch();
          onUpdate?.call();
        },
        onStatus: (status) {
          // Entre deux tours, on montre l'outil en cours ; le prochain texte le remplacera.
          reply.text = '⟡ $status…';
          state.touch();
        },
      );
      reply.text = answer.isEmpty ? '…' : answer;
    } catch (e) {
      reply.text = 'Impossible de joindre Groq : $e';
    } finally {
      state.chatBusy = false;
      state.saveChatSoon();
      onUpdate?.call();
    }
    return true;
  }
}
