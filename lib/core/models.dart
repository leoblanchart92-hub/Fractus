// Modèles : sessions d'agents, étapes, demandes de permission, questions, chat.

import 'dart:async';
import 'dart:ui';

import 'layout.dart';

enum StepKind { read, edit, run, search, note, prompt }

class SessionStep {
  SessionStep(this.kind, this.text, {this.detail});
  final StepKind kind;
  final String text;
  final String? detail;
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
  ChatMessage(this.role, this.text);
  final String role; // "user" | "assistant" | "system"
  String text;
}
