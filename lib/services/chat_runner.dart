// Envoyer un message à Fractus : le même chemin pour l'île et pour le téléphone.
// Ajoute le message, fait réfléchir le modèle (outils compris), met la réponse
// à jour au fil de l'eau dans la conversation de l'état.

import '../core/attachments.dart';
import '../core/models.dart';
import '../core/state.dart';
import 'attachment_reader.dart';
import 'chat_service.dart';

class ChatRunner {
  ChatRunner._();

  /// Renvoie faux si Fractus était déjà occupé (ou rien à envoyer : ni texte ni fichier).
  static Future<bool> send(
    AppState state,
    ChatService chat,
    String text, {
    List<Attachment> files = const [],
    void Function()? onUpdate,
  }) async {
    var t = text.trim();
    if ((t.isEmpty && files.isEmpty) || state.chatBusy) return false;
    final attached = List<Attachment>.from(files);
    if (t.isEmpty) t = attached.length == 1 ? 'Regarde ce fichier.' : 'Regarde ces fichiers.';
    final reply = ChatMessage('assistant', '…');
    state.chatBusy = true;
    state.touch();
    onUpdate?.call();
    // D'abord lire les fichiers (le texte, les images décrites), puis poser le message.
    String hidden = '';
    if (attached.isNotEmpty) {
      final waiting = ChatMessage('assistant', '⟡ je regarde ${attached.length == 1 ? attached.first.name : '${attached.length} fichiers'}…');
      state.addChat(waiting);
      try {
        hidden = await AttachmentReader.describe(attached, chat, t, onStatus: (s) {
          waiting.text = '⟡ $s…';
          state.touch();
          onUpdate?.call();
        });
      } finally {
        state.chat.remove(waiting);
      }
    }
    state.addChat(ChatMessage('user', t, files: attached.map((f) => f.name).toList(), hidden: hidden.isEmpty ? null : hidden));
    state.addChat(reply);
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
