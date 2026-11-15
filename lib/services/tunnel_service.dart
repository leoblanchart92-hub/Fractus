// Le tunnel Internet : pour que le téléphone joigne le PC sans être sur le
// même Wi-Fi, sans VPN et sans rien ouvrir sur la box.
//
// On s'appuie sur « cloudflared » (Cloudflare, gratuit, sans compte) : il
// ouvre une connexion sortante vers Cloudflare, qui nous donne une adresse
// https://<aléatoire>.trycloudflare.com menant à notre serveur local. Le code
// d'appairage reste exigé sur chaque requête, comme en Wi-Fi.
//
// L'adresse change à chaque relance : le serveur « téléphone » la dépose,
// chiffrée avec le code, au point de rendez-vous (voir core/rendezvous.dart)
// pour que le téléphone la retrouve tout seul.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/settings.dart';

enum TunnelStatus { off, downloading, starting, online, error }

class TunnelService extends ChangeNotifier {
  TunnelService();

  static const String downloadUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe';

  TunnelStatus status = TunnelStatus.off;
  String? url;
  String? error;
  double progress = 0;

  Process? _proc;
  bool _wanted = false;
  int _port = 0;
  int _generation = 0;
  int _backoff = 2;

  bool get online => status == TunnelStatus.online && url != null;

  /// Le binaire : à côté des réglages (%APPDATA%\fractus\cloudflared.exe).
  static Future<File> binary() async {
    final d = await Settings.dir();
    return File('${d.path}${Platform.pathSeparator}cloudflared.exe');
  }

  Future<void> start(int port) async {
    _wanted = true;
    _port = port;
    final gen = ++_generation;
    await _kill();
    unawaited(_run(gen));
  }

  Future<void> stop() async {
    _wanted = false;
    _generation++;
    await _kill();
    url = null;
    error = null;
    status = TunnelStatus.off;
    notifyListeners();
  }

  /// Relance (après une erreur, ou pour changer d'adresse).
  Future<void> restart() async {
    if (_port == 0) return;
    _backoff = 2;
    await start(_port);
  }

  Future<void> _kill() async {
    final p = _proc;
    _proc = null;
    if (p == null) return;
    try {
      p.kill();
      await p.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _ensureBinary() async {
    final f = await binary();
    if (await f.exists() && await f.length() > 10 * 1024 * 1024) return;
    status = TunnelStatus.downloading;
    progress = 0;
    notifyListeners();
    final part = File('${f.path}.part');
    final req = http.Request('GET', Uri.parse(downloadUrl))..headers['User-Agent'] = 'Fractus (Windows)';
    final res = await http.Client().send(req).timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) throw HttpException('Téléchargement de cloudflared refusé (${res.statusCode})');
    final total = res.contentLength ?? 0;
    final sink = part.openWrite();
    var done = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) {
          progress = done / total;
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }
    if (done < 10 * 1024 * 1024) {
      try {
        await part.delete();
      } catch (_) {}
      throw const FormatException('cloudflared téléchargé incomplet');
    }
    await part.rename(f.path);
  }

  Future<void> _run(int gen) async {
    try {
      await _ensureBinary();
    } catch (e) {
      if (gen != _generation) return;
      error = 'Impossible de récupérer cloudflared : $e';
      status = TunnelStatus.error;
      notifyListeners();
      return;
    }
    final exe = (await binary()).path;
    final re = RegExp(r'https://[a-z0-9-]+\.trycloudflare\.com');
    while (_wanted && gen == _generation) {
      status = TunnelStatus.starting;
      url = null;
      notifyListeners();
      try {
        final p = await Process.start(
          exe,
          ['tunnel', '--url', 'http://127.0.0.1:$_port', '--no-autoupdate', '--protocol', 'http2', '--loglevel', 'info'],
          runInShell: false,
        );
        _proc = p;
        void scan(String line) {
          if (gen != _generation) return;
          final m = re.firstMatch(line);
          if (m == null || m.group(0) == url) return;
          url = m.group(0);
          status = TunnelStatus.online;
          error = null;
          _backoff = 2;
          notifyListeners();
        }

        final outDone = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).forEach(scan);
        final errDone = p.stderr.transform(utf8.decoder).transform(const LineSplitter()).forEach(scan);
        final code = await p.exitCode;
        await Future.wait([outDone, errDone]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
        if (gen != _generation) return;
        error = 'Le tunnel s\'est arrêté (code $code) — nouvel essai dans $_backoff s.';
      } catch (e) {
        if (gen != _generation) return;
        error = 'Tunnel : $e';
      }
      _proc = null;
      url = null;
      status = TunnelStatus.error;
      notifyListeners();
      await Future<void>.delayed(Duration(seconds: _backoff));
      _backoff = min(_backoff * 2, 60);
    }
  }

  @override
  void dispose() {
    _wanted = false;
    _generation++;
    unawaited(_kill());
    super.dispose();
  }
}
