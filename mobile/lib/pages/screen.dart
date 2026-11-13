// L'écran du PC : une capture, rafraîchie à la demande ou toutes les 3 s.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class ScreenPage extends StatefulWidget {
  const ScreenPage({super.key, required this.link});
  final PcLink link;

  @override
  State<ScreenPage> createState() => _ScreenPageState();
}

class _ScreenPageState extends State<ScreenPage> {
  bool _auto = false;
  Timer? _timer;
  String? _url;
  int _tick = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final c = widget.link.client;
    if (c == null) return;
    setState(() {
      _url = c.screenUrl();
      _tick++;
    });
  }

  void _toggleAuto() {
    setState(() => _auto = !_auto);
    _timer?.cancel();
    if (_auto) {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.link.online;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              const Expanded(child: Text('Écran du PC', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              IconButton(
                tooltip: _auto ? 'Arrêter le direct' : 'Direct (toutes les 3 s)',
                icon: Icon(_auto ? Icons.pause_circle_rounded : Icons.play_circle_rounded, color: _auto ? P.accent : P.dim),
                onPressed: online ? _toggleAuto : null,
              ),
              IconButton(
                tooltip: 'Capturer',
                icon: const Icon(Icons.photo_camera_rounded, color: P.dim),
                onPressed: online ? _refresh : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: _url == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      online ? 'Appuie sur l\'appareil photo pour voir l\'écran du PC.' : 'Connecte-toi au PC pour voir son écran.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: P.dim3),
                    ),
                  ),
                )
              : InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      _url!,
                      key: ValueKey(_tick),
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(color: P.accent)),
                      errorBuilder: (c, e, st) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Capture impossible (écran verrouillé ?).', style: TextStyle(color: P.dim)),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
