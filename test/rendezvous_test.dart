// Le point de rendez-vous et le code d'appairage : ce qui permet au téléphone
// de trouver le PC avec le code seul. Si ça casse, plus rien ne se connecte.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fractus/core/rendezvous.dart';
import 'package:fractus/core/settings.dart';

void main() {
  group('code d\'appairage', () {
    test('a la forme XXXX-XXXX sans caractères ambigus', () {
      for (var i = 0; i < 50; i++) {
        final t = Settings.newRemoteToken();
        expect(t, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$')), reason: t);
      }
    });

    test('se compare sans tiret ni casse', () {
      expect(Settings.normalizeToken('ab2c-d3ef'), 'AB2CD3EF');
      expect(Settings.normalizeToken(' AB2C D3EF '), 'AB2CD3EF');
      expect(Rendezvous.normalize('ab2c-d3ef'), Settings.normalizeToken('AB2C-D3EF'));
    });
  });

  group('point de rendez-vous', () {
    const token = 'AB2C-D3EF';

    test('le sujet dépend du code, pas de sa typographie, et ne le révèle pas', () {
      final a = Rendezvous.topic('AB2C-D3EF');
      expect(a, Rendezvous.topic('ab2cd3ef'));
      expect(a, isNot(Rendezvous.topic('AB2C-D3EG')));
      expect(a, matches(RegExp(r'^fractus-[0-9a-f]{40}$')));
      expect(a.toUpperCase(), isNot(contains('AB2CD3EF')));
      expect(Rendezvous.publishUri(token).toString(), 'https://ntfy.sh/$a');
      expect(Rendezvous.pollUri(token).path, '/$a/json');
    });

    test('ce qui est scellé se rouvre avec le même code, et seulement lui', () {
      final payload = {
        'host': 'MON-PC',
        'port': 7790,
        'addresses': ['192.168.1.20', 'https://abc.trycloudflare.com'],
        'url': 'https://abc.trycloudflare.com',
      };
      final sealed = Rendezvous.seal(token, payload);
      expect(sealed, startsWith('f1.'));
      expect(sealed, isNot(contains('MON-PC')));
      expect(sealed, isNot(contains('trycloudflare')));
      expect(Rendezvous.open('ab2cd3ef', sealed), payload);
      expect(Rendezvous.open('AB2C-D3EG', sealed), isNull);
      expect(Rendezvous.open(token, 'n\'importe quoi'), isNull);
      // Deux scellés du même message diffèrent (nonce), et se rouvrent tous les deux.
      final again = Rendezvous.seal(token, payload);
      expect(again, isNot(sealed));
      expect(Rendezvous.open(token, again), payload);
    });

    test('un message altéré est rejeté', () {
      final sealed = Rendezvous.seal(token, {'url': 'https://abc.trycloudflare.com'});
      final body = sealed.substring(3);
      // On retourne un bit au milieu du corps chiffré.
      final bytes = base64Url.decode(base64Url.normalize(body));
      bytes[20] ^= 0x01;
      final tampered = 'f1.${base64Url.encode(bytes)}';
      expect(Rendezvous.open(token, tampered), isNull);
    });

    test('dans le flux ntfy, on prend le plus récent qui est à nous', () {
      final old = Rendezvous.seal(token, {'url': 'https://old.trycloudflare.com'});
      final fresh = Rendezvous.seal(token, {'url': 'https://new.trycloudflare.com'});
      final other = Rendezvous.seal('ZZZZ-ZZZZ', {'url': 'https://pas-a-nous.trycloudflare.com'});
      final ndjson = [
        jsonEncode({'id': '1', 'time': 100, 'event': 'message', 'message': old}),
        jsonEncode({'id': '2', 'time': 300, 'event': 'message', 'message': other}),
        jsonEncode({'id': '3', 'time': 200, 'event': 'message', 'message': fresh}),
        jsonEncode({'id': '4', 'time': 400, 'event': 'message', 'message': 'spam'}),
        '',
        'pas du json',
      ].join('\n');
      expect(Rendezvous.latest(token, ndjson)?['url'], 'https://new.trycloudflare.com');
      expect(Rendezvous.latest('ZZZZ-ZZZZ', ndjson)?['url'], 'https://pas-a-nous.trycloudflare.com');
      expect(Rendezvous.latest('QQQQ-QQQQ', ndjson), isNull);
      expect(Rendezvous.latest(token, ''), isNull);
    });
  });
}
