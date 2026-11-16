// Les nouveautés du PC : CHANGELOG.md embarqué, la version vue, le point rouge.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/changelog.dart';
import '../core/settings.dart';

class News extends ChangeNotifier {
  News(this.settings);
  final Settings settings;

  List<ReleaseNote> notes = const [];
  String current = '';

  Future<void> load(String currentVersion) async {
    current = currentVersion;
    try {
      notes = Changelog.parse(await rootBundle.loadString('CHANGELOG.md'));
    } catch (_) {
      notes = const [];
    }
    notifyListeners();
  }

  /// Il y a des versions qu'on n'a pas encore montrées (jusqu'à la version installée).
  bool get unseen => notes.any((n) => Changelog.compare(n.version, settings.seenVersion) > 0 && (current.isEmpty || Changelog.compare(n.version, current) <= 0));

  /// La version installée n'a jamais été présentée : à ouvrir une fois au lancement.
  bool get shouldShowOnLaunch => current.isNotEmpty && settings.seenVersion != current && Changelog.find(notes, current) != null;

  /// À appeler quand la page a été ouverte : on retient la version installée.
  Future<void> markSeen() async {
    if (current.isEmpty || settings.seenVersion == current) return;
    settings.seenVersion = current;
    await settings.save();
    notifyListeners();
  }
}
