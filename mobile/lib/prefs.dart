// La connexion au PC (adresse, port, code), gardée sur le téléphone — et
// recopiée dans les données du widget pour que ses boutons marchent sans l'appli.

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PcConnectionInfo {
  PcConnectionInfo({required this.host, required this.port, required this.token, List<String>? hosts})
      : hosts = _merge(host, hosts ?? const []);

  /// L'adresse en cours d'utilisation.
  final String host;
  final int port;
  final String token;

  /// Toutes les adresses connues du PC (Wi-Fi à la maison, tunnel Internet ailleurs),
  /// `host` en premier : on essaie dans l'ordre jusqu'à ce qu'une réponde.
  final List<String> hosts;

  /// Une adresse peut être une IP du réseau Wi-Fi ou l'URL complète
  /// du tunnel Internet du PC (https://….trycloudflare.com).
  String get baseUrl => baseUrlOf(host, port);

  static String baseUrlOf(String h, int port) => isTunnel(h) ? h.replaceAll(RegExp(r'/+$'), '') : 'http://$h:$port';

  static bool isTunnel(String a) => a.startsWith('https://') || a.startsWith('http://');

  static List<String> _merge(String first, List<String> others) {
    final out = <String>[];
    for (final h in [first, ...others]) {
      final t = h.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  PcConnectionInfo withHost(String h) => PcConnectionInfo(host: h, port: port, token: token, hosts: hosts);

  PcConnectionInfo withHosts(List<String> more) => PcConnectionInfo(host: host, port: port, token: token, hosts: [...hosts, ...more]);

  /// « Internet » ou « Wi-Fi » : par où on passe.
  static String networkLabel(String a) => isTunnel(a) ? 'Internet' : 'Wi-Fi';

  /// Le lien d'appairage du QR code du PC : `fractus://pair?host=…&hosts=a,b&port=…&code=…`.
  static PcConnectionInfo? fromPairLink(String link) {
    final u = Uri.tryParse(link.trim());
    if (u == null || u.scheme != 'fractus' || u.host != 'pair') return null;
    final host = u.queryParameters['host'] ?? '';
    final code = u.queryParameters['code'] ?? '';
    if (host.isEmpty || code.isEmpty) return null;
    final port = int.tryParse(u.queryParameters['port'] ?? '') ?? 7790;
    final hosts = (u.queryParameters['hosts'] ?? '').split(',');
    return PcConnectionInfo(host: host, port: port, token: code.trim().toUpperCase(), hosts: hosts);
  }

  /// « 192.168.1.20:7790 », « 192.168.1.20 » (port par défaut) ou l'URL du tunnel.
  static PcConnectionInfo parse(String address, String token) {
    final raw = address.trim();
    if (raw.startsWith('https://') || raw.contains('trycloudflare.com')) {
      final u = raw.startsWith('http') ? raw : 'https://$raw';
      return PcConnectionInfo(host: u.replaceAll(RegExp(r'/+$'), ''), port: 443, token: token.trim().toUpperCase());
    }
    var a = raw.replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), '');
    var port = 7790;
    final i = a.lastIndexOf(':');
    if (i > 0 && int.tryParse(a.substring(i + 1)) != null) {
      port = int.parse(a.substring(i + 1));
      a = a.substring(0, i);
    }
    return PcConnectionInfo(host: a, port: port, token: token.trim().toUpperCase());
  }
}

class Prefs {
  static Future<PcConnectionInfo?> load() async {
    final p = await SharedPreferences.getInstance();
    final host = p.getString('host') ?? '';
    if (host.isEmpty) return null;
    return PcConnectionInfo(
      host: host,
      port: p.getInt('port') ?? 7790,
      token: p.getString('token') ?? '',
      hosts: (p.getString('hosts') ?? '').split(','),
    );
  }

  static Future<void> save(PcConnectionInfo i) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('host', i.host);
    await p.setInt('port', i.port);
    await p.setString('token', i.token);
    // Le service natif lit `flutter.hosts` (séparées par des virgules).
    await p.setString('hosts', i.hosts.join(','));
    await HomeWidget.saveWidgetData<String>('host', i.host);
    await HomeWidget.saveWidgetData<int>('port', i.port);
    await HomeWidget.saveWidgetData<String>('token', i.token);
  }

  /// Notifications en arrière-plan (le service natif lit la même clé : `flutter.bg_notify`).
  static Future<bool> notifyEnabled() async => (await SharedPreferences.getInstance()).getBool('bg_notify') ?? false;

  static Future<void> setNotifyEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool('bg_notify', v);

  /// Depuis le widget (isolat de fond) : les mêmes infos, lues côté widget.
  static Future<PcConnectionInfo?> loadForWidget() async {
    final host = await HomeWidget.getWidgetData<String>('host') ?? '';
    if (host.isEmpty) return load();
    return PcConnectionInfo(
      host: host,
      port: await HomeWidget.getWidgetData<int>('port') ?? 7790,
      token: await HomeWidget.getWidgetData<String>('token') ?? '',
    );
  }
}
