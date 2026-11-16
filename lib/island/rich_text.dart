// Le rendu des réponses de Fractus (PC et téléphone) : le Markdown de poche de
// core/markdown.dart posé en widgets — titres, listes, citations, blocs de code
// avec « Copier », gras / italique / code en ligne.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/markdown.dart';
import '../core/theme.dart';

class MarkdownBody extends StatelessWidget {
  const MarkdownBody(this.text, {super.key, this.size = 12.5, this.selectable = false, this.color = Palette.ink});
  final String text;
  final double size;

  /// Sur PC, le texte se sélectionne à la souris ; sur téléphone, l'appui long copie la bulle.
  final bool selectable;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!Markdown.looksRich(text)) return _text(TextSpan(text: text, style: ui(size, height: 1.35, color: color)));
    final blocks = Markdown.parse(text);
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(SizedBox(height: b.kind == MdBlockKind.heading ? 8 : 5));
      children.add(_block(b));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _text(TextSpan span) => selectable ? SelectableText.rich(span) : Text.rich(span);

  TextSpan _inline(List<MdSpan> spans, {double? sz, FontWeight? weight, Color? col}) {
    final base = sz ?? size;
    return TextSpan(
      children: [
        for (final s in spans)
          if (s.code)
            TextSpan(
              text: '\u2009${s.text}\u2009',
              style: mono(base - 0.5, color: Palette.cyan).copyWith(backgroundColor: Palette.cardFlat, height: 1.35),
            )
          else
            TextSpan(
              text: s.link != null && !s.text.contains('://') && s.link != s.text ? '${s.text} (${s.link})' : s.text,
              style: ui(
                base,
                weight: weight ?? (s.bold ? FontWeight.w600 : FontWeight.w400),
                color: s.link != null ? Palette.accent : (col ?? color),
                height: 1.35,
              ).copyWith(fontStyle: s.italic ? FontStyle.italic : null, decoration: s.link != null ? TextDecoration.underline : null),
            ),
      ],
    );
  }

  Widget _block(MdBlock b) {
    switch (b.kind) {
      case MdBlockKind.paragraph:
        return _text(_inline(b.spans));
      case MdBlockKind.heading:
        final sz = b.level <= 1 ? size + 3 : (b.level == 2 ? size + 1.5 : size + 0.5);
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _text(_inline(b.spans, sz: sz, weight: FontWeight.w700)),
        );
      case MdBlockKind.bullets:
      case MdBlockKind.numbers:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < b.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: b.kind == MdBlockKind.numbers ? 20 : 14,
                      child: Text(
                        b.kind == MdBlockKind.numbers ? '${i + 1}.' : '•',
                        style: ui(size, color: Palette.accent2, weight: FontWeight.w600, height: 1.35),
                      ),
                    ),
                    Expanded(child: _text(_inline(b.items[i]))),
                  ],
                ),
              ),
          ],
        );
      case MdBlockKind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: Palette.accent2, width: 2))),
          child: _text(_inline(b.spans, col: Palette.dim)),
        );
      case MdBlockKind.rule:
        return Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Palette.hairline);
      case MdBlockKind.code:
        return CodeBlock(code: b.code, lang: b.lang, size: size, selectable: selectable);
    }
  }
}

/// Un bloc de code : bandeau avec le langage et « Copier », texte en monospace,
/// défilement horizontal si les lignes sont longues.
class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.code, this.lang = '', this.size = 12.5, this.selectable = false});
  final String code;
  final String lang;
  final double size;
  final bool selectable;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.code.split('\n').length;
    final span = TextSpan(text: widget.code, style: mono(math.max(10.5, widget.size - 1), color: Palette.ink2).copyWith(height: 1.4));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Palette.cardFlat,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 24,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.hairline))),
            child: Row(
              children: [
                Text(
                  widget.lang.isEmpty ? (lines > 1 ? '$lines lignes' : 'code') : widget.lang,
                  style: ui(10, color: Palette.dim3, weight: FontWeight.w600),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _copy,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 12, color: _copied ? Palette.green2 : Palette.dim),
                          const SizedBox(width: 4),
                          Text(_copied ? 'Copié' : 'Copier', style: ui(10.5, color: _copied ? Palette.green2 : Palette.dim)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: widget.selectable ? SelectableText.rich(span) : Text.rich(span),
          ),
        ],
      ),
    );
  }
}

/// « Fractus écrit… » : trois points qui respirent.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.label});

  /// Une courte ligne à côté des points (l'outil en cours, par exemple).
  final String? label;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 6,
              height: 6,
              margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.accent.withValues(alpha: 0.35 + 0.65 * (0.5 + 0.5 * math.sin((_c.value * 2 * math.pi) - i * 1.1))),
              ),
            ),
          if (widget.label != null && widget.label!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(widget.label!, style: ui(11.5, color: Palette.dim).copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

/// L'heure courte d'un message : « 14:03 ».
String hourMinute(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
