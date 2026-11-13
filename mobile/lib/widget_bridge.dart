// Le pont avec les widgets d'écran d'accueil (home_widget) :
//   - l'appli pousse l'état du PC dans les données du widget ;
//   - les boutons du widget réveillent `backgroundCallback` (sans ouvrir l'appli)
//     qui parle au PC puis rafraîchit le widget.

import 'dart:async';

import 'package:home_widget/home_widget.dart';

import 'api.dart';
import 'models.dart';
import 'prefs.dart';

const _providers = ['FractusWidgetSmall', 'FractusWidgetLarge'];

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<void> pushStatusToWidgets(PcStatus? s, {bool online = true, String? error}) async {
  final pending = s?.pending;
  await HomeWidget.saveWidgetData<String>('online', online && s != null ? '1' : '0');
  await HomeWidget.saveWidgetData<String>(
    'state_label',
    s == null ? (error ?? 'PC injoignable') : '${s.host} · Fractus ${stateLabel(s.botState)}',
  );
  await HomeWidget.saveWidgetData<String>('pending_id', pending?.requestId ?? '');
  await HomeWidget.saveWidgetData<String>(
    'pending',
    pending == null ? '' : (pending.isQuestion ? 'Question : ${pending.questions.firstOrNull?.question ?? ''}' : '${pending.label} — ${pending.summary}'),
  );
  await HomeWidget.saveWidgetData<String>('last_message', s?.lastReply ?? '');
  await HomeWidget.saveWidgetData<String>('updated', _hm(DateTime.now()));
  for (final p in _providers) {
    await HomeWidget.updateWidget(name: p, androidName: p);
  }
}

/// Appelé par Android quand on touche un bouton du widget (isolat de fond).
@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri == null) return;
  final info = await Prefs.loadForWidget();
  if (info == null) {
    await pushStatusToWidgets(null, online: false, error: 'Ouvre l\'appli pour configurer');
    return;
  }
  final c = PcClient(info);
  String? error;
  try {
    switch (uri.host) {
      case 'action':
        await c.action(uri.queryParameters['name'] ?? '');
        break;
      case 'decide':
        final id = await HomeWidget.getWidgetData<String>('pending_id') ?? '';
        if (id.isNotEmpty) await c.decide(id, uri.queryParameters['d'] ?? 'deny');
        break;
      case 'refresh':
      default:
        break;
    }
  } catch (e) {
    error = e is PcError ? e.message : 'PC injoignable';
  }
  try {
    final s = await c.status();
    await pushStatusToWidgets(s);
  } catch (e) {
    await pushStatusToWidgets(null, online: false, error: error ?? (e is PcError ? e.message : 'PC injoignable'));
  }
}
