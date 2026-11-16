// La page « Nouveautés » de l'île : ce qui a changé, version par version.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/news.dart';
import '../news_list.dart';
import '../widgets.dart';

class NewsView extends StatefulWidget {
  const NewsView({super.key, required this.news});
  final News news;

  @override
  State<NewsView> createState() => _NewsViewState();
}

class _NewsViewState extends State<NewsView> {
  /// La version vue au moment d'ouvrir : les badges « Nouveau » restent le temps de la lecture.
  late final String _seenAtOpen = widget.news.settings.seenVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.news.markSeen());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.news,
      builder: (context, _) {
        final n = widget.news;
        return IslandCard(
          padding: const EdgeInsets.only(left: 96, right: 10, top: 8, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('NOUVEAUTÉS', style: ui(10, weight: FontWeight.w700, color: Palette.dim4)),
                  const SizedBox(width: 8),
                  if (n.current.isNotEmpty) Text('Fractus ${n.current}', style: ui(10, color: Palette.dim4)),
                  const Spacer(),
                  Text('${n.notes.length} versions', style: ui(10, color: Palette.dim4)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(child: NewsList(notes: n.notes, current: n.current, seen: _seenAtOpen, selectable: true)),
            ],
          ),
        );
      },
    );
  }
}
