// Les réglages, dans l'île : affichage, son, hooks, chat, et la sortie.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state.dart';
import '../../core/theme.dart';
import '../../services/chat_service.dart';
import '../../services/update_service.dart';
import '../controller.dart';
import '../widgets.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.state,
    required this.controller,
    required this.hookPort,
    required this.hookError,
    required this.onQuit,
    required this.onRestartHooks,
    required this.updates,
    required this.onStartupChanged,
    required this.chat,
  });
  final AppState state;
  final IslandController controller;
  final int? hookPort;
  final String? hookError;
  final VoidCallback onQuit;
  final VoidCallback onRestartHooks;
  final UpdateService updates;
  final ValueChanged<bool> onStartupChanged;
  final ChatService chat;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _key = TextEditingController(text: widget.state.settings.chatApiKey);
  late final TextEditingController _model = TextEditingController(text: widget.state.settings.chatModel);
  late final TextEditingController _workspace = TextEditingController(text: widget.state.settings.chatWorkspace);
  bool _savedChat = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  late final TextEditingController _port = TextEditingController(text: widget.state.settings.hookPort.toString());
  bool _copied = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _workspace.dispose();
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
            _toggle('Lancer Fractus avec Windows', s.launchAtStartup, (v) {
              s.launchAtStartup = v;
              widget.state.saveSettingsSoon();
              widget.onStartupChanged(v);
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
            _section('Chat (Groq)'),
            Row(
              children: [
                Expanded(flex: 3, child: _field(_key, hint: 'Clé API Groq (gsk_…) — gratuite sur console.groq.com', obscure: true)),
                const SizedBox(width: 6),
                IslandButton(
                  label: _testing ? 'Test…' : 'Tester',
                  compact: true,
                  onTap: _testing ? () {} : _testKey,
                ),
                const SizedBox(width: 6),
                IslandButton(
                  label: _savedChat ? 'Enregistré' : 'Enregistrer',
                  compact: true,
                  primary: true,
                  onTap: _saveChat,
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 3),
              Text(_testResult!, style: ui(11, color: _testOk ? Palette.dim : Palette.redText)),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: _field(_model, hint: 'Modèle : automatique (le plus puissant du compte)')),
                const SizedBox(width: 6),
                _modelPicker(),
              ],
            ),
            const SizedBox(height: 4),
            _field(_workspace, hint: 'Dossier de travail de l\'agent (vide = projet de l\'agent en avant, sinon ton profil)'),
            _toggle('Recherche web et exécution de code (groq/compound)', s.chatWebSearch, (v) {
              s.chatWebSearch = v;
              widget.state.saveSettingsSoon();
            }),
            Text(
              'Fractus agit comme Claude Code : il lit, cherche, écrit, modifie et lance des commandes dans le dossier de travail — '
              'chaque action passe par la carte Autoriser / Refuser / Toujours. La clé reste sur cette machine.',
              style: ui(11, color: Palette.dim3),
            ),
            _section('Mises à jour'),
            _toggle('Chercher les mises à jour automatiquement', s.autoUpdate, (v) {
              s.autoUpdate = v;
              widget.state.saveSettingsSoon();
              widget.updates.setAutoCheck(v);
            }),
            AnimatedBuilder(
              animation: widget.updates,
              builder: (context, _) {
                final u = widget.updates;
                final String txt;
                switch (u.status) {
                  case UpdateStatus.checking:
                    txt = 'Recherche…';
                  case UpdateStatus.upToDate:
                    txt = 'Fractus ${u.currentVersion} — à jour';
                  case UpdateStatus.available:
                    txt = 'Fractus ${u.available?.version} disponible';
                  case UpdateStatus.downloading:
                    txt = 'Téléchargement ${(u.progress * 100).round()} %';
                  case UpdateStatus.installing:
                    txt = 'Installation…';
                  case UpdateStatus.error:
                    txt = u.error ?? 'Échec';
                  case UpdateStatus.idle:
                    txt = 'Fractus ${u.currentVersion}';
                }
                return Row(
                  children: [
                    Expanded(
                      child: Text(txt,
                          style: ui(12, color: u.status == UpdateStatus.error ? Palette.redText : Palette.dim)),
                    ),
                    if (u.status == UpdateStatus.available)
                      IslandButton(label: 'Installer', compact: true, primary: true, onTap: u.install)
                    else
                      IslandButton(
                        label: 'Vérifier',
                        compact: true,
                        onTap: u.status == UpdateStatus.checking ? () {} : () => u.check(),
                      ),
                  ],
                );
              },
            ),
            _section('Fractus'),
            Row(
              children: [
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

  void _saveChat() {
    final s = widget.state.settings;
    s.chatApiKey = _key.text.trim();
    s.chatModel = _model.text.trim();
    s.chatWorkspace = _workspace.text.trim();
    widget.state.saveSettingsSoon();
    setState(() => _savedChat = true);
  }

  Future<void> _testKey() async {
    _saveChat();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final models = await widget.chat.listModels();
      setState(() {
        _testOk = true;
        _testResult = models.isEmpty
            ? 'Clé acceptée, mais aucun modèle de chat disponible.'
            : 'Clé OK — ${models.length} modèles. Automatique : ${widget.chat.effectiveModel}.';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _modelPicker() {
    final models = widget.chat.models;
    return PopupMenuButton<String>(
      tooltip: models.isEmpty ? 'Teste la clé pour lister les modèles' : 'Choisir un modèle',
      color: Palette.card,
      padding: EdgeInsets.zero,
      onSelected: (id) {
        _model.text = id == '' ? '' : id;
        _saveChat();
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: '', height: 30, child: Text('Automatique (le plus puissant)', style: ui(12))),
        for (final m in models)
          PopupMenuItem(
            value: m.id,
            height: 30,
            child: Text(
              m.contextWindow > 0 ? '${m.id}  ·  ${(m.contextWindow / 1000).round()}k' : m.id,
              style: ui(12),
            ),
          ),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: Palette.tabOn, borderRadius: BorderRadius.circular(7)),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(models.isEmpty ? 'Modèles' : '${models.length} modèles', style: ui(11.5, color: Palette.dim)),
            const Icon(Icons.expand_more_rounded, size: 14, color: Palette.dim),
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
                activeThumbColor: Palette.blue,
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
