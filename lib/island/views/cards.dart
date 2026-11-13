// Les cartes d'alerte : permission, question, terminé, erreur, étourdi, vide, salut.

import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../controller.dart';
import '../widgets.dart';

const EdgeInsets _cardPad = EdgeInsets.only(left: 108, top: 12, right: 14, bottom: 12);

/// La colonne des autres sessions, à droite de la carte (mode « column »).
class SessionColumn extends StatelessWidget {
  const SessionColumn({super.key, required this.state, required this.controller, this.exclude});
  final AppState state;
  final IslandController controller;
  final String? exclude;

  @override
  Widget build(BuildContext context) {
    final others = state.orderedSessions.where((s) => s.id != exclude).take(4).toList();
    return SizedBox(
      width: 34,
      child: Column(
        children: [
          for (final s in others)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Tooltip(
                message: s.project,
                waitDuration: const Duration(milliseconds: 500),
                textStyle: ui(11),
                decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(6)),
                child: GestureDetector(
                  onTap: () => controller.state.focus(s.id),
                  child: MiniBot(color: s.color, state: s.state, size: 18, badge: s.badge),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carte + colonne, la disposition de toutes les alertes.
class _CardWithColumn extends StatelessWidget {
  const _CardWithColumn({required this.state, required this.controller, required this.card, this.exclude});
  final AppState state;
  final IslandController controller;
  final Widget card;
  final String? exclude;

  @override
  Widget build(BuildContext context) {
    final hasOthers = state.sessions.length > (exclude == null ? 0 : 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: card),
        if (hasOthers) ...[
          const SizedBox(width: 6),
          SessionColumn(state: state, controller: controller, exclude: exclude),
        ],
      ],
    );
  }
}

class ApprovalView extends StatelessWidget {
  const ApprovalView({super.key, required this.state, required this.controller});
  final AppState state;
  final IslandController controller;

  String _title(ApprovalInfo a, String agent) {
    switch (a.toolName) {
      case 'Bash':
        return '$agent veut lancer une commande';
      case 'Edit':
      case 'MultiEdit':
      case 'NotebookEdit':
        return '$agent veut modifier un fichier';
      case 'Write':
        return '$agent veut écrire un fichier';
      case 'Read':
        return '$agent veut lire un fichier';
      case 'WebFetch':
      case 'WebSearch':
        return '$agent veut aller sur le web';
      default:
        return '$agent veut utiliser ${a.toolName}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = state.pendingApproval;
    if (a == null) return const SizedBox.shrink();
    final s = state.sessions[a.sessionId];
    final color = s?.color ?? colorForProject(a.project);
    final waiting = state.approvalQueue.length;
    return _CardWithColumn(
      state: state,
      controller: controller,
      exclude: a.sessionId,
      card: IslandCard(
        wash: Wash.amber,
        padding: _cardPad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: TitleRow(color: color, project: a.project, subtitle: _title(a, s?.agent ?? 'Claude Code'))),
                if (waiting > 0) Text('+$waiting en attente', style: ui(11, color: Palette.dim3)),
              ],
            ),
            const SizedBox(height: 8),
            CodeChip(a.summary.isEmpty ? a.toolName : a.summary),
            const Spacer(),
            Row(
              children: [
                IslandButton(label: 'Refuser', keyHint: 'N', onTap: () => controller.decide(Decision.deny)),
                const SizedBox(width: 8),
                IslandButton(label: 'Autoriser', keyHint: 'Y', primary: true, onTap: () => controller.decide(Decision.allow)),
                const SizedBox(width: 8),
                IslandButton(label: 'Toujours', onTap: () => controller.decide(Decision.always)),
                const Spacer(),
                _LinkText('Dans le terminal', onTap: controller.deferToTerminal),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class QuestionView extends StatefulWidget {
  const QuestionView({super.key, required this.state, required this.controller});
  final AppState state;
  final IslandController controller;

  @override
  State<QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<QuestionView> {
  int _index = 0;
  final Map<String, String> _answers = {};
  final Set<String> _multi = {};
  String? _requestId;

  @override
  Widget build(BuildContext context) {
    final a = widget.state.pendingApproval;
    if (a == null || !a.isQuestion) return const SizedBox.shrink();
    if (_requestId != a.requestId) {
      _requestId = a.requestId;
      _index = 0;
      _answers.clear();
      _multi.clear();
    }
    final qs = a.questions!;
    final q = qs[_index.clamp(0, qs.length - 1)];
    final s = widget.state.sessions[a.sessionId];
    final color = s?.color ?? colorForProject(a.project);

    void pick(String label) {
      if (q.multi) {
        setState(() {
          if (!_multi.remove(label)) _multi.add(label);
        });
        return;
      }
      _answers[q.question] = label;
      _next();
    }

    return _CardWithColumn(
      state: widget.state,
      controller: widget.controller,
      exclude: a.sessionId,
      card: IslandCard(
        wash: Wash.cyan,
        padding: _cardPad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TitleRow(
                    color: color,
                    project: a.project,
                    subtitle: '${s?.agent ?? 'Claude Code'} te pose une question',
                  ),
                ),
                if (qs.length > 1) Text('${_index + 1}/${qs.length}', style: ui(11, color: Palette.dim3)),
              ],
            ),
            const SizedBox(height: 4),
            Text(q.question, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(15.5, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final o in q.options)
                      IslandButton(
                        label: q.multi && _multi.contains(o) ? '✓ $o' : o,
                        primary: q.multi && _multi.contains(o),
                        onTap: () => pick(o),
                      ),
                    if (q.multi) IslandButton(label: 'Envoyer', primary: true, onTap: () {
                      _answers[q.question] = _multi.join(', ');
                      _multi.clear();
                      _next();
                    }),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _LinkText('Répondre dans le terminal', onTap: widget.controller.deferToTerminal),
            ),
          ],
        ),
      ),
    );
  }

  void _next() {
    final a = widget.state.pendingApproval;
    if (a == null) return;
    if (_index + 1 < a.questions!.length) {
      setState(() => _index++);
    } else {
      widget.controller.answerQuestion(Map.of(_answers));
    }
  }
}

class FinishedView extends StatelessWidget {
  const FinishedView({super.key, required this.state, required this.controller, this.error = false});
  final AppState state;
  final IslandController controller;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final s = state.frontSession;
    if (s == null) return const SizedBox.shrink();
    final message = s.lastMessage ?? (error ? 'Quelque chose a échoué.' : 'C\'est fait.');
    return _CardWithColumn(
      state: state,
      controller: controller,
      exclude: s.id,
      card: IslandCard(
        wash: error ? Wash.red : Wash.green,
        padding: _cardPad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TitleRow(color: s.color, project: s.project, subtitle: error ? '${s.agent} a échoué' : '${s.agent} a terminé'),
            const SizedBox(height: 4),
            Expanded(
              child: Text(_firstLines(message), maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(15.5, weight: FontWeight.w700)),
            ),
            Row(
              children: [
                IslandButton(label: 'Voir la session', primary: true, onTap: () => controller.state.setView(IslandView.overview)),
                const SizedBox(width: 8),
                IslandButton(label: 'OK', onTap: controller.dismissCard),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _firstLines(String m) {
    final clean = m.replaceAll(RegExp(r'[#*`>_]'), '').trim();
    return clean.split('\n').where((l) => l.trim().isNotEmpty).take(2).join(' ');
  }
}

class ConfusedView extends StatelessWidget {
  const ConfusedView({super.key});

  @override
  Widget build(BuildContext context) {
    return IslandCard(
      wash: Wash.pink,
      padding: const EdgeInsets.only(left: 124, top: 14, right: 14, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Ouille…', style: ui(15.5, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Trois tapes d\'un coup, Fractus a la tête qui tourne. Laisse-lui une seconde.',
              style: ui(12.5, color: Palette.dim)),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.onDemo, required this.onSettings, this.hookPort});
  final VoidCallback onDemo;
  final VoidCallback onSettings;
  final int? hookPort;

  @override
  Widget build(BuildContext context) {
    return IslandCard(
      wash: Wash.soft,
      padding: const EdgeInsets.only(left: 116, top: 14, right: 14, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Aucun agent en cours', style: ui(15, weight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            hookPort == null
                ? 'Le serveur de hooks n\'a pas pu démarrer : vois les réglages.'
                : 'Lance Claude Code avec le hook Fractus (port $hookPort), ou regarde la démo.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ui(12.5, color: Palette.dim),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IslandButton(label: 'Jouer la démo', primary: true, onTap: onDemo),
              const SizedBox(width: 8),
              IslandButton(label: 'Brancher un agent', onTap: onSettings),
            ],
          ),
        ],
      ),
    );
  }
}

class GreetingView extends StatelessWidget {
  const GreetingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.82),
      child: Text('Fractus', style: ui(12, weight: FontWeight.w600, color: Palette.dim3)),
    );
  }
}

class _LinkText extends StatefulWidget {
  const _LinkText(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(widget.label, style: ui(11.5, color: _hover ? Palette.ink : Palette.dim3)),
      ),
    );
  }
}
