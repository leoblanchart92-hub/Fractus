// La mise à jour de l'appli : on regarde la dernière Release GitHub, on
// télécharge l'APK dans le cache, et on tend le fichier à l'installateur
// Android. Un seul GET sur api.github.com, c'est tout.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'native.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, ready, error }

class Updater extends ChangeNotifier {
  Updater({this.repo = 'leoblanchart92-hub/Fractus'});
  final String repo;

  UpdateStatus status = UpdateStatus.idle;
  String currentVersion = '';
  String? latestVersion;
  String? apkUrl;
  String? error;
  double progress = 0;
  String? _file;

  bool get available => status == UpdateStatus.available || status == UpdateStatus.downloading || status == UpdateStatus.ready;

  Future<void> check() async {
    if (status == UpdateStatus.checking || status == UpdateStatus.downloading) return;
    status = UpdateStatus.checking;
    error = null;
    notifyListeners();
    try {
      if (currentVersion.isEmpty) currentVersion = await Native.versionName();
      final r = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Fractus-Android'},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw HttpException('GitHub a répondu ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = '${j['tag_name'] ?? ''}';
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      String? url;
      for (final a in (j['assets'] as List? ?? const [])) {
        if (a is Map && '${a['name']}' == 'Fractus-Android.apk') url = '${a['browser_download_url']}';
      }
      latestVersion = version;
      apkUrl = url;
      status = url != null && _newer(version, currentVersion) ? UpdateStatus.available : UpdateStatus.upToDate;
    } catch (e) {
      status = UpdateStatus.error;
      error = e is SocketException ? 'Pas d\'accès à GitHub' : e.toString();
    }
    notifyListeners();
  }

  Future<void> download() async {
    final url = apkUrl;
    if (url == null || status == UpdateStatus.downloading) return;
    status = UpdateStatus.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final dir = await Native.cacheDir();
      if (dir.isEmpty) throw const FileSystemException('Dossier cache introuvable');
      final file = File('$dir/Fractus-Android.apk');
      final client = http.Client();
      try {
        final res = await client.send(http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Fractus-Android');
        if (res.statusCode != 200) throw HttpException('Téléchargement refusé (${res.statusCode})');
        final total = res.contentLength ?? 0;
        var done = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in res.stream) {
            sink.add(chunk);
            done += chunk.length;
            if (total > 0) {
              final p = done / total;
              if (p - progress > 0.01) {
                progress = p;
                notifyListeners();
              }
            }
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }
      _file = file.path;
      progress = 1;
      status = UpdateStatus.ready;
      notifyListeners();
      await install();
    } catch (e) {
      status = UpdateStatus.error;
      error = e is SocketException ? 'Pas d\'accès à GitHub' : e.toString();
      notifyListeners();
    }
  }

  /// Rouvre l'installateur (si l'utilisateur l'a fermé).
  Future<void> install() async {
    final f = _file;
    if (f == null) return;
    final ok = await Native.installApk(f);
    if (!ok) {
      status = UpdateStatus.error;
      error = 'Impossible d\'ouvrir l\'installateur';
      notifyListeners();
    }
  }

  static bool _newer(String a, String b) {
    List<int> parse(String v) => v.split(RegExp(r'[^0-9]+')).where((p) => p.isNotEmpty).map(int.parse).toList();
    final x = parse(a), y = parse(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }
}

/// L'instance partagée par toute l'appli.
final Updater updater = Updater();
