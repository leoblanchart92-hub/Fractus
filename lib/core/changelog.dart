// Les nouveautés : le CHANGELOG.md de la racine, lu par le PC et le téléphone.
// Une section par version (`## 0.11.4 · 16 novembre 2026`), le corps en Markdown.

class ReleaseNote {
  const ReleaseNote({required this.version, required this.date, required this.body});
  final String version;
  final String date;

  /// Le Markdown de la section (sans son titre).
  final String body;
}

class Changelog {
  Changelog._();

  static final RegExp _section = RegExp(r'^##\s+v?(\d+(?:\.\d+)*)\s*(?:[·—–-]\s*(.*))?$');

  static List<ReleaseNote> parse(String md) {
    final out = <ReleaseNote>[];
    String? version;
    String date = '';
    final body = StringBuffer();
    void flush() {
      final v = version;
      if (v == null) return;
      out.add(ReleaseNote(version: v, date: date, body: body.toString().trim()));
      body.clear();
    }

    for (final raw in md.replaceAll('\r\n', '\n').split('\n')) {
      final m = _section.firstMatch(raw.trimRight());
      if (m != null) {
        flush();
        version = m.group(1);
        date = (m.group(2) ?? '').trim();
        continue;
      }
      if (version != null) body.writeln(raw);
    }
    flush();
    return out;
  }

  /// Compare deux versions « a.b.c » (négatif si a < b).
  static int compare(String a, String b) {
    List<int> parts(String v) => v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[^\d]+')).where((s) => s.isNotEmpty).map(int.parse).toList();
    final pa = parts(a), pb = parts(b);
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Les versions strictement plus récentes que [seen] (vide = tout est nouveau).
  static List<ReleaseNote> newerThan(List<ReleaseNote> notes, String seen) =>
      seen.trim().isEmpty ? notes : notes.where((n) => compare(n.version, seen) > 0).toList();

  /// La section d'une version, telle quelle (pour les notes de version GitHub).
  static ReleaseNote? find(List<ReleaseNote> notes, String version) {
    for (final n in notes) {
      if (compare(n.version, version) == 0) return n;
    }
    return null;
  }
}
