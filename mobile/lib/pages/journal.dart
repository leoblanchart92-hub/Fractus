// Le journal d'activité du PC : tout ce que Fractus a fait, et Annuler.

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';

class JournalPage extends StatelessWidget {
  const JournalPage({super.key, required this.link});
  final PcLink link;

  static IconData _icon(String kind) => switch (kind) {
        'write' => Icons.note_add_rounded,
        'edit' => Icons.edit_rounded,
        'command' => Icons.terminal_rounded,
        'action' => Icons.mouse_rounded,
        'memory' => Icons.psychology_rounded,
        'restore' => Icons.undo_rounded,
        _ => Icons.circle_outlined,
      };

  static Color _color(String kind) => switch (kind) {
        'write' => P.green,
        'edit' => P.accent,
        'command' => P.amber,
        'action' => P.accent3,
        'memory' => const Color(0xFFF472B6),
        _ => P.dim,
      };

  static String _when(DateTime d) {
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final items = link.status?.journal ?? const <PcJournalEntry>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              const Expanded(child: Text('Journal d\'activité', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: P.card,
                        title: const Text('Vider le journal ?'),
                        content: const Text('Les copies de sauvegarde seront effacées : plus d\'Annuler possible.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Garder')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vider', style: TextStyle(color: P.red))),
                        ],
                      ),
                    );
                    if (ok == true) await link.run((c) => c.clearJournal());
                  },
                  child: const Text('Vider', style: TextStyle(color: P.dim)),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Rien pour l\'instant. Les fichiers écrits ou modifiés, les commandes et les actions de Fractus sur le PC apparaîtront ici, avec Annuler pour les fichiers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: P.dim3, height: 1.4),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final e = items[i];
                    return Card(
                      child: ListTile(
                        dense: true,
                        leading: Icon(_icon(e.kind), color: e.undone ? P.dim3 : _color(e.kind), size: 20),
                        title: Text(
                          e.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: e.undone ? P.dim3 : P.ink),
                        ),
                        subtitle: Text(
                          [_when(e.at), if (e.detail != null) e.detail!].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: P.dim3, fontSize: 11.5),
                        ),
                        trailing: e.canUndo
                            ? TextButton(
                                onPressed: () async {
                                  final err = await link.run((c) => c.undo(e.id));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Restauré')));
                                  }
                                },
                                child: const Text('Annuler'),
                              )
                            : (e.undone ? const Text('annulé', style: TextStyle(color: P.dim3, fontSize: 11)) : null),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
