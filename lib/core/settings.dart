// Réglages, enregistrés dans %APPDATA%\fractus\settings.json.
// Aucune télémétrie : rien ne quitte la machine sauf vers les services configurés.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class Settings {
  Settings();

  /// Ouvrir l'île en survolant l'île compacte (sinon : au clic).
  bool openOnHover = false;
  bool muted = false;
  /// Port local du serveur de hooks (l'agent y poste ses événements).
  int hookPort = 7788;
  /// Clé API Groq (gsk_…) pour le chat (vide = chat désactivé).
  String chatApiKey = '';
  /// Modèle Groq (vide = le plus capable disponible sur le compte, choisi automatiquement).
  String chatModel = '';
  /// Recherche web et exécution de code côté Groq (modèle groq/compound).
  bool chatWebSearch = false;
  /// Dossier de travail de l'agent Fractus (vide = projet de l'agent en avant, sinon le profil).
  String chatWorkspace = '';
  /// Permissions « Toujours autoriser » : "tool|commande" → vrai.
  Set<String> alwaysAllow = {};
  /// Saluer (coucou de la main) au lancement.
  bool greetOnLaunch = true;
  /// Démarrer Fractus avec Windows (clé Run du registre, par utilisateur).
  bool launchAtStartup = true;
  /// Chercher les nouvelles versions sur GitHub (au lancement puis toutes les 6 h).
  bool autoUpdate = true;
  /// Contrôle depuis le téléphone (appli Android) : serveur sur le réseau local.
  bool remoteEnabled = false;
  int remotePort = 7790;
  /// Code d'appairage (Bearer) demandé à chaque requête du téléphone.
  String remoteToken = '';

  Map<String, dynamic> toJson() => {
        'openOnHover': openOnHover,
        'muted': muted,
        'hookPort': hookPort,
        'chatApiKey': chatApiKey,
        'chatModel': chatModel,
        'chatWebSearch': chatWebSearch,
        'chatWorkspace': chatWorkspace,
        'alwaysAllow': alwaysAllow.toList(),
        'greetOnLaunch': greetOnLaunch,
        'launchAtStartup': launchAtStartup,
        'autoUpdate': autoUpdate,
        'remoteEnabled': remoteEnabled,
        'remotePort': remotePort,
        'remoteToken': remoteToken,
      };

  static Settings fromJson(Map<String, dynamic> j) {
    final s = Settings();
    s.openOnHover = j['openOnHover'] == true;
    s.muted = j['muted'] == true;
    s.hookPort = (j['hookPort'] is int) ? j['hookPort'] as int : 7788;
    s.chatApiKey = (j['chatApiKey'] ?? '') as String;
    // Un ancien réglage d'un autre fournisseur ne vaut rien chez Groq : on repart à vide.
    if (!s.chatApiKey.startsWith('gsk_')) s.chatApiKey = '';
    // Un modèle d'un autre fournisseur (claude-…, gpt-4o…) n'existe pas chez Groq.
    final m = (j['chatModel'] ?? '') as String;
    s.chatModel = (m.startsWith('claude') || m.startsWith('gpt-4') || m.startsWith('gpt-5')) ? '' : m;
    s.chatWebSearch = j['chatWebSearch'] == true;
    s.chatWorkspace = (j['chatWorkspace'] ?? '') as String;
    final aa = j['alwaysAllow'];
    if (aa is List) s.alwaysAllow = aa.whereType<String>().toSet();
    s.greetOnLaunch = j['greetOnLaunch'] != false;
    s.launchAtStartup = j['launchAtStartup'] != false;
    s.autoUpdate = j['autoUpdate'] != false;
    s.remoteEnabled = j['remoteEnabled'] == true;
    s.remotePort = (j['remotePort'] is int) ? j['remotePort'] as int : 7790;
    s.remoteToken = (j['remoteToken'] ?? '').toString();
    return s;
  }

  /// Le dossier de Fractus (%APPDATA%\\fractus) : réglages, conversations,
  /// mémoire, journal et copies de sauvegarde.
  static Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}fractus');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _file() async {
    final d = await dir();
    return File('${d.path}${Platform.pathSeparator}settings.json');
  }

  static Future<Settings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return Settings();
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map<String, dynamic>) return Settings.fromJson(raw);
    } catch (_) {}
    return Settings();
  }

  /// Un code d'appairage lisible : 8 caractères sans ambiguïté (XXXX-XXXX).
  static String newRemoteToken() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final b = StringBuffer();
    for (var i = 0; i < 8; i++) {
      if (i == 4) b.write('-');
      b.write(alphabet[r.nextInt(alphabet.length)]);
    }
    return b.toString();
  }

  /// Le code tel qu'on le compare : sans tiret ni casse.
  static String normalizeToken(String t) => t.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    } catch (_) {}
  }
}
