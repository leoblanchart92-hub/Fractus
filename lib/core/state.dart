// L'état de l'île : mode, vue, sessions, demandes en attente, chat.
// Pendant de windows/src/core/state.ts.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'layout.dart';
import 'models.dart';
import 'settings.dart';

class AppState extends ChangeNotifier {
  AppState(this.settings);

  Settings settings;

  IslandMode mode = IslandMode.hidden;
  IslandView view = IslandView.empty;

  /// L'île reste ouverte tant qu'une carte attend une décision ou que le chat a le focus.
  bool pinned = false;

  final Map<String, Session> sessions = {};
  String? focusedId;

  ApprovalInfo? pendingApproval;
  final List<ApprovalInfo> approvalQueue = [];

  /// Le plus de demandes en attente d'un coup, carte comprise (ApprovalQueue.maxPending).
  static const int maxPending = 5;

  final List<ChatMessage> chat = [];
  bool chatBusy = false;

  /// Nombre de « points » que la bande d'en-tête annonce : « N en cours ».
  int get runningCount => sessions.values.where((s) => s.isActive).length;

  Session? get focused => focusedId == null ? null : sessions[focusedId!];

  List<Session> get orderedSessions {
    final list = sessions.values.toList();
    list.sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  /// La pastille mise en avant : celle du focus, sinon la plus récente.
  Session? get frontSession => focused ?? (orderedSessions.isEmpty ? null : orderedSessions.first);

  /// L'état de Fractus, celui de la session en avant (ou idle).
  BotState get botState {
    if (pendingApproval != null) return pendingApproval!.isQuestion ? BotState.question : BotState.approval;
    final s = frontSession;
    if (s == null) return BotState.idle;
    return s.state;
  }

  IslandView defaultView() => sessions.isEmpty ? IslandView.empty : IslandView.overview;

  void setMode(IslandMode m) {
    if (mode == m) return;
    mode = m;
    notifyListeners();
  }

  void setView(IslandView v) {
    if (view == v) return;
    view = v;
    notifyListeners();
  }

  void focus(String? id) {
    focusedId = id;
    if (id != null) sessions[id]?.badge = false;
    notifyListeners();
  }

  Session upsertSession(String id, String project, String agent) {
    final s = sessions.putIfAbsent(id, () => Session(id: id, project: project, agent: agent));
    s.project = project;
    s.agent = agent;
    s.updated = DateTime.now();
    focusedId ??= id;
    return s;
  }

  void removeSession(String id) {
    sessions.remove(id);
    if (focusedId == id) focusedId = sessions.isEmpty ? null : orderedSessions.first.id;
    if (sessions.isEmpty && view == IslandView.overview) view = IslandView.empty;
    notifyListeners();
  }

  // ── Permissions et questions ─────────────────────────────────────────────

  /// Pose une demande : sur la carte si elle est libre, sinon dans la file.
  /// Renvoie vrai si la carte vient de la prendre (→ alerte).
  bool enqueueApproval(ApprovalInfo info) {
    if (pendingApproval == null) {
      pendingApproval = info;
      view = info.isQuestion ? IslandView.question : IslandView.approval;
      pinned = true;
      notifyListeners();
      return true;
    }
    if (approvalQueue.length + 1 >= maxPending) {
      info.finish(null); // trop de monde : le terminal reprend celle-ci
      return false;
    }
    approvalQueue.add(info);
    sessions[info.sessionId]?.badge = true;
    notifyListeners();
    return false;
  }

  /// La carte a répondu ; la suivante dans la file prend la place.
  /// Renvoie la demande qui vient d'arriver sur la carte, s'il y en a une.
  ApprovalInfo? endApproval() {
    pendingApproval = null;
    if (approvalQueue.isNotEmpty) {
      final next = approvalQueue.removeAt(0);
      pendingApproval = next;
      view = next.isQuestion ? IslandView.question : IslandView.approval;
      sessions[next.sessionId]?.badge = approvalQueue.any((x) => x.sessionId == next.sessionId);
      notifyListeners();
      return next;
    }
    pinned = false;
    view = defaultView();
    notifyListeners();
    return null;
  }

  /// Retire une demande expirée (où qu'elle soit).
  void expireApproval(String requestId) {
    approvalQueue.removeWhere((x) {
      if (x.requestId != requestId) return false;
      x.finish(null);
      return true;
    });
    if (pendingApproval?.requestId == requestId) {
      pendingApproval!.finish(null);
      endApproval();
    } else {
      notifyListeners();
    }
  }

  // ── Chat ──────────────────────────────────────────────────────────────────

  void addChat(ChatMessage m) {
    chat.add(m);
    if (chat.length > 60) chat.removeAt(0);
    notifyListeners();
  }

  void touch() => notifyListeners();

  Timer? _saveTimer;
  void saveSettingsSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => settings.save());
    notifyListeners();
  }
}
