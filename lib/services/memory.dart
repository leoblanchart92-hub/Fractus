// La mémoire longue de Fractus : un simple fichier Markdown,
//   %APPDATA%\fractus\memoire.md
// lu au début de chaque conversation et glissé dans le prompt système. Fractus
// l'enrichit lui-même (outil remember, sous permission) ; l'utilisateur peut
// l'ouvrir et le modifier à la main. Une ligne par fait.

import 'dart:io';

import '../core/settings.dart';

class LongTermMemory {
  static const int maxLines = 300;
  /// Ce qu'on glisse au plus dans le prompt (caractères).
  static const int promptBudget = 8000;

  static const String header = '# Mémoire de Fractus\n\n'
      'Ce que Fractus sait de toi, une ligne par fait. Il relit ce fichier à chaque conversation.\n'
      'Tu peux le modifier à la main ; lui demander « retiens que… » ou « oublie… » le met à jour.\n\n';

  File? _file;

  Future<File> file() async {
    if (_file != null) return _file!;
    final d = await Settings.dir();
    return _file = File('${d.path}${Platform.pathSeparator}memoire.md');
  }

  Future<String> path() async => (await file()).path;

  Future<String> read() async {
    try {
      final f = await file();
      if (!await f.exists()) return '';
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// Les faits seuls (sans l'en-tête), pour le prompt.
  Future<String> facts() async {
    final lines = (await read()).split('\n').map((l) => l.trimRight()).where((l) => l.startsWith('- ')).toList();
    var out = lines.join('\n');
    if (out.length > promptBudget) out = '${out.substring(out.length - promptBudget)}\n(…début tronqué : la mémoire est longue, fais le ménage avec forget)';
    return out;
  }

  Future<int> count() async => (await read()).split('\n').where((l) => l.trimLeft().startsWith('- ')).length;

  /// Ajoute un fait (une ligne). Renvoie un message pour le modèle.
  Future<String> remember(String text) async {
    final fact = text.replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r'^[-*•]\s*'), '');
    if (fact.isEmpty) return 'Rien à retenir (texte vide).';
    final f = await file();
    var content = await read();
    if (content.trim().isEmpty) content = header;
    final existing = content.split('\n');
    final needle = fact.toLowerCase();
    if (existing.any((l) => l.toLowerCase().contains(needle))) return 'Déjà en mémoire : « $fact ».';
    if (existing.where((l) => l.startsWith('- ')).length >= maxLines) {
      return 'Mémoire pleine ($maxLines faits) : retire d\'abord des faits périmés avec forget.';
    }
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (!content.endsWith('\n')) content += '\n';
    content += '- $fact _(noté le $date)_\n';
    await f.writeAsString(content);
    return 'Retenu : « $fact ».';
  }

  /// Retire les faits qui contiennent ce texte. Renvoie le nombre retiré.
  Future<int> forget(String text) async {
    final needle = text.trim().toLowerCase();
    if (needle.isEmpty) return 0;
    final f = await file();
    final content = await read();
    if (content.isEmpty) return 0;
    final lines = content.split('\n');
    final kept = lines.where((l) => !(l.startsWith('- ') && l.toLowerCase().contains(needle))).toList();
    final removed = lines.length - kept.length;
    if (removed > 0) await f.writeAsString(kept.join('\n'));
    return removed;
  }

  Future<void> clear() async {
    try {
      final f = await file();
      if (await f.exists()) await f.writeAsString(header);
    } catch (_) {}
  }

  /// Ouvre le fichier dans l'éditeur par défaut (Bloc-notes…).
  Future<void> openInEditor() async {
    final f = await file();
    if (!await f.exists()) await f.writeAsString(header);
    if (Platform.isWindows) {
      await Process.start('notepad.exe', [f.path], mode: ProcessStartMode.detached);
    }
  }
}
