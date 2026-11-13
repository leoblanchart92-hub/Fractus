// Les réglages, dans l'île : affichage, son, hooks, chat, et la sortie.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state.dart';
import '../../core/theme.dart';
import '../controller.dart';
import '../widgets.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.state,
    required this.controller,
    required this.hookPort,
    required this.hookError,
    required this.onDemo,
    required this.onQuit,
    required this.onRestartHooks,
  });
  final AppState state;
  final IslandController controller;
  final int? hookPort;
  final String? hookError;
  final VoidCallback onDemo;
  final VoidCallback onQuit;
  final VoidCallback onRestartHooks;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _key = TextEditingController(text: widget.state.settings.anthropicApiKey);
  late final TextEditingController _model = TextEditingController(text: widget.state.settings.chatModel);
  late final TextEditingController _port = TextEditingController(text: widget.state.settings.hookPort.toString());
  bool _copied = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _port.dispose();
    super.dispose();
  }

  String get _hookCommand =>
      'powershell -NoProfile -ExecutionPolicy Bypass -File "<dossier Fractus>\\hook\\fractus-hook.ps1"';

  @override
  Widget build(BuildContext context) {
    final s = widget.state.settings;
    return IslandCard(
      padding: const EdgeInsets.only(left: 96, right: 10, top: 8, bottom: 8),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _section('Île'),
            _toggle('Ouvrir au survol', s.openOnHover, (v) {
              s.openOnHover = v;
              widget.state.saveSettingsSoon();
            }),
            _toggle('Sons coupés', s.muted, (v) {
              s.muted = v;
              widget.state.saveSettingsSoon();
            }),
            _toggle('Saluer au lancement', s.greetOnLaunch, (v) {
              s.greetOnLaunch = v;
              widget.state.saveSettingsSoon();
            }),
            _section('Agents'),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.hookPort != null
                        ? 'Serveur de hooks : http://127.0.0.1:${widget.hookPort}/hook'
                        : (widget.hookError ?? 'Serveur de hooks arrêté'),
                    style: ui(12, color: widget.hookPort != null ? Palette.dim : Palette.redText),
                  ),
                ),
                SizedBox(width: 56, child: _field(_port, hint: 'Port', number: true)),
                const SizedBox(width: 6),
                IslandButton(
                  label: 'Appliquer',
                  compact: true,
                  onTap: () {
                    final p = int.tryParse(_port.text);
                    if (p != null && p > 1024 && p < 65536) {
                      s.hookPort = p;
                      widget.state.saveSettingsSoon();
                      widget.onRestartHooks();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dans Claude Code : hooks → $_hookCommand (voir hook/README.md).',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ui(11.5, color: Palette.dim3),
                  ),
                ),
                const SizedBox(width: 6),
                IslandButton(
                  label: _copied ? 'Copié' : 'Copier',
                  compact: true,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: _hookCommand));
                    setState(() => _copied = true);
                  },
                ),
              ],
            ),
            if (s.alwaysAllow.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text('${s.alwaysAllow.length} règle(s) « Toujours autoriser »', style: ui(12, color: Palette.dim)),
                  ),
                  IslandButton(
                    label: 'Oublier',
                    compact: true,
                    onTap: () {
                      s.alwaysAllow.clear();
                      widget.state.saveSettingsSoon();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
            _section('Chat'),
            Row(
              children: [
                Expanded(flex: 3, child: _field(_key, hint: 'Clé API Anthropic (sk-ant-…)', obscure: true)),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: _field(_model, hint: 'Modèle')),
                const SizedBox(width: 6),
                IslandButton(
                  label: 'Enregistrer',
                  compact: true,
                  primary: true,
                  onTap: () {
                    s.anthropicApiKey = _key.text.trim();
                    if (_model.text.trim().isNotEmpty) s.chatModel = _model.text.trim();
                    widget.state.saveSettingsSoon();
                  },
                ),
              ],
            ),
            Text('La clé reste sur cette machine (settings.json). Rien n\'est envoyé sans ton message.',
                style: ui(11, color: Palette.dim3)),
            _section('Fractus'),
            Row(
              children: [
                IslandButton(label: 'Jouer la démo', compact: true, onTap: widget.onDemo),
                const SizedBox(width: 8),
                IslandButton(label: 'Quitter Fractus', compact: true, onTap: widget.onQuit),
                const Spacer(),
                Text('Interface d\'après Coucou (Louis Raillé, MIT)', style: ui(10.5, color: Palette.dim4)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 3),
        child: Text(t.toUpperCase(), style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: ui(12.5))),
          SizedBox(
            height: 20,
            child: FittedBox(
              child: Switch(
                value: value,
                activeColor: Palette.blue,
                onChanged: (v) {
                  onChanged(v);
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, {required String hint, bool obscure = false, bool number = false}) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(7)),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        style: ui(12),
        cursorColor: Palette.ink,
        decoration: InputDecoration(
          isDense: true,
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: ui(12, color: Palette.dim3),
        ),
      ),
    );
  }
}
