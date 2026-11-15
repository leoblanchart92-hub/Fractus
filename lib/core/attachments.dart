// Les fichiers qu'on donne à Fractus (glissés sur l'île). Pur Dart, sans
// accès disque : le tri par type, la taille lisible, le bloc que lit le modèle.
// La lecture elle-même est dans services/attachment_reader.dart.

enum AttachmentKind { image, text, folder, other }

class Attachment {
  Attachment(this.path, {this.size = 0, bool isFolder = false})
      : name = baseName(path),
        kind = isFolder ? AttachmentKind.folder : kindOf(path);

  final String path;
  final String name;
  final int size;
  final AttachmentKind kind;

  static String baseName(String path) {
    final clean = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final i = clean.lastIndexOf('/');
    return i < 0 ? clean : clean.substring(i + 1);
  }

  static String extensionOf(String path) {
    final n = baseName(path);
    final i = n.lastIndexOf('.');
    return i <= 0 ? '' : n.substring(i + 1).toLowerCase();
  }

  static const Set<String> imageExt = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'};

  static const Set<String> textExt = {
    'txt', 'md', 'markdown', 'rst', 'log', 'csv', 'tsv', 'json', 'jsonl', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'env',
    'xml', 'html', 'htm', 'css', 'scss', 'svg', 'sql', 'sh', 'bash', 'zsh', 'bat', 'cmd', 'ps1', 'psm1',
    'dart', 'py', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'java', 'kt', 'kts', 'swift', 'c', 'h', 'cc', 'cpp', 'hpp', 'cs',
    'go', 'rs', 'rb', 'php', 'lua', 'r', 'm', 'scala', 'gradle', 'properties', 'cmake', 'make', 'mk', 'dockerfile',
    'tex', 'bib', 'srt', 'vtt', 'ics', 'reg', 'gitignore', 'editorconfig', 'lock',
  };

  static AttachmentKind kindOf(String path) {
    final e = extensionOf(path);
    if (imageExt.contains(e)) return AttachmentKind.image;
    if (textExt.contains(e)) return AttachmentKind.text;
    final n = baseName(path).toLowerCase();
    if (n == 'makefile' || n == 'dockerfile' || n == 'license' || n == 'readme') return AttachmentKind.text;
    return AttachmentKind.other;
  }

  /// « 12 Ko », « 3,4 Mo »…
  static String humanSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} Ko';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} Mo';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} Go';
  }

  String get sizeLabel => size > 0 ? humanSize(size) : '';

  /// Ce que le modèle lit pour ce fichier. `body` : le texte du fichier, la
  /// description de l'image, ou le contenu du dossier ; null = pas lu.
  String modelBlock({String? body, String? note, int maxChars = 12000}) {
    final b = StringBuffer();
    final what = switch (kind) {
      AttachmentKind.image => 'Image',
      AttachmentKind.text => 'Fichier texte',
      AttachmentKind.folder => 'Dossier',
      AttachmentKind.other => 'Fichier',
    };
    b.write('### $what : $name');
    if (size > 0) b.write(' (${humanSize(size)})');
    b.writeln();
    b.writeln('Chemin : $path');
    if (note != null && note.isNotEmpty) b.writeln(note);
    if (body != null) {
      var t = body;
      final cut = t.length > maxChars;
      if (cut) t = t.substring(0, maxChars);
      final label = switch (kind) {
        AttachmentKind.image => 'Ce que montre l\'image',
        AttachmentKind.folder => 'Contenu',
        _ => 'Contenu',
      };
      b.writeln('$label :');
      b.writeln('```');
      b.writeln(t.trimRight());
      b.writeln('```');
      if (cut) b.writeln('(coupé à $maxChars caractères sur ${body.length} — utilise read_file sur le chemin pour la suite)');
    }
    return b.toString();
  }

  /// L'en-tête du bloc joint, commun à tous les fichiers d'un message.
  static String header(int count) =>
      count == 1 ? '[Fichier joint par l\'utilisateur — il en parle dans son message]' : '[$count fichiers joints par l\'utilisateur — il en parle dans son message]';
}
