// La connexion au PC vue du téléphone : lecture du code, des adresses, du QR
// code, de l'état envoyé par le PC, et du point de rendez-vous.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fractus_mobile/core/rendezvous.dart';
import 'package:fractus_mobile/models.dart';
import 'package:fractus_mobile/prefs.dart';

void main() {
  group('adresse du PC', () {
    test('IP seule, IP:port, avec ou sans http://', () {
      final a = PcConnectionInfo.parse('192.168.1.20', 'ab2c-d3ef');
      expect(a.host, '192.168.1.20');
      expect(a.port, 7790);
      expect(a.token, 'AB2C-D3EF');
      expect(a.baseUrl, 'http://192.168.1.20:7790');

      final b = PcConnectionInfo.parse(' http://192.168.1.20:8000/ ', 'AB2C-D3EF');
      expect(b.host, '192.168.1.20');
      expect(b.port, 8000);
      expect(b.baseUrl, 'http://192.168.1.20:8000');
    });

    test('l\'URL du tunnel Internet est gardée telle quelle (https)', () {
      final a = PcConnectionInfo.parse('https://abc-def.trycloudflare.com/', 'AB2C-D3EF');
      expect(a.host, 'https://abc-def.trycloudflare.com');
      expect(a.baseUrl, 'https://abc-def.trycloudflare.com');
      expect(PcConnectionInfo.isTunnel(a.host), isTrue);
      expect(PcConnectionInfo.networkLabel(a.host), 'Internet');

      final b = PcConnectionInfo.parse('abc-def.trycloudflare.com', 'AB2C-D3EF');
      expect(b.baseUrl, 'https://abc-def.trycloudflare.com');

      expect(PcConnectionInfo.isTunnel('192.168.1.20'), isFalse);
      expect(PcConnectionInfo.networkLabel('192.168.1.20'), 'Wi-Fi');
    });

    test('la liste des adresses : la courante d\'abord, sans doublon ni vide', () {
      final i = PcConnectionInfo(host: '192.168.1.20', port: 7790, token: 'X', hosts: ['', ' 192.168.1.20 ', '10.0.0.5', 'https://abc.trycloudflare.com', '10.0.0.5']);
      expect(i.hosts, ['192.168.1.20', '10.0.0.5', 'https://abc.trycloudflare.com']);

      final j = i.withHost('https://abc.trycloudflare.com');
      expect(j.host, 'https://abc.trycloudflare.com');
      expect(j.hosts.first, 'https://abc.trycloudflare.com');
      expect(j.hosts.toSet(), i.hosts.toSet());
      expect(j.baseUrl, 'https://abc.trycloudflare.com');

      final k = i.withHosts(['172.16.0.2', '192.168.1.20']);
      expect(k.hosts, ['192.168.1.20', '10.0.0.5', 'https://abc.trycloudflare.com', '172.16.0.2']);
    });

    test('le QR code d\'appairage', () {
      final hosts = Uri.encodeQueryComponent('192.168.1.20,https://abc.trycloudflare.com');
      final i = PcConnectionInfo.fromPairLink('fractus://pair?host=192.168.1.20&hosts=$hosts&port=7790&code=ab2c-d3ef');
      expect(i, isNotNull);
      expect(i!.host, '192.168.1.20');
      expect(i.port, 7790);
      expect(i.token, 'AB2C-D3EF');
      expect(i.hosts, ['192.168.1.20', 'https://abc.trycloudflare.com']);

      // Ancien QR, sans liste d'adresses.
      final old = PcConnectionInfo.fromPairLink('fractus://pair?host=192.168.1.20&port=7790&code=AB2C-D3EF');
      expect(old!.hosts, ['192.168.1.20']);

      expect(PcConnectionInfo.fromPairLink('https://example.com'), isNull);
      expect(PcConnectionInfo.fromPairLink('fractus://pair?host=&code=X'), isNull);
    });
  });

  group('état envoyé par le PC', () {
    test('se lit même incomplet', () {
      final s = PcStatus.fromJson(const {});
      expect(s.host, '');
      expect(s.addresses, isEmpty);
      expect(s.sessions, isEmpty);
      expect(s.pending, isNull);
      expect(s.chatBusy, isFalse);
    });

    test('se lit en entier', () {
      final s = PcStatus.fromJson(jsonDecode('''
        {"app":"fractus","version":"0.10.8","host":"MON-PC","addresses":["192.168.1.20","https://abc.trycloudflare.com"],
         "port":7790,"botState":"thinking","chatBusy":true,
         "sessions":[{"id":"s1","project":"Korus","agent":"claude","state":"running","active":true}],
         "pending":{"requestId":"r1","project":"Korus","tool":"Bash","summary":"rm -rf build","label":"Lancer une commande"},
         "conversation":{"id":"c1","title":"Test","messages":[{"role":"user","text":"salut","at":"2026-11-15T10:00:00Z"}]},
         "settings":{"model":"llama","workspace":"C:\\\\dev"}}
      ''') as Map);
      expect(s.host, 'MON-PC');
      expect(s.addresses, ['192.168.1.20', 'https://abc.trycloudflare.com']);
      expect(s.botState, 'thinking');
      expect(s.chatBusy, isTrue);
      expect(s.sessions.single.project, 'Korus');
      expect(s.pending!.requestId, 'r1');
      expect(s.messages.single.text, 'salut');
      expect(s.messages.single.at.toUtc().hour, 10);
      expect(s.settings!.model, 'llama');
    });
  });

  group('point de rendez-vous (même code des deux côtés)', () {
    test('le téléphone rouvre ce que le PC scelle', () {
      final sealed = Rendezvous.seal('AB2C-D3EF', {'url': 'https://abc.trycloudflare.com', 'addresses': ['192.168.1.20'], 'port': 7790});
      final line = jsonEncode({'id': '1', 'time': 1, 'event': 'message', 'message': sealed});
      final p = Rendezvous.latest('ab2cd3ef', line);
      expect(p?['url'], 'https://abc.trycloudflare.com');
      expect(p?['addresses'], ['192.168.1.20']);
      expect(Rendezvous.latest('AB2C-D3EG', line), isNull);
    });
  });
}
