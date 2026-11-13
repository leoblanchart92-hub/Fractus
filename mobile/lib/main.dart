// Fractus sur le téléphone : la même île que sur le PC — Fractus, ses cartes,
// ses étapes en direct — posée en haut de l'écran, au-dessus de l'écran du PC.
// Tout passe par le serveur « téléphone » de Fractus sur le PC (réseau local).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'api.dart';
import 'companion/bot_engine.dart';
import 'core/theme.dart';
import 'island/phone_island.dart';
import 'widget_bridge.dart';

final link = PcLink();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HomeWidget.registerInteractivityCallback(backgroundCallback);
  await link.load();
  link.onStatus = (s) => pushStatusToWidgets(s);
  link.restart();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF05060B),
  ));
  runApp(const FractusMobileApp());
}

class FractusMobileApp extends StatelessWidget {
  const FractusMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fractus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05060B),
        colorScheme: const ColorScheme.dark(
          primary: Palette.accent,
          secondary: Palette.accent3,
          surface: Palette.card,
          error: Palette.red,
        ),
        popupMenuTheme: const PopupMenuThemeData(color: Palette.card),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.blue : Palette.dim3),
          trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.blue.withValues(alpha: 0.35) : Palette.tabOn),
        ),
        textSelectionTheme: const TextSelectionThemeData(cursorColor: Palette.ink, selectionColor: Color(0x5538BDF8)),
      ),
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
  final BotEngine _bot = BotEngine();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bot.dispose();
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
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Le bureau du PC, en direct, derrière l'île — comme sur le PC.
          Positioned.fill(child: PcScreen(link: link)),
          // L'île, collée au bord haut (sous la barre d'état).
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: PhoneIsland(link: link, bot: _bot),
          ),
        ],
      ),
    );
  }
}

/// L'écran du PC rafraîchi toutes les deux secondes quand le PC répond.
class PcScreen extends StatefulWidget {
  const PcScreen({super.key, required this.link});
  final PcLink link;

  @override
  State<PcScreen> createState() => _PcScreenState();
}

class _PcScreenState extends State<PcScreen> {
  Timer? _timer;
  String? _url;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _refresh();
  }

  void _refresh() {
    final c = widget.link.client;
    if (!mounted || !widget.link.online || c == null) return;
    setState(() => _url = c.screenUrl(width: 900));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.link,
      builder: (context, _) {
        final url = _url;
        final online = widget.link.online && url != null;
        return Container(
          color: const Color(0xFF05060B),
          alignment: Alignment.center,
          child: online
              ? Image.network(
                  url,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                )
              : Opacity(
                  opacity: 0.35,
                  child: Text('Fractus', style: ui(13, weight: FontWeight.w600, color: Palette.dim3)),
                ),
        );
      },
    );
  }
}
