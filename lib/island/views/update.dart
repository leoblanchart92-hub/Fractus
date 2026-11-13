// La carte « mise à jour » : une nouvelle version est là, on l'installe ou pas.

import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../services/update_service.dart';
import '../widgets.dart';

class UpdateView extends StatelessWidget {
  const UpdateView({super.key, required this.updates, required this.onLater});
  final UpdateService updates;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: updates,
      builder: (context, _) {
        final info = updates.available;
        final status = updates.status;
        final busy = status == UpdateStatus.downloading || status == UpdateStatus.installing;
        final String line;
        if (status == UpdateStatus.installing) {
          line = 'Installation… Fractus se relance dans un instant.';
        } else if (status == UpdateStatus.downloading) {
          line = 'Téléchargement ${(updates.progress * 100).round()} %';
        } else if (status == UpdateStatus.error) {
          line = updates.error ?? 'Quelque chose a échoué.';
        } else if (info != null && info.notes.isNotEmpty) {
          line = _firstLine(info.notes);
        } else {
          line = 'Nouveautés et corrections. Deux secondes, Fractus se relance tout seul.';
        }
        return IslandCard(
          wash: Wash.cyan,
          padding: const EdgeInsets.only(left: 124, top: 12, right: 14, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mise à jour', style: ui(11.5, weight: FontWeight.w600, color: Palette.dim)),
              const SizedBox(height: 2),
              Text(
                info == null ? 'Fractus est à jour' : 'Fractus ${info.version} est disponible',
                style: ui(15.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ui(12.5, color: status == UpdateStatus.error ? Palette.redText : Palette.dim),
                ),
              ),
              if (busy)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: status == UpdateStatus.installing ? null : updates.progress,
                    minHeight: 4,
                    backgroundColor: Palette.tabOn,
                    color: Palette.blue,
                  ),
                )
              else
                Row(
                  children: [
                    if (info != null) ...[
                      IslandButton(label: 'Installer', primary: true, onTap: updates.install),
                      const SizedBox(width: 8),
                    ],
                    IslandButton(label: info != null ? 'Plus tard' : 'OK', onTap: onLater),
                    const Spacer(),
                    Text('Version actuelle ${updates.currentVersion}', style: ui(10.5, color: Palette.dim4)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  String _firstLine(String notes) {
    final clean = notes.replaceAll(RegExp(r'[#*`>_]'), '').trim();
    return clean.split('\n').where((l) => l.trim().isNotEmpty).take(2).join(' ');
  }
}
