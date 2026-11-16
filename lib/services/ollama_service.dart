// Ollama sur ce PC : le moteur local du chat. Fractus sait l'installer
// (OllamaSetup.exe depuis GitHub, silencieux, par utilisateur), le lancer,
// télécharger un modèle, et dire où il en est. Rien ne sort de la machine.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/settings.dart';

enum OllamaStatus { unknown, absent, installing, stopped, starting, ready, pulling, error }

class OllamaModel {
  const OllamaModel(this.name, {this.size = 0, this.families = const []});
  final String name;
  final int size;
  final List<String> families;

  /// Un modèle qui voit les images (clip / mllama / qwen2vl / gemma3…).
  bool get vision =>
      families.any((f) => f == 'clip' || f == 'mllama' || f.contains('vl') || f == 'gemma3' || f == 'mistral3') ||
      RegExp(r'vl|llava|vision|minicpm-v|moondream|gemma3').hasMatch(name.toLowerCase());
}

class OllamaService extends ChangeNotifier {
  OllamaService();

  static const String host = 'http://127.0.0.1:11434';
  static const String setupUrl = 'https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe';

  OllamaStatus status = OllamaStatus.unknown;
  String? error;
  String version = '';
  List<OllamaModel> models = const [];

  /// Progression de l'installation ou du téléchargement d'un modèle (0..1), et sa légende.
  double progress = 0;
  String progressLabel = '';

  /// Le modèle en cours de téléchargement.
  String? pulling;

  bool get ready => status == OllamaStatus.ready || status == OllamaStatus.pulling;
  bool get busy => status == OllamaStatus.installing || status == OllamaStatus.starting || status == OllamaStatus.pulling;

  bool hasModel(String name) {
    final n = _norm(name);
    return models.any((m) => _norm(m.name) == n);
  }

  static String _norm(String n) => n.contains(':') ? n.toLowerCase() : '${n.toLowerCase()}:latest';

  /// Une courte ligne d'état pour les réglages et le téléphone.
  String get statusLine {
    switch (status) {
      case OllamaStatus.unknown:
        return 'Vérification…';
      case OllamaStatus.absent:
        return 'Ollama n\'est pas installé sur ce PC.';
      case OllamaStatus.installing:
        return progressLabel.isEmpty ? 'Installation d\'Ollama…' : progressLabel;
      case OllamaStatus.stopped:
        return 'Ollama est installé mais ne tourne pas.';
      case OllamaStatus.starting:
        return 'Démarrage d\'Ollama…';
      case OllamaStatus.ready:
        return 'Ollama ${version.isEmpty ? '' : version} prêt · ${models.length} modèle${models.length > 1 ? 's' : ''}';
      case OllamaStatus.pulling:
        return progressLabel.isEmpty ? 'Téléchargement de $pulling…' : progressLabel;
      case OllamaStatus.error:
        return error ?? 'Erreur';
    }
  }

  // ── Où est l'exécutable ───────────────────────────────────────────────────

  Future<File?> _findExe() async {
    if (!Platform.isWindows) return null;
    final env = Platform.environment;
    final candidates = <String>[
      '${env['LOCALAPPDATA'] ?? ''}\\Programs\\Ollama\\ollama.exe',
      '${env['ProgramFiles'] ?? ''}\\Ollama\\ollama.exe',
      '${(await Settings.dir()).path}\\ollama\\ollama.exe',
    ];
    for (final c in candidates) {
      if (c.startsWith('\\')) continue;
      final f = File(c);
      if (await f.exists()) return f;
    }
    try {
      final r = await Process.run('where.exe', ['ollama.exe']).timeout(const Duration(seconds: 5));
      final out = (r.stdout as String).trim().split(RegExp(r'\r?\n')).first.trim();
      if (r.exitCode == 0 && out.isNotEmpty && await File(out).exists()) return File(out);
    } catch (_) {}
    return null;
  }

  // ── Le serveur ────────────────────────────────────────────────────────────

  Future<bool> _ping() async {
    try {
      final res = await http.get(Uri.parse('$host/api/version')).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return false;
      final j = jsonDecode(res.body);
      version = (j is Map ? j['version'] : '')?.toString() ?? '';
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshModels() async {
    try {
      final res = await http.get(Uri.parse('$host/api/tags')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body);
      final list = ((j is Map ? j['models'] : null) as List?) ?? const [];
      models = [
        for (final m in list.whereType<Map>())
          OllamaModel(
            '${m['name'] ?? m['model'] ?? ''}',
            size: (m['size'] is num) ? (m['size'] as num).toInt() : 0,
            families: (((m['details'] as Map?)?['families'] as List?) ?? const []).map((e) => '$e').toList(),
          ),
      ]..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    } catch (_) {}
  }

  /// Où en est-on : installé ? lancé ? quels modèles ?
  Future<void> refresh() async {
    if (busy) return;
    if (await _ping()) {
      status = OllamaStatus.ready;
      error = null;
      notifyListeners();
      await refreshModels();
      return;
    }
    final exe = await _findExe();
    status = exe == null ? OllamaStatus.absent : OllamaStatus.stopped;
    notifyListeners();
  }

  /// Lance `ollama serve` (détaché) et attend qu'il réponde.
  Future<bool> start() async {
    if (await _ping()) {
      status = OllamaStatus.ready;
      notifyListeners();
      await refreshModels();
      return true;
    }
    final exe = await _findExe();
    if (exe == null) {
      status = OllamaStatus.absent;
      notifyListeners();
      return false;
    }
    status = OllamaStatus.starting;
    error = null;
    notifyListeners();
    try {
      await Process.start(
        exe.path,
        ['serve'],
        mode: ProcessStartMode.detached,
        environment: {
          ...Platform.environment,
          // Assez de contexte pour le prompt de Fractus et ses outils.
          'OLLAMA_CONTEXT_LENGTH': '16384',
        },
      );
    } catch (e) {
      status = OllamaStatus.error;
      error = 'Impossible de lancer Ollama : $e';
      notifyListeners();
      return false;
    }
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await _ping()) {
        status = OllamaStatus.ready;
        notifyListeners();
        await refreshModels();
        return true;
      }
    }
    status = OllamaStatus.error;
    error = 'Ollama ne répond pas après son lancement.';
    notifyListeners();
    return false;
  }

  // ── Installation ──────────────────────────────────────────────────────────

  /// Télécharge OllamaSetup.exe (GitHub) et l'installe en silence, pour cet utilisateur.
  Future<bool> install() async {
    if (busy) return false;
    status = OllamaStatus.installing;
    error = null;
    progress = 0;
    progressLabel = 'Téléchargement d\'Ollama…';
    notifyListeners();
    try {
      final dir = await Settings.dir();
      final setup = File('${dir.path}${Platform.pathSeparator}OllamaSetup.exe');
      await _download(setupUrl, setup, label: 'Téléchargement d\'Ollama');
      progressLabel = 'Installation d\'Ollama (une minute)…';
      progress = 0;
      notifyListeners();
      final r = await Process.run(setup.path, ['/VERYSILENT', '/NORESTART', '/SP-', '/SUPPRESSMSGBOXES'])
          .timeout(const Duration(minutes: 10));
      if (r.exitCode != 0) throw Exception('l\'installateur a renvoyé ${r.exitCode}');
      try {
        await setup.delete();
      } catch (_) {}
      // L'installateur lance l'appli Ollama (icône dans la zone de notification) ; sinon on la lance.
      for (var i = 0; i < 20; i++) {
        if (await _ping()) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      status = OllamaStatus.stopped;
      return await start();
    } catch (e) {
      status = OllamaStatus.error;
      error = 'Installation d\'Ollama impossible : ${e.toString().replaceFirst('Exception: ', '')}';
      notifyListeners();
      return false;
    }
  }

  Future<void> _download(String url, File to, {required String label}) async {
    final part = File('${to.path}.part');
    final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Fractus (Windows)';
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw HttpException('téléchargement refusé (${res.statusCode})');
      final total = res.contentLength ?? 0;
      final sink = part.openWrite();
      var done = 0;
      var lastPct = -1;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          done += chunk.length;
          if (total > 0) {
            progress = done / total;
            final pct = (progress * 100).floor();
            if (pct != lastPct) {
              lastPct = pct;
              progressLabel = '$label : $pct % (${_mb(done)} / ${_mb(total)} Mo)';
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (done < 1024 * 1024) throw const FormatException('fichier téléchargé incomplet');
      if (await to.exists()) await to.delete();
      await part.rename(to.path);
    } finally {
      client.close();
    }
  }

  static String _mb(int b) => (b / 1024 / 1024).round().toString();

  // ── Les modèles ───────────────────────────────────────────────────────────

  /// `ollama pull`, avec la progression.
  Future<bool> pull(String name) async {
    final model = name.trim();
    if (model.isEmpty || busy) return false;
    if (!await _ping() && !await start()) return false;
    status = OllamaStatus.pulling;
    pulling = model;
    progress = 0;
    progressLabel = 'Téléchargement de $model…';
    error = null;
    notifyListeners();
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$host/api/pull'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({'model': model, 'stream': true});
      final res = await client.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        final text = await res.stream.bytesToString();
        throw Exception(_err(text, res.statusCode));
      }
      var lastPct = -1;
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(minutes: 5))) {
        if (line.trim().isEmpty) continue;
        Map j;
        try {
          j = jsonDecode(line) as Map;
        } catch (_) {
          continue;
        }
        if (j['error'] != null) throw Exception(_err(line, 0));
        final st = '${j['status'] ?? ''}';
        final total = (j['total'] is num) ? (j['total'] as num).toInt() : 0;
        final done = (j['completed'] is num) ? (j['completed'] as num).toInt() : 0;
        if (total > 0) {
          progress = done / total;
          final pct = (progress * 100).floor();
          if (pct != lastPct) {
            lastPct = pct;
            progressLabel = 'Téléchargement de $model : $pct % (${_mb(done)} / ${_mb(total)} Mo)';
            notifyListeners();
          }
        } else if (st.isNotEmpty) {
          progressLabel = '$model : $st';
          notifyListeners();
        }
      }
      status = OllamaStatus.ready;
      pulling = null;
      progressLabel = '';
      notifyListeners();
      await refreshModels();
      return hasModel(model);
    } catch (e) {
      status = OllamaStatus.error;
      pulling = null;
      error = 'Téléchargement de $model impossible : ${e.toString().replaceFirst('Exception: ', '')}';
      notifyListeners();
      return false;
    } finally {
      client.close();
    }
  }

  static String _err(String body, int status) {
    try {
      final j = jsonDecode(body);
      final e = j is Map ? j['error'] : null;
      if (e != null) {
        final t = e.toString();
        if (t.contains('not found') || t.contains('file does not exist')) return 'modèle introuvable sur ollama.com — vérifie le nom';
        return t;
      }
    } catch (_) {}
    return status == 0 ? body : 'erreur $status';
  }

  /// Tout préparer d'un coup : installer si besoin, lancer, télécharger le modèle.
  Future<bool> ensure(String model) async {
    await refresh();
    if (status == OllamaStatus.absent && !await install()) return false;
    if (status == OllamaStatus.stopped && !await start()) return false;
    if (!ready) return false;
    if (!hasModel(model)) return await pull(model);
    return true;
  }
}
