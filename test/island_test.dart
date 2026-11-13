import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:fractus/core/layout.dart';
import 'package:fractus/core/models.dart';
import 'package:fractus/core/settings.dart';
import 'package:fractus/core/state.dart';
import 'package:fractus/island/controller.dart';
import 'package:fractus/services/update_service.dart';

void main() {
  _versionTests();
  test('la géométrie de l\'île est celle de Coucou', () {
    expect(islandSize(IslandMode.hidden, IslandView.empty), const Size(184, 0));
    expect(islandSize(IslandMode.compact, IslandView.empty), const Size(288, 32));
    expect(islandSize(IslandMode.expanded, IslandView.overview), const Size(640, 160));
    expect(islandSize(IslandMode.expanded, IslandView.prompt, chatCount: 3), const Size(640, 300));
    final bot = botPosition(IslandMode.expanded, IslandView.approval, 160);
    expect(bot.cx, 62);
    expect(bot.cy, 101);
    expect(bot.diameter, 56);
  });

  test('les hooks font vivre une session', () {
    final state = AppState(Settings());
    final c = IslandController(state);
    c.handleHook({'hook_event_name': 'UserPromptSubmit', 'session_id': 's1', 'cwd': r'C:\dev\Korus', 'prompt': 'Go'});
    expect(state.sessions.length, 1);
    expect(state.frontSession!.project, 'Korus');
    expect(state.frontSession!.state, BotState.thinking);

    c.handleHook({
      'hook_event_name': 'PreToolUse',
      'session_id': 's1',
      'cwd': r'C:\dev\Korus',
      'tool_name': 'Bash',
      'tool_input': {'command': 'npm test'}
    });
    expect(state.frontSession!.state, BotState.working);
    expect(state.frontSession!.steps.last.kind, StepKind.run);
    expect(state.frontSession!.steps.last.text, 'npm test');
    c.dispose();
  });

  test('une permission attend le clic et répond allow', () async {
    final state = AppState(Settings());
    final c = IslandController(state);
    final future = c.requestPermission({
      'hook_event_name': 'PermissionRequest',
      'request_id': 'r1',
      'session_id': 's1',
      'cwd': r'C:\dev\Korus',
      'tool_name': 'Bash',
      'tool_input': {'command': 'npx prisma migrate deploy'}
    });
    expect(state.pendingApproval, isNotNull);
    expect(state.view, IslandView.approval);
    expect(state.mode, IslandMode.expanded);
    c.decide(Decision.allow);
    final reply = await future;
    expect(reply!['hookSpecificOutput']['decision']['behavior'], 'allow');
    expect(state.pendingApproval, isNull);
    c.dispose();
  });

  test('sans clic, « dans le terminal » rend la main sans décision', () async {
    final state = AppState(Settings());
    final c = IslandController(state);
    final future = c.requestPermission({
      'hook_event_name': 'PermissionRequest',
      'request_id': 'r2',
      'cwd': r'C:\dev\Korus',
      'tool_name': 'Write',
      'tool_input': {'file_path': r'C:\dev\Korus\a.txt'}
    });
    c.deferToTerminal();
    expect(await future, isNull);
    c.dispose();
  });

  test('une question renvoie la même entrée avec les réponses', () async {
    final state = AppState(Settings());
    final c = IslandController(state);
    final future = c.requestPermission({
      'hook_event_name': 'PermissionRequest',
      'request_id': 'q1',
      'cwd': r'C:\dev\SBE Hub',
      'tool_name': 'AskUserQuestion',
      'tool_input': {
        'questions': [
          {'question': 'Quel moteur ?', 'options': [{'label': 'Algolia'}, {'label': 'Meilisearch'}]}
        ]
      }
    });
    expect(state.view, IslandView.question);
    c.answerQuestion({'Quel moteur ?': 'Algolia'});
    final reply = await future;
    final decision = reply!['hookSpecificOutput']['decision'] as Map;
    expect(decision['behavior'], 'allow');
    expect(decision['updatedInput']['answers']['Quel moteur ?'], 'Algolia');
    c.dispose();
  });
}

void _versionTests() {
  test('la comparaison de versions suit le semver', () {
    expect(UpdateService.compareVersions('0.2.0', '0.1.0'), greaterThan(0));
    expect(UpdateService.compareVersions('0.1.0', '0.1.0+1'), 0);
    expect(UpdateService.compareVersions('1.0.0', '0.9.9'), greaterThan(0));
    expect(UpdateService.compareVersions('0.2.0-beta', '0.2.0'), lessThan(0));
    expect(UpdateService.compareVersions('0.1.0', '0.1.1'), lessThan(0));
  });
}
