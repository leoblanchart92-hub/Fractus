// Palette « Aurora » de l'île : un noir bleuté profond, des surfaces légèrement
// teintées, et un accent qui glisse du cyan Fractus au violet — en dégradé sur
// les boutons principaux, en lueur diffuse sur l'enveloppe. Les tailles et la
// typographie restent celles de l'île de Coucou.

import 'package:flutter/material.dart';

class Palette {
  Palette._();
  static const Color ink = Color(0xFFF5F6F8); // texte principal
  static const Color ink2 = Color(0xFFF1F2F4);
  static const Color dim = Color(0xFF9398A1);
  static const Color dim2 = Color(0xFF8E939C);
  static const Color dim3 = Color(0xFF6B7079);
  static const Color dim4 = Color(0xFF5F646D);
  static const Color dim5 = Color(0xFF4B5563);
  static const Color card = Color(0xFF121626);
  static const Color cardFlat = Color(0xFF0C0F1A);
  static const Color tabOn = Color(0xFF1C2136);
  static const Color hairline = Color(0x12FFFFFF);
  /// L'enveloppe de l'île (haut → bas).
  static const Color islandTop = Color(0xFF0E1120);
  static const Color islandBottom = Color(0xFF070912);
  /// L'accent Aurora : cyan Fractus → violet.
  static const Color accent = Color(0xFF38BDF8);
  static const Color accent2 = Color(0xFF818CF8);
  static const Color accent3 = Color(0xFFA78BFA);
  static const List<Color> aurora = [accent, accent2, accent3];
  /// Texte posé sur l'accent.
  static const Color onAccent = Color(0xFF07101C);
  static const Color red = Color(0xFFF4505E);
  static const Color redText = Color(0xFFFF8D97);
  static const Color green = Color(0xFF22C55E);
  static const Color green2 = Color(0xFF34D399);
  static const Color amber = Color(0xFFF5A524);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color indigo = Color(0xFF6366F1);
  static const Color pink = Color(0xFFF472B6);
  static const Color blue = Color(0xFF38BDF8);
}

const List<String> uiFontFallback = [
  'Segoe UI Variable Text',
  'Segoe UI',
  'Segoe UI Emoji',
  'Noto Sans',
  'sans-serif',
];

const List<String> monoFontFallback = ['Cascadia Mono', 'Consolas', 'monospace'];

TextStyle ui(double size, {FontWeight weight = FontWeight.w400, Color color = Palette.ink, double? height}) {
  return TextStyle(
    fontFamily: 'Segoe UI',
    fontFamilyFallback: uiFontFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    decoration: TextDecoration.none,
  );
}

TextStyle mono(double size, {Color color = Palette.ink}) {
  return TextStyle(
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: monoFontFallback,
    fontSize: size,
    color: color,
    decoration: TextDecoration.none,
  );
}
