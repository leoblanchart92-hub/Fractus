// Fractus sur le téléphone : la même île que sur le PC — Fractus, ses cartes,
// ses étapes en direct — en plein écran.
// Tout passe par le serveur « téléphone » de Fractus sur le PC (réseau local).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'api.dart';
import 'companion/bot_engine.dart';
import 'core/theme.dart';
import 'island/phone_island.dart';
import 'native.dart';
import 'prefs.dart';
import 'updater.dart';
import 'widget_bridge.dart';

final link = PcLink();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HomeWidget.registerInteractivityCallback(backgroundCallback);
  await link.load();
  link.onStatus = (s) => pushStatusToWidgets(s);
  link.restart();
  // Le service de notifications, s'il est activé (il survit à l'appli).
  if (await Prefs.notifyEnabled() && link.configured) await Native.startService();
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
    _handleLaunchLink();
    Future.delayed(const Duration(seconds: 2), updater.check);
  }

  /// Un QR code scanné avec l'appareil photo du téléphone ouvre `fractus://pair?…`.
  Future<void> _handleLaunchLink() async {
    final l = await Native.launchLink();
    if (l == null) return;
    final info = PcConnectionInfo.fromPairLink(l);
    if (info != null) await link.setInfo(info);
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
    if (state == AppLifecycleState.resumed) {
      link.restart();
      _handleLaunchLink();
    }
    if (state == AppLifecycleState.paused) link.pause();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: PhoneIsland(link: link, bot: _bot),
    );
  }
}
