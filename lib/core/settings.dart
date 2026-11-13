// Réglages, enregistrés dans %APPDATA%\fractus\settings.json.
// Aucune télémétrie : rien ne quitte la machine sauf vers les services configurés.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Settings {
  Settings();

  /// Ouvrir l'île en survolant l'île compacte (sinon : au clic).
  bool openOnHover = false;
  bool muted = false;
  /// Port local du serveur de hooks (l'agent y poste ses événements).
  int hookPort = 7788;
  /// Fournisseur du chat : groq (défaut), openai (ou compatible), anthropic.
  String chatProvider = 'groq';
  /// Clé API du fournisseur choisi (vide = chat désactivé).
  String chatApiKey = '';
  /// Modèle (vide = celui proposé par défaut pour le fournisseur).
  String chatModel = '';
  /// URL de base personnalisée pour un serveur compatible OpenAI (vide = officielle).
  String chatBaseUrl = '';
  /// Permissions « Toujours autoriser » : "tool|commande" → vrai.
  Set<String> alwaysAllow = {};
  /// Saluer (coucou de la main) au lancement.
  bool greetOnLaunch = true;
  /// Démarrer Fractus avec Windows (clé Run du registre, par utilisateur).
  bool launchAtStartup = true;
  /// Chercher les nouvelles versions sur GitHub (au lancement puis toutes les 6 h).
  bool autoUpdate = true;

  Map<String, dynamic> toJson() => {
        'openOnHover': openOnHover,
        'muted': muted,
        'hookPort': hookPort,
        'chatProvider': chatProvider,
        'chatApiKey': chatApiKey,
        'chatModel': chatModel,
        'chatBaseUrl': chatBaseUrl,
        'alwaysAllow': alwaysAllow.toList(),
        'greetOnLaunch': greetOnLaunch,
        'launchAtStartup': launchAtStartup,
        'autoUpdate': autoUpdate,
      };

  static Settings fromJson(Map<String, dynamic> j) {
    final s = Settings();
    s.openOnHover = j['openOnHover'] == true;
    s.muted = j['muted'] == true;
    s.hookPort = (j['hookPort'] is int) ? j['hookPort'] as int : 7788;
    s.chatProvider = (j['chatProvider'] ?? 'groq') as String;
    s.chatApiKey = (j['chatApiKey'] ?? '') as String;
    s.chatModel = (j['chatModel'] ?? '') as String;
    s.chatBaseUrl = (j['chatBaseUrl'] ?? '') as String;
    // Anciens réglages (clé Anthropic seule) : on bascule sur Anthropic.
    final legacy = (j['anthropicApiKey'] ?? '') as String;
    if (s.chatApiKey.isEmpty && legacy.isNotEmpty) {
      s.chatApiKey = legacy;
      s.chatProvider = 'anthropic';
    }
    final aa = j['alwaysAllow'];
    if (aa is List) s.alwaysAllow = aa.whereType<String>().toSet();
    s.greetOnLaunch = j['greetOnLaunch'] != false;
    s.launchAtStartup = j['launchAtStartup'] != false;
    s.autoUpdate = j['autoUpdate'] != false;
    return s;
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    final d = Directory('${dir.path}${Platform.pathSeparator}fractus');
    if (!await d.exists()) await d.create(recursive: true);
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

  Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    } catch (_) {}
  }
}
