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
import 'services/chat_tools.dart';
import 'services/conversation_store.dart';
import 'services/hook_server.dart';
import 'services/journal.dart';
import 'services/memory.dart';
import 'services/remote_server.dart';
import 'services/startup_service.dart';
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'services/window_service.dart';

late TrayService tray;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowService.prepare();

  final settings = await Settings.load();
  final state = AppState(settings);
  final controller = IslandController(state);
  // La mémoire : conversations, mémoire longue, journal d'activité.
  final conversations = ConversationStore();
  await conversations.refresh();
  state.conversations = conversations;
  final latest = await conversations.loadLatest();
  // On reprend la dernière conversation si elle est récente (moins de 12 h).
  if (latest != null && DateTime.now().difference(latest.updated) < const Duration(hours: 12)) {
    state.conversation = latest;
  }
  final journal = Journal();
  await journal.load();
  final memory = LongTermMemory();
  final window = WindowService(state, controller);
  final hooks = HookServer(controller);
  final chat = ChatService(
    apiKey: settings.chatApiKey,
    model: settings.chatModel,
    webSearch: settings.chatWebSearch,
    tools: ChatTools(state, controller: controller)
      ..workspace = settings.chatWorkspace
      ..journal = journal
      ..memory = memory,
  );
  state.addListener(() {
    chat.apiKey = state.settings.chatApiKey;
    chat.model = state.settings.chatModel;
    chat.webSearch = state.settings.chatWebSearch;
    chat.tools.workspace = state.settings.chatWorkspace;
  });
  final startup = StartupService();
  final updates = UpdateService(autoCheck: settings.autoUpdate);
  // Le téléphone : serveur sur le réseau local, protégé par le code d'appairage.
  final remote = RemoteServer(state: state, controller: controller, chat: chat, tools: chat.tools, version: () => updates.currentVersion, journal: journal, memory: memory);
  Future<void> applyRemote() async {
    if (state.settings.remoteEnabled) {
      if (state.settings.remoteToken.isEmpty) {
        state.settings.remoteToken = Settings.newRemoteToken();
        await state.settings.save();
      }
      await remote.start(state.settings.remotePort);
    } else {
      await remote.stop();
    }
    state.touch();
  }

  Future<void> quit() async {
    await conversations.flush();
    await journal.flush();
    await remote.stop();
    await hooks.stop();
    await tray.stop();
    await window.quit();
  }

  tray = TrayService(
    state: state,
    controller: controller,
    onCheckUpdates: () {
      controller.open(IslandView.update);
      updates.check();
    },
    onQuit: quit,
  );

  // Une nouvelle version : l'île s'ouvre sur la carte de mise à jour.
  updates.onAvailable = (_) => controller.alert(IslandView.update);
  // Avant l'installateur : on coupe le serveur et l'icône, la fenêtre suit.
  updates.onBeforeInstall = () async {
    await conversations.flush();
    await journal.flush();
    await remote.stop();
    await hooks.stop();
    await tray.stop();
  };

  runApp(FractusApp(
    state: state,
    controller: controller,
    window: window,
    hooks: hooks,
    chat: chat,
    updates: updates,
    onQuit: quit,
    onStartupChanged: startup.apply,
    journal: journal,
    memory: memory,
    remote: remote,
    onRemoteChanged: applyRemote,
  ));

  await window.show();
  await hooks.start(settings.hookPort);
  await applyRemote();
  await tray.start();
  await startup.init();
  await startup.apply(settings.launchAtStartup);
  await updates.init();
  state.touch();

  // Le salut au lancement : Fractus sort, fait coucou, puis se retire.
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
    required this.chat,
    required this.updates,
    required this.onQuit,
    required this.onStartupChanged,
    required this.journal,
    required this.memory,
    required this.remote,
    required this.onRemoteChanged,
  });

  final AppState state;
  final IslandController controller;
  final WindowService window;
  final HookServer hooks;
  final ChatService chat;
  final UpdateService updates;
  final Future<void> Function() onQuit;
  final ValueChanged<bool> onStartupChanged;
  final Journal journal;
  final LongTermMemory memory;
  final RemoteServer remote;
  final Future<void> Function() onRemoteChanged;

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
          onQuit: onQuit,
          onRestartHooks: () async {
            await hooks.start(state.settings.hookPort);
            state.touch();
          },
          updates: updates,
          onStartupChanged: onStartupChanged,
          journal: journal,
          memory: memory,
          remote: remote,
          onRemoteChanged: onRemoteChanged,
        ),
      ),
    );
  }
}
