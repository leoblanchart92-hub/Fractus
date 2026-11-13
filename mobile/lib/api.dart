// Le client HTTP vers le PC, et la connexion vivante (flux d'événements).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  Future<void> _loop(int gen) async {
    var backoff = 1;
    while (_running && gen == _generation) {
      final c = client;
      if (c == null) {
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }
      try {
        await for (final s in c.events()) {
          if (gen != _generation) return;
          status = s;
          online = true;
          error = null;
          backoff = 1;
          notifyListeners();
          unawaited(onStatus?.call(s));
        }
        // Le flux s'est fermé proprement : on se reconnecte.
      } catch (e) {
        if (gen != _generation) return;
        online = false;
        error = e is PcError ? e.message : 'PC injoignable (${info?.host}:${info?.port})';
        notifyListeners();
        if (e is PcError && e.status == 401) {
          await Future<void>.delayed(const Duration(seconds: 10));
        }
      }
      await Future<void>.delayed(Duration(seconds: backoff));
      backoff = (backoff * 2).clamp(1, 15);
    }
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
