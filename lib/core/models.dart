// Modèles : sessions d'agents, étapes, demandes de permission, questions, chat.

import 'dart:async';
import 'dart:ui';

import 'layout.dart';

enum StepKind { read, edit, run, search, note, prompt }

class SessionStep {
  SessionStep(this.kind, this.text, {this.detail}) : at = DateTime.now();
  final StepKind kind;
  final String text;
  final String? detail;
  final DateTime at;
}

class Session {
  Session({
    required this.id,
    required this.project,
    required this.agent,
    Color? color,
  }) : color = color ?? colorForProject(project);

  final String id;
  String project;
  String agent;
  /// Dossier de travail de l'agent (le `cwd` des hooks), s'il est connu.
  String cwd = '';
  Color color;
  BotState state = BotState.working;
  final List<SessionStep> steps = [];
  String? prompt;
  String? lastMessage;
  DateTime updated = DateTime.now();
  /// Nombre d'alertes en attente sur cette pastille (point sur le mini Fractus).
  bool badge = false;

  bool get isActive => state == BotState.working || state == BotState.thinking || state == BotState.searching;

  void addStep(SessionStep s) {
    steps.add(s);
    if (steps.length > 40) steps.removeAt(0);
    updated = DateTime.now();
  }
}

enum Decision { allow, always, deny }

class AskedQuestion {
  AskedQuestion({required this.question, required this.options, this.header, this.multi = false});
  final String question;
  final List<String> options;
  final String? header;
  final bool multi;
}

class ApprovalInfo {
  ApprovalInfo({
    required this.requestId,
    required this.sessionId,
    required this.project,
    required this.toolName,
    required this.summary,
    required this.toolInput,
    this.questions,
  });

  final String requestId;
  final String sessionId;
  final String project;
  final String toolName;
  /// Ce qui est montré sur la carte : la commande, le fichier, le motif…
  final String summary;
  final Map<String, dynamic> toolInput;
  /// Posé quand l'outil est AskUserQuestion : la carte devient une question.
  final List<AskedQuestion>? questions;

  final Completer<Map<String, dynamic>?> completer = Completer();
  final DateTime createdAt = DateTime.now();

  bool get isQuestion => questions != null && questions!.isNotEmpty;

  /// Répond à l'agent ; la réponse `null` = « demande dans le terminal ».
  void finish(Map<String, dynamic>? reply) {
    if (!completer.isCompleted) completer.complete(reply);
  }
}

class ChatMessage {
  ChatMessage(this.role, this.text, {DateTime? at}) : at = at ?? DateTime.now();
  final String role; // "user" | "assistant" | "system"
  String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {'role': role, 'text': text, 'at': at.toIso8601String()};

  static ChatMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final role = j['role'];
    final text = j['text'];
    if (role is! String || text is! String) return null;
    return ChatMessage(role, text, at: DateTime.tryParse((j['at'] ?? '').toString()));
  }
}

/// Une conversation du chat : ses messages, un titre (la première demande), ses dates.
class Conversation {
  Conversation({String? id, DateTime? created})
      : id = id ?? DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        created = created ?? DateTime.now(),
        updated = created ?? DateTime.now();

  final String id;
  final DateTime created;
  DateTime updated;
  String title = '';
  final List<ChatMessage> messages = [];

  /// Les messages gardés en mémoire (le fichier garde les mêmes).
  static const int maxMessages = 400;

  bool get isEmpty => messages.isEmpty;

  void add(ChatMessage m) {
    messages.add(m);
    if (messages.length > maxMessages) messages.removeAt(0);
    if (title.isEmpty && m.role == 'user') title = titleFrom(m.text);
    updated = DateTime.now();
  }

  static String titleFrom(String text) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= 48 ? one : '${one.substring(0, 47)}…';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  static Conversation? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final c = Conversation(id: id, created: DateTime.tryParse((j['created'] ?? '').toString()));
    c.updated = DateTime.tryParse((j['updated'] ?? '').toString()) ?? c.created;
    c.title = (j['title'] ?? '').toString();
    final msgs = j['messages'];
    if (msgs is List) {
      for (final m in msgs) {
        final cm = ChatMessage.fromJson(m);
        if (cm != null) c.messages.add(cm);
      }
    }
    if (c.title.isEmpty) {
      for (final m in c.messages) {
        if (m.role == 'user') {
          c.title = titleFrom(m.text);
          break;
        }
      }
    }
    return c;
  }
}

/// Ce qu'on sait d'une conversation sans l'ouvrir (pour la liste).
class ConversationMeta {
  const ConversationMeta({required this.id, required this.title, required this.updated, required this.count});
  final String id;
  final String title;
  final DateTime updated;
  final int count;
}
