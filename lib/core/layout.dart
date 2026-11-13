// Géométrie de l'île — reprise point pour point de Coucou
// (IslandTypes.swift / windows/src/core/layout.ts). Tout est en pixels logiques.

import 'dart:ui';

enum IslandMode { hidden, compact, expanded }

enum IslandView {
  overview,
  empty,
  approval,
  question,
  error,
  finished,
  confused,
  prompt,
  settings,
  greeting,
  launch,
  update,
}

enum BotState {
  idle,
  working,
  thinking,
  searching,
  approval,
  question,
  error,
  finished,
  ratelimit,
  sleeping,
  dizzy,
}

enum BotEmote { love, surprised, proud, wink, yawn, happy, annoyed }

enum AgentLayoutMode { none, grid, pills, column }

class ViewLayout {
  const ViewLayout({
    required this.height,
    required this.botX,
    this.botY,
    required this.botDiameter,
    required this.agentMode,
  });
  final double height;
  final double botX;
  final double? botY; // null = centré automatiquement
  final double botDiameter;
  final AgentLayoutMode agentMode;
}

/// La fenêtre est un panneau fixe de 720×320 (la plus grande vue), comme le
/// panneau macOS ; l'île est dessinée dedans, collée au bord haut et centrée.
const double panelW = 720;
const double panelH = 320;

/// Pas d'encoche sur un PC : tailles cachée/compacte de docs/SPEC.md.
const double notchW = 184;
const double notchH = 32;
const double compactW = 288; // notchW + 104
const double expandedW = 640;

const double roundedCorner = 14; // cachée / compacte
const double expandedCorner = 22;

/// Bande invisible qui réveille l'île quand elle est cachée.
const double wakeStripW = 240;
const double wakeStripH = 6;

const Map<IslandView, ViewLayout> viewLayouts = {
  IslandView.overview: ViewLayout(height: 160, botX: 68, botDiameter: 58, agentMode: AgentLayoutMode.pills),
  IslandView.empty: ViewLayout(height: 160, botX: 70, botDiameter: 62, agentMode: AgentLayoutMode.none),
  IslandView.approval: ViewLayout(height: 160, botX: 62, botDiameter: 56, agentMode: AgentLayoutMode.column),
  IslandView.question: ViewLayout(height: 160, botX: 62, botDiameter: 56, agentMode: AgentLayoutMode.column),
  IslandView.error: ViewLayout(height: 160, botX: 62, botDiameter: 58, agentMode: AgentLayoutMode.column),
  IslandView.finished: ViewLayout(height: 160, botX: 62, botDiameter: 58, agentMode: AgentLayoutMode.column),
  IslandView.confused: ViewLayout(height: 160, botX: 76, botDiameter: 66, agentMode: AgentLayoutMode.column),
  IslandView.prompt: ViewLayout(height: 160, botX: 52, botDiameter: 44, agentMode: AgentLayoutMode.column),
  IslandView.settings: ViewLayout(height: 160, botX: 54, botDiameter: 46, agentMode: AgentLayoutMode.none),
  IslandView.greeting: ViewLayout(height: 150, botX: 320, botY: 90, botDiameter: 0, agentMode: AgentLayoutMode.none),
  IslandView.launch: ViewLayout(height: 160, botX: 58, botDiameter: 52, agentMode: AgentLayoutMode.none),
  IslandView.update: ViewLayout(height: 160, botX: 62, botDiameter: 58, agentMode: AgentLayoutMode.none),
};

/// La vue question avec des choix : la place pour deux rangées.
const double questionPickerH = 200;

/// La vue chat grandit avec la conversation (IslandContainer.chatPromptHeight).
double chatPromptHeight(int messageCount) => (240 + messageCount * 40).clamp(240, 300).toDouble();

Size islandSize(IslandMode mode, IslandView view, {int chatCount = 0, bool questionPicker = false}) {
  switch (mode) {
    case IslandMode.hidden:
      // Pas d'encoche où se cacher : l'île se rétracte à zéro.
      return const Size(notchW, 0);
    case IslandMode.compact:
      return const Size(compactW, notchH);
    case IslandMode.expanded:
      double h;
      if (view == IslandView.prompt) {
        h = chatPromptHeight(chatCount);
      } else if (view == IslandView.question && questionPicker) {
        h = questionPickerH;
      } else {
        h = viewLayouts[view]!.height;
      }
      return Size(expandedW, h);
  }
}

class BotPlacement {
  const BotPlacement(this.cx, this.cy, this.diameter, this.opacity);
  final double cx;
  final double cy;
  final double diameter;
  final double opacity;
}

/// IslandRootView.botPosition — cy mesuré depuis le bord haut de l'île.
BotPlacement botPosition(IslandMode mode, IslandView view, double islandH) {
  switch (mode) {
    case IslandMode.hidden:
      return const BotPlacement(46, 16, 6, 0);
    case IslandMode.compact:
      return const BotPlacement(40, 16, 20, 1);
    case IslandMode.expanded:
      final layout = viewLayouts[view]!;
      if (layout.botY != null) {
        return BotPlacement(layout.botX, layout.botY!, layout.botDiameter, 1);
      }
      // Centre de la carte fixe de 84 pt (8 pt de marge + 34 pt d'en-tête → contenu à y = 42)
      const headerBottom = 42.0;
      const cardH = 84.0;
      final cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2;
      return BotPlacement(layout.botX, cy, layout.botDiameter, 1);
  }
}

Color botGlowColor(BotState s) {
  switch (s) {
    case BotState.working:
      return const Color(0xFF3B9EFF);
    case BotState.thinking:
      return const Color(0xFFA78BFA);
    case BotState.searching:
      return const Color(0xFF6366F1);
    case BotState.approval:
      return const Color(0xFFF5A524);
    case BotState.error:
      return const Color(0xFFF4505E);
    case BotState.finished:
      return const Color(0xFF34D399);
    case BotState.ratelimit:
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFFFFFFFF);
  }
}

double botGlowOpacity(BotState s) {
  switch (s) {
    case BotState.idle:
    case BotState.sleeping:
      return 0.15;
    case BotState.dizzy:
      return 0;
    default:
      return 0.65;
  }
}

// Couleurs des projets (IslandConst.projectColors)
const Map<String, Color> _projectColors = {
  'korus': Color(0xFFFF5A4E),
  'sbe hub': Color(0xFF2EC4A0),
  'morning ai brief': Color(0xFFF29B38),
  'publication ig': Color(0xFF7C5CFF),
  'ig post': Color(0xFF7C5CFF),
  'fractus': Color(0xFF38BDF8),
  'notch buddy': Color(0xFFEC4899),
};

const List<Color> _fallbackColors = [
  Color(0xFF22C55E),
  Color(0xFFEAB308),
  Color(0xFF60A5FA),
  Color(0xFFE879F9),
];

Color colorForProject(String name) {
  final key = name.toLowerCase().trim();
  final exact = _projectColors[key];
  if (exact != null) return exact;
  for (final e in _projectColors.entries) {
    if (key.startsWith(e.key) || key.contains(e.key)) return e.value;
  }
  var hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return _fallbackColors[hash % _fallbackColors.length];
}

/// Teinte de fond des cartes (CardBackground.washColor)
enum Wash { red, green, pink, amber, cyan, indigo, soft, none }

Color washColor(Wash wash) {
  switch (wash) {
    case Wash.red:
      return const Color(0xFFF4505E).withValues(alpha: 0.55);
    case Wash.green:
      return const Color(0xFF34D399).withValues(alpha: 0.5);
    case Wash.pink:
      return const Color(0xFFF472B6).withValues(alpha: 0.55);
    case Wash.amber:
      return const Color(0xFFF5A524).withValues(alpha: 0.42);
    case Wash.cyan:
      return const Color(0xFF22D3EE).withValues(alpha: 0.38);
    case Wash.indigo:
      return const Color(0xFF6366F1).withValues(alpha: 0.5);
    case Wash.soft:
      return const Color(0xFFFFFFFF).withValues(alpha: 0.08);
    case Wash.none:
      return const Color(0x00000000);
  }
}
