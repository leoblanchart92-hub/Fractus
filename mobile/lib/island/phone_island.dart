// L'île de Fractus, sur le téléphone — en plein écran : le même fond, la même
// lueur Aurora, le même en-tête à onglets que sur le PC ; Fractus en grand
// sous l'en-tête, et la carte du moment qui remplit le reste de l'écran.

import 'package:flutter/material.dart';

import '../api.dart';
import '../companion/bot_engine.dart';
import '../companion/companion_view.dart';
import '../core/anim.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../updater.dart';
import 'bridge.dart';
import 'views.dart';
import 'widgets.dart';

/// Les vues de l'île du téléphone (celles du PC, plus l'écran du PC).
enum PhoneView { overview, empty, approval, question, prompt, journal, settings, screen }

class PhoneIsland extends StatefulWidget {
  const PhoneIsland({super.key, required this.link, required this.bot});
  final PcLink link;
  final BotEngine bot;

  @override
  State<PhoneIsland> createState() => _PhoneIslandState();
}

class _PhoneIslandState extends State<PhoneIsland> {
  PhoneView _tab = PhoneView.overview;
  int _slaps = 0;
  DateTime _lastSlap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _greeted = false;

  PcLink get link => widget.link;
  BotEngine get bot => widget.bot;

  @override
  void initState() {
    super.initState();
    link.addListener(_sync);
    updater.addListener(_sync);
    if (!link.configured) _tab = PhoneView.settings;
  }

  @override
  void dispose() {
    link.removeListener(_sync);
    updater.removeListener(_sync);
    super.dispose();
  }

  /// Fractus prend l'état du PC (et dort quand il est injoignable).
  void _sync() {
    if (!mounted) return;
    final s = link.status;
    final target = !link.online || s == null ? BotState.sleeping : botStateOf(s.botState);
    if (bot.state != target && bot.state != BotState.dizzy) bot.setState(target);
    if (link.online && !_greeted) {
      _greeted = true;
      Future.delayed(const Duration(milliseconds: 300), bot.greet);
    }
    setState(() {});
  }

  PhoneView get _view {
    final s = link.status;
    if (s?.pending != null) return s!.pending!.isQuestion ? PhoneView.question : PhoneView.approval;
    if (!link.configured) return PhoneView.settings;
    if (_tab == PhoneView.overview && (s == null || s.sessions.isEmpty)) return PhoneView.empty;
    return _tab;
  }

  void _slap() {
    final now = DateTime.now();
    _slaps = now.difference(_lastSlap) < const Duration(milliseconds: 900) ? _slaps + 1 : 1;
    _lastSlap = now;
    if (_slaps >= 3) {
      _slaps = 0;
      bot.setState(BotState.dizzy);
      Future.delayed(const Duration(milliseconds: 2200), () {
        if (mounted) {
          bot.setState(link.online ? botStateOf(link.status?.botState ?? 'idle') : BotState.sleeping, force: true);
        }
      });
      return;
    }
    bot.slap();
  }

  /// La taille de Fractus selon la vue : en grand pour les cartes, plus discret
  /// quand la vue a besoin de place (chat, journal, réglages, écran, clavier).
  double _botDiameter(PhoneView view, bool keyboard) {
    if (keyboard) return 44;
    switch (view) {
      case PhoneView.overview:
      case PhoneView.empty:
      case PhoneView.approval:
      case PhoneView.question:
        return 112;
      case PhoneView.prompt:
      case PhoneView.journal:
      case PhoneView.settings:
      case PhoneView.screen:
        return 60;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final view = _view;
    final keyboard = mq.viewInsets.bottom > 80;
    final sessions = sessionsOf(link.status);
    final top = mq.padding.top;
    final diameter = _botDiameter(view, keyboard);
    final botTop = top + 34 + 6;
    final contentTop = botTop + diameter + 10;
    final bottom = (keyboard ? mq.viewInsets.bottom : mq.padding.bottom) + 10;
    final w = mq.size.width;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.islandTop, Palette.islandBottom],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(child: IgnorePointer(child: _AuroraGlow())),
          // ── La vue, sous Fractus, jusqu'en bas ─────────────────────────
          AnimatedPositioned(
            duration: openDuration,
            curve: openCurve,
            left: 10,
            right: 10,
            top: contentTop,
            bottom: bottom,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(key: ValueKey(view), child: _viewFor(view)),
            ),
          ),
          // ── L'en-tête ──────────────────────────────────────────────────
          Positioned(left: 0, width: w, top: top, height: 34, child: _header(view, sessions)),
          // ── Fractus ────────────────────────────────────────────────────
          AnimatedPositioned(
            duration: openDuration,
            curve: openCurve,
            left: (w - diameter) / 2,
            top: botTop,
            width: diameter,
            height: diameter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _slap,
              child: CompanionView(engine: bot, size: diameter),
            ),
          ),
          // ── Les minis des autres sessions, à droite de Fractus ─────────
          if (sessions.length > 1 && !keyboard)
            Positioned(
              left: (w + diameter) / 2 + 10,
              top: botTop + diameter / 2 - 10,
              child: Row(
                children: [
                  for (final s in sessions.skip(1).take(3))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: MiniBot(color: s.color, state: s.state, size: 18, badge: s.badge),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(PhoneView view, List<Session> sessions) {
    final running = sessions.where((s) => s.isActive).length;
    final muted = link.status?.settings?.muted ?? false;
    void go(PhoneView v) => setState(() => _tab = v);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          HeaderTab(icon: Icons.home_rounded, on: view == PhoneView.overview || view == PhoneView.empty, onTap: () => go(PhoneView.overview)),
          const SizedBox(width: 8),
          HeaderTab(icon: Icons.chat_bubble_rounded, on: view == PhoneView.prompt, size: 13, onTap: () => go(PhoneView.prompt)),
          const SizedBox(width: 8),
          HeaderTab(icon: Icons.auto_awesome_rounded, size: 15, onTap: () => go(PhoneView.prompt)),
          const SizedBox(width: 8),
          HeaderTab(icon: Icons.history_rounded, on: view == PhoneView.journal, size: 15, onTap: () => go(PhoneView.journal)),
          const SizedBox(width: 8),
          HeaderTab(icon: Icons.desktop_windows_rounded, on: view == PhoneView.screen, size: 14, onTap: () => go(PhoneView.screen)),
          const Spacer(),
          if (running > 0) ...[
            Text('$running en cours', style: ui(12, color: Palette.dim2)),
            const SizedBox(width: 10),
          ],
          if (updater.available) ...[
            HeaderTab(icon: Icons.system_update_rounded, on: true, size: 14, onTap: () => go(PhoneView.settings)),
            const SizedBox(width: 4),
          ],
          HeaderTab(
            icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: 14,
            onTap: () => link.run((c) => c.settings({'muted': !muted})),
          ),
          const SizedBox(width: 4),
          HeaderTab(icon: Icons.settings_rounded, on: view == PhoneView.settings, size: 14, onTap: () => go(view == PhoneView.settings ? PhoneView.overview : PhoneView.settings)),
        ],
      ),
    );
  }

  Widget _viewFor(PhoneView view) {
    switch (view) {
      case PhoneView.overview:
        return PhoneOverview(link: link);
      case PhoneView.empty:
        return PhoneEmpty(link: link, onChat: () => setState(() => _tab = PhoneView.prompt));
      case PhoneView.approval:
        return PhoneApproval(link: link);
      case PhoneView.question:
        return PhoneQuestion(link: link);
      case PhoneView.prompt:
        return PhoneChat(link: link);
      case PhoneView.journal:
        return PhoneJournal(link: link);
      case PhoneView.settings:
        return PhoneSettings(link: link, onConnected: () => setState(() => _tab = PhoneView.overview));
      case PhoneView.screen:
        return PhoneScreen(link: link);
    }
  }
}

/// Deux halos très doux — cyan en haut à gauche, violet en bas à droite.
class _AuroraGlow extends StatelessWidget {
  const _AuroraGlow();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: -120,
          top: -80,
          child: Container(
            width: 420,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Palette.accent.withValues(alpha: 0.13), Palette.accent.withValues(alpha: 0)]),
            ),
          ),
        ),
        Positioned(
          right: -140,
          bottom: -140,
          child: Container(
            width: 460,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Palette.accent3.withValues(alpha: 0.13), Palette.accent3.withValues(alpha: 0)]),
            ),
          ),
        ),
      ],
    );
  }
}
