// L'île de Fractus, sur le téléphone : la même enveloppe que sur le PC (congés,
// lueur Aurora, en-tête à onglets, Fractus à gauche, la carte du moment),
// nourrie par l'état du PC. Repliée : la petite île compacte avec les minis.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../companion/bot_engine.dart';
import '../companion/companion_view.dart';
import '../core/anim.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'widgets.dart';
import 'bridge.dart';
import 'views.dart';

/// Les vues de l'île du téléphone (un sous-ensemble de celles du PC).
enum PhoneView { overview, empty, approval, question, prompt, journal, settings }

const Map<PhoneView, IslandView> _layoutOf = {
  PhoneView.overview: IslandView.overview,
  PhoneView.empty: IslandView.empty,
  PhoneView.approval: IslandView.approval,
  PhoneView.question: IslandView.question,
  PhoneView.prompt: IslandView.prompt,
  PhoneView.journal: IslandView.journal,
  PhoneView.settings: IslandView.settings,
};

/// Hauteurs ouvertes, en pixels logiques : celles du PC pour les cartes, plus
/// de place pour le chat, le journal et les réglages (on a un écran en hauteur).
const Map<PhoneView, double> _heights = {
  PhoneView.overview: 190,
  PhoneView.empty: 166,
  PhoneView.approval: 190,
  PhoneView.question: 230,
  PhoneView.prompt: 460,
  PhoneView.journal: 400,
  PhoneView.settings: 470,
};

class PhoneIsland extends StatefulWidget {
  const PhoneIsland({super.key, required this.link, required this.bot});
  final PcLink link;
  final BotEngine bot;

  @override
  State<PhoneIsland> createState() => _PhoneIslandState();
}

class _PhoneIslandState extends State<PhoneIsland> {
  PhoneView _tab = PhoneView.overview;
  bool _compact = false;
  bool _opening = true;
  bool _wasCompact = false;
  int _slaps = 0;
  DateTime _lastSlap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _greeted = false;

  PcLink get link => widget.link;
  BotEngine get bot => widget.bot;

  @override
  void initState() {
    super.initState();
    link.addListener(_sync);
    if (!link.configured) _tab = PhoneView.settings;
  }

  @override
  void dispose() {
    link.removeListener(_sync);
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
    // Une demande arrive : l'île s'ouvre toute seule, comme sur le PC.
    if (s?.pending != null && _compact) _compact = false;
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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final w = _compact ? compactW : math.min(expandedW, screenW - 12);
    final view = _view;
    final sessions = sessionsOf(link.status);
    // La vue d'ensemble grandit avec les étapes et les pastilles des autres sessions.
    var wanted = _heights[view]!;
    if (view == PhoneView.overview) {
      final front = sessions.first;
      wanted = 120 + 20.0 * front.steps.length.clamp(1, 5).toDouble() + (sessions.length > 1 ? 52.0 : 0.0);
    }
    final room = mq.size.height - mq.padding.top - mq.viewInsets.bottom - 12;
    final h = _compact ? notchH : math.min(wanted, math.max(140.0, room));
    if (_compact != _wasCompact) {
      _opening = !_compact;
      _wasCompact = _compact;
    }
    final duration = _opening ? openDuration : closeDuration;
    final curve = _opening ? openCurve : closeCurve;
    final corner = _compact ? roundedCorner : expandedCorner;
    final bp = botPosition(_compact ? IslandMode.compact : IslandMode.expanded, _layoutOf[view]!, _compact ? h : math.min(h, 240.0));

    return Align(
      alignment: Alignment.topCenter,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          AnimatedContainer(
            duration: duration,
            curve: curve,
            width: w + 28,
            height: 14,
            child: const CustomPaint(painter: _EarsPainter()),
          ),
          AnimatedContainer(
            duration: duration,
            curve: curve,
            width: w,
            height: h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Palette.islandTop, Palette.islandBottom],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(corner)),
              border: Border.all(color: Palette.accent2.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(color: Palette.accent.withValues(alpha: 0.10), blurRadius: 28, offset: const Offset(-6, 10)),
                BoxShadow(color: Palette.accent3.withValues(alpha: 0.10), blurRadius: 28, offset: const Offset(6, 10)),
                const BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
              ],
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _compact ? () => setState(() => _compact = false) : null,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (!_compact) const Positioned.fill(child: IgnorePointer(child: _AuroraGlow())),
                  if (!_compact)
                    Positioned(
                      left: 8,
                      width: w - 16,
                      top: 42,
                      height: math.max(0.0, h - 50),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(key: ValueKey(view), child: _viewFor(view)),
                      ),
                    ),
                  if (!_compact) Positioned(left: 0, width: w, top: 0, height: 34, child: _header(view, sessions)),
                  if (_compact) ..._compactMinis(w, sessions),
                  AnimatedPositioned(
                    duration: duration,
                    curve: curve,
                    left: bp.cx - bp.diameter / 2,
                    top: bp.cy - bp.diameter / 2,
                    width: bp.diameter,
                    height: bp.diameter,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _compact ? () => setState(() => _compact = false) : _slap,
                      child: CompanionView(engine: bot, size: bp.diameter),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _compactMinis(double w, List<Session> sessions) {
    final list = sessions.take(3).toList();
    const slots = [Offset(-52, 4), Offset(-30, 4), Offset(-41, 18)];
    return [
      for (var i = 0; i < list.length; i++)
        Positioned(
          left: w + slots[i].dx - 8,
          top: slots[i].dy - 3,
          child: MiniBot(color: list[i].color, state: list[i].state, size: 11, badge: list[i].badge),
        ),
    ];
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
          const Spacer(),
          if (running > 0) ...[
            Text('$running en cours', style: ui(12, color: Palette.dim2)),
            const SizedBox(width: 10),
          ],
          HeaderTab(
            icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: 14,
            onTap: () => link.run((c) => c.settings({'muted': !muted})),
          ),
          const SizedBox(width: 4),
          HeaderTab(icon: Icons.settings_rounded, on: view == PhoneView.settings, size: 14, onTap: () => go(view == PhoneView.settings ? PhoneView.overview : PhoneView.settings)),
          const SizedBox(width: 4),
          HeaderTab(icon: Icons.close_rounded, size: 14, onTap: () => setState(() => _compact = true)),
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
    }
  }
}

/// Les deux congés concaves qui raccordent l'île au bord haut de l'écran.
class _EarsPainter extends CustomPainter {
  const _EarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const r = 14.0;
    final paint = Paint()..color = Palette.islandTop;
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

/// Deux halos très doux — cyan à gauche, violet à droite — derrière les cartes.
class _AuroraGlow extends StatelessWidget {
  const _AuroraGlow();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: -80,
          top: -60,
          child: Container(
            width: 300,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Palette.accent.withValues(alpha: 0.13), Palette.accent.withValues(alpha: 0)]),
            ),
          ),
        ),
        Positioned(
          right: -90,
          bottom: -90,
          child: Container(
            width: 320,
            height: 240,
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
