// Le serveur local qui reçoit les hooks des agents (hook/fractus-hook.ps1 les
// relaie). Écoute sur 127.0.0.1 uniquement. Pendant du relais `coucou-hook`.
//
//   POST /hook      corps = le JSON du hook tel que Claude Code le donne sur stdin.
//                   Pour PermissionRequest, la réponse attend le clic (≤ 110 s)
//                   et renvoie le JSON que l'agent attend sur stdout, ou un
//                   corps vide si personne n'a cliqué (→ l'agent demande dans
//                   son terminal, comme si Fractus n'était pas là).
//   GET  /health    « ok »

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../island/controller.dart';

class HookServer {
  HookServer(this.controller);

  final IslandController controller;
  HttpServer? _server;
  int? port;
  String? error;

  Future<void> start(int wantedPort) async {
    await stop();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, wantedPort, shared: true);
      port = _server!.port;
      error = null;
      _server!.listen(_handle, onError: (_) {});
    } catch (e) {
      error = 'Port $wantedPort indisponible : $e';
      port = null;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      if (req.method == 'GET' && req.uri.path == '/health') {
        res.write('{"ok":true,"app":"fractus"}');
        await res.close();
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/hook') {
        final body = await utf8.decoder.bind(req).join();
        Map<String, dynamic> payload;
        try {
          final raw = jsonDecode(body);
          payload = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
        } catch (_) {
          payload = <String, dynamic>{};
        }
        final agent = req.uri.queryParameters['agent'];
        if (agent != null && agent.isNotEmpty) payload['fractus_agent'] = agent;

        final name = payload['hook_event_name'];
        if (name == 'PermissionRequest') {
          final reply = await controller.requestPermission(payload).timeout(
                const Duration(seconds: 112),
                onTimeout: () => null,
              );
          if (reply == null) {
            res.statusCode = HttpStatus.noContent;
          } else {
            res.write(jsonEncode(reply));
          }
          await res.close();
          return;
        }
        controller.handleHook(payload);
        res.write('{}');
        await res.close();
        return;
      }
      res.statusCode = HttpStatus.notFound;
      res.write('{"error":"not found"}');
      await res.close();
    } catch (e) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }
}
