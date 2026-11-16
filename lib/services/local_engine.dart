// Le moteur intégré : un modèle qui tourne dans Fractus, sans rien installer.
//   - le moteur : llama-server (llama.cpp, build CPU Windows, ~25 Mo) téléchargé
//     depuis GitHub dans %APPDATA%\fractus\engine\ ;
//   - le modèle : le fichier GGUF récupéré directement sur la bibliothèque
//     d'Ollama (registry.ollama.ai, les mêmes noms : « qwen3:1.7b »), vérifié
//     par son empreinte SHA-256, rangé dans %APPDATA%\fractus\models\ ;
//   - lancé en enfant de Fractus sur 127.0.0.1:11435 (API compatible OpenAI,
//     outils compris grâce à --jinja), arrêté avec lui.
// Rien ne sort de la machine une fois téléchargé.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/settings.dart';

enum LocalStatus { unknown, needsRuntime, downloadingRuntime, needsModel, downloadingModel, starting, ready, error }

class LocalEngineService extends ChangeNotifier {
  LocalEngineService();

  static const int port = 11435;
  static String get host => 'http://127.0.0.1:$port';
  static const String registry = 'https://registry.ollama.ai';

  LocalStatus status = LocalStatus.unknown;
  String? error;
  double progress = 0;
  String progressLabel = '';

  /// Le modèle que sert le processus en cours (vide = rien ne tourne).
  String running = '';
  Process? _proc;
  bool _busy = false;

  bool get ready => status == LocalStatus.ready;
  bool get busy => _busy;

  String get statusLine {
    switch (status) {
      case LocalStatus.unknown:
        return 'Vérification…';
      case LocalStatus.needsRuntime:
        return 'Le moteur n\'est pas encore téléchargé (25 Mo, une fois).';
      case LocalStatus.downloadingRuntime:
      case LocalStatus.downloadingModel:
        return progressLabel.isEmpty ? 'Téléchargement…' : progressLabel;
      case LocalStatus.needsModel:
        return 'Le modèle n\'est pas encore téléchargé.';
      case LocalStatus.starting:
        return 'Chargement du modèle…';
      case LocalStatus.ready:
        return 'Prêt : $running tourne dans Fractus.';
      case LocalStatus.error:
        return error ?? 'Erreur';
    }
  }

  // ── Dossiers ──────────────────────────────────────────────────────────────

  Future<Directory> _engineDir() async {
    final d = Directory('${(await Settings.dir()).path}${Platform.pathSeparator}engine');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> _modelsDir() async {
    final d = Directory('${(await Settings.dir()).path}${Platform.pathSeparator}models');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File?> _serverExe() async {
    final d = await _engineDir();
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('llama-server.exe')) return e;
    }
    return null;
  }

  /// « qwen3:1.7b » → « qwen3-1.7b.gguf » ; « user/repo:tag » → « user_repo-tag.gguf ».
  static String fileNameFor(String model) {
    final m = normalize(model);
    return '${m.replaceAll('/', '_').replaceAll(':', '-')}.gguf';
  }

  /// Toujours « nom:tag » (tag « latest » par défaut).
  static String normalize(String model) {
    final t = model.trim().toLowerCase();
    return t.contains(':') ? t : '$t:latest';
  }

  Future<File> modelFile(String model) async => File('${(await _modelsDir()).path}${Platform.pathSeparator}${fileNameFor(model)}');

  Future<bool> hasModel(String model) async {
    final f = await modelFile(model);
    return await f.exists() && await f.length() > 50 * 1024 * 1024;
  }

  /// Les modèles déjà téléchargés (noms « nom:tag »).
  Future<List<String>> installedModels() async {
    final out = <String>[];
    await for (final e in (await _modelsDir()).list()) {
      if (e is File && e.path.endsWith('.gguf')) {
        final base = e.uri.pathSegments.last.replaceAll('.gguf', '');
        final i = base.lastIndexOf('-');
        out.add(i > 0 ? '${base.substring(0, i)}:${base.substring(i + 1)}'.replaceAll('_', '/') : base);
      }
    }
    out.sort();
    return out;
  }

  // ── État ──────────────────────────────────────────────────────────────────

  Future<bool> _ping() async {
    try {
      final res = await http.get(Uri.parse('$host/health')).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> refresh(String model) async {
    if (_busy) return;
    if (_proc != null && running == normalize(model) && await _ping()) {
      status = LocalStatus.ready;
      notifyListeners();
      return;
    }
    if (await _serverExe() == null) {
      status = LocalStatus.needsRuntime;
    } else if (!await hasModel(model)) {
      status = LocalStatus.needsModel;
    } else {
      status = LocalStatus.unknown; // tout est là, il ne reste qu'à lancer
    }
    notifyListeners();
  }

  /// Tout préparer et lancer : moteur, modèle, serveur. `onStatus` reçoit une
  /// ligne courte à montrer (le chat l'affiche pendant qu'il attend).
  Future<bool> ensure(String model, {void Function(String status)? onStatus}) async {
    if (_busy) {
      onStatus?.call(progressLabel.isEmpty ? 'préparation en cours' : progressLabel);
      return false;
    }
    _busy = true;
    void Function()? unhook;
    if (onStatus != null) {
      void relay() => onStatus(progressLabel.isEmpty ? statusLine : progressLabel);
      addListener(relay);
      unhook = () => removeListener(relay);
    }
    try {
      if (await _serverExe() == null && !await _downloadRuntime()) return false;
      if (!await hasModel(model) && !await pullModel(model)) return false;
      return await start(model);
    } finally {
      _busy = false;
      unhook?.call();
      notifyListeners();
    }
  }

  // ── Le moteur (llama-server) ──────────────────────────────────────────────

  Future<bool> _downloadRuntime() async {
    status = LocalStatus.downloadingRuntime;
    error = null;
    progress = 0;
    progressLabel = 'Recherche du moteur…';
    notifyListeners();
    try {
      // La dernière version qui a un build Windows CPU.
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=8'),
        headers: const {'User-Agent': 'Fractus (Windows)', 'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('GitHub a répondu ${res.statusCode}');
      String? url;
      String? name;
      for (final r in (jsonDecode(res.body) as List).whereType<Map>()) {
        for (final a in ((r['assets'] as List?) ?? const []).whereType<Map>()) {
          final n = '${a['name'] ?? ''}';
          if (n.startsWith('llama-') && n.endsWith('-bin-win-cpu-x64.zip')) {
            url = '${a['browser_download_url']}';
            name = n;
            break;
          }
        }
        if (url != null) break;
      }
      if (url == null) throw const FormatException('aucun build Windows trouvé');
      final dir = await _engineDir();
      final zip = File('${dir.path}${Platform.pathSeparator}$name');
      await _download(url, zip, label: 'Téléchargement du moteur');
      progressLabel = 'Installation du moteur…';
      notifyListeners();
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      for (final f in archive) {
        if (!f.isFile) continue;
        final rel = f.name.replaceAll('\\', '/');
        final out = File('${dir.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>, flush: true);
      }
      try {
        await zip.delete();
      } catch (_) {}
      if (await _serverExe() == null) throw const FormatException('llama-server.exe absent de l\'archive');
      status = LocalStatus.needsModel;
      progressLabel = '';
      notifyListeners();
      return true;
    } catch (e) {
      status = LocalStatus.error;
      error = 'Moteur impossible à récupérer : ${e.toString().replaceFirst('Exception: ', '')}';
      notifyListeners();
      return false;
    }
  }

  // ── Le modèle (bibliothèque Ollama, sans Ollama) ──────────────────────────

  /// Télécharge le GGUF de « nom:tag » depuis registry.ollama.ai, empreinte vérifiée.
  Future<bool> pullModel(String model) async {
    final full = normalize(model);
    status = LocalStatus.downloadingModel;
    error = null;
    progress = 0;
    progressLabel = 'Recherche de $full…';
    notifyListeners();
    try {
      final parts = full.split(':');
      final tag = parts.last;
      var repo = parts.first;
      if (!repo.contains('/')) repo = 'library/$repo';
      final man = await http.get(
        Uri.parse('$registry/v2/$repo/manifests/$tag'),
        headers: const {'Accept': 'application/vnd.docker.distribution.manifest.v2+json', 'User-Agent': 'Fractus (Windows)'},
      ).timeout(const Duration(seconds: 30));
      if (man.statusCode == 404) throw Exception('« $full » n\'existe pas dans la bibliothèque Ollama — vérifie le nom (ollama.com/library)');
      if (man.statusCode != 200) throw HttpException('la bibliothèque a répondu ${man.statusCode}');
      final j = jsonDecode(man.body) as Map;
      Map? layer;
      for (final l in ((j['layers'] as List?) ?? const []).whereType<Map>()) {
        if ('${l['mediaType']}' == 'application/vnd.ollama.image.model') {
          layer = l;
          break;
        }
      }
      if (layer == null) throw const FormatException('pas de fichier modèle dans ce paquet');
      final digest = '${layer['digest']}';
      final size = (layer['size'] is num) ? (layer['size'] as num).toInt() : 0;
      final to = await modelFile(full);
      final sum = await _download('$registry/v2/$repo/blobs/$digest', to, label: 'Téléchargement de $full', expectedSize: size, hash: true);
      if (digest.startsWith('sha256:') && sum != null && sum != digest.substring(7)) {
        try {
          await to.delete();
        } catch (_) {}
        throw const FormatException('fichier abîmé pendant le téléchargement (empreinte différente) — réessaie');
      }
      status = LocalStatus.unknown;
      progressLabel = '';
      notifyListeners();
      return true;
    } catch (e) {
      status = LocalStatus.error;
      error = 'Modèle impossible à récupérer : ${e.toString().replaceFirst('Exception: ', '')}';
      notifyListeners();
      return false;
    }
  }

  /// Téléchargement avec progression ; renvoie l'empreinte SHA-256 si demandée.
  Future<String?> _download(String url, File to, {required String label, int expectedSize = 0, bool hash = false}) async {
    final part = File('${to.path}.part');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Fractus (Windows)';
      final res = await client.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw HttpException('téléchargement refusé (${res.statusCode})');
      final total = res.contentLength ?? expectedSize;
      final sink = part.openWrite();
      final digest = hash ? _DigestSink() : null;
      final hasher = digest == null ? null : sha256.startChunkedConversion(digest);
      var done = 0;
      var lastPct = -1;
      var lastTick = DateTime.now();
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 120))) {
          sink.add(chunk);
          hasher?.add(chunk);
          done += chunk.length;
          final now = DateTime.now();
          if (total > 0) {
            progress = done / total;
            final pct = (progress * 100).floor();
            if (pct != lastPct || now.difference(lastTick).inMilliseconds > 700) {
              lastPct = pct;
              lastTick = now;
              progressLabel = '$label : $pct % (${_mb(done)} / ${_mb(total)} Mo)';
              notifyListeners();
            }
          } else if (now.difference(lastTick).inMilliseconds > 700) {
            lastTick = now;
            progressLabel = '$label : ${_mb(done)} Mo';
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      hasher?.close();
      if (total > 0 && done < total) throw const FormatException('téléchargement incomplet');
      if (await to.exists()) await to.delete();
      await part.rename(to.path);
      return digest?.value?.toString();
    } finally {
      client.close();
    }
  }

  static String _mb(int b) => (b / 1024 / 1024).round().toString();

  // ── Le serveur ────────────────────────────────────────────────────────────

  /// Lance llama-server sur le modèle (relance si c'en est un autre) et attend qu'il réponde.
  Future<bool> start(String model) async {
    final full = normalize(model);
    if (_proc != null && running == full && await _ping()) {
      status = LocalStatus.ready;
      notifyListeners();
      return true;
    }
    await stop();
    final exe = await _serverExe();
    if (exe == null) {
      status = LocalStatus.needsRuntime;
      notifyListeners();
      return false;
    }
    final file = await modelFile(full);
    if (!await file.exists()) {
      status = LocalStatus.needsModel;
      notifyListeners();
      return false;
    }
    status = LocalStatus.starting;
    error = null;
    progressLabel = '';
    notifyListeners();
    final tail = <String>[];
    try {
      final p = await Process.start(
        exe.path,
        [
          '-m', file.path,
          '--host', '127.0.0.1',
          '--port', '$port',
          '-c', '16384',
          '--jinja',
          '--log-disable',
        ],
        workingDirectory: exe.parent.path,
        runInShell: false,
      );
      _proc = p;
      running = full;
      void keep(String s) {
        for (final l in s.split('\n')) {
          if (l.trim().isEmpty) continue;
          tail.add(l.trim());
          if (tail.length > 12) tail.removeAt(0);
        }
      }
      p.stdout.transform(utf8.decoder).listen(keep, onError: (_) {});
      p.stderr.transform(utf8.decoder).listen(keep, onError: (_) {});
      unawaited(p.exitCode.then((code) {
        if (_proc != p) return;
        _proc = null;
        running = '';
        if (status == LocalStatus.ready || status == LocalStatus.starting) {
          status = LocalStatus.error;
          error = 'Le moteur s\'est arrêté (code $code)${tail.isEmpty ? '' : ' : ${tail.last}'}';
          notifyListeners();
        }
      }));
    } catch (e) {
      status = LocalStatus.error;
      error = 'Impossible de lancer le moteur : $e';
      notifyListeners();
      return false;
    }
    // Le chargement du modèle prend de quelques secondes à une minute.
    for (var i = 0; i < 240; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_proc == null) return false;
      if (await _ping()) {
        status = LocalStatus.ready;
        notifyListeners();
        return true;
      }
    }
    status = LocalStatus.error;
    error = 'Le moteur ne répond pas après deux minutes${tail.isEmpty ? '' : ' : ${tail.last}'}';
    notifyListeners();
    await stop();
    return false;
  }

  Future<void> stop() async {
    final p = _proc;
    _proc = null;
    running = '';
    if (p == null) return;
    try {
      p.kill();
      await p.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
