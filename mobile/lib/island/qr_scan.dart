// Le scan du QR code affiché par le PC (Réglages → Téléphone → QR code) :
// la caméra plein écran, et on revient avec le lien `fractus://pair?…`.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';
import 'widgets.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v == null) continue;
      if (v.startsWith('fractus://')) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
      if (_hint == null) setState(() => _hint = 'Ce n\'est pas le QR code de Fractus.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Palette.islandBottom,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: top + 12,
            child: Row(
              children: [
                Expanded(
                  child: Text('Vise le QR code affiché par Fractus sur le PC', style: ui(14, weight: FontWeight.w600)),
                ),
                HeaderTab(icon: Icons.close_rounded, onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 36,
            child: Column(
              children: [
                if (_hint != null) Text(_hint!, style: ui(12.5, color: Palette.amber)),
                const SizedBox(height: 10),
                Text(
                  'Sur le PC : Réglages → Téléphone → QR code',
                  textAlign: TextAlign.center,
                  style: ui(12, color: Palette.dim3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
