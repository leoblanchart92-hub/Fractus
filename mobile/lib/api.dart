// Le client HTTP vers le PC, et la connexion vivante (flux d'événements).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'core/rendezvous.dart';
import 'models.dart';
import 'prefs.dart';

class PcClient {
  PcClient(this.conn);
  final PcConnectionInfo conn;

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('${conn.baseUrl}$path').replace(queryParameters: q);
  Map<String, String> get _h => {'authorization': 'Bearer ${conn.token}', 'content-type': 'application/json'};

  /// L'URL d'une capture d'écran (le code passe en paramètre : Image.network).
  String screenUrl({int width = 1100}) =>
      _u('/api/screen.jpg', {'w': '$width', 'token': conn.token, 't': '${DateTime.now().millisecondsSinceEpoch}'}).toString();

  Future<Map<String, dynamic>> ping() async {
    final r = await http.get(_u('/api/ping')).timeout(const Duration(seconds: 5));
    return _json(r);
  }

  Future<PcStatus> status() async {
    final r = await http.get(_u('/api/status'), headers: _h).timeout(const Duration(seconds: 8));
    return PcStatus.fromJson(_json(r));
  }

  Future<void> decide(String requestId, String decision) =>
      _post('/api/approvals/decide', {'requestId': requestId, 'decision': decision});

  Future<void> answer(String requestId, Map<String, String> answers) =>
      _post('/api/approvals/answer', {'requestId': requestId, 'answers': answers});

  Future<void> sendChat(String text) => _post('/api/chat', {'text': text});

  Future<void> newChat() => _post('/api/chat/new', {});

  Future<void> action(String name) => _post('/api/action', {'action': name});

  Future<void> undo(String id) => _post('/api/journal/undo', {'id': id});
  Future<void> clearJournal() => _post('/api/journal/clear', {});

  Future<String> memory() async {
    final r = await http.get(_u('/api/memory'), headers: _h).timeout(const Duration(seconds: 8));
    return '${_json(r)['text'] ?? ''}';
  }

  Future<void> saveMemory(String text) => _post('/api/memory', {'text': text});

  Future<void> openConversation(String id) => _post('/api/conversations/open', {'id': id});
  Future<void> deleteConversation(String id) => _post('/api/conversations/delete', {'id': id});

  Future<void> settings(Map<String, Object?> patch) => _post('/api/settings', patch);

  Future<Map<String, dynamic>> _post(String path, Map body) async {
    final r = await http.post(_u(path), headers: _h, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    return _json(r);
  }

  static Map<String, dynamic> _json(http.Response r) {
    Map<String, dynamic> j = {};
    try {
      final raw = jsonDecode(utf8.decode(r.bodyBytes));
      if (raw is Map<String, dynamic>) j = raw;
    } catch (_) {}
    if (r.statusCode >= 400) {
      final msg = j['error']?.toString() ?? 'erreur ${r.statusCode}';
      throw PcError(r.statusCode, msg);
    }
    return j;
  }

  /// Le flux d'événements : un PcStatus à chaque changement sur le PC.
  Stream<PcStatus> events() async* {
    final client = http.Client();
    try {
      final req = http.Request('GET', _u('/api/events'))..headers.addAll(_h);
      final res = await client.send(req).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw PcError(res.statusCode, res.statusCode == 401 ? 'code d\'appairage incorrect' : 'erreur ${res.statusCode}');
      }
      final buffer = StringBuffer();
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 45))) {
        if (line.startsWith('data:')) {
          buffer.write(line.substring(5).trim());
        } else if (line.isEmpty && buffer.isNotEmpty) {
          final payload = buffer.toString();
          buffer.clear();
          try {
            final j = jsonDecode(payload);
            if (j is Map) yield PcStatus.fromJson(j);
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }
}

class PcError implements Exception {
  PcError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// La connexion vivante : garde le dernier état, se reconnecte toute seule.
class PcLink extends ChangeNotifier {
  PcLink();

  PcConnectionInfo? info;
  PcClient? client;
  PcStatus? status;
  bool online = false;
  String? error;
  bool _running = false;
  int _generation = 0;

  bool get configured => info != null && info!.host.isNotEmpty && info!.token.isNotEmpty;

  Future<void> load() async {
    info = await Prefs.load();
    client = configured ? PcClient(info!) : null;
    notifyListeners();
  }

  Future<void> setInfo(PcConnectionInfo i) async {
    await Prefs.save(i);
    info = i;
    client = configured ? PcClient(i) : null;
    status = null;
    online = false;
    error = null;
    notifyListeners();
    restart();
  }

  /// (Re)lance la boucle de connexion.
  void restart() {
    _generation++;
    _running = true;
    unawaited(_loop(_generation));
  }

  void pause() {
    _running = false;
    _generation++;
  }

  /// Par où on passe en ce moment : « Wi-Fi » ou « Internet » (vide hors ligne).
  String get network => online && info != null ? PcConnectionInfo.networkLabel(info!.host) : '';

  Future<void> _loop(int gen) async {
    var backoff = 1;
    while (_running && gen == _generation) {
      var i = info;
      if (i == null || !configured) {
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }
      try {
        // Plusieurs adresses connues : la première qui répond gagne (Wi-Fi chez
        // soi, Internet ailleurs). On ne change d'adresse que si la nôtre se tait.
        if (i.hosts.length > 1) {
          final h = await _firstAlive(i);
          if (gen != _generation) return;
          if (h != null && h != i.host) {
            i = i.withHost(h);
            info = i;
            client = PcClient(i);
            unawaited(Prefs.save(i));
          }
        }
        final c = client ??= PcClient(i);
        await for (final s in c.events()) {
          if (gen != _generation) return;
          status = s;
          online = true;
          error = null;
          backoff = 1;
          _learnAddresses(s);
          notifyListeners();
          unawaited(onStatus?.call(s));
        }
        // Le flux s'est fermé proprement : on se reconnecte.
      } catch (e) {
        if (gen != _generation) return;
        online = false;
        error = e is PcError ? e.message : 'PC injoignable (${_short(info?.host)})';
        notifyListeners();
        if (e is PcError && e.status == 401) {
          await Future<void>.delayed(const Duration(seconds: 10));
        } else if (await _rendezvous()) {
          // Le PC a une nouvelle adresse Internet : on y va tout de suite.
          backoff = 1;
          continue;
        }
      }
      await Future<void>.delayed(Duration(seconds: backoff));
      backoff = (backoff * 2).clamp(1, 15);
    }
  }

  /// Interroge toutes les adresses en parallèle ; la première qui répond (notre
  /// adresse actuelle d'abord, si elle répond dans la seconde).
  Future<String?> _firstAlive(PcConnectionInfo i) async {
    final completer = Completer<String?>();
    var pending = i.hosts.length;
    String? firstOther;
    Future<void> probe(String h) async {
      try {
        await PcClient(i.withHost(h)).ping();
        if (!completer.isCompleted) {
          if (h == i.host) {
            completer.complete(h);
          } else {
            firstOther ??= h;
          }
        }
      } catch (_) {}
      if (--pending == 0 && !completer.isCompleted) completer.complete(firstOther);
    }

    for (final h in i.hosts) {
      unawaited(probe(h));
    }
    // L'adresse actuelle a une seconde d'avance ; sinon on prend la première autre.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 1200)).then((_) {
      if (!completer.isCompleted && firstOther != null) completer.complete(firstOther);
    }));
    return completer.future.timeout(const Duration(seconds: 6), onTimeout: () => firstOther);
  }

  static String _short(String? h) {
    if (h == null) return '';
    return h.replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), '');
  }

  DateTime _lastRendezvous = DateTime.fromMillisecondsSinceEpoch(0);

  /// Appairage par le code seul : le PC a déposé ses adresses au point de
  /// rendez-vous ; on les essaie toutes et on garde celles qui existent.
  /// Renvoie un message d'erreur lisible, ou `null` si c'est connecté.
  static Future<String?> findByCode(String code, void Function(PcConnectionInfo info) onFound) async {
    final token = Rendezvous.normalize(code);
    if (token.length < 6) return 'Le code fait 8 caractères (ex. AB2C-D3EF).';
    String body;
    try {
      final r = await http.get(Rendezvous.pollUri(token)).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return 'Point de rendez-vous indisponible (${r.statusCode}). Réessaie dans un instant.';
      body = r.body;
    } catch (_) {
      return 'Pas d\'accès à Internet sur le téléphone ?';
    }
    final p = Rendezvous.latest(token, body);
    if (p == null) {
      return 'Aucun PC ne s\'annonce avec ce code. Sur le PC : Fractus ouvert, Réglages → Téléphone activé, et vérifie le code.';
    }
    final port = (p['port'] is int) ? p['port'] as int : 7790;
    final candidates = <String>[
      for (final a in (p['addresses'] is List ? p['addresses'] as List : const [])) '$a',
      if (PcConnectionInfo.isTunnel('${p['url'] ?? ''}')) '${p['url']}',
    ].where((h) => h.isNotEmpty).toSet().toList();
    if (candidates.isEmpty) return 'Le PC ne donne aucune adresse.';
    final pretty = token.length == 8 ? '${token.substring(0, 4)}-${token.substring(4)}' : token;
    final base = PcConnectionInfo(host: candidates.first, port: port, token: pretty, hosts: candidates);
    // La première qui répond : le Wi-Fi est plus rapide, Internet marche de partout.
    final alive = await probeAll(base);
    if (alive.isEmpty) {
      return 'PC trouvé (${p['host'] ?? ''}) mais injoignable pour l\'instant : il est allumé ? Fractus tourne ? Réessaie dans quelques secondes.';
    }
    final lan = alive.where((h) => !PcConnectionInfo.isTunnel(h));
    onFound(base.withHost(lan.isNotEmpty ? lan.first : alive.first));
    return null;
  }

  /// Le diagnostic, étape par étape, en français : ce qui marche et ce qui coince.
  static Future<List<String>> diagnose(String code, PcConnectionInfo? current) async {
    final out = <String>[];
    final token = Rendezvous.normalize(code.isEmpty ? (current?.token ?? '') : code);
    // 1. Internet sur le téléphone ?
    try {
      final r = await http.get(Uri.parse('${Rendezvous.server}/v1/health')).timeout(const Duration(seconds: 8));
      out.add(r.statusCode == 200 ? '✓ Internet sur le téléphone' : '✗ Internet : réponse ${r.statusCode}');
    } catch (e) {
      out.add('✗ Pas d\'Internet sur le téléphone (ou ntfy.sh bloqué) : $e');
    }
    // 2. Le PC s'annonce-t-il avec ce code ?
    final hosts = <String>{...?current?.hosts};
    var port = current?.port ?? 7790;
    if (token.length < 6) {
      out.add('✗ Code vide ou trop court (8 caractères)');
    } else {
      try {
        final r = await http.get(Rendezvous.pollUri(token)).timeout(const Duration(seconds: 10));
        final p = r.statusCode == 200 ? Rendezvous.latest(token, r.body) : null;
        if (p == null) {
          out.add('✗ Aucun PC ne s\'annonce avec le code $token (PC à jour ? Réglages → Téléphone activé ? même code ?)');
        } else {
          final at = DateTime.tryParse('${p['at'] ?? ''}')?.toLocal();
          final age = at == null ? '' : ' (il y a ${DateTime.now().difference(at).inMinutes} min)';
          out.add('✓ PC « ${p['host'] ?? '?'} » annoncé$age');
          if (p['port'] is int) port = p['port'] as int;
          for (final a in (p['addresses'] is List ? p['addresses'] as List : const [])) {
            hosts.add('$a');
          }
          final url = '${p['url'] ?? ''}';
          if (PcConnectionInfo.isTunnel(url)) {
            hosts.add(url);
          } else {
            out.add('✗ Le PC n\'annonce pas d\'adresse Internet (ligne « Accès depuis Internet » pas verte sur le PC)');
          }
        }
      } catch (e) {
        out.add('✗ Point de rendez-vous injoignable : $e');
      }
    }
    // 3. Chaque adresse : joignable ? code accepté ?
    if (hosts.isEmpty) out.add('✗ Aucune adresse à essayer');
    await Future.wait([
      for (final h in hosts)
        () async {
          final label = PcConnectionInfo.isTunnel(h) ? 'Internet' : 'Wi-Fi';
          final conn = PcConnectionInfo(host: h, port: port, token: token);
          try {
            await PcClient(conn).ping().timeout(const Duration(seconds: 7));
          } catch (e) {
            out.add('✗ $label ${_short(h)} : injoignable (${e is PcError ? e.message : 'pas de réponse'})');
            return;
          }
          try {
            await PcClient(conn).status().timeout(const Duration(seconds: 7));
            out.add('✓ $label ${_short(h)} : répond, code accepté');
          } catch (e) {
            out.add('✗ $label ${_short(h)} : répond mais ${e is PcError ? e.message : 'erreur'}');
          }
        }(),
    ]);
    return out;
  }

  /// Les adresses de `i.hosts` qui répondent (avec le code), en parallèle.
  static Future<List<String>> probeAll(PcConnectionInfo i) async {
    final ok = <String>[];
    await Future.wait([
      for (final h in i.hosts)
        () async {
          try {
            await PcClient(i.withHost(h)).status().timeout(const Duration(seconds: 7));
            ok.add(h);
          } catch (_) {}
        }(),
    ]);
    return ok;
  }

  /// Le PC est introuvable : peut-être que son tunnel Internet a changé
  /// d'adresse. On demande au point de rendez-vous (chiffré avec le code).
  /// Vrai si on a appris une adresse nouvelle (devenue l'adresse courante).
  Future<bool> _rendezvous() async {
    final i = info;
    if (i == null || i.token.isEmpty) return false;
    final now = DateTime.now();
    if (now.difference(_lastRendezvous) < const Duration(seconds: 45)) return false;
    _lastRendezvous = now;
    try {
      final r = await http.get(Rendezvous.pollUri(i.token)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return false;
      final p = Rendezvous.latest(i.token, r.body);
      final url = '${p?['url'] ?? ''}';
      if (!PcConnectionInfo.isTunnel(url)) return false;
      if (i.host == url) return false;
      // Les anciennes adresses de tunnel ne reviendront pas : on les remplace.
      final kept = i.hosts.where((h) => !PcConnectionInfo.isTunnel(h)).toList();
      final fresh = PcConnectionInfo(host: url, port: i.port, token: i.token, hosts: kept);
      info = fresh;
      client = PcClient(fresh);
      await Prefs.save(fresh);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Le PC nous dit où il est joignable : on retient ses adresses pour plus tard.
  void _learnAddresses(PcStatus s) {
    final i = info;
    if (i == null || s.addresses.isEmpty) return;
    final fresh = s.addresses.where((a) => !i.hosts.contains(a)).toList();
    // Un nouveau tunnel remplace l'ancien (son adresse ne reviendra pas).
    final tunnels = s.addresses.where(PcConnectionInfo.isTunnel).toSet();
    final stale = tunnels.isEmpty ? const <String>[] : i.hosts.where((h) => PcConnectionInfo.isTunnel(h) && !tunnels.contains(h) && h != i.host).toList();
    if (fresh.isEmpty && stale.isEmpty) return;
    info = PcConnectionInfo(host: i.host, port: i.port, token: i.token, hosts: [...i.hosts.where((h) => !stale.contains(h)), ...fresh]);
    unawaited(Prefs.save(info!));
    notifyListeners();
  }

  /// Appelé à chaque nouvel état (le widget d'écran d'accueil s'en sert).
  Future<void> Function(PcStatus s)? onStatus;

  /// Une action, avec remontée d'erreur lisible.
  Future<String?> run(Future<void> Function(PcClient c) f) async {
    final c = client;
    if (c == null) return 'Configure d\'abord la connexion.';
    try {
      await f(c);
      return null;
    } catch (e) {
      return e is PcError ? e.message : 'PC injoignable';
    }
  }
}
