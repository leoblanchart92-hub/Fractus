// Du PC vers l'île du téléphone : l'état reçu (PcStatus) devient les mêmes
// objets que ceux de l'île du PC (Session, SessionStep, BotState…), pour que
// les briques partagées (pastilles, mini Fractus, cartes) s'en servent telles quelles.

import '../core/layout.dart';
import '../core/models.dart';
import '../models.dart';

BotState botStateOf(String name) => BotState.values.firstWhere((b) => b.name == name, orElse: () => BotState.idle);

StepKind stepKindOf(String name) => StepKind.values.firstWhere((k) => k.name == name, orElse: () => StepKind.note);

Session sessionOf(PcSession p) {
  final s = Session(id: p.id, project: p.project, agent: p.agent)
    ..state = botStateOf(p.state)
    ..prompt = p.prompt
    ..lastMessage = p.lastMessage;
  for (final st in p.steps) {
    s.steps.add(SessionStep(stepKindOf(st.kind), st.text, detail: st.detail));
  }
  return s;
}

/// Les sessions du PC, la plus récente d'abord (comme `orderedSessions`).
List<Session> sessionsOf(PcStatus? s) => s == null ? const [] : s.sessions.map(sessionOf).toList();
