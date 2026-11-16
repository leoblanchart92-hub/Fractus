// Les nouveautés sur le téléphone : le CHANGELOG.md (copié dans assets/ par
// tool/sync_shared.sh), la version vue, et la feuille qui les affiche.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'core/changelog.dart';
import 'core/theme.dart';
import 'island/news_list.dart';
import 'native.dart';
import 'prefs.dart';

class PhoneNews extends ChangeNotifier {
  PhoneNews._();
  static final PhoneNews instance = PhoneNews._();

  List<ReleaseNote> notes = const [];
  String current = '';
  String seen = '';
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      notes = Changelog.parse(await rootBundle.loadString('assets/CHANGELOG.md'));
    } catch (_) {
      notes = const [];
    }
    try {
      current = await Native.versionName();
    } catch (_) {}
    seen = await Prefs.seenVersion();
    notifyListeners();
  }

  bool get unseen => notes.any((n) => Changelog.compare(n.version, seen) > 0 && (current.isEmpty || Changelog.compare(n.version, current) <= 0));

  bool get shouldShowOnLaunch => current.isNotEmpty && seen != current && Changelog.find(notes, current) != null;

  Future<void> markSeen() async {
    if (current.isEmpty || seen == current) return;
    seen = current;
    await Prefs.setSeenVersion(current);
    notifyListeners();
  }

  /// La feuille « Nouveautés », du bas de l'écran.
  Future<void> show(BuildContext context) async {
    await load();
    if (!context.mounted) return;
    final seenAtOpen = seen;
    markSeen();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.islandBottom,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Palette.dim5, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('NOUVEAUTÉS', style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
                  const SizedBox(width: 8),
                  if (current.isNotEmpty) Text('Fractus $current', style: ui(10, color: Palette.dim4)),
                  const Spacer(),
                  Text('${notes.length} versions', style: ui(10, color: Palette.dim4)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: NewsList(
                  notes: notes,
                  current: current,
                  seen: seenAtOpen,
                  controller: scroll,
                  padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
