// L'île : l'enveloppe noire collée en haut de l'écran, son en-tête, Mochi,
// et la vue du moment. Pendant de windows/src/island/island.ts (la partie vue).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/anim.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../mochi/mochi_view.dart';
import '../services/chat_service.dart';
import 'controller.dart';
import 'views/cards.dart';
import 'views/chat.dart';
import 'views/overview.dart';
import 'views/settings.dart';
import 'widgets.dart';

class IslandWidget extends StatefulWidget {
  const IslandWidget({
    super.key,
    required this.state,
    required this.controller,
    required this.chat,
    required this.hookPort,
    required this.hookError,
    required this.onDemo,
    required this.onQuit,
    required this.onRestartHooks,
  });

  final AppState state;
  final IslandController controller;
  final ChatService chat;
  final int? Function() hookPort;
  final String? Function() hookError;
  final VoidCallback onDemo;
  final VoidCallback onQuit;
  final VoidCallback onRestartHooks;

  @override
  State<IslandWidget> createState() => _IslandWidgetState();
}

class _IslandWidgetState extends State<IslandWidget> {
  final FocusNode _keys = FocusNode(debugLabel: 'island');
  IslandMode _lastMode = IslandMode.hidden;
  bool _opening = true;

  AppState get state => widget.state;
  IslandController get c => widget.controller;

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      if (state.view == IslandView.prompt || state.view == IslandView.settings) {
        state.setView(state.defaultView());
      }
      c.close();
      return KeyEventResult.handled;
    }
    if (state.pendingApproval != null && !state.pendingApproval!.isQuestion) {
      if (k == LogicalKeyboardKey.keyY) {
        c.decide(Decision.allow);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyN) {
        c.decide(Decision.deny);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([state, c]),
      builder: (context, _) {
        final mode = state.mode;
        final view = state.view;
        final size = islandSize(
          mode,
          view,
          chatCount: state.chat.length,
          questionPicker: state.pendingApproval?.isQuestion == true,
        );
        // Ouverture : la courbe « spring » ; fermeture : plus sèche.
        final rank = {IslandMode.hidden: 0, IslandMode.compact: 1, IslandMode.expanded: 2};
        if (mode != _lastMode) {
          _opening = rank[mode]! >= rank[_lastMode]!;
          _lastMode = mode;
        }
        final duration = _opening ? openDuration : closeDuration;
        final curve = _opening ? openCurve : closeCurve;
        final corner = mode == IslandMode.expanded ? expandedCorner : roundedCorner;
        final h = size.height;
        final bot = botPosition(mode, view, h);
        final botD = view == IslandView.greeting && mode == IslandMode.expanded ? 76.0 : bot.diameter;

        if (mode == IslandMode.expanded && !_keys.hasFocus && view != IslandView.prompt && view != IslandView.settings) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_keys.hasFocus) _keys.requestFocus();
          });
        }

        return Align(
          alignment: Alignment.topCenter,
          child: Focus(
            focusNode: _keys,
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: c.tapIsland,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // Les « oreilles » : les petits congés qui raccordent l'île au bord de l'écran.
                  AnimatedContainer(
                    duration: duration,
                    curve: curve,
                    width: size.width + 28,
                    height: h > 0 ? 14 : 0,
                    child: h > 0 ? const CustomPaint(painter: _EarsPainter()) : null,
                  ),
                  AnimatedContainer(
                    duration: duration,
                    curve: curve,
                    width: size.width,
                    height: h,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(corner)),
                    ),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // ── La vue ─────────────────────────────────────────
                        // La vue est posée à sa taille finale (jamais négative pendant
                        // l'animation de l'enveloppe) ; l'enveloppe la rogne en attendant.
                        if (mode == IslandMode.expanded)
                          Positioned(
                            left: 8,
                            width: size.width - 16,
                            top: view == IslandView.greeting ? 0 : 42,
                            height: math.max(0.0, h - (view == IslandView.greeting ? 0 : 50)),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: KeyedSubtree(key: ValueKey(view), child: _viewFor(view)),
                            ),
                          ),

                        // ── L'en-tête ──────────────────────────────────────
                        if (mode == IslandMode.expanded && view != IslandView.greeting)
                          Positioned(left: 0, width: size.width, top: 0, height: 34, child: _header(view)),

                        // ── Les mini Mochis de l'île compacte ──────────────
                        if (mode == IslandMode.compact) ..._compactMinis(size.width),

                        // ── Mochi ──────────────────────────────────────────
                        AnimatedPositioned(
                          duration: duration,
                          curve: curve,
                          left: bot.cx - botD / 2,
                          top: bot.cy - botD / 2,
                          width: botD,
                          height: botD,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: bot.opacity,
                            child: botD <= 0
                                ? const SizedBox.shrink()
                                : MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    onEnter: (_) => c.hoverBot(true),
                                    onExit: (_) => c.hoverBot(false),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        if (mode == IslandMode.compact) {
                                          c.open();
                                        } else {
                                          c.slapBot();
                                        }
                                      },
                                      child: MochiView(engine: c.bot, size: botD),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _compactMinis(double w) {
    final sessions = state.orderedSessions.take(3).toList();
    if (sessions.isEmpty) return const [];
    // Un petit nuage de minis à droite, comme sur la capture « compact ».
    const slots = [Offset(-52, 4), Offset(-30, 4), Offset(-41, 18)];
    final out = <Widget>[];
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final o = slots[i];
      out.add(Positioned(
        left: w + o.dx - 8,
        top: o.dy - 3,
        child: MiniBot(color: s.color, state: s.state, size: 11, badge: s.badge),
      ));
    }
    return out;
  }

  Widget _header(IslandView view) {
    final running = state.runningCount;
    final muted = state.settings.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          HeaderTab(
            icon: Icons.home_rounded,
            on: view == IslandView.overview || view == IslandView.empty,
            tooltip: 'Accueil',
            onTap: () => state.setView(state.defaultView()),
          ),
          const SizedBox(width: 8),
          HeaderTab(
            icon: Icons.chat_bubble_rounded,
            on: view == IslandView.prompt,
            tooltip: 'Chat',
            size: 13,
            onTap: () => state.setView(IslandView.prompt),
          ),
          const SizedBox(width: 8),
          HeaderTab(icon: Icons.add_rounded, tooltip: 'Jouer la démo', size: 17, onTap: widget.onDemo),
          const Spacer(),
          if (running > 0) ...[
            Text('$running en cours', style: ui(12, color: Palette.dim2)),
            const SizedBox(width: 10),
          ],
          HeaderTab(
            icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            tooltip: muted ? 'Remettre le son' : 'Couper le son',
            size: 14,
            onTap: () {
              state.settings.muted = !muted;
              state.saveSettingsSoon();
            },
          ),
          const SizedBox(width: 4),
          HeaderTab(
            icon: Icons.settings_rounded,
            on: view == IslandView.settings,
            tooltip: 'Réglages',
            size: 14,
            onTap: () => state.setView(view == IslandView.settings ? state.defaultView() : IslandView.settings),
          ),
          const SizedBox(width: 4),
          HeaderTab(icon: Icons.close_rounded, tooltip: 'Replier', size: 14, onTap: c.close),
        ],
      ),
    );
  }

  Widget _viewFor(IslandView view) {
    switch (view) {
      case IslandView.overview:
        return OverviewView(state: state, controller: c);
      case IslandView.empty:
        return EmptyView(
          onDemo: widget.onDemo,
          onSettings: () => state.setView(IslandView.settings),
          hookPort: widget.hookPort(),
        );
      case IslandView.approval:
        return ApprovalView(state: state, controller: c);
      case IslandView.question:
        return QuestionView(state: state, controller: c);
      case IslandView.finished:
        return FinishedView(state: state, controller: c);
      case IslandView.error:
        return FinishedView(state: state, controller: c, error: true);
      case IslandView.confused:
        return const ConfusedView();
      case IslandView.prompt:
        return ChatView(state: state, controller: c, chat: widget.chat);
      case IslandView.settings:
        return SettingsView(
          state: state,
          controller: c,
          hookPort: widget.hookPort(),
          hookError: widget.hookError(),
          onDemo: widget.onDemo,
          onQuit: widget.onQuit,
          onRestartHooks: widget.onRestartHooks,
        );
      case IslandView.greeting:
        return const GreetingView();
      case IslandView.launch:
        return OverviewView(state: state, controller: c);
    }
  }
}

/// Les deux congés concaves de 14 px de part et d'autre du haut de l'île
/// (#island::before / ::after dans le prototype).
class _EarsPainter extends CustomPainter {
  const _EarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const r = 14.0;
    final paint = Paint()..color = Colors.black;
    // Gauche : un carré de 14×14 moins un cercle centré en (0, 14).
    final left = Path.combine(
      PathOperation.difference,
      Path()..addRect(const Rect.fromLTWH(0, 0, r, r)),
      Path()..addOval(Rect.fromCircle(center: const Offset(0, r), radius: r)),
    );
    canvas.drawPath(left, paint);
    final right = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(size.width - r, 0, r, r)),
      Path()..addOval(Rect.fromCircle(center: Offset(size.width, r), radius: r)),
    );
    canvas.drawPath(right, paint);
  }

  @override
  bool shouldRepaint(covariant _EarsPainter oldDelegate) => false;
}
