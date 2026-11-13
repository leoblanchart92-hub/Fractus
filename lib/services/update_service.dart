// Mises à jour : Fractus interroge les Releases GitHub du dépôt, compare la
// version publiée à la sienne, télécharge l'installateur (Fractus-Setup-x.y.z.exe)
// dans %TEMP% et le lance en silencieux. L'installateur ferme Fractus, remplace
// les fichiers et le relance. Rien d'autre ne sort de la machine : une requête
// GET sur api.github.com, c'est tout.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, error }

class UpdateInfo {
  const UpdateInfo({required this.version, required this.url, required this.notes, required this.size});
  final String version;
  final String url;
  final String notes;
  final int size;
}

class UpdateService extends ChangeNotifier {
  UpdateService({this.repo = 'leoblanchart92-hub/Fractus', this.autoCheck = true});

  /// Dépôt GitHub « propriétaire/nom » dont on lit les Releases.
  final String repo;
  bool autoCheck;

  UpdateStatus status = UpdateStatus.idle;
  UpdateInfo? available;
  String currentVersion = '0.0.0';
  String? error;
  /// 0…1 pendant le téléchargement.
  double progress = 0;
  DateTime? lastCheck;

  /// Appelé quand une nouvelle version est trouvée (pour ouvrir l'île).
  void Function(UpdateInfo info)? onAvailable;
  /// Appelé juste avant de lancer l'installateur (pour fermer proprement).
  Future<void> Function()? onBeforeInstall;

  Timer? _timer;
  Timer? _first;
  /// Versions que l'utilisateur a remises « à plus tard » (on ne le relance pas).
  final Set<String> _snoozed = {};

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) currentVersion = info.version;
    } catch (_) {}
    notifyListeners();
    _schedule();
  }

  void setAutoCheck(bool v) {
    autoCheck = v;
    _schedule();
  }

  void _schedule() {
    _first?.cancel();
    _timer?.cancel();
    if (!autoCheck) return;
    // Un premier contrôle 25 s après le lancement, puis toutes les 6 heures.
    _first = Timer(const Duration(seconds: 25), () => check(silent: true));
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check(silent: true));
  }

  /// Cherche une nouvelle version. `silent` : ne signale pas « à jour » ni les
  /// erreurs réseau (contrôles automatiques).
  Future<void> check({bool silent = false}) async {
    if (status == UpdateStatus.checking || status == UpdateStatus.downloading || status == UpdateStatus.installing) {
      return;
    }
    status = UpdateStatus.checking;
    error = null;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Fractus/$currentVersion (Windows)',
        },
      ).timeout(const Duration(seconds: 15));
      lastCheck = DateTime.now();
      if (res.statusCode == 404) {
        // Pas encore de Release publiée.
        status = UpdateStatus.upToDate;
        notifyListeners();
        return;
      }
      if (res.statusCode != 200) throw HttpException('GitHub a répondu ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      final assets = (j['assets'] as List?) ?? const [];
      Map<String, dynamic>? setup;
      for (final a in assets) {
        final name = ((a as Map)['name'] ?? '') as String;
        if (name.toLowerCase().startsWith('fractus-setup') && name.toLowerCase().endsWith('.exe')) {
          setup = a.cast<String, dynamic>();
          break;
        }
      }
      if (version.isEmpty || setup == null || compareVersions(version, currentVersion) <= 0) {
        available = null;
        status = UpdateStatus.upToDate;
        notifyListeners();
        return;
      }
      available = UpdateInfo(
        version: version,
        url: setup['browser_download_url'] as String,
        notes: ((j['body'] ?? '') as String).trim(),
        size: (setup['size'] is int) ? setup['size'] as int : 0,
      );
      status = UpdateStatus.available;
      notifyListeners();
      if (!_snoozed.contains(version) || !silent) onAvailable?.call(available!);
    } catch (e) {
      error = silent ? null : _describe(e);
      status = silent ? UpdateStatus.idle : UpdateStatus.error;
      notifyListeners();
    }
  }

  /// « Plus tard » : on garde l'info mais on n'ouvre plus l'île pour cette version.
  void snooze() {
    final v = available?.version;
    if (v != null) _snoozed.add(v);
    notifyListeners();
  }

  /// Télécharge l'installateur puis le lance en silencieux ; Fractus se ferme.
  Future<void> install() async {
    final info = available;
    if (info == null || status == UpdateStatus.downloading || status == UpdateStatus.installing) return;
    status = UpdateStatus.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}Fractus-Setup-${info.version}.exe');
    try {
      final req = http.Request('GET', Uri.parse(info.url))..headers['User-Agent'] = 'Fractus/$currentVersion (Windows)';
      final res = await http.Client().send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('Téléchargement refusé (${res.statusCode})');
      final total = res.contentLength ?? info.size;
      final sink = file.openWrite();
      var done = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) {
          progress = done / total;
          notifyListeners();
        }
      }
      await sink.close();
      if (done < 1024 * 1024) throw const FormatException('Fichier téléchargé incomplet');

      status = UpdateStatus.installing;
      notifyListeners();
      await onBeforeInstall?.call();
      // Inno Setup : silencieux, ferme l'application en cours, relance après.
      await Process.start(
        file.path,
        const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/SP-'],
        mode: ProcessStartMode.detached,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      exit(0);
    } catch (e) {
      error = _describe(e);
      status = UpdateStatus.error;
      notifyListeners();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  String _describe(Object e) {
    if (e is SocketException) return 'Pas de connexion à GitHub.';
    if (e is TimeoutException) return 'GitHub ne répond pas.';
    return e.toString().replaceFirst('Exception: ', '');
  }

  /// Compare deux versions « x.y.z[-pré][+build] ». Négatif si a < b.
  static int compareVersions(String a, String b) {
    List<int> parse(String v) {
      final core = v.split('+').first.split('-').first;
      return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final pa = parse(a);
    final pb = parse(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    // Une pré-version (0.2.0-beta) passe avant la version finale (0.2.0).
    final preA = a.split('+').first.contains('-');
    final preB = b.split('+').first.contains('-');
    if (preA != preB) return preA ? -1 : 1;
    return 0;
  }

  @override
  void dispose() {
    _first?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
