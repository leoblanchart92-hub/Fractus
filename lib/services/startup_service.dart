// Lancement avec Windows : une valeur « Fractus » dans
// HKCU\Software\Microsoft\Windows\CurrentVersion\Run, posée ou retirée selon
// le réglage. Par utilisateur, sans droits administrateur.

import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

class StartupService {
  bool _ready = false;

  Future<void> init() async {
    try {
      launchAtStartup.setup(
        appName: 'Fractus',
        appPath: Platform.resolvedExecutable,
        args: const ['--autostart'],
      );
      _ready = true;
    } catch (_) {}
  }

  Future<void> apply(bool enabled) async {
    if (!_ready) return;
    try {
      if (enabled) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (_) {}
  }

  Future<bool> isEnabled() async {
    if (!_ready) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (_) {
      return false;
    }
  }
}
