// La palette Aurora de Fractus, côté téléphone.

import 'package:flutter/material.dart';

class P {
  P._();
  static const bg = Color(0xFF070912);
  static const card = Color(0xFF121626);
  static const card2 = Color(0xFF1C2136);
  static const hairline = Color(0x14FFFFFF);
  static const ink = Color(0xFFF5F6F8);
  static const dim = Color(0xFF9398A1);
  static const dim3 = Color(0xFF6B7079);
  static const accent = Color(0xFF38BDF8);
  static const accent2 = Color(0xFF818CF8);
  static const accent3 = Color(0xFFA78BFA);
  static const aurora = [accent, accent2, accent3];
  static const red = Color(0xFFF4505E);
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFF5A524);
}

ThemeData fractusTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: P.bg,
    colorScheme: const ColorScheme.dark(primary: P.accent, secondary: P.accent3, surface: P.card),
    cardTheme: CardThemeData(
      color: P.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: P.hairline)),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: P.bg, elevation: 0, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0C0F1A),
      indicatorColor: P.accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5, color: P.dim)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: P.card2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      hintStyle: const TextStyle(color: P.dim3),
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: P.card2, contentTextStyle: TextStyle(color: P.ink)),
  );
}

/// Bouton principal, dégradé Aurora.
class AuroraButton extends StatelessWidget {
  const AuroraButton({super.key, required this.label, required this.onTap, this.icon, this.danger = false, this.flat = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool danger;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: flat ? P.ink : const Color(0xFF07101C)), const SizedBox(width: 8)],
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: flat ? P.ink : const Color(0xFF07101C))),
        ],
      ),
    );
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: flat ? null : LinearGradient(colors: danger ? const [P.red, Color(0xFFFB7185)] : P.aurora),
            color: flat ? P.card2 : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 18),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: P.dim3, letterSpacing: 0.6)),
      );
}
