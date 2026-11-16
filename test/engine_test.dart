// Le moteur du chat : réglages (migration des anciens fichiers) et choix Ollama / Groq.

import 'package:flutter_test/flutter_test.dart';
import 'package:fractus/core/settings.dart';
import 'package:fractus/services/chat_service.dart';
import 'package:fractus/services/chat_tools.dart';
import 'package:fractus/core/state.dart';
import 'package:fractus/island/controller.dart';

void main() {
  test('réglages neufs : Ollama avec le modèle par défaut', () {
    final s = Settings.fromJson({});
    expect(s.chatEngine, 'ollama');
    expect(s.ollamaModel, Settings.defaultOllamaModel);
    expect(s.toJson()['chatEngine'], 'ollama');
  });

  test('anciens réglages avec une clé Groq : on reste sur Groq ; sans clé : Ollama', () {
    expect(Settings.fromJson({'chatApiKey': 'gsk_abc'}).chatEngine, 'groq');
    expect(Settings.fromJson({'chatApiKey': ''}).chatEngine, 'ollama');
    expect(Settings.fromJson({'chatApiKey': 'gsk_abc', 'chatEngine': 'ollama'}).chatEngine, 'ollama');
    expect(Settings.fromJson({'ollamaModel': '  '}).ollamaModel, Settings.defaultOllamaModel);
    expect(Settings.fromJson({'ollamaModel': 'qwen3:4b'}).ollamaModel, 'qwen3:4b');
  });

  test('ChatService : local sans clé, Groq avec clé ; le modèle effectif suit le moteur', () {
    final state = AppState(Settings());
    final tools = ChatTools(state, controller: IslandController(state));
    final local = ChatService(apiKey: '', model: '', tools: tools, engine: 'ollama', ollamaModel: 'lfm3:1.7b');
    expect(local.isLocal, isTrue);
    expect(local.configured, isTrue);
    expect(local.effectiveModel, 'lfm3:1.7b');
    expect(local.baseUrl, startsWith('http://127.0.0.1:11434'));

    final cloud = ChatService(apiKey: '', model: '', tools: tools, engine: 'groq');
    expect(cloud.isLocal, isFalse);
    expect(cloud.configured, isFalse);
    cloud.apiKey = 'gsk_x';
    expect(cloud.configured, isTrue);
    expect(cloud.baseUrl, ChatService.groqUrl);
  });
}
