// L'icône dans la zone de notification : Fractus tourne en arrière-plan, sans
// fenêtre dans la barre des tâches. Clic gauche → ouvre l'île ; clic droit →
// menu (ouvrir, réglages, mises à jour, quitter).

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:tray_manager/tray_manager.dart';

import '../core/layout.dart';
import '../core/state.dart';
import '../island/controller.dart';

class TrayService with TrayListener {
  TrayService({
    required this.state,
    required this.controller,
    required this.onCheckUpdates,
    required this.onQuit,
  });

  final AppState state;
  final IslandController controller;
  final VoidCallback onCheckUpdates;
  final Future<void> Function() onQuit;

  static const _open = 'open';
  static const _settings = 'settings';
  static const _updates = 'updates';
  static const _quit = 'quit';

  Future<void> start() async {
    try {
      trayManager.addListener(this);
      await trayManager.setIcon('assets/fractus.ico');
      await trayManager.setToolTip('Fractus');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: _open, label: 'Ouvrir Fractus'),
        MenuItem(key: _settings, label: 'Réglages'),
        MenuItem.separator(),
        MenuItem(key: _updates, label: 'Vérifier les mises à jour'),
        MenuItem.separator(),
        MenuItem(key: _quit, label: 'Quitter Fractus'),
      ]));
    } catch (_) {
      // Sans icône, Fractus reste utilisable : l'île répond toujours à la souris en haut de l'écran.
    }
  }

  Future<void> stop() async {
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    controller.open(state.defaultView());
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _open:
        controller.open(state.defaultView());
      case _settings:
        controller.open(IslandView.settings);
      case _updates:
        onCheckUpdates();
      case _quit:
        onQuit();
    }
  }
}
