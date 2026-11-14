// Le canal vers le code Android natif (MainActivity.kt) : version, lien
// d'appairage, permission de notifier, service de fond, installation d'un APK.

import 'package:flutter/services.dart';

class Native {
  static const MethodChannel _ch = MethodChannel('app.fractus/native');

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// La version installée (versionName), ex. « 0.10.0 ».
  static Future<String> versionName() async => (await _call<String>('versionName')) ?? '';

  /// Le lien `fractus://pair?...` qui a ouvert l'appli, une seule fois.
  static Future<String?> launchLink() => _call<String>('launchLink');

  /// Demande la permission de notifier (Android 13+). Vrai si déjà accordée.
  static Future<bool> requestNotifications() async => (await _call<bool>('requestNotifications')) ?? false;

  static Future<void> startService() => _call<bool>('startService');
  static Future<void> stopService() => _call<bool>('stopService');
  static Future<bool> serviceRunning() async => (await _call<bool>('serviceRunning')) ?? false;

  static Future<String> cacheDir() async => (await _call<String>('cacheDir')) ?? '';

  /// Ouvre l'installateur Android sur un APK du dossier cache.
  static Future<bool> installApk(String path) async => (await _call<bool>('installApk', {'path': path})) ?? false;
}
