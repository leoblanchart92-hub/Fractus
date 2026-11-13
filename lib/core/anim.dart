// Courbes et ressorts — mêmes constantes que le prototype de Coucou
// (design/prototype/notch-buddy.html → BotEngine.swift → windows/src/core/anim.ts).

import 'dart:math' as math;
import 'package:flutter/animation.dart';

typedef EaseFn = double Function(double t);

class Ease {
  Ease._();
  static double out(double t) => 1 - math.pow(1 - t, 3).toDouble();
  static double inOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
  static double back(double t) {
    const c1 = 1.7;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3).toDouble() + c1 * math.pow(t - 1, 2).toDouble();
  }

  static double lin(double t) => t;
  static double easeIn(double t) => t * t * t;
}

double lerp(double a, double b, double t) => a + (b - a) * t;
double clamp(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

/// Ouverture de l'île : cubic-bezier(.32,1.22,.42,1) — le « spring » du prototype.
const Curve openCurve = Cubic(0.32, 1.22, 0.42, 1);

/// Fermeture : cubic-bezier(.45,0,.2,1) en 340 ms.
const Curve closeCurve = Cubic(0.45, 0, 0.2, 1);

const Duration openDuration = Duration(milliseconds: 520);
const Duration closeDuration = Duration(milliseconds: 340);
