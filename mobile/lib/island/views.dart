// Les vues de l'île du téléphone : les mêmes cartes que sur le PC (vue
// d'ensemble avec les étapes en direct, permission, question, vide, chat,
// journal, réglages), nourries par l'état que le PC envoie.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../models.dart';
import '../native.dart';
import '../prefs.dart';
import '../updater.dart';
import 'bridge.dart';
import 'qr_scan.dart';
import 'widgets.dart';

// En plein écran, Fractus est au-dessus des cartes : pas de marge à gauche.
const EdgeInsets _cardPad = EdgeInsets.fromLTRB(16, 14, 16, 14);
const EdgeInsets _listPad = EdgeInsets.fromLTRB(14, 10, 12, 10);

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _when(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return _hm(d);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${_hm(d)}';
}

// ─── Vue d'ensemble : la session en avant, ses étapes en direct, les autres ───

class PhoneOverview extends StatefulWidget {
  const PhoneOverview({super.key, required this.link});
  final PcLink link;

  @override
  State<PhoneOverview> createState() => _PhoneOverviewState();
}

class _PhoneOverviewState extends State<PhoneOverview> {
  String? _focus;

  @override
  Widget build(BuildContext context) {
    final sessions = sessionsOf(widget.link.status);
    if (sessions.isEmpty) return const SizedBox.shrink();
    final front = sessions.where((s) => s.id == _focus).firstOrNull ?? sessions.first;
    final others = sessions.where((s) => s.id != front.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: IslandCard(
            padding: _cardPad,
            child: _FocusCard(session: front),
          ),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              children: [
                for (final s in others.take(6))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SessionPill(session: s, width: 126, onTap: () => setState(() => _focus = s.id)),
                  ),
              ],
            ),
          ),
        ],
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
    final steps = session.steps;
    final message = session.lastMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TitleRow(color: session.color, project: session.project, subtitle: _subtitle),
        if (session.prompt != null && session.prompt!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(session.prompt!, maxLines: 3, overflow: TextOverflow.ellipsis, style: ui(13, color: Palette.dim, height: 1.3)),
        ],
        const SizedBox(height: 8),
        Text('CE QU\'IL FAIT', style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
        const SizedBox(height: 4),
        Expanded(
          child: steps.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(session.isActive ? 'Il démarre…' : 'En attente…', style: ui(13, color: Palette.dim3)),
                )
              // La liste est inversée : la dernière étape en bas, toujours visible.
              : ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.zero,
                  itemCount: steps.length,
                  itemBuilder: (_, i) {
                    final idx = steps.length - 1 - i;
                    return _StepRow(step: steps[idx], current: idx == steps.length - 1 && session.isActive);
                  },
                ),
        ),
        if (message != null && message.trim().isNotEmpty && !session.isActive) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(12)),
            child: Text(_firstLines(message), maxLines: 4, overflow: TextOverflow.ellipsis, style: ui(12.5, color: Palette.ink, height: 1.35)),
          ),
        ],
      ],
    );
  }

  static String _firstLines(String m) {
    final clean = m.replaceAll(RegExp(r'[#*`>_]'), '').trim();
    return clean.split('\n').where((l) => l.trim().isNotEmpty).take(4).join(' ');
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
              maxLines: current ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: ui(size, weight: current ? FontWeight.w500 : FontWeight.w400, color: color),
            ),
          ),
          if (current)
            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Palette.accent)),
        ],
      ),
    );
  }
}

// ─── Vide : rien ne tourne sur le PC ─────────────────────────────────────────

class PhoneEmpty extends StatelessWidget {
  const PhoneEmpty({super.key, required this.link, required this.onChat});
  final PcLink link;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final online = link.online;
    final host = link.info?.host ?? '';
    return IslandCard(
      wash: online ? Wash.soft : Wash.red,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(online ? 'Je suis Fractus. Qu\'est-ce qu\'on fait ?' : 'Je dors : le PC ne répond pas.', style: ui(15, weight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            online
                ? 'Rien ne tourne sur ${link.status?.host ?? 'le PC'} pour l\'instant. Demande-moi quelque chose, je le ferai là-bas.'
                : (link.error ?? 'Vérifie que Fractus est ouvert sur le PC et que le téléphone est sur le même réseau ($host).'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: ui(12.5, color: Palette.dim, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (online)
                IslandButton(label: 'Demander à Fractus', primary: true, onTap: onChat)
              else
                IslandButton(label: 'Réessayer', primary: true, onTap: link.restart),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Permission ──────────────────────────────────────────────────────────────

class PhoneApproval extends StatelessWidget {
  const PhoneApproval({super.key, required this.link});
  final PcLink link;

  String _title(PcPending a, String agent) {
    switch (a.tool) {
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
      case 'Fractus':
        return '$agent veut agir sur ton PC';
      default:
        return '$agent veut utiliser ${a.tool}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = link.status?.pending;
    if (a == null) return const SizedBox.shrink();
    final s = link.status!.sessions.where((x) => x.project == a.project).firstOrNull;
    final agent = s?.agent ?? (a.project == 'Fractus' ? 'Fractus' : 'Claude Code');
    final color = colorForProject(a.project);
    void decide(String d) => link.run((c) => c.decide(a.requestId, d));
    return IslandCard(
      wash: Wash.amber,
      padding: _cardPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitleRow(color: color, project: a.project, subtitle: _title(a, agent)),
          const SizedBox(height: 10),
          CodeChip(a.summary.isEmpty ? a.tool : a.summary),
          const SizedBox(height: 10),
          Expanded(
            child: a.preview == null || a.preview!.trim().isEmpty
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Palette.cardFlat, borderRadius: BorderRadius.circular(12), border: Border.all(color: Palette.hairline)),
                    child: SingleChildScrollView(child: Text(a.preview!, style: mono(11.5, color: Palette.dim))),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: IslandButton(label: 'Refuser', onTap: () => decide('deny'))),
              const SizedBox(width: 8),
              Expanded(child: IslandButton(label: 'Autoriser', primary: true, onTap: () => decide('allow'))),
              const SizedBox(width: 8),
              Expanded(child: IslandButton(label: 'Toujours', onTap: () => decide('always'))),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Question ────────────────────────────────────────────────────────────────

class PhoneQuestion extends StatefulWidget {
  const PhoneQuestion({super.key, required this.link});
  final PcLink link;

  @override
  State<PhoneQuestion> createState() => _PhoneQuestionState();
}

class _PhoneQuestionState extends State<PhoneQuestion> {
  int _index = 0;
  final Map<String, String> _answers = {};
  final Set<String> _multi = {};
  String? _requestId;

  @override
  Widget build(BuildContext context) {
    final a = widget.link.status?.pending;
    if (a == null || !a.isQuestion || a.questions.isEmpty) return const SizedBox.shrink();
    if (_requestId != a.requestId) {
      _requestId = a.requestId;
      _index = 0;
      _answers.clear();
      _multi.clear();
    }
    final qs = a.questions;
    final q = qs[_index.clamp(0, qs.length - 1)];
    final s = widget.link.status!.sessions.where((x) => x.project == a.project).firstOrNull;

    void pick(String label) {
      if (q.multi) {
        setState(() {
          if (!_multi.remove(label)) _multi.add(label);
        });
        return;
      }
      _answers[q.question] = label;
      _next(a);
    }

    return IslandCard(
      wash: Wash.cyan,
      padding: _cardPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TitleRow(
                  color: colorForProject(a.project),
                  project: a.project,
                  subtitle: '${s?.agent ?? 'Claude Code'} te pose une question',
                ),
              ),
              if (qs.length > 1) Text('${_index + 1}/${qs.length}', style: ui(11, color: Palette.dim3)),
            ],
          ),
          const SizedBox(height: 4),
          Text(q.question, maxLines: 6, overflow: TextOverflow.ellipsis, style: ui(15.5, weight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 12),
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
                  if (q.multi)
                    IslandButton(
                      label: 'Envoyer',
                      primary: true,
                      onTap: () {
                        _answers[q.question] = _multi.join(', ');
                        _multi.clear();
                        _next(a);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _next(PcPending a) {
    if (_index + 1 < a.questions.length) {
      setState(() => _index++);
    } else {
      widget.link.run((c) => c.answer(a.requestId, Map.of(_answers)));
    }
  }
}

// ─── Chat : la conversation du PC, dans l'île ────────────────────────────────

class PhoneChat extends StatefulWidget {
  const PhoneChat({super.key, required this.link});
  final PcLink link;

  @override
  State<PhoneChat> createState() => _PhoneChatState();
}

class _PhoneChatState extends State<PhoneChat> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  int _seen = -1;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    final busy = widget.link.status?.chatBusy ?? false;
    if (t.isEmpty || busy) return;
    _text.clear();
    await widget.link.run((c) => c.sendChat(t));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.link.status;
    final msgs = st?.messages ?? const <PcMessage>[];
    final busy = st?.chatBusy ?? false;
    final sig = msgs.length * 1000 + (msgs.lastOrNull?.text.length ?? 0);
    if (sig != _seen) {
      _seen = sig;
      _scrollDown();
    }
    final quick = st?.quickActions ?? const <String, String>{};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          _TopBar(link: widget.link),
          Expanded(
            child: msgs.isEmpty
                ? Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 6),
                      child: Text(
                        st == null
                            ? 'Connecte-toi au PC pour discuter.'
                            : (st.settings?.configured ?? true)
                                ? 'Demande-moi n\'importe quoi : je pilote ton PC, je code, et je retiens ce que tu me dis de retenir.'
                                : 'Ajoute ta clé Groq dans les réglages du PC pour discuter.',
                        style: ui(12, color: Palette.dim3),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => _Bubble(msgs[i]),
                  ),
          ),
          if (quick.isNotEmpty && msgs.isEmpty)
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final e in quick.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 4),
                      child: IslandButton(label: e.value, compact: true, onTap: () => widget.link.run((c) => c.action(e.key))),
                    ),
                ],
              ),
            ),
          _Field(controller: _text, focus: _focus, busy: busy, onSend: _send),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.link});
  final PcLink link;

  @override
  Widget build(BuildContext context) {
    final st = link.status;
    final title = st?.conversationTitle ?? '';
    final history = (st?.conversations ?? const <PcConversationMeta>[]).where((m) => m.id != st?.conversationId).take(12).toList();
    final busy = st?.chatBusy ?? false;
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Expanded(
            child: Text(title.isEmpty ? 'Nouvelle conversation' : title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(11, color: Palette.dim3)),
          ),
          PopupMenuButton<String>(
            tooltip: 'Conversations précédentes',
            color: Palette.card,
            padding: EdgeInsets.zero,
            enabled: !busy && st != null,
            onSelected: (id) {
              if (id.startsWith('del:')) {
                link.run((c) => c.deleteConversation(id.substring(4)));
              } else {
                link.run((c) => c.openConversation(id));
              }
            },
            itemBuilder: (_) => [
              if (history.isEmpty)
                PopupMenuItem(enabled: false, height: 30, child: Text('Aucune autre conversation', style: ui(12, color: Palette.dim3))),
              for (final m in history)
                PopupMenuItem(
                  value: m.id,
                  height: 32,
                  child: Row(
                    children: [
                      SizedBox(width: 44, child: Text(_when(m.updated), style: ui(10.5, color: Palette.dim4))),
                      Expanded(child: Text(m.title.isEmpty ? '(sans titre)' : m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12))),
                    ],
                  ),
                ),
              if (st != null && st.messages.isNotEmpty) ...[
                const PopupMenuDivider(height: 6),
                PopupMenuItem(
                  value: 'del:${st.conversationId}',
                  height: 30,
                  child: Text('Supprimer cette conversation', style: ui(12, color: Palette.redText)),
                ),
              ],
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.history_rounded, size: 15, color: Palette.dim),
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: busy ? null : () => link.run((c) => c.newChat()),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.add_comment_outlined, size: 15, color: Palette.dim),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final PcMessage m;

  @override
  Widget build(BuildContext context) {
    final user = m.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: user ? Palette.tabOn : Palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.hairline),
        ),
        child: SelectableText(m.text, style: ui(12.5, height: 1.35)),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.focus, required this.busy, required this.onSend});
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              style: ui(13),
              cursorColor: Palette.ink,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Écris à Fractus…',
                hintStyle: ui(13, color: Palette.dim3),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(gradient: LinearGradient(colors: Palette.aurora), shape: BoxShape.circle),
              child: busy
                  ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded, size: 17, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Journal d'activité ──────────────────────────────────────────────────────

class PhoneJournal extends StatefulWidget {
  const PhoneJournal({super.key, required this.link});
  final PcLink link;

  @override
  State<PhoneJournal> createState() => _PhoneJournalState();
}

class _PhoneJournalState extends State<PhoneJournal> {
  String? _message;
  bool _confirmClear = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.link.status?.journal ?? const <PcJournalEntry>[];
    return IslandCard(
      padding: _listPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('JOURNAL D\'ACTIVITÉ', style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
              const SizedBox(width: 8),
              if (items.isNotEmpty) Text('${items.length}', style: ui(10, color: Palette.dim4)),
              const Spacer(),
              if (_message != null)
                Padding(padding: const EdgeInsets.only(right: 8), child: Text(_message!, style: ui(11, color: Palette.dim))),
              if (items.isNotEmpty)
                IslandButton(
                  label: _confirmClear ? 'Confirmer' : 'Vider',
                  compact: true,
                  onTap: () async {
                    if (!_confirmClear) {
                      setState(() => _confirmClear = true);
                      return;
                    }
                    final err = await widget.link.run((c) => c.clearJournal());
                    if (mounted) {
                      setState(() {
                        _confirmClear = false;
                        _message = err ?? 'Journal et copies effacés';
                      });
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Rien pour l\'instant. Les fichiers que Fractus écrit ou modifie, les commandes qu\'il lance et ses actions '
                      'sur le PC apparaîtront ici — avec une copie d\'avant et un bouton Annuler pour les fichiers.',
                      style: ui(12, color: Palette.dim3, height: 1.35),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (_, i) => _JournalRow(
                      entry: items[i],
                      onUndo: () async {
                        final err = await widget.link.run((c) => c.undo(items[i].id));
                        if (mounted) setState(() => _message = err ?? 'Restauré');
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _JournalRow extends StatelessWidget {
  const _JournalRow({required this.entry, required this.onUndo});
  final PcJournalEntry entry;
  final VoidCallback onUndo;

  IconData get _icon => switch (entry.kind) {
        'write' => Icons.note_add_rounded,
        'edit' => Icons.edit_rounded,
        'command' => Icons.terminal_rounded,
        'action' => Icons.mouse_rounded,
        'memory' => Icons.psychology_rounded,
        _ => Icons.undo_rounded,
      };

  Color get _color => switch (entry.kind) {
        'write' => Palette.green2,
        'edit' => Palette.accent,
        'command' => Palette.amber,
        'action' => Palette.accent3,
        'memory' => Palette.pink,
        _ => Palette.dim,
      };

  @override
  Widget build(BuildContext context) {
    final dimmed = entry.undone;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 38, child: Text(_hm(entry.at), style: ui(10.5, color: Palette.dim4))),
          Icon(_icon, size: 13, color: dimmed ? Palette.dim4 : _color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, color: dimmed ? Palette.dim3 : Palette.ink, height: 1.2)),
          ),
          const SizedBox(width: 8),
          if (entry.canUndo)
            IslandButton(label: 'Annuler', compact: true, onTap: onUndo)
          else if (entry.undone)
            Text('annulé', style: ui(10.5, color: Palette.dim4)),
        ],
      ),
    );
  }
}

// ─── Réglages : la connexion au PC, puis les réglages du PC lui-même ─────────

class PhoneSettings extends StatefulWidget {
  const PhoneSettings({super.key, required this.link, required this.onConnected});
  final PcLink link;
  final VoidCallback onConnected;

  @override
  State<PhoneSettings> createState() => _PhoneSettingsState();
}

class _PhoneSettingsState extends State<PhoneSettings> {
  late final TextEditingController _address = TextEditingController(
    text: widget.link.info == null ? '' : '${widget.link.info!.host}:${widget.link.info!.port}',
  );
  late final TextEditingController _code = TextEditingController(text: widget.link.info?.token ?? '');
  late final TextEditingController _workspace = TextEditingController(text: widget.link.status?.settings?.workspace ?? '');
  String? _message;
  bool _testing = false;
  bool _notify = false;

  @override
  void initState() {
    super.initState();
    Prefs.notifyEnabled().then((v) {
      if (mounted) setState(() => _notify = v);
    });
    updater.addListener(_onUpdater);
  }

  @override
  void dispose() {
    updater.removeListener(_onUpdater);
    _address.dispose();
    _code.dispose();
    _workspace.dispose();
    super.dispose();
  }

  void _onUpdater() {
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    final link = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (link == null || !mounted) return;
    final info = PcConnectionInfo.fromPairLink(link);
    if (info == null) {
      setState(() => _message = 'QR code illisible');
      return;
    }
    _address.text = '${info.host}:${info.port}';
    _code.text = info.token;
    await _connect();
  }

  Future<void> _setNotify(bool v) async {
    setState(() => _notify = v);
    await Prefs.setNotifyEnabled(v);
    if (v) {
      await Native.requestNotifications();
      await Native.startService();
    } else {
      await Native.stopService();
    }
  }

  Future<void> _connect() async {
    final address = _address.text.trim();
    final code = _code.text.trim();
    if (address.isEmpty || code.isEmpty) {
      setState(() => _message = 'Adresse et code obligatoires');
      return;
    }
    setState(() {
      _testing = true;
      _message = null;
    });
    PcConnectionInfo info;
    try {
      info = PcConnectionInfo.parse(address, code);
    } catch (_) {
      setState(() {
        _testing = false;
        _message = 'Adresse invalide (ex. 192.168.1.20:7790)';
      });
      return;
    }
    String? err;
    try {
      await PcClient(info).status();
    } catch (e) {
      err = e is PcError ? e.message : 'PC injoignable à ${info.host}:${info.port}';
    }
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _testing = false;
        _message = err;
      });
      return;
    }
    await widget.link.setInfo(info);
    if (_notify) await Native.startService();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _message = 'Connecté';
    });
    widget.onConnected();
  }

  Future<void> _patch(Map<String, Object?> p) async {
    final err = await widget.link.run((c) => c.settings(p));
    if (mounted) setState(() => _message = err ?? 'Enregistré sur le PC');
  }

  Future<void> _editMemory() async {
    final c = widget.link.client;
    if (c == null) return;
    String text;
    try {
      text = await c.memory();
    } catch (e) {
      if (mounted) setState(() => _message = 'Mémoire illisible');
      return;
    }
    if (!mounted) return;
    final ctl = TextEditingController(text: text);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.islandTop,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: MediaQuery.of(ctx).viewInsets.bottom + 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MÉMOIRE DE FRACTUS (memoire.md)', style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
            const SizedBox(height: 8),
            Container(
              height: 280,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Palette.hairline)),
              child: TextField(
                controller: ctl,
                maxLines: null,
                expands: true,
                style: mono(12),
                cursorColor: Palette.ink,
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IslandButton(label: 'Enregistrer', primary: true, onTap: () => Navigator.pop(ctx, true)),
                const SizedBox(width: 8),
                IslandButton(label: 'Annuler', onTap: () => Navigator.pop(ctx, false)),
              ],
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final err = await widget.link.run((x) => x.saveMemory(ctl.text));
      if (mounted) setState(() => _message = err ?? 'Mémoire enregistrée');
    }
    ctl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.link.status?.settings;
    final online = widget.link.online && st != null;
    if (st != null && _workspace.text.isEmpty && st.workspace.isNotEmpty) _workspace.text = st.workspace;
    return IslandCard(
      padding: _listPad,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Row(
            children: [
              _section('Connexion au PC'),
              const Spacer(),
              if (_message != null) Text(_message!, style: ui(11, color: Palette.dim)),
            ],
          ),
          Text(
            'Sur le PC : Réglages → Téléphone. Recopie l\'adresse et le code affichés.',
            style: ui(11.5, color: Palette.dim3, height: 1.3),
          ),
          const SizedBox(height: 6),
          _field(_address, hint: 'Adresse du PC (ex. 192.168.1.20:7790)'),
          const SizedBox(height: 6),
          _field(_code, hint: 'Code d\'appairage'),
          const SizedBox(height: 8),
          Row(
            children: [
              IslandButton(label: _testing ? 'Connexion…' : 'Se connecter', primary: true, onTap: _testing ? () {} : _connect),
              const SizedBox(width: 8),
              IslandButton(label: 'Scanner le QR code', onTap: _scan),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.link.online ? '● ${widget.link.status?.host ?? ''} · Fractus ${widget.link.status?.version ?? ''}' : '○ hors ligne',
            style: ui(11, color: widget.link.online ? Palette.green2 : Palette.dim3),
          ),
          _section('Notifications'),
          _toggle('Prévenir quand Fractus attend ton accord, même appli fermée', _notify, _setNotify),
          Text(
            _notify
                ? 'Une notification discrète reste affichée (c\'est elle qui garde la connexion au PC). Les demandes arrivent avec Autoriser / Refuser / Toujours.'
                : 'Un petit service garde la connexion au PC ouverte ; les demandes arrivent en notification avec les boutons de réponse.',
            style: ui(11, color: Palette.dim3, height: 1.3),
          ),
          _section('Mise à jour de l\'appli'),
          _updateRow(),
          if (online) ...[
            _section('Chat (Groq) — sur le PC'),
            Row(
              children: [
                Expanded(child: Text('Modèle : ${st.model.isEmpty ? 'automatique' : st.model}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12.5))),
                _modelPicker(st),
              ],
            ),
            if (st.effectiveModel.isNotEmpty) Text('utilisé : ${st.effectiveModel}', style: ui(10.5, color: Palette.dim4)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _field(_workspace, hint: 'Dossier de travail sur le PC')),
                const SizedBox(width: 6),
                IslandButton(label: 'OK', compact: true, onTap: () => _patch({'workspace': _workspace.text.trim()})),
              ],
            ),
            _toggle('Recherche web', st.webSearch, (v) => _patch({'webSearch': v})),
            _toggle('Son coupé sur le PC', st.muted, (v) => _patch({'muted': v})),
            _section('Mémoire et historique'),
            Row(
              children: [
                Expanded(child: Text('memoire.md — ce que Fractus retient', style: ui(12.5))),
                IslandButton(label: 'Modifier', compact: true, onTap: _editMemory),
              ],
            ),
            _section('Toujours autorisé'),
            if (st.alwaysAllow.isEmpty)
              Text('Aucune règle. « Toujours » sur une permission en ajoute une.', style: ui(11.5, color: Palette.dim3))
            else ...[
              for (final k in st.alwaysAllow)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(11.5, color: Palette.dim))),
                      IslandButton(label: 'Oublier', compact: true, onTap: () => _patch({'forgetAlwaysKey': k})),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              IslandButton(label: 'Tout oublier', compact: true, onTap: () => _patch({'forgetAlways': true})),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _updateRow() {
    final u = updater;
    final String txt;
    switch (u.status) {
      case UpdateStatus.idle:
        txt = u.currentVersion.isEmpty ? 'Fractus téléphone' : 'Fractus téléphone ${u.currentVersion}';
      case UpdateStatus.checking:
        txt = 'Recherche…';
      case UpdateStatus.upToDate:
        txt = 'Fractus téléphone ${u.currentVersion} — à jour';
      case UpdateStatus.available:
        txt = 'Version ${u.latestVersion} disponible (tu as la ${u.currentVersion})';
      case UpdateStatus.downloading:
        txt = 'Téléchargement… ${(u.progress * 100).round()} %';
      case UpdateStatus.ready:
        txt = 'Téléchargée : Android te propose de l\'installer';
      case UpdateStatus.error:
        txt = u.error ?? 'Erreur';
    }
    final busy = u.status == UpdateStatus.checking || u.status == UpdateStatus.downloading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(txt, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(12.5, color: u.status == UpdateStatus.error ? Palette.redText : Palette.ink))),
            const SizedBox(width: 8),
            if (u.status == UpdateStatus.available)
              IslandButton(label: 'Télécharger', primary: true, compact: true, onTap: u.download)
            else if (u.status == UpdateStatus.ready)
              IslandButton(label: 'Installer', primary: true, compact: true, onTap: u.install)
            else
              IslandButton(label: busy ? '…' : 'Vérifier', compact: true, onTap: busy ? () {} : u.check),
          ],
        ),
        if (u.status == UpdateStatus.downloading)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: u.progress, minHeight: 4, backgroundColor: Palette.tabOn, color: Palette.accent),
            ),
          ),
        const SizedBox(height: 2),
        Text('Depuis les Releases GitHub du projet. L\'APK est signé avec la clé de Fractus : la mise à jour s\'installe par-dessus, sans rien perdre.',
            style: ui(11, color: Palette.dim3, height: 1.3)),
      ],
    );
  }

  Widget _modelPicker(PcSettings st) {
    return PopupMenuButton<String>(
      tooltip: 'Choisir un modèle',
      color: Palette.card,
      padding: EdgeInsets.zero,
      onSelected: (id) {
        if (id == '\u0000list') {
          _patch({'listModels': true});
        } else {
          _patch({'model': id});
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: '', height: 30, child: Text('Automatique (le plus puissant)', style: ui(12))),
        for (final m in st.models) PopupMenuItem(value: m, height: 30, child: Text(m, style: ui(12))),
        if (st.models.isEmpty) PopupMenuItem(value: '\u0000list', height: 30, child: Text('Charger la liste des modèles…', style: ui(12, color: Palette.dim))),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(7)),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(st.models.isEmpty ? 'Modèles' : '${st.models.length} modèles', style: ui(11.5, color: Palette.dim)),
            const Icon(Icons.expand_more_rounded, size: 14, color: Palette.dim),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 3),
        child: Text(t.toUpperCase(), style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: ui(12.5))),
          SizedBox(
            height: 20,
            child: FittedBox(child: Switch(value: value, onChanged: onChanged)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, {required String hint}) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(7)),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: c,
        style: ui(12),
        cursorColor: Palette.ink,
        decoration: InputDecoration(isDense: true, isCollapsed: true, border: InputBorder.none, hintText: hint, hintStyle: ui(12, color: Palette.dim3)),
      ),
    );
  }
}

// ─── L'écran du PC, dans l'île ───────────────────────────────────────────────

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.link});
  final PcLink link;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  Timer? _timer;
  String? _url;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _refresh();
  }

  void _refresh() {
    final c = widget.link.client;
    if (!mounted || !widget.link.online || c == null) return;
    setState(() => _url = c.screenUrl(width: 1100));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    final online = widget.link.online && url != null;
    return IslandCard(
      padding: _listPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ÉCRAN DU PC', style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
              const SizedBox(width: 8),
              Text(online ? 'toutes les 2 s · pince pour zoomer' : 'hors ligne', style: ui(10, color: Palette.dim4)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Palette.cardFlat,
                alignment: Alignment.center,
                child: online
                    ? InteractiveViewer(
                        maxScale: 5,
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Text('Capture indisponible', style: ui(12, color: Palette.dim3)),
                        ),
                      )
                    : Text('Connecte-toi au PC pour voir son écran.', style: ui(12, color: Palette.dim3)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
