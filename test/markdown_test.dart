// Le Markdown de poche des réponses : blocs et marques en ligne.

import 'package:flutter_test/flutter_test.dart';
import 'package:fractus/core/markdown.dart';

void main() {
  test('texte simple : un seul paragraphe, rien de riche', () {
    expect(Markdown.looksRich('Bonjour, tout va bien.'), isFalse);
    final b = Markdown.parse('Bonjour,\ntout va bien.');
    expect(b.length, 1);
    expect(b.single.kind, MdBlockKind.paragraph);
    expect(b.single.plain, 'Bonjour,\ntout va bien.');
  });

  test('gras, italique, code et lien en ligne', () {
    final spans = Markdown.parseInline('Un **mot** fort, *doux*, `x = 1` et [doc](https://ex.fr).');
    expect(spans.where((s) => s.bold).map((s) => s.text), ['mot']);
    expect(spans.where((s) => s.italic).map((s) => s.text), ['doux']);
    expect(spans.where((s) => s.code).map((s) => s.text), ['x = 1']);
    final link = spans.singleWhere((s) => s.link != null);
    expect(link.text, 'doc');
    expect(link.link, 'https://ex.fr');
    expect(spans.map((s) => s.text).join(), 'Un mot fort, doux, x = 1 et doc.');
  });

  test('une étoile seule ou un tiret bas dans un mot restent du texte', () {
    expect(Markdown.parseInline('2 * 3 = 6').map((s) => s.text).join(), '2 * 3 = 6');
    expect(Markdown.parseInline('ma_variable_ici').single.italic, isFalse);
    expect(Markdown.parseInline('**pas fermé').single.text, '**pas fermé');
  });

  test('titres, listes, citation, séparateur', () {
    final b = Markdown.parse('''
## Plan
- un
- deux
  suite de deux
1. premier
2) second
> note
---
fin''');
    expect(b.map((x) => x.kind), [
      MdBlockKind.heading,
      MdBlockKind.bullets,
      MdBlockKind.numbers,
      MdBlockKind.quote,
      MdBlockKind.rule,
      MdBlockKind.paragraph,
    ]);
    expect(b[0].level, 2);
    expect(b[0].plain, 'Plan');
    expect(b[1].items.length, 2);
    expect(b[1].items[1].map((s) => s.text).join(), 'deux\nsuite de deux');
    expect(b[2].items.length, 2);
    expect(b[3].plain, 'note');
  });

  test('bloc de code : langage, contenu intact, et bloc ouvert pendant le streaming', () {
    final b = Markdown.parse('Voici :\n```dart\nvoid main() {\n  print("**pas du gras**");\n}\n```\nVoilà.');
    expect(b.length, 3);
    expect(b[1].kind, MdBlockKind.code);
    expect(b[1].lang, 'dart');
    expect(b[1].code, 'void main() {\n  print("**pas du gras**");\n}');
    final open = Markdown.parse('```py\nx = 1');
    expect(open.single.kind, MdBlockKind.code);
    expect(open.single.code, 'x = 1');
  });
}
