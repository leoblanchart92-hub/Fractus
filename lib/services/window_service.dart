// La fenêtre : un panneau transparent de 720×320 collé en haut au centre de
// l'écran, toujours au premier plan, absent de la barre des tâches. Elle laisse
// passer la souris partout sauf sur l'île, et suit le curseur pour réveiller
// l'île (bande de 240×6 en haut) et faire suivre le regard de Mochi.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/layout.dart';
import '../core/state.dart';
import '../island/controller.dart';

class WindowService {
  WindowService(this.state, this.controller);

  final AppState state;
  final IslandController controller;

  Offset origin = Offset.zero;
  Timer? _poll;
  bool _ignoring = false;
  bool _busy = false;

  /// À appeler avant runApp.
  static Future<void> prepare() async {
    await windowManager.ensureInitialized();
    await Window.initialize();
  }

  Future<void> show() async {
    const options = WindowOptions(
      size: Size(panelW, panelH),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setHasShadow(false);
      await Window.setEffect(effect: WindowEffect.transparent, color: Colors.transparent);
      await placeAtTop();
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
    });
    controller.onWake = () => _setIgnore(false);
    _poll = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  Future<void> placeAtTop() async {
    try {
      final d = await screenRetriever.getPrimaryDisplay();
      final x = ((d.size.width - panelW) / 2).roundToDouble();
      origin = Offset(x, 0);
      await windowManager.setPosition(origin);
      await windowManager.setSize(const Size(panelW, panelH));
    } catch (_) {}
  }

  Future<void> _setIgnore(bool v) async {
    if (_ignoring == v) return;
    _ignoring = v;
    try {
      await windowManager.setIgnoreMouseEvents(v, forward: true);
    } catch (_) {}
  }

  /// Le rectangle de l'île dans la fenêtre, pour le mode et la vue actuels.
  Rect islandRect() {
    final s = islandSize(
      state.mode,
      state.view,
      chatCount: state.chat.length,
      questionPicker: state.pendingApproval?.isQuestion == true,
    );
    return Rect.fromLTWH((panelW - s.width) / 2, 0, s.width, s.height);
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      final local = cursor - origin;
      final rect = islandRect();
      final wake = Rect.fromLTWH((panelW - wakeStripW) / 2, 0, wakeStripW, wakeStripH + 2);
      final inside = (state.mode == IslandMode.hidden)
          ? wake.contains(local)
          : rect.inflate(8).contains(local) || wake.contains(local);
      controller.pointerInside(inside);

      // Le regard de Mochi suit le curseur, de près comme de loin.
      final bp = botPosition(state.mode, state.view, rect.height);
      final bx = rect.left + bp.cx;
      final by = rect.top + bp.cy;
      controller.look((local.dx - bx) / 220, (local.dy - by) / 160);

      await _setIgnore(!inside);
    } catch (_) {
      // Pas de curseur global (session verrouillée…) : on attend le prochain tour.
    } finally {
      _busy = false;
    }
  }

  Future<void> quit() async {
    _poll?.cancel();
    await windowManager.destroy();
  }

  void dispose() {
    _poll?.cancel();
  }
}
