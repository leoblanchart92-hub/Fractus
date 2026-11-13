// Fractus sur le téléphone : voir si Fractus tourne, autoriser ses demandes,
// lui parler, voir l'écran du PC et déclencher des actions rapides.
// Tout passe par le serveur « téléphone » de Fractus sur le PC (réseau local).

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'api.dart';
import 'pages/chat.dart';
import 'pages/home.dart';
import 'pages/screen.dart';
import 'pages/settings.dart';
import 'theme.dart';
import 'widget_bridge.dart';

final link = PcLink();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HomeWidget.registerInteractivityCallback(backgroundCallback);
  await link.load();
  link.onStatus = (s) => pushStatusToWidgets(s);
  link.restart();
  runApp(const FractusMobileApp());
}

class FractusMobileApp extends StatelessWidget {
  const FractusMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fractus',
      debugShowCheckedModeBanner: false,
      theme: fractusTheme(),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!link.configured) _tab = 3;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Le flux ne vit que quand l'appli est visible (Android coupe le réseau en fond).
    if (state == AppLifecycleState.resumed) link.restart();
    if (state == AppLifecycleState.paused) link.pause();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final pages = [
          HomePage(link: link, onOpenSettings: () => setState(() => _tab = 3)),
          ChatPage(link: link),
          ScreenPage(link: link),
          SettingsPage(link: link, onSaved: () => setState(() => _tab = 0)),
        ];
        final pending = link.status?.pending != null;
        return Scaffold(
          body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                icon: Badge(isLabelVisible: pending, child: const Icon(Icons.home_rounded)),
                label: 'Fractus',
              ),
              const NavigationDestination(icon: Icon(Icons.chat_bubble_rounded), label: 'Chat'),
              const NavigationDestination(icon: Icon(Icons.desktop_windows_rounded), label: 'Écran'),
              const NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Réglages'),
            ],
          ),
        );
      },
    );
  }
}
