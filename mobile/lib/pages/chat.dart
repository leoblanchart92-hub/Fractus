// Le chat : la conversation en cours sur le PC, et le champ pour parler à Fractus.

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.link});
  final PcLink link;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = -1;
  int _lastLen = -1;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    final err = await widget.link.run((c) => c.sendChat(t));
    if (!mounted) return;
    if (err != null) {
      _text.text = t;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _autoScroll(List<PcMessage> msgs) {
    final len = msgs.isEmpty ? 0 : msgs.last.text.length;
    if (msgs.length != _lastCount || len != _lastLen) {
      _lastCount = msgs.length;
      _lastLen = len;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.link.status;
    final msgs = s?.messages ?? const <PcMessage>[];
    _autoScroll(msgs);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s == null || s.conversationTitle.isEmpty ? 'Nouvelle conversation' : s.conversationTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: P.dim, fontSize: 13),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Conversations précédentes',
                icon: const Icon(Icons.history_rounded, color: P.dim),
                color: P.card2,
                enabled: s != null && !s.chatBusy,
                onSelected: (id) async {
                  final err = id.startsWith('del:')
                      ? await widget.link.run((c) => c.deleteConversation(id.substring(4)))
                      : await widget.link.run((c) => c.openConversation(id));
                  if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                },
                itemBuilder: (_) {
                  final others = (s?.conversations ?? const <PcConversationMeta>[]).where((m) => m.id != s?.conversationId).toList();
                  return [
                    if (others.isEmpty)
                      const PopupMenuItem(enabled: false, child: Text('Aucune autre conversation', style: TextStyle(color: P.dim3))),
                    for (final m in others)
                      PopupMenuItem(
                        value: m.id,
                        child: Text(m.title.isEmpty ? '(sans titre)' : m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    if (s != null && s.messages.isNotEmpty) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'del:${s.conversationId}', child: const Text('Supprimer cette conversation', style: TextStyle(color: P.red))),
                    ],
                  ];
                },
              ),
              IconButton(
                tooltip: 'Nouvelle conversation',
                icon: const Icon(Icons.add_comment_outlined, color: P.dim),
                onPressed: s == null || s.chatBusy
                    ? null
                    : () async {
                        final err = await widget.link.run((c) => c.newChat());
                        if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.link.online
                          ? 'Parle à Fractus comme sur le PC : « ouvre Chrome », « combien de place sur C: », « retiens que… ». Les permissions arrivent dans l\'onglet Fractus.'
                          : 'Connecte-toi au PC pour discuter.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: P.dim3, height: 1.4),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) => _Bubble(msgs[i]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'Écris à Fractus…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: s?.chatBusy == true ? null : _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: P.aurora), shape: BoxShape.circle),
                    child: s?.chatBusy == true
                        ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
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

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final PcMessage m;

  @override
  Widget build(BuildContext context) {
    final user = m.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: user ? P.card2 : P.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: P.hairline),
        ),
        child: SelectableText(m.text, style: const TextStyle(fontSize: 14, height: 1.35)),
      ),
    );
  }
}
