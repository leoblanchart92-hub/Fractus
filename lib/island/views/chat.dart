// Le chat dans l'île : la conversation, le champ, la flèche d'envoi.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../services/chat_runner.dart';
import '../../services/chat_service.dart';
import '../controller.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.state, required this.controller, required this.chat});
  final AppState state;
  final IslandController controller;
  final ChatService chat;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // Le chat garde l'île ouverte tant que le champ a le focus.
      if (widget.state.pendingApproval == null) {
        widget.state.pinned = _focus.hasFocus;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    if (widget.state.pendingApproval == null) widget.state.pinned = false;
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || widget.state.chatBusy) return;
    _text.clear();
    await ChatRunner.send(widget.state, widget.chat, t, onUpdate: _scrollDown);
    _focus.requestFocus();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.state.chat;
    return Padding(
      padding: const EdgeInsets.only(left: 96, right: 12, bottom: 12),
      child: Column(
        children: [
          _TopBar(state: widget.state, onChanged: () {
            setState(() {});
            _scrollDown();
            _focus.requestFocus();
          }),
          Expanded(
            child: msgs.isEmpty
                ? Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 6),
                      child: Text(
                        widget.chat.configured
                            ? 'Demande-moi n\'importe quoi : je pilote ton PC, je code, et je retiens ce que tu me dis de retenir.'
                            : 'Ajoute ta clé Groq dans les réglages pour discuter.',
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
          _Field(
            controller: _text,
            focus: _focus,
            busy: widget.state.chatBusy,
            onSend: _send,
            onEscape: () {
              _focus.unfocus();
              widget.controller.close();
            },
          ),
        ],
      ),
    );
  }
}

/// Au-dessus du fil : le titre de la conversation, l'historique, « nouvelle ».
class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.onChanged});
  final AppState state;
  final VoidCallback onChanged;

  static String _when(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = state.conversation;
    final store = state.conversations;
    final history = (store?.index ?? const <ConversationMeta>[]).where((m) => m.id != c.id).take(12).toList();
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Expanded(
            child: Text(
              c.title.isEmpty ? 'Nouvelle conversation' : c.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ui(11, color: Palette.dim3),
            ),
          ),
          if (store != null)
            PopupMenuButton<String>(
              tooltip: 'Conversations précédentes',
              color: Palette.card,
              padding: EdgeInsets.zero,
              enabled: !state.chatBusy,
              onSelected: (id) async {
                if (id.startsWith('del:')) {
                  await state.deleteConversation(id.substring(4));
                } else {
                  await state.openConversation(id);
                }
                onChanged();
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
                        SizedBox(width: 40, child: Text(_when(m.updated), style: ui(10.5, color: Palette.dim4))),
                        Expanded(
                          child: Text(m.title.isEmpty ? '(sans titre)' : m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12)),
                        ),
                      ],
                    ),
                  ),
                if (!c.isEmpty) ...[
                  const PopupMenuDivider(height: 6),
                  PopupMenuItem(
                    value: 'del:${c.id}',
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
          Tooltip(
            message: 'Nouvelle conversation',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: state.chatBusy
                    ? null
                    : () async {
                        await state.newConversation();
                        onChanged();
                      },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.add_comment_outlined, size: 15, color: Palette.dim),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final ChatMessage m;

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
  const _Field({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.onSend,
    required this.onEscape,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onEscape;

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
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): onEscape,
              },
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
          ),
          const SizedBox(width: 6),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onSend,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: Palette.aurora), shape: BoxShape.circle),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 17, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
