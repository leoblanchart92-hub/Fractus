// L'accueil : le PC, la demande en attente (Autoriser / Refuser / Toujours),
// l'état de Fractus et des autres agents, les actions rapides.

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.link, required this.onOpenSettings});
  final PcLink link;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final s = link.status;
    return RefreshIndicator(
      color: P.accent,
      onRefresh: () async => link.restart(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _Header(link: link, onOpenSettings: onOpenSettings),
          if (s != null && s.pending != null) ...[
            const SectionTitle('Demande en attente'),
            _PendingCard(link: link, pending: s.pending!, queue: s.queue),
          ],
          const SectionTitle('Fractus'),
          _FractusCard(link: link),
          if (s?.fractus != null && s!.fractus!.steps.isNotEmpty) ...[
            const SectionTitle('En direct — ce qu\'il fait'),
            _ActivityCard(session: s.fractus!, busy: s.chatBusy),
          ],
          if (s != null && s.sessions.where((x) => x.id != 'fractus').isNotEmpty) ...[
            const SectionTitle('Autres agents'),
            for (final x in s.sessions.where((x) => x.id != 'fractus')) _SessionTile(session: x),
          ],
          const SectionTitle('Actions rapides'),
          _QuickActions(link: link),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.link, required this.onOpenSettings});
  final PcLink link;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final s = link.status;
    final online = link.online && s != null;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: P.aurora, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.diamond_rounded, color: Color(0xFF07101C)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fractus', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: online ? P.green : P.red, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      !link.configured
                          ? 'Pas encore connecté au PC'
                          : online
                              ? '${s!.host} · en ligne · v${s!.version}'
                              : (link.error ?? 'Connexion…'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: P.dim, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!link.configured) TextButton(onPressed: onOpenSettings, child: const Text('Configurer')),
      ],
    );
  }
}

class _PendingCard extends StatefulWidget {
  const _PendingCard({required this.link, required this.pending, required this.queue});
  final PcLink link;
  final PcPending pending;
  final int queue;

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard> {
  final Map<String, Set<String>> _picked = {};
  bool _busy = false;

  Future<void> _do(Future<void> Function(PcClient c) f) async {
    setState(() => _busy = true);
    final err = await widget.link.run(f);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [P.amber.withValues(alpha: 0.16), P.card],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.front_hand_rounded, color: P.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${p.project} · ${p.isQuestion ? 'Question' : p.label}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.queue > 0) Text('+${widget.queue} en file', style: const TextStyle(color: P.dim, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            if (!p.isQuestion) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF0C0F1A), borderRadius: BorderRadius.circular(12)),
                child: SelectableText(p.summary, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
              if (p.preview != null && p.preview!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF0C0F1A), borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    child: Text(p.preview!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: P.dim)),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AuroraButton(
                      label: 'Refuser',
                      danger: true,
                      onTap: _busy ? null : () => _do((c) => c.decide(p.requestId, 'deny')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AuroraButton(
                      label: 'Autoriser',
                      onTap: _busy ? null : () => _do((c) => c.decide(p.requestId, 'allow')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => _do((c) => c.decide(p.requestId, 'always')),
                  child: const Text('Toujours autoriser ce type d\'action', style: TextStyle(color: P.dim)),
                ),
              ),
            ] else ...[
              for (final q in p.questions) ...[
                if (q.header != null) Text(q.header!, style: const TextStyle(color: P.dim3, fontSize: 12)),
                Text(q.question, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in q.options)
                      FilterChip(
                        label: Text(o),
                        selected: _picked[q.question]?.contains(o) ?? false,
                        selectedColor: P.accent.withValues(alpha: 0.25),
                        onSelected: (v) => setState(() {
                          final set = _picked.putIfAbsent(q.question, () => {});
                          if (!q.multi) set.clear();
                          v ? set.add(o) : set.remove(o);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              AuroraButton(
                label: 'Répondre',
                icon: Icons.send_rounded,
                onTap: _busy || _picked.values.every((s) => s.isEmpty)
                    ? null
                    : () => _do((c) => c.answer(p.requestId, {for (final e in _picked.entries) if (e.value.isNotEmpty) e.key: e.value.join(', ')})),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FractusCard extends StatelessWidget {
  const _FractusCard({required this.link});
  final PcLink link;

  @override
  Widget build(BuildContext context) {
    final s = link.status;
    final f = s?.fractus;
    final state = s?.botState ?? 'idle';
    final color = Color(stateColor(state));
    final online = link.online && s != null;
    final busy = s?.chatBusy == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                boxShadow: [if (online) BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 18)],
              ),
              child: Icon(online ? Icons.auto_awesome_rounded : Icons.power_settings_new_rounded, color: online ? color : P.dim3),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    !online ? 'Fractus ne répond pas' : 'Fractus ${stateLabel(state)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    !online
                        ? 'Vérifie que Fractus tourne sur le PC et que le téléphone est sur le même Wi-Fi.'
                        : (busy && f?.lastStep != null
                            ? f!.lastStep!
                            : (f?.lastMessage ?? 'Aucune tâche en cours. Dis-lui quelque chose dans Chat.')),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: P.dim, fontSize: 12.5, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le fil des outils de Fractus (lecture, écriture, commande…), le plus récent en bas.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.session, required this.busy});
  final PcSession session;
  final bool busy;

  static IconData _icon(String kind) => switch (kind) {
        'read' => Icons.description_outlined,
        'edit' => Icons.edit_rounded,
        'run' => Icons.terminal_rounded,
        'search' => Icons.search_rounded,
        'prompt' => Icons.person_rounded,
        _ => Icons.circle_outlined,
      };

  static Color _color(String kind) => switch (kind) {
        'read' => P.accent,
        'edit' => P.green,
        'run' => P.amber,
        'search' => P.accent3,
        'prompt' => P.dim,
        _ => P.dim3,
      };

  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final steps = session.steps.reversed.take(14).toList().reversed.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 56, child: Text(_hm(steps[i].at), style: const TextStyle(color: P.dim3, fontSize: 11))),
                    Icon(_icon(steps[i].kind), size: 15, color: _color(steps[i].kind)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        steps[i].text,
                        maxLines: steps[i].kind == 'prompt' ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: steps[i].kind == 'prompt' ? P.ink : P.dim,
                          fontWeight: steps[i].kind == 'prompt' ? FontWeight.w600 : FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (busy && i == steps.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 6, top: 2),
                        child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: P.accent)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final PcSession session;

  @override
  Widget build(BuildContext context) {
    final color = Color(stateColor(session.state));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          title: Text('${session.project} · ${session.agent}'),
          subtitle: Text(
            session.lastStep ?? stateLabel(session.state),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: P.dim, fontSize: 12),
          ),
          trailing: Text(stateLabel(session.state), style: TextStyle(color: color, fontSize: 11.5)),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.link});
  final PcLink link;

  static const _icons = {
    'lock': Icons.lock_rounded,
    'sleep': Icons.bedtime_rounded,
    'mute': Icons.volume_off_rounded,
    'volume_down': Icons.volume_down_rounded,
    'volume_up': Icons.volume_up_rounded,
    'play_pause': Icons.play_arrow_rounded,
    'prev': Icons.skip_previous_rounded,
    'next': Icons.skip_next_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final labels = link.status?.quickActions ?? const {
      'lock': 'Verrouiller le PC',
      'sleep': 'Mettre en veille',
      'mute': 'Couper / rétablir le son',
      'volume_down': 'Volume −',
      'volume_up': 'Volume +',
      'play_pause': 'Lecture / pause',
      'prev': 'Piste précédente',
      'next': 'Piste suivante',
    };
    final order = ['lock', 'sleep', 'mute', 'volume_down', 'volume_up', 'play_pause', 'prev', 'next'];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        for (final a in order.where(labels.containsKey))
          Material(
            color: P.card,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final err = await link.run((c) => c.action(a));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? labels[a]!), duration: const Duration(seconds: 1)));
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_icons[a] ?? Icons.bolt_rounded, color: P.accent, size: 26),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      labels[a]!.replaceFirst(' le PC', '').replaceFirst('Couper / rétablir le son', 'Son'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 11, color: P.dim),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
