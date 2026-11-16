// Le fichier des nouveautés : bien formé, à jour, et lu correctement.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fractus/core/changelog.dart';

void main() {
  test('lecture des sections, dates et corps', () {
    final notes = Changelog.parse('''
# Titre
intro ignorée

## 1.2.0 · 3 mars 2026
- a
- b

## 1.1.0 — 1er mars 2026
Texte.
''');
    expect(notes.map((n) => n.version), ['1.2.0', '1.1.0']);
    expect(notes[0].date, '3 mars 2026');
    expect(notes[0].body, '- a\n- b');
    expect(notes[1].date, '1er mars 2026');
    expect(notes[1].body, 'Texte.');
  });

  test('comparaison de versions et filtre « plus récent que »', () {
    expect(Changelog.compare('0.11.4', '0.11.3'), greaterThan(0));
    expect(Changelog.compare('0.9.0', '0.10.0'), lessThan(0));
    expect(Changelog.compare('v1.0', '1.0.0'), 0);
    final notes = [
      const ReleaseNote(version: '0.11.4', date: '', body: ''),
      const ReleaseNote(version: '0.11.3', date: '', body: ''),
      const ReleaseNote(version: '0.10.0', date: '', body: ''),
    ];
    expect(Changelog.newerThan(notes, '0.11.3').map((n) => n.version), ['0.11.4']);
    expect(Changelog.newerThan(notes, '').length, 3);
    expect(Changelog.find(notes, '0.10.0')?.version, '0.10.0');
    expect(Changelog.find(notes, '0.0.1'), isNull);
  });

  test('CHANGELOG.md a une section pour la version du pubspec, en tête', () {
    final md = File('CHANGELOG.md').readAsStringSync();
    final notes = Changelog.parse(md);
    expect(notes, isNotEmpty);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*([\d.]+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    expect(notes.first.version, v, reason: 'ajoute une section « ## $v · date » en haut de CHANGELOG.md');
    expect(notes.first.body, isNotEmpty);
    // L'ordre : du plus récent au plus ancien.
    for (var i = 1; i < notes.length; i++) {
      expect(Changelog.compare(notes[i - 1].version, notes[i].version), greaterThan(0), reason: '${notes[i - 1].version} avant ${notes[i].version}');
    }
  });
}
