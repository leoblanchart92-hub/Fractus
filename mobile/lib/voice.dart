// Parler à Fractus : la dictée du téléphone (reconnaissance vocale du système,
// pas de serveur à nous). Un seul moteur pour toute l'appli.

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class Voice extends ChangeNotifier {
  Voice._();
  static final Voice instance = Voice._();

  final SpeechToText _stt = SpeechToText();
  bool _initDone = false;
  bool available = false;
  bool listening = false;
  String? error;

  Future<bool> _init() async {
    if (_initDone) return available;
    _initDone = true;
    try {
      available = await _stt.initialize(
        onStatus: (status) {
          // « listening », « notListening », « done » : on suit le micro réel.
          final now = _stt.isListening;
          if (now != listening) {
            listening = now;
            notifyListeners();
          }
        },
        onError: (e) {
          error = _describe(e.errorMsg);
          listening = false;
          notifyListeners();
        },
      );
    } catch (e) {
      available = false;
      error = 'Dictée indisponible : $e';
    }
    return available;
  }

  static String _describe(String code) {
    switch (code) {
      case 'error_no_match':
      case 'error_speech_timeout':
        return 'Je n\'ai rien entendu.';
      case 'error_network':
      case 'error_network_timeout':
        return 'La dictée a besoin d\'Internet.';
      case 'error_permission':
      case 'error_insufficient_permissions':
        return 'Autorise le micro pour Fractus (réglages Android).';
      case 'error_busy':
        return 'Le micro est déjà utilisé.';
      default:
        return 'Dictée : $code';
    }
  }

  /// Écoute et renvoie le texte au fur et à mesure (`done` au résultat final).
  /// Faux si la dictée n'est pas possible sur ce téléphone (voir [error]).
  Future<bool> start(void Function(String text, bool done) onText) async {
    if (listening) return true;
    if (!await _init()) {
      error ??= 'Dictée indisponible sur ce téléphone (pas de reconnaissance vocale, ou micro refusé).';
      notifyListeners();
      return false;
    }
    error = null;
    listening = true;
    notifyListeners();
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) {
          onText(r.recognizedWords, r.finalResult);
          if (r.finalResult && listening) {
            listening = false;
            notifyListeners();
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      error = 'Dictée : $e';
      listening = false;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
    listening = false;
    notifyListeners();
  }
}
