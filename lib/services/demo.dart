// Le scénario de démonstration — celui des captures de Coucou (design/captures) :
// quatre projets, une migration Prisma, une permission, une question, une fin.
// Il passe par le même chemin que les vrais hooks.

import 'dart:async';

import '../island/controller.dart';

class Demo {
  Demo(this.controller);

  final IslandController controller;
  final List<Timer> _timers = [];
  bool running = false;

  void _at(int ms, void Function() fn) {
    _timers.add(Timer(Duration(milliseconds: ms), fn));
  }

  Map<String, dynamic> _ev(String name, String session, String cwd, [Map<String, dynamic>? extra]) => {
        'hook_event_name': name,
        'session_id': session,
        'cwd': cwd,
        ...?extra,
      };

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    running = false;
  }

  void start() {
    stop();
    running = true;
    const korus = r'C:\dev\Korus';
    const sbe = r'C:\dev\SBE Hub';
    const brief = r'C:\dev\Morning Brief';
    const ig = r'C:\dev\Publication IG';
    final c = controller;

    // Les trois autres projets tournent déjà.
    _at(200, () {
      c.handleHook(_ev('UserPromptSubmit', 'sbe', sbe, {'prompt': 'Ajoute la recherche de cours'}));
      c.handleHook(_ev('UserPromptSubmit', 'brief', brief, {'prompt': 'Génère le brief de demain'}));
      c.handleHook(_ev('UserPromptSubmit', 'ig', ig, {'prompt': 'Prépare le post de la semaine'}));
      c.handleHook(_ev('PreToolUse', 'brief', brief, {
        'tool_name': 'WebSearch',
        'tool_input': {'query': 'actualités IA 13 novembre'}
      }));
      c.handleHook(_ev('PreToolUse', 'ig', ig, {
        'tool_name': 'Write',
        'tool_input': {'file_path': r'C:\dev\Publication IG\posts\semaine-46.md'}
      }));
    });

    // Korus : une session Claude Code, étape par étape.
    _at(900, () => c.handleHook(_ev('UserPromptSubmit', 'korus', korus, {
          'prompt': 'Applique la migration des factures et vérifie les tests'
        })));
    _at(1800, () => c.handleHook(_ev('PreToolUse', 'korus', korus, {
          'tool_name': 'Read',
          'tool_input': {'file_path': r'C:\dev\Korus\prisma\schema.prisma'}
        })));
    _at(3200, () => c.handleHook(_ev('PreToolUse', 'korus', korus, {
          'tool_name': 'Edit',
          'tool_input': {'file_path': r'C:\dev\Korus\prisma\migrations\20261113_factures\migration.sql'}
        })));
    _at(4600, () => c.handleHook(_ev('PreToolUse', 'korus', korus, {
          'tool_name': 'Grep',
          'tool_input': {'pattern': 'invoice_total'}
        })));

    // La permission : « npx prisma migrate deploy ».
    _at(6200, () async {
      final reply = await c.requestPermission(_ev('PermissionRequest', 'korus', korus, {
        'request_id': 'demo-perm-1',
        'tool_name': 'Bash',
        'tool_input': {'command': 'npx prisma migrate deploy', 'description': 'Applique la migration'}
      }));
      if (!running) return;
      if (reply == null) return;
      final allowed = reply.toString().contains('allow');
      if (!allowed) {
        _at(600, () => c.handleHook(_ev('Stop', 'korus', korus, {
              'last_assistant_message': 'Migration annulée : commande refusée.'
            })));
        return;
      }
      c.handleHook(_ev('PreToolUse', 'korus', korus, {
        'tool_name': 'Bash',
        'tool_input': {'command': 'npx prisma migrate deploy'}
      }));
      _at(2200, () => c.handleHook(_ev('PreToolUse', 'korus', korus, {
            'tool_name': 'Bash',
            'tool_input': {'command': 'npm test -- --run'}
          })));
      // La question, posée par SBE Hub.
      _at(3800, () async {
        final answer = await c.requestPermission(_ev('PermissionRequest', 'sbe', sbe, {
          'request_id': 'demo-q-1',
          'tool_name': 'AskUserQuestion',
          'tool_input': {
            'questions': [
              {
                'question': 'Quel moteur pour la recherche de cours ?',
                'header': 'Recherche',
                'options': [
                  {'label': 'Postgres full-text'},
                  {'label': 'Meilisearch'},
                  {'label': 'Algolia'},
                ],
              }
            ]
          }
        }));
        if (!running) return;
        if (answer != null) {
          c.handleHook(_ev('PreToolUse', 'sbe', sbe, {
            'tool_name': 'Edit',
            'tool_input': {'file_path': r'C:\dev\SBE Hub\src\search\engine.ts'}
          }));
        }
      });
      // Korus a terminé.
      _at(5600, () => c.handleHook(_ev('Stop', 'korus', korus, {
            'last_assistant_message': 'Migration appliquée, 14 tests passés.'
          })));
    });
  }
}
