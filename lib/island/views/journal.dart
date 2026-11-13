// Le journal d'activité : ce que Fractus a fait, et Annuler pour les fichiers.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/journal.dart';
import '../widgets.dart';

class JournalView extends StatefulWidget {
  const JournalView({super.key, required this.journal});
  final Journal journal;

  @override
  State<JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<JournalView> {
  String? _message;
  bool _confirmClear = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.journal,
      builder: (context, _) {
        final items = widget.journal.newestFirst;
        return IslandCard(
          padding: const EdgeInsets.only(left: 96, right: 10, top: 8, bottom: 8),
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
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(_message!, style: ui(11, color: Palette.dim)),
                    ),
                  if (items.isNotEmpty)
                    IslandButton(
                      label: _confirmClear ? 'Confirmer' : 'Vider',
                      compact: true,
                      onTap: () async {
                        if (!_confirmClear) {
                          setState(() => _confirmClear = true);
                          return;
                        }
                        await widget.journal.clear();
                        if (mounted) {
                          setState(() {
                            _confirmClear = false;
                            _message = 'Journal et copies effacés';
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
                    : ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          itemBuilder: (_, i) => _Row(
                            entry: items[i],
                            onUndo: () async {
                              final err = await widget.journal.undo(items[i]);
                              if (mounted) setState(() => _message = err ?? 'Restauré');
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.onUndo});
  final JournalEntry entry;
  final VoidCallback onUndo;

  IconData get _icon => switch (entry.kind) {
        JournalKind.write => Icons.note_add_rounded,
        JournalKind.edit => Icons.edit_rounded,
        JournalKind.command => Icons.terminal_rounded,
        JournalKind.action => Icons.mouse_rounded,
        JournalKind.memory => Icons.psychology_rounded,
        JournalKind.restore => Icons.undo_rounded,
      };

  Color get _color => switch (entry.kind) {
        JournalKind.write => Palette.green2,
        JournalKind.edit => Palette.accent,
        JournalKind.command => Palette.amber,
        JournalKind.action => Palette.accent3,
        JournalKind.memory => Palette.pink,
        JournalKind.restore => Palette.dim,
      };

  String get _when {
    final d = entry.at;
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final dimmed = entry.undone;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 38, child: Text(_when, style: ui(10.5, color: Palette.dim4))),
          Icon(_icon, size: 13, color: dimmed ? Palette.dim4 : _color),
          const SizedBox(width: 7),
          Expanded(
            child: Tooltip(
              message: entry.detail ?? '',
              waitDuration: const Duration(milliseconds: 600),
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ui(12, color: dimmed ? Palette.dim3 : Palette.ink, height: 1.2),
              ),
            ),
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
