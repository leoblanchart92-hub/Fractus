// Le chat dans l'île : la conversation, le champ, la flèche d'envoi.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
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

  String _context() {
    final b = StringBuffer();
    for (final s in widget.state.orderedSessions.take(4)) {
      b.writeln('- ${s.project} (${s.agent}) : ${s.state.name}'
          '${s.steps.isNotEmpty ? ' — ${s.steps.last.text}' : ''}');
    }
    return b.toString();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || widget.state.chatBusy) return;
    _text.clear();
    widget.state.addChat(ChatMessage('user', t));
    widget.state.chatBusy = true;
    widget.state.touch();
    _scrollDown();
    try {
      final reply = await widget.chat.send(widget.state.chat, context: _context());
      widget.state.addChat(ChatMessage('assistant', reply.isEmpty ? '…' : reply));
    } catch (e) {
      widget.state.addChat(ChatMessage('assistant', 'Impossible de joindre le modèle : $e'));
    } finally {
      widget.state.chatBusy = false;
      widget.state.touch();
      _scrollDown();
      _focus.requestFocus();
    }
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
          Expanded(
            child: msgs.isEmpty
                ? Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 6),
                      child: Text(
                        widget.chat.configured
                            ? 'Pose une question à ${widget.chat.provider.assistantName} : il voit tes sessions en cours.'
                            : 'Ajoute ta clé ${widget.chat.provider.label} dans les réglages pour discuter.',
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
          color: user ? const Color(0xFF2A2D32) : Palette.card,
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
                decoration: const BoxDecoration(color: Color(0xFFF5F6F8), shape: BoxShape.circle),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0B0C0E)),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 17, color: Color(0xFF0B0C0E)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
