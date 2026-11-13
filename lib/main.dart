// Fractus — un petit compagnon en haut de l'écran qui surveille vos agents IA.
// Interface reprise de Coucou (Louis-CFM/coucou, code MIT) et portée en Flutter
// pour Windows. Voir README.md pour la licence des noms et du personnage.

import 'dart:async';

import 'package:flutter/material.dart';

import 'core/layout.dart';
import 'core/settings.dart';
import 'core/state.dart';
import 'island/controller.dart';
import 'island/island_widget.dart';
import 'services/chat_service.dart';
import 'services/demo.dart';
import 'services/hook_server.dart';
import 'services/window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowService.prepare();

  final settings = await Settings.load();
  final state = AppState(settings);
  final controller = IslandController(state);
  final window = WindowService(state, controller);
  final hooks = HookServer(controller);
  final demo = Demo(controller);
  final chat = ChatService(apiKey: settings.anthropicApiKey, model: settings.chatModel);
  state.addListener(() {
    chat.apiKey = state.settings.anthropicApiKey;
    chat.model = state.settings.chatModel;
  });

  runApp(FractusApp(
    state: state,
    controller: controller,
    window: window,
    hooks: hooks,
    demo: demo,
    chat: chat,
  ));

  await window.show();
  await hooks.start(settings.hookPort);
  state.touch();

  // Le salut au lancement : Mochi sort, fait coucou, puis se retire.
  if (settings.greetOnLaunch) {
    Timer(const Duration(milliseconds: 600), () {
      controller.open(IslandView.greeting);
      Timer(const Duration(milliseconds: 450), controller.bot.greet);
      Timer(const Duration(milliseconds: 2900), () {
        if (state.view == IslandView.greeting) {
          state.setView(state.defaultView());
          controller.close();
          Timer(const Duration(milliseconds: 1200), controller.hide);
        }
      });
    });
  }
}

class FractusApp extends StatelessWidget {
  const FractusApp({
    super.key,
    required this.state,
    required this.controller,
    required this.window,
    required this.hooks,
    required this.demo,
    required this.chat,
  });

  final AppState state;
  final IslandController controller;
  final WindowService window;
  final HookServer hooks;
  final Demo demo;
  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fractus',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(primary: Color(0xFF3B9EFF), surface: Color(0xFF141518)),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: IslandWidget(
          state: state,
          controller: controller,
          chat: chat,
          hookPort: () => hooks.port,
          hookError: () => hooks.error,
          onDemo: () {
            demo.start();
            controller.open(state.defaultView());
          },
          onQuit: () async {
            demo.stop();
            await hooks.stop();
            await window.quit();
          },
          onRestartHooks: () async {
            await hooks.start(state.settings.hookPort);
            state.touch();
          },
        ),
      ),
    );
  }
}
