// Le « point de rendez-vous » entre le PC et le téléphone.
//
// Quand le PC est joignable par un tunnel Internet, son adresse change à chaque
// redémarrage. Le PC la dépose donc, chiffrée avec le code d'appairage, sur un
// sujet ntfy.sh dont le nom est dérivé du code (impossible à deviner). Le
// téléphone va l'y lire quand il ne trouve plus le PC. Personne d'autre n'y
// comprend rien sans le code, et le code reste nécessaire pour parler au PC.
//
// Partagé tel quel entre le PC (lib/core) et le téléphone (mobile/lib/core).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class Rendezvous {
  static const String server = 'https://ntfy.sh';

  static String normalize(String token) => token.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  /// Le sujet ntfy : un haché du code, rien de reconnaissable.
  static String topic(String token) {
    final h = sha256.convert(utf8.encode('fractus-rendezvous|${normalize(token)}')).toString();
    return 'fractus-${h.substring(0, 40)}';
  }

  static Uri publishUri(String token) => Uri.parse('$server/${topic(token)}');

  /// Tout ce que le serveur garde encore (12 h sur ntfy.sh), en JSON ligne par ligne.
  static Uri pollUri(String token) => Uri.parse('$server/${topic(token)}/json?poll=1&since=all');

  static List<int> _key(String token) => sha256.convert(utf8.encode('fractus-key|${normalize(token)}')).bytes;

  static List<int> _stream(List<int> key, List<int> nonce, int length) {
    final out = <int>[];
    var counter = 0;
    while (out.length < length) {
      final block = Hmac(sha256, key).convert([...nonce, (counter >> 24) & 0xff, (counter >> 16) & 0xff, (counter >> 8) & 0xff, counter & 0xff]).bytes;
      out.addAll(block);
      counter++;
    }
    return out.sublist(0, length);
  }

  static List<int> _tag(List<int> key, List<int> nonceAndBody) => Hmac(sha256, [...key, 0x54]).convert(nonceAndBody).bytes.sublist(0, 16);

  /// Chiffre et signe un petit message avec le code : « f1.<base64url> ».
  static String seal(String token, Map<String, Object?> payload) {
    final key = _key(token);
    final rnd = Random.secure();
    final nonce = List<int>.generate(16, (_) => rnd.nextInt(256));
    final plain = utf8.encode(jsonEncode(payload));
    final ks = _stream(key, nonce, plain.length);
    final body = Uint8List.fromList([for (var i = 0; i < plain.length; i++) plain[i] ^ ks[i]]);
    final tag = _tag(key, [...nonce, ...body]);
    return 'f1.${base64Url.encode([...nonce, ...body, ...tag])}';
  }

  /// L'inverse : `null` si le message n'est pas pour nous ou a été altéré.
  static Map<String, dynamic>? open(String token, String sealed) {
    try {
      if (!sealed.startsWith('f1.')) return null;
      final raw = base64Url.decode(base64Url.normalize(sealed.substring(3)));
      if (raw.length < 16 + 16) return null;
      final key = _key(token);
      final nonce = raw.sublist(0, 16);
      final body = raw.sublist(16, raw.length - 16);
      final tag = raw.sublist(raw.length - 16);
      final want = _tag(key, [...nonce, ...body]);
      var diff = 0;
      for (var i = 0; i < 16; i++) {
        diff |= want[i] ^ tag[i];
      }
      if (diff != 0) return null;
      final ks = _stream(key, nonce, body.length);
      final plain = utf8.decode([for (var i = 0; i < body.length; i++) body[i] ^ ks[i]]);
      final j = jsonDecode(plain);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Dans la réponse de `pollUri` (une ligne JSON par message) : le message le
  /// plus récent qui se déchiffre avec notre code, ou `null`.
  static Map<String, dynamic>? latest(String token, String ndjson) {
    Map<String, dynamic>? best;
    var bestTime = -1;
    for (final line in const LineSplitter().convert(ndjson)) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line);
        if (m is! Map || m['event'] != 'message') continue;
        final t = (m['time'] is int) ? m['time'] as int : 0;
        if (t < bestTime) continue;
        final p = open(token, '${m['message'] ?? ''}');
        if (p == null) continue;
        best = p;
        bestTime = t;
      } catch (_) {}
    }
    return best;
  }
}
