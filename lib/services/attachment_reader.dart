// Lire les fichiers posés sur l'île pour les donner au modèle : le texte tel
// quel (coupé), les images décrites par un modèle vision, les dossiers listés,
// le reste par son chemin (les outils read_file / run_command font la suite).

import 'dart:convert';
import 'dart:io';

import '../core/attachments.dart';
import 'chat_service.dart';

class AttachmentReader {
  AttachmentReader._();

  /// Taille au-delà de laquelle on ne lit pas un fichier texte en entier.
  static const int maxTextBytes = 400 * 1024;
  static const int maxImageBytes = 6 * 1024 * 1024;

  /// Construit un [Attachment] depuis un chemin (taille, dossier ou non).
  static Future<Attachment> inspect(String path) async {
    try {
      final t = await FileSystemEntity.type(path);
      if (t == FileSystemEntityType.directory) return Attachment(path, isFolder: true);
      final size = t == FileSystemEntityType.file ? await File(path).length() : 0;
      return Attachment(path, size: size);
    } catch (_) {
      return Attachment(path);
    }
  }

  /// Le bloc caché que le modèle lit avec le message. `prompt` guide la
  /// description des images ; `onStatus` reçoit une courte ligne d'activité.
  static Future<String> describe(
    List<Attachment> files,
    ChatService chat,
    String prompt, {
    void Function(String status)? onStatus,
  }) async {
    if (files.isEmpty) return '';
    final out = StringBuffer(Attachment.header(files.length));
    out.writeln();
    for (final f in files) {
      onStatus?.call('je lis ${f.name}');
      out.writeln();
      out.write(await _one(f, chat, prompt));
    }
    return out.toString().trimRight();
  }

  static Future<String> _one(Attachment f, ChatService chat, String prompt) async {
    try {
      switch (f.kind) {
        case AttachmentKind.text:
          if (f.size > maxTextBytes) {
            return f.modelBlock(note: 'Trop gros pour être joint en entier : lis-le par morceaux avec read_file / search_text.');
          }
          final bytes = await File(f.path).readAsBytes();
          String text;
          try {
            text = utf8.decode(bytes);
          } catch (_) {
            text = latin1.decode(bytes);
          }
          return f.modelBlock(body: text);
        case AttachmentKind.image:
          if (f.size > maxImageBytes) return f.modelBlock(note: 'Image trop lourde pour être regardée (plus de 6 Mo).');
          final bytes = await File(f.path).readAsBytes();
          final mime = switch (Attachment.extensionOf(f.path)) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            'gif' => 'image/gif',
            'bmp' => 'image/bmp',
            _ => 'image/jpeg',
          };
          final question = prompt.trim().isEmpty
              ? 'Décris précisément cette image : ce qu\'on voit, tout texte lisible (recopie-le), les détails utiles.'
              : 'L\'utilisateur dit : « ${prompt.trim()} ». Décris précisément cette image en vue de lui répondre : ce qu\'on voit, tout texte lisible (recopie-le), les détails utiles.';
          try {
            final d = await chat.describeImage(bytes, question, mime: mime);
            return f.modelBlock(body: d.isEmpty ? '(le modèle vision n\'a rien renvoyé)' : d);
          } catch (e) {
            return f.modelBlock(note: 'Impossible de regarder l\'image : $e');
          }
        case AttachmentKind.folder:
          final lines = <String>[];
          var n = 0;
          await for (final e in Directory(f.path).list(followLinks: false)) {
            if (++n > 200) {
              lines.add('… (liste coupée à 200 entrées — utilise list_directory pour la suite)');
              break;
            }
            final name = Attachment.baseName(e.path);
            lines.add(e is Directory ? '$name/' : name);
          }
          lines.sort();
          return f.modelBlock(body: lines.isEmpty ? '(vide)' : lines.join('\n'), maxChars: 8000);
        case AttachmentKind.other:
          return f.modelBlock(
            note: 'Type non lu directement. Si c\'est utile, ouvre-le avec les outils : read_file (texte), run_command (ex. PowerShell pour un PDF/DOCX/ZIP), open (l\'ouvrir pour l\'utilisateur).',
          );
      }
    } catch (e) {
      return f.modelBlock(note: 'Impossible de lire ce fichier : $e');
    }
  }
}
