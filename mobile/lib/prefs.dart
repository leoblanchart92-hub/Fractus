// La connexion au PC (adresse, port, code), gardée sur le téléphone — et
// recopiée dans les données du widget pour que ses boutons marchent sans l'appli.

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PcConnectionInfo {
  const PcConnectionInfo({required this.host, required this.port, required this.token});
  final String host;
  final int port;
  final String token;

  String get baseUrl => 'http://$host:$port';

  /// « 192.168.1.20:7790 » ou « 192.168.1.20 » (port par défaut).
  static PcConnectionInfo parse(String address, String token) {
    var a = address.trim().replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), '');
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
    return PcConnectionInfo(host: host, port: p.getInt('port') ?? 7790, token: p.getString('token') ?? '');
  }

  static Future<void> save(PcConnectionInfo i) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('host', i.host);
    await p.setInt('port', i.port);
    await p.setString('token', i.token);
    await HomeWidget.saveWidgetData<String>('host', i.host);
    await HomeWidget.saveWidgetData<int>('port', i.port);
    await HomeWidget.saveWidgetData<String>('token', i.token);
  }

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
