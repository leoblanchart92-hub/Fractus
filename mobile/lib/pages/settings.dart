// Les réglages : l'adresse du PC et le code d'appairage affichés dans Fractus
// (Réglages → Téléphone), le test de connexion, l'aide.

import 'package:flutter/material.dart';

import '../api.dart';
import '../prefs.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.link, required this.onSaved});
  final PcLink link;
  final VoidCallback onSaved;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _address = TextEditingController(
    text: widget.link.info == null ? '' : '${widget.link.info!.host}:${widget.link.info!.port}',
  );
  late final _code = TextEditingController(text: widget.link.info?.token ?? '');
  String? _result;
  bool _ok = false;
  bool _testing = false;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _test({bool save = false}) async {
    final info = PcConnectionInfo.parse(_address.text, _code.text);
    if (info.host.isEmpty || info.token.isEmpty) {
      setState(() {
        _ok = false;
        _result = 'Entre l\'adresse et le code.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final c = PcClient(info);
      final s = await c.status();
      setState(() {
        _ok = true;
        _result = 'Connecté à ${s.host} (Fractus ${s.version}).';
      });
      if (save) {
        await widget.link.setInfo(info);
        widget.onSaved();
      }
    } catch (e) {
      setState(() {
        _ok = false;
        _result = e is PcError
            ? (e.status == 401 ? 'Code refusé : vérifie-le dans Fractus → Réglages → Téléphone.' : e.message)
            : 'PC injoignable. Même Wi-Fi ? Fractus lancé ? Contrôle téléphone activé ? Pare-feu ouvert ?';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Réglages', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SectionTitle('Le PC'),
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'Adresse du PC, ex. 192.168.1.20:7790', prefixIcon: Icon(Icons.computer_rounded, color: P.dim3)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Code d\'appairage, ex. K7PX-4MQ2', prefixIcon: Icon(Icons.key_rounded, color: P.dim3)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: AuroraButton(label: _testing ? 'Test…' : 'Tester', flat: true, onTap: _testing ? null : () => _test())),
            const SizedBox(width: 10),
            Expanded(child: AuroraButton(label: 'Enregistrer', icon: Icons.check_rounded, onTap: _testing ? null : () => _test(save: true))),
          ],
        ),
        if (_result != null) ...[
          const SizedBox(height: 10),
          Text(_result!, style: TextStyle(color: _ok ? P.green : P.red, fontSize: 13)),
        ],
        const SectionTitle('Comment ça marche'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '1. Sur le PC : Fractus → ⚙️ Réglages → Téléphone → active « Autoriser le contrôle depuis le téléphone ». '
              'L\'adresse et le code s\'affichent (bouton Copier).\n\n'
              '2. Le téléphone doit être sur le même Wi-Fi que le PC. Si ça ne se connecte pas, clique « Pare-feu » dans ces mêmes réglages (une fois).\n\n'
              '3. Depuis l\'extérieur : installe Tailscale sur le PC et le téléphone, puis utilise l\'adresse Tailscale du PC (100.x.x.x:7790).\n\n'
              'Les widgets d\'écran d\'accueil (petit : boutons ; grand : état + dernière réponse + Autoriser/Refuser) marchent une fois la connexion enregistrée.',
              style: TextStyle(color: P.dim, height: 1.45, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
