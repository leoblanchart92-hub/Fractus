// Un Markdown de poche pour les réponses de Fractus : titres, listes, citations,
// blocs de code, séparateurs ; en ligne : gras, italique, code, liens.
// Pur Dart (partagé avec le téléphone), sans dépendance ; le rendu est dans
// island/rich_text.dart. Ce qu'on ne comprend pas reste du texte tel quel.

enum MdBlockKind { paragraph, heading, bullets, numbers, code, quote, rule }

class MdSpan {
  const MdSpan(this.text, {this.bold = false, this.italic = false, this.code = false, this.link});
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? link;

  @override
  String toString() => '${bold ? 'B' : ''}${italic ? 'I' : ''}${code ? 'C' : ''}${link != null ? 'L' : ''}($text)';
}

class MdBlock {
  const MdBlock(this.kind, {this.spans = const [], this.items = const [], this.level = 0, this.lang = '', this.code = ''});
  final MdBlockKind kind;

  /// Paragraphe, titre, citation : le texte en ligne.
  final List<MdSpan> spans;

  /// Listes : un élément = ses spans.
  final List<List<MdSpan>> items;
  final int level;
  final String lang;
  final String code;

  /// Le texte brut (sans marques), pour copier ou résumer.
  String get plain => kind == MdBlockKind.code ? code : [for (final s in spans) s.text, for (final it in items) it.map((s) => s.text).join()].join();
}

class Markdown {
  Markdown._();

  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^\s{0,3}[-*•]\s+(.*)$');
  static final RegExp _number = RegExp(r'^\s{0,3}\d{1,3}[.)]\s+(.*)$');
  static final RegExp _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
  static final RegExp _fence = RegExp(r'^\s{0,3}(```|~~~)\s*([\w+#.-]*)\s*$');

  /// Vrai si le texte contient des marques qui méritent un rendu (sinon, du texte simple suffit).
  static bool looksRich(String text) =>
      text.contains('```') ||
      text.contains('**') ||
      text.contains('`') ||
      RegExp(r'(^|\n)\s{0,3}([-*•]|\d{1,3}[.)]|#{1,6}|>)\s').hasMatch(text) ||
      RegExp(r'\[[^\]]+\]\(https?://').hasMatch(text);

  static List<MdBlock> parse(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final out = <MdBlock>[];
    final para = <String>[];
    var listKind = MdBlockKind.paragraph;
    final listItems = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      out.add(MdBlock(MdBlockKind.paragraph, spans: parseInline(para.join('\n'))));
      para.clear();
    }

    void flushList() {
      if (listItems.isEmpty) return;
      out.add(MdBlock(listKind, items: [for (final it in listItems) parseInline(it)]));
      listItems.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final fence = _fence.firstMatch(line);
      if (fence != null) {
        flushPara();
        flushList();
        final mark = fence.group(1)!;
        final lang = fence.group(2) ?? '';
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith(mark)) {
          buf.add(lines[i]);
          i++;
        }
        i++; // la clôture (ou la fin du texte : bloc laissé ouvert pendant le streaming)
        out.add(MdBlock(MdBlockKind.code, lang: lang, code: buf.join('\n')));
        continue;
      }
      if (line.trim().isEmpty) {
        flushPara();
        flushList();
        i++;
        continue;
      }
      if (_rule.hasMatch(line)) {
        flushPara();
        flushList();
        out.add(const MdBlock(MdBlockKind.rule));
        i++;
        continue;
      }
      final h = _heading.firstMatch(line);
      if (h != null) {
        flushPara();
        flushList();
        out.add(MdBlock(MdBlockKind.heading, level: h.group(1)!.length, spans: parseInline(h.group(2)!.replaceAll(RegExp(r'\s#+$'), ''))));
        i++;
        continue;
      }
      if (line.trimLeft().startsWith('>')) {
        flushPara();
        flushList();
        final buf = <String>[];
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          buf.add(lines[i].trimLeft().substring(1).trimLeft());
          i++;
        }
        out.add(MdBlock(MdBlockKind.quote, spans: parseInline(buf.join('\n'))));
        continue;
      }
      final b = _bullet.firstMatch(line);
      final n = b == null ? _number.firstMatch(line) : null;
      if (b != null || n != null) {
        flushPara();
        final kind = b != null ? MdBlockKind.bullets : MdBlockKind.numbers;
        if (listItems.isNotEmpty && kind != listKind) flushList();
        listKind = kind;
        listItems.add((b ?? n)!.group(1)!);
        i++;
        // Les lignes indentées qui suivent prolongent l'élément.
        while (i < lines.length && lines[i].startsWith('  ') && lines[i].trim().isNotEmpty && !_bullet.hasMatch(lines[i]) && !_number.hasMatch(lines[i])) {
          listItems[listItems.length - 1] = '${listItems.last}\n${lines[i].trim()}';
          i++;
        }
        continue;
      }
      if (listItems.isNotEmpty) flushList();
      para.add(line);
      i++;
    }
    flushPara();
    flushList();
    return out;
  }

  /// Gras `**x**` / `__x__`, italique `*x*` / `_x_`, code `` `x` ``, lien `[t](u)`.
  static List<MdSpan> parseInline(String s) {
    final out = <MdSpan>[];
    final buf = StringBuffer();
    var bold = false, italic = false;

    void flush() {
      if (buf.isEmpty) return;
      out.add(MdSpan(buf.toString(), bold: bold, italic: italic));
      buf.clear();
    }

    bool wordChar(int i) => i >= 0 && i < s.length && RegExp(r'\w').hasMatch(s[i]);

    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '`') {
        final end = s.indexOf('`', i + 1);
        if (end > i + 1) {
          flush();
          out.add(MdSpan(s.substring(i + 1, end), code: true));
          i = end + 1;
          continue;
        }
      }
      if (c == '[') {
        final m = RegExp(r'^\[([^\]]+)\]\(([^)\s]+)\)').firstMatch(s.substring(i));
        if (m != null) {
          flush();
          out.add(MdSpan(m.group(1)!, link: m.group(2), bold: bold, italic: italic));
          i += m.group(0)!.length;
          continue;
        }
      }
      if (s.startsWith('**', i) || s.startsWith('__', i)) {
        final mark = s.substring(i, i + 2);
        // Ouvre si suivi d'un caractère ; ferme si on est en gras.
        if (bold || (i + 2 < s.length && s[i + 2] != ' ' && s.indexOf(mark, i + 2) > 0)) {
          flush();
          bold = !bold;
          i += 2;
          continue;
        }
      }
      if ((c == '*' || c == '_') && s.startsWith(c + c, i)) {
        // Un « ** » qui n'a pas trouvé sa fermeture : du texte tel quel.
        buf.write(c + c);
        i += 2;
        continue;
      }
      if ((c == '*' || c == '_') && !(c == '_' && wordChar(i - 1) && wordChar(i + 1))) {
        if (italic || (i + 1 < s.length && s[i + 1] != ' ' && s.indexOf(c, i + 1) > 0)) {
          flush();
          italic = !italic;
          i++;
          continue;
        }
      }
      buf.write(c);
      i++;
    }
    flush();
    return out;
  }
}
