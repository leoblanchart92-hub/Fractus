// La liste des nouveautés (PC et téléphone) : une carte par version, la plus
// récente en haut, « Nouveau » sur celles qu'on n'a pas encore vues.

import 'package:flutter/material.dart';

import '../core/changelog.dart';
import '../core/theme.dart';
import 'rich_text.dart';

class NewsList extends StatelessWidget {
  const NewsList({super.key, required this.notes, required this.current, required this.seen, this.controller, this.selectable = false, this.padding});
  final List<ReleaseNote> notes;

  /// La version installée (mise en avant).
  final String current;

  /// La dernière version déjà vue ('' = rien vu).
  final String seen;
  final ScrollController? controller;
  final bool selectable;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Center(child: Text('Pas de nouveautés à afficher.', style: ui(12, color: Palette.dim3)));
    }
    return ListView.builder(
      controller: controller,
      padding: padding ?? const EdgeInsets.only(bottom: 8),
      itemCount: notes.length,
      itemBuilder: (_, i) {
        final n = notes[i];
        final isNew = seen.isEmpty || Changelog.compare(n.version, seen) > 0;
        final isCurrent = Changelog.compare(n.version, current) == 0;
        final future = current.isNotEmpty && Changelog.compare(n.version, current) > 0;
        return Container(
          margin: EdgeInsets.only(top: i == 0 ? 0 : 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            color: isCurrent ? Palette.tabOn : Palette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isNew ? Palette.accent2.withValues(alpha: 0.45) : Palette.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(n.version, style: ui(13.5, weight: FontWeight.w700)),
                  if (n.date.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(n.date, style: ui(10.5, color: Palette.dim3)),
                  ],
                  const Spacer(),
                  if (future)
                    _tag('À venir', Palette.dim3)
                  else if (isCurrent)
                    _tag('Installée', Palette.green2)
                  else if (isNew)
                    _tag('Nouveau', Palette.accent),
                ],
              ),
              const SizedBox(height: 6),
              MarkdownBody(n.body, size: 12, selectable: selectable),
            ],
          ),
        );
      },
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: ui(9.5, weight: FontWeight.w700, color: c)),
      );
}
