// Les fichiers posés sur l'île : tri par type, taille lisible, bloc du modèle,
// et le message qui les porte (affiché / envoyé / enregistré).

import 'package:flutter_test/flutter_test.dart';
import 'package:fractus/core/attachments.dart';
import 'package:fractus/core/layout.dart';
import 'package:fractus/core/models.dart';

void main() {
  group('Attachment', () {
    test('reconnaît le type par l\'extension (Windows ou Unix)', () {
      expect(Attachment.kindOf(r'C:\Users\Léo\Images\capture.PNG'), AttachmentKind.image);
      expect(Attachment.kindOf('/tmp/notes.md'), AttachmentKind.text);
      expect(Attachment.kindOf(r'D:\dev\main.dart'), AttachmentKind.text);
      expect(Attachment.kindOf(r'D:\docs\rapport.pdf'), AttachmentKind.other);
      expect(Attachment.kindOf(r'D:\dev\Makefile'), AttachmentKind.text);
      expect(Attachment(r'D:\dev\projet', isFolder: true).kind, AttachmentKind.folder);
    });

    test('nom de base et taille lisible', () {
      expect(Attachment.baseName(r'C:\Users\Léo\Images\capture.png'), 'capture.png');
      expect(Attachment.baseName('/home/leo/dossier/'), 'dossier');
      expect(Attachment.humanSize(512), '512 o');
      expect(Attachment.humanSize(14 * 1024), '14 Ko');
      expect(Attachment.humanSize((3.4 * 1024 * 1024).round()), '3,4 Mo');
    });

    test('le bloc du modèle porte le chemin et coupe les gros contenus', () {
      final a = Attachment(r'D:\dev\gros.log', size: 5000);
      final block = a.modelBlock(body: 'x' * 100, maxChars: 40);
      expect(block, contains('gros.log'));
      expect(block, contains(r'Chemin : D:\dev\gros.log'));
      expect(block, contains('coupé à 40 caractères sur 100'));
      expect(block, contains('read_file'));
      final small = a.modelBlock(body: 'bonjour');
      expect(small, isNot(contains('coupé')));
      expect(small, contains('bonjour'));
    });
  });

  group('ChatMessage avec fichiers', () {
    test('le texte caché part au modèle, pas à l\'écran, et survit au JSON', () {
      final m = ChatMessage('user', 'Regarde', files: const ['a.txt'], hidden: 'contenu de a');
      expect(m.text, 'Regarde');
      expect(m.modelText, 'Regarde\n\ncontenu de a');
      final back = ChatMessage.fromJson(m.toJson())!;
      expect(back.files, ['a.txt']);
      expect(back.hidden, 'contenu de a');
      expect(back.modelText, m.modelText);
    });

    test('un message sans fichier reste comme avant', () {
      final m = ChatMessage('assistant', 'Salut');
      expect(m.modelText, 'Salut');
      expect(m.toJson().containsKey('files'), isFalse);
      expect(m.toJson().containsKey('hidden'), isFalse);
      expect(ChatMessage.fromJson({'role': 'user', 'text': 'x'})!.files, isEmpty);
    });
  });

  test('l\'île grandit d\'une rangée quand des fichiers attendent', () {
    final base = islandSize(IslandMode.expanded, IslandView.prompt, chatCount: 0);
    final withFiles = islandSize(IslandMode.expanded, IslandView.prompt, chatCount: 0, files: true);
    expect(withFiles.height - base.height, filesRowH);
    expect(withFiles.width, base.width);
  });
}
