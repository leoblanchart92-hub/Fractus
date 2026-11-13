// Les briques des vues : carte, pastille, mini Mochi, boutons, ligne de titre.

import 'package:flutter/material.dart';

import '../core/layout.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../mochi/bot_engine.dart';
import '../mochi/mochi_view.dart';

/// La carte sombre de l'île (#141518, rayon 20), avec sa teinte en bas.
class IslandCard extends StatelessWidget {
  const IslandCard({super.key, required this.child, this.wash = Wash.none, this.padding});
  final Widget child;
  final Wash wash;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Palette.card,
              borderRadius: BorderRadius.all(Radius.circular(20)),
              border: Border.fromBorderSide(BorderSide(color: Palette.hairline)),
            ),
          ),
          if (wash != Wash.none)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 1.4),
                      radius: 1.1,
                      colors: [washColor(wash), washColor(wash).withOpacity(0)],
                      stops: const [0, 1],
                    ),
                  ),
                ),
              ),
            ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );
  }
}

/// « ● Korus  Claude Code veut lancer une commande »
class TitleRow extends StatelessWidget {
  const TitleRow({super.key, required this.color, required this.project, required this.subtitle});
  final Color color;
  final String project;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: ui(13.5, weight: FontWeight.w700),
              children: [
                TextSpan(text: project),
                TextSpan(text: '  $subtitle', style: ui(13.5, color: Palette.dim)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Un bouton de carte : sombre, ou blanc pour l'action principale.
class IslandButton extends StatefulWidget {
  const IslandButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.keyHint,
    this.compact = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final String? keyHint;
  final bool compact;

  @override
  State<IslandButton> createState() => _IslandButtonState();
}

class _IslandButtonState extends State<IslandButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? (_hover ? Colors.white : const Color(0xFFF5F6F8))
        : (_hover ? const Color(0x24FFFFFF) : const Color(0x14FFFFFF));
    final fg = widget.primary ? const Color(0xFF0B0C0E) : Palette.ink;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.compact ? 24 : 28,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 14),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label, style: ui(widget.compact ? 12 : 13, weight: FontWeight.w600, color: fg)),
              if (widget.keyHint != null) ...[
                const SizedBox(width: 7),
                KeyHint(widget.keyHint!, dark: widget.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// La petite touche encadrée (N, Y, ⏎).
class KeyHint extends StatelessWidget {
  const KeyHint(this.label, {super.key, this.dark = false});
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = dark ? const Color(0xFF0B0C0E) : Palette.dim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.55), width: 1),
      ),
      child: Text(label, style: ui(10, weight: FontWeight.w700, color: c, height: 1)),
    );
  }
}

/// Le texte d'une commande / d'un fichier, en monospace sur fond #1D1F23.
class CodeChip extends StatelessWidget {
  const CodeChip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(8)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(12)),
    );
  }
}

/// Le mini Mochi d'une pastille : un aplat de couleur, les yeux, le badge.
class MiniBot extends StatefulWidget {
  const MiniBot({super.key, required this.color, required this.state, this.size = 20, this.badge = false});
  final Color color;
  final BotState state;
  final double size;
  final bool badge;

  @override
  State<MiniBot> createState() => _MiniBotState();
}

class _MiniBotState extends State<MiniBot> {
  late final BotEngine _engine = BotEngine(isMini: true, bodyColor: widget.color);

  @override
  void initState() {
    super.initState();
    _engine.setState(widget.state, force: true);
    _engine.setPermanentEmote(_emoteFor(widget.state));
  }

  BotEmote? _emoteFor(BotState s) {
    switch (s) {
      case BotState.finished:
        return BotEmote.happy;
      case BotState.error:
        return BotEmote.annoyed;
      default:
        return null;
    }
  }

  @override
  void didUpdateWidget(covariant MiniBot old) {
    super.didUpdateWidget(old);
    _engine.bodyColor = widget.color;
    if (old.state != widget.state) {
      _engine.setState(widget.state);
      _engine.setPermanentEmote(_emoteFor(widget.state));
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Le canvas dépasse un peu du corps : le mini mesure 1,2× sa « taille ».
    final s = widget.size * 1.25;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MochiView(engine: _engine, size: s, glow: false),
          if (widget.badge)
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Palette.amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Une pastille de session : mini Mochi + nom du projet, dans sa couleur.
class SessionPill extends StatefulWidget {
  const SessionPill({super.key, required this.session, required this.onTap, this.width});
  final Session session;
  final VoidCallback onTap;
  final double? width;

  @override
  State<SessionPill> createState() => _SessionPillState();
}

class _SessionPillState extends State<SessionPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.session.color;
    final label = Color.lerp(c, Colors.white, 0.35)!;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: widget.width,
          height: 30,
          padding: const EdgeInsets.only(left: 6, right: 12),
          decoration: BoxDecoration(
            color: c.withOpacity(_hover ? 0.22 : 0.13),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withOpacity(0.38)),
          ),
          child: Row(
            children: [
              MiniBot(color: c, state: widget.session.state, size: 20, badge: widget.session.badge),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.session.project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ui(12.5, weight: FontWeight.w600, color: label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une icône d'en-tête ronde (26 px), allumée quand l'onglet est actif.
class HeaderTab extends StatefulWidget {
  const HeaderTab({super.key, required this.icon, required this.onTap, this.on = false, this.tooltip, this.size = 15});
  final IconData icon;
  final VoidCallback onTap;
  final bool on;
  final String? tooltip;
  final double size;

  @override
  State<HeaderTab> createState() => _HeaderTabState();
}

class _HeaderTabState extends State<HeaderTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: widget.on ? Palette.tabOn : (_hover ? const Color(0x14FFFFFF) : Colors.transparent),
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, size: widget.size, color: widget.on || _hover ? Palette.ink : Palette.dim2),
        ),
      ),
    );
    if (widget.tooltip == null) return w;
    return Tooltip(
      message: widget.tooltip!,
      waitDuration: const Duration(milliseconds: 600),
      textStyle: ui(11, color: Palette.ink),
      decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(6)),
      child: w,
    );
  }
}

IconData stepIcon(StepKind k) {
  switch (k) {
    case StepKind.read:
      return Icons.crop_square_rounded;
    case StepKind.edit:
      return Icons.description_outlined;
    case StepKind.run:
      return Icons.terminal_rounded;
    case StepKind.search:
      return Icons.search_rounded;
    case StepKind.note:
      return Icons.circle;
    case StepKind.prompt:
      return Icons.chat_bubble_outline_rounded;
  }
}
