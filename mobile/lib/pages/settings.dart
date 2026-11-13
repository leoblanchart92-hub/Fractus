// Les réglages : l'adresse du PC et le code d'appairage affichés dans Fractus
// (Réglages → Téléphone), le test de connexion, l'aide.

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
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
        if (widget.link.online && widget.link.status?.settings != null) _PcSettings(link: widget.link, settings: widget.link.status!.settings!),
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


/// Les réglages du Fractus du PC qu'on peut changer à distance.
class _PcSettings extends StatefulWidget {
  const _PcSettings({required this.link, required this.settings});
  final PcLink link;
  final PcSettings settings;

  @override
  State<_PcSettings> createState() => _PcSettingsState();
}

class _PcSettingsState extends State<_PcSettings> {
  late final _workspace = TextEditingController(text: widget.settings.workspace);

  @override
  void dispose() {
    _workspace.dispose();
    super.dispose();
  }

  Future<void> _patch(Map<String, Object?> p) async {
    final err = await widget.link.run((c) => c.settings(p));
    if (err != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _editMemory() async {
    final c = widget.link.client;
    if (c == null) return;
    String text;
    try {
      text = await c.memory();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    final ctrl = TextEditingController(text: text);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: P.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('memoire.md — ce que Fractus sait de toi', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
              child: TextField(
                controller: ctrl,
                maxLines: null,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
                decoration: const InputDecoration(hintText: '- un fait par ligne'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: AuroraButton(label: 'Annuler', flat: true, onTap: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(child: AuroraButton(label: 'Enregistrer', icon: Icons.check_rounded, onTap: () => Navigator.pop(ctx, true))),
              ],
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final err = await widget.link.run((c) => c.saveMemory(ctrl.text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Mémoire enregistrée sur le PC')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Fractus sur le PC'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.memory_rounded, color: P.accent),
                title: const Text('Modèle Groq'),
                subtitle: Text(st.model.isEmpty ? 'Automatique → ${st.effectiveModel}' : st.model, style: const TextStyle(color: P.dim, fontSize: 12)),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.expand_more_rounded, color: P.dim),
                  color: P.card2,
                  onSelected: (m) => _patch({'model': m}),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('Automatique (le plus puissant)')),
                    for (final m in st.models) PopupMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))),
                    if (st.models.isEmpty) PopupMenuItem(value: st.model, onTap: () => _patch({'listModels': true}), child: const Text('Charger la liste des modèles…')),
                  ],
                ),
              ),
              const Divider(height: 1, color: P.hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded, color: P.accent),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _workspace,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Dossier de travail (actuel : ${st.baseDir})',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (v) => _patch({'workspace': v}),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.check_rounded, color: P.dim), onPressed: () => _patch({'workspace': _workspace.text})),
                  ],
                ),
              ),
              const Divider(height: 1, color: P.hairline),
              SwitchListTile(
                secondary: const Icon(Icons.travel_explore_rounded, color: P.accent),
                title: const Text('Recherche web (groq/compound)'),
                value: st.webSearch,
                onChanged: (v) => _patch({'webSearch': v}),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_off_rounded, color: P.accent),
                title: const Text('Sons de l\'île coupés'),
                value: st.muted,
                onChanged: (v) => _patch({'muted': v}),
              ),
              const Divider(height: 1, color: P.hairline),
              ListTile(
                leading: const Icon(Icons.psychology_rounded, color: P.accent),
                title: const Text('Mémoire longue (memoire.md)'),
                subtitle: const Text('Lire et modifier ce que Fractus retient de toi', style: TextStyle(color: P.dim, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded, color: P.dim),
                onTap: _editMemory,
              ),
              if (st.alwaysAllow.isNotEmpty) ...[
                const Divider(height: 1, color: P.hairline),
                ExpansionTile(
                  leading: const Icon(Icons.verified_user_rounded, color: P.accent),
                  title: Text('${st.alwaysAllow.length} règle(s) « Toujours autoriser »'),
                  children: [
                    for (final k in st.alwaysAllow)
                      ListTile(
                        dense: true,
                        title: Text(k.replaceFirst('Fractus|', 'PC : ').replaceFirst('|', ' '), style: const TextStyle(fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: P.dim),
                          onPressed: () => _patch({'forgetAlwaysKey': k}),
                        ),
                      ),
                    TextButton(onPressed: () => _patch({'forgetAlways': true}), child: const Text('Tout oublier', style: TextStyle(color: P.red))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
