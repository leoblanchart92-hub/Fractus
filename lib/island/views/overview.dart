// La vue d'ensemble : la session en avant à gauche, les autres pastilles à droite.

import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../controller.dart';
import '../widgets.dart';

class OverviewView extends StatelessWidget {
  const OverviewView({super.key, required this.state, required this.controller});
  final AppState state;
  final IslandController controller;

  @override
  Widget build(BuildContext context) {
    final front = state.frontSession;
    final others = state.orderedSessions.where((s) => s.id != front?.id).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: IslandCard(
            padding: const EdgeInsets.only(left: 108, top: 12, right: 12, bottom: 10),
            child: front == null ? const SizedBox.shrink() : _FocusCard(session: front),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: IslandCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: others.isEmpty
                ? Center(
                    child: Text('Aucune autre session', style: ui(12, color: Palette.dim3)),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in others.take(6))
                        SessionPill(session: s, width: 126, onTap: () => controller.state.focus(s.id)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.session});
  final Session session;

  String get _subtitle {
    switch (session.state) {
      case BotState.finished:
        return '${session.agent} a terminé';
      case BotState.error:
        return '${session.agent} a échoué';
      case BotState.idle:
        return '${session.agent} attend';
      case BotState.approval:
        return '${session.agent} attend ton accord';
      case BotState.question:
        return '${session.agent} te pose une question';
      default:
        return session.agent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = session.steps.length > 3 ? session.steps.sublist(session.steps.length - 3) : session.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TitleRow(color: session.color, project: session.project, subtitle: _subtitle),
        const SizedBox(height: 6),
        if (steps.isEmpty)
          Text(session.prompt ?? 'En attente…', maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(13, color: Palette.dim)),
        for (var i = 0; i < steps.length; i++) _StepRow(step: steps[i], current: i == steps.length - 1),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.current});
  final SessionStep step;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = current ? Palette.ink : Palette.dim3;
    final size = current ? 14.5 : 12.5;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: current ? 3 : 2),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Icon(stepIcon(step.kind), size: step.kind == StepKind.note ? 6 : (current ? 14 : 12), color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ui(size, weight: current ? FontWeight.w500 : FontWeight.w400, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
