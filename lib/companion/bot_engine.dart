// Fractus — le compagnon. Moteur d'animation dérivé de celui de Coucou
// (windows/src/mochi/engine.ts, MIT) : mêmes tweens, courbes et particules.
// Le personnage, lui, est un petit cristal (« fractus » = éclat, en latin) :
// une gemme hexagonale aux angles adoucis, aux facettes translucides, avec les
// mêmes grands yeux expressifs. Dessiné en code, sans image : un Canvas et un ticker.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/anim.dart';
import '../core/layout.dart';

enum EyeShape { pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink }

enum BadgeKind { dots, bang, question, dot }

class BotBadge {
  const BotBadge(this.kind, this.color);
  final BadgeKind kind;
  final Color color;

  String get key => '${kind.name}-$color';
}

enum _Prop { yaw, pitch, roll, tilt, open, sx, sy, oy, ox, tint, blush, es, badgeS }

class _Key {
  const _Key(this.target, this.durationMs, this.ease);
  final double target;
  final double durationMs;
  final EaseFn ease;
}

class _Tween {
  _Tween(this.prop, this.keys, this.from, this.startMs, this.onComplete);
  final _Prop prop;
  final List<_Key> keys;
  int index = 0;
  double from;
  double startMs;
  final VoidCallback? onComplete;
}

class BotStateCfg {
  const BotStateCfg({
    required this.color,
    required this.tint,
    required this.eye,
    this.badge,
    this.bounces = false,
    this.scans = false,
    this.breathes = false,
    this.zz = false,
    this.sweat = false,
    this.look,
    this.tilt = 0,
  });
  final Color color;
  final double tint;
  final EyeShape eye;
  final BotBadge? badge;
  final bool bounces;
  final bool scans;
  final bool breathes;
  final bool zz;
  final bool sweat;
  final Offset? look;
  final double tilt;
}

enum _PType { heart, star, spark, sweat, z }

class _Particle {
  _Particle(this.type, this.x, this.y, this.vx, this.vy, this.age, this.life, this.rot, this.size);
  final _PType type;
  double x, y, vx, vy, age, life, rot, size;
}

// ── Constantes (FractusConst) ───────────────────────────────────────────────────

const double _eyeW = 0.25;
const double _eyeH = 0.27;
const double _eyeSp = 0.37;
const double _eyeP = -0.12;
// Teintes du cristal au repos : un verre pâle, légèrement bleuté.
const Color _baseTop = Color(0xFFF2F7FB);
const Color _baseBottom = Color(0xFFB7CCE0);
// Couleur d'accent de Fractus (la facette qui capte la lumière).
const Color _accent = Color(0xFF38BDF8);
const Color _ink = Color(0xFF1A1412);
const Color _miniInk = Color(0xFF10131A);

class BotColors {
  BotColors._();
  static const idle = Color.fromRGBO(230, 233, 238, 1);
  static const working = Color.fromRGBO(59, 158, 255, 1);
  static const thinking = Color.fromRGBO(139, 92, 246, 1);
  static const searching = Color.fromRGBO(99, 101, 242, 1);
  static const approval = Color.fromRGBO(245, 165, 36, 1);
  static const question = Color.fromRGBO(34, 211, 238, 1);
  static const error = Color.fromRGBO(244, 80, 94, 1);
  static const finished = Color.fromRGBO(52, 212, 153, 1);
  static const ratelimit = Color.fromRGBO(251, 146, 60, 1);
  static const sleeping = Color.fromRGBO(148, 162, 184, 1);
  static const dizzy = Color.fromRGBO(244, 114, 182, 1);
}

final Map<BotState, BotStateCfg> botStates = {
  BotState.idle: const BotStateCfg(color: BotColors.idle, tint: 0, eye: EyeShape.pill),
  BotState.working: const BotStateCfg(
      color: BotColors.working, tint: 0.72, eye: EyeShape.pill, badge: BotBadge(BadgeKind.dots, BotColors.working)),
  BotState.thinking: const BotStateCfg(
      color: BotColors.thinking,
      tint: 0.72,
      eye: EyeShape.pill,
      badge: BotBadge(BadgeKind.dots, BotColors.thinking),
      look: Offset(0.55, 0.55)),
  BotState.searching: const BotStateCfg(
      color: BotColors.searching,
      tint: 0.72,
      eye: EyeShape.pill,
      badge: BotBadge(BadgeKind.dots, BotColors.searching),
      scans: true),
  BotState.approval: const BotStateCfg(
      color: BotColors.approval,
      tint: 0.78,
      eye: EyeShape.wide,
      badge: BotBadge(BadgeKind.bang, BotColors.approval),
      bounces: true),
  BotState.question: const BotStateCfg(
      color: BotColors.question,
      tint: 0.75,
      eye: EyeShape.pill,
      badge: BotBadge(BadgeKind.question, BotColors.question),
      tilt: 0.17),
  BotState.error: const BotStateCfg(
      color: BotColors.error, tint: 0.78, eye: EyeShape.flat, badge: BotBadge(BadgeKind.dot, BotColors.error)),
  BotState.finished: const BotStateCfg(
      color: BotColors.finished, tint: 0.35, eye: EyeShape.happy, badge: BotBadge(BadgeKind.dot, BotColors.finished)),
  BotState.ratelimit: const BotStateCfg(
      color: BotColors.ratelimit,
      tint: 0.72,
      eye: EyeShape.tired,
      badge: BotBadge(BadgeKind.dot, BotColors.ratelimit),
      sweat: true),
  BotState.sleeping: const BotStateCfg(
      color: BotColors.sleeping, tint: 0.32, eye: EyeShape.closed, breathes: true, zz: true),
  BotState.dizzy: const BotStateCfg(color: BotColors.dizzy, tint: 0.7, eye: EyeShape.spiral),
};

/// État → son (BotStateCfg.sound).
const Map<BotState, String> stateSound = {
  BotState.working: 'work',
  BotState.thinking: 'think',
  BotState.searching: 'search',
  BotState.approval: 'approval',
  BotState.question: 'question',
  BotState.error: 'error',
  BotState.finished: 'finish',
  BotState.ratelimit: 'rate',
  BotState.sleeping: 'sleep',
  BotState.dizzy: 'dizzy',
};

const Map<BotEmote, EyeShape> _emoteEye = {
  BotEmote.love: EyeShape.heart,
  BotEmote.surprised: EyeShape.dot,
  BotEmote.proud: EyeShape.star,
  BotEmote.wink: EyeShape.wink,
  BotEmote.yawn: EyeShape.tired,
  BotEmote.happy: EyeShape.happy,
  BotEmote.annoyed: EyeShape.line,
};

final Stopwatch _clock = Stopwatch()..start();
double _now() => _clock.elapsedMicroseconds / 1e6;
double _nowMs() => _clock.elapsedMicroseconds / 1e3;

final math.Random _rng = math.Random();

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t.clamp(0, 1))!;

Path _roundRect(double x, double y, double w, double h, double r) {
  final rr = math.max(0.0, math.min(r, math.min(w / 2, h / 2)));
  return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rr)));
}

Path _heart(double s) {
  return Path()
    ..moveTo(0, s * 0.38)
    ..cubicTo(-s * 1.05, -s * 0.15, -s * 0.5, -s * 0.95, 0, -s * 0.38)
    ..cubicTo(s * 0.5, -s * 0.95, s * 1.05, -s * 0.15, 0, s * 0.38)
    ..close();
}

Path _star(double ro, double ri) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isOdd ? ri : ro;
    final a = -math.pi / 2 + (i * math.pi) / 5;
    final pt = Offset(math.cos(a) * r, math.sin(a) * r);
    if (i == 0) {
      p.moveTo(pt.dx, pt.dy);
    } else {
      p.lineTo(pt.dx, pt.dy);
    }
  }
  return p..close();
}

// ── Moteur ────────────────────────────────────────────────────────────────────

class BotEngine extends ChangeNotifier {
  BotEngine({this.isMini = false, this.bodyColor});

  final bool isMini;

  /// Couleur unie du corps pour les mini Fractus des pastilles (null = dégradé de Fractus).
  Color? bodyColor;

  // État animé (BotEngine `s`)
  double yaw = 0, pitch = 0, roll = 0, tilt = 0, open = 1;
  double sx = 1, sy = 1, oy = 0, ox = 0;
  double tint = 0, blush = 0, es = 1, badgeS = 0;

  // Cibles
  double tgYaw = 0, tgPitch = 0, tgTilt = 0, tgSy = 1, tgSx = 1, tgEs = 1;

  /// Hauteur supplémentaire au-dessus du corps pour que les cœurs sortent sans être coupés.
  double particleOverhang = 0;

  Color col = BotColors.idle;
  Color colT = BotColors.idle;

  BotState state = BotState.idle;
  BotStateCfg cfg = botStates[BotState.idle]!;

  EyeShape? eyeOverride;
  double eyeOverrideUntil = 0;
  EyeShape? permanentEye;
  BotEmote? permanentEmote;
  double miniNextBehavior = 0;

  BotBadge? badge;
  String _badgeKey = 'none';
  int _badgeToken = 0;

  final Map<_Prop, _Tween> _tweens = {};
  final Set<_Prop> _locks = {};
  final List<_Particle> _particles = [];

  double lookX = 0;
  double lookY = 0;

  double lastTime = _now();
  final double _t0 = _now() - _rng.nextDouble() * 5;
  double _nextBlink = _now() + 1.5 + _rng.nextDouble() * 2;
  double waveUntil = 0;
  double waveStart = 0;
  int _greetToken = 0;
  double _lastAmbient = 0;
  final List<double> _slapTimes = [];
  Offset _miniLookTarget = Offset.zero;
  double _miniLookNextTime = 0;

  /// Trois tapes en 1,7 s → étourdi (+ vue « confused »).
  VoidCallback? onDizzy;

  /// Un son à jouer (le propriétaire décide : coupé ou non).
  void Function(String name)? onSound;

  final List<Timer> _timers = [];

  void _later(int ms, VoidCallback fn) {
    late Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (!_disposed) fn();
    });
    _timers.add(t);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  // ── API publique ───────────────────────────────────────────────────────────

  void setState(BotState next, {bool force = false}) {
    if (state == next && !force) return;
    final prev = state;
    state = next;
    cfg = botStates[next]!;
    colT = cfg.color;
    if (!_locks.contains(_Prop.tint)) tint = cfg.tint;
    if (!_locks.contains(_Prop.tilt)) tgTilt = cfg.tilt;
    setBadge(cfg.badge);

    switch (next) {
      case BotState.finished:
        doRoll(950, 1);
        _later(500, () => _emit(_PType.spark, 5));
        break;
      case BotState.error:
        _anim(_Prop.ox, [
          _Key(0.08, 50, Ease.out),
          _Key(-0.08, 70, Ease.inOut),
          _Key(0.05, 70, Ease.inOut),
          _Key(0, 90, Ease.out),
        ]);
        break;
      case BotState.approval:
        _anim(_Prop.oy, [_Key(-0.2, 150, Ease.out), _Key(0, 300, Ease.back)]);
        break;
      case BotState.dizzy:
        doRoll(1300, 2);
        break;
      case BotState.question:
        blink();
        break;
      case BotState.ratelimit:
        _emit(_PType.sweat, 1);
        break;
      default:
        if (prev != BotState.idle || next != BotState.idle) blink();
    }
  }

  void setBadge(BotBadge? b) {
    final key = b?.key ?? 'none';
    if (key == _badgeKey) return;
    _badgeKey = key;
    final tok = ++_badgeToken;
    _anim(_Prop.badgeS, [_Key(0, 90, Ease.inOut)]);
    _later(100, () {
      if (tok != _badgeToken) return;
      badge = b;
      if (b != null) _anim(_Prop.badgeS, [_Key(1, 280, Ease.back)]);
    });
  }

  void blink() {
    if (_locks.contains(_Prop.open)) return;
    _anim(_Prop.open, [_Key(0.06, 70, Ease.inOut), _Key(1, 130, Ease.out)]);
  }

  void squash() {
    _anim(_Prop.sy, [_Key(0.78, 70, Ease.out), _Key(1.1, 130, Ease.out), _Key(1, 170, Ease.inOut)]);
    _anim(_Prop.sx, [_Key(1.16, 70, Ease.out), _Key(0.95, 130, Ease.out), _Key(1, 170, Ease.inOut)]);
  }

  void slap() {
    interruptGreet();
    if (state == BotState.dizzy) return;
    final t = _now();
    _slapTimes.removeWhere((s) => t - s >= 1.7);
    _slapTimes.add(t);
    onSound?.call('slap');
    squash();
    if (_slapTimes.length >= 3) {
      _slapTimes.clear();
      onDizzy?.call();
    } else {
      eyeOverride = EyeShape.line;
      eyeOverrideUntil = t + 0.8;
      _later(60, () => onSound?.call('annoyed'));
    }
  }

  void doRoll(int durationMs, int turns) {
    roll = 0;
    _anim(_Prop.roll, [_Key(math.pi * 2 * turns, durationMs.toDouble(), Ease.inOut)], () => roll = 0);
  }

  /// Le petit salut de la main — le « coucou ». Timings de BotEngine.greet().
  void greet() {
    final t = _now();
    final tok = ++_greetToken;
    waveStart = t + 0.45;
    waveUntil = t + 1.55;

    eyeOverride = EyeShape.happy;
    eyeOverrideUntil = t + 2.0;
    _anim(_Prop.oy, [_Key(-0.06, 220, Ease.out), _Key(0.0, 220, Ease.back)]);

    _later(250, () {
      if (_greetToken != tok) return;
      _anim(_Prop.sy, [_Key(0.95, 100, Ease.out), _Key(1.0, 260, Ease.back)]);
      _anim(_Prop.sx, [_Key(1.04, 100, Ease.out), _Key(1.0, 260, Ease.back)]);
      onSound?.call('greet');
    });
    _later(550, () {
      if (_greetToken == tok) blink();
    });
    _later(1500, () {
      if (_greetToken == tok) blink();
    });
    _later(1550, () {
      if (_greetToken != tok) return;
      waveUntil = 0;
    });
    _later(1750, () {
      if (_greetToken != tok) return;
      eyeOverride = EyeShape.happy;
      eyeOverrideUntil = _now() + 0.3;
    });
  }

  double get hands {
    // La main se lève avec le salut (0 → 1 en 280 ms, retombe en 200 ms).
    final n = _now();
    if (waveStart == 0 || waveUntil == 0) return 0;
    if (n < waveStart - 0.2) return 0;
    if (n < waveStart + 0.08) return clamp((n - (waveStart - 0.2)) / 0.28, 0, 1);
    if (n < waveUntil) return 1;
    return clamp(1 - (n - waveUntil) / 0.2, 0, 1);
  }

  void interruptGreet() {
    if (_now() >= waveUntil) return;
    _greetToken++;
    waveUntil = 0;
    waveStart = 0;
  }

  void setPermanentEmote(BotEmote? emote) {
    permanentEmote = emote;
    if (emote == BotEmote.wink) {
      miniNextBehavior = _now() + 0.8 + _rng.nextDouble() * 1.7;
      return;
    }
    permanentEye = emote == null ? null : _emoteEye[emote];
    if (permanentEye != null) {
      eyeOverride = permanentEye;
      eyeOverrideUntil = double.infinity;
    } else if (eyeOverrideUntil == double.infinity) {
      eyeOverride = null;
      eyeOverrideUntil = 0;
    }
    miniNextBehavior = _now() + 0.8 + _rng.nextDouble() * 1.7;
  }

  void triggerEmote(BotEmote emote, {double duration = 1.8}) {
    final t = _now();
    eyeOverride = _emoteEye[emote];
    eyeOverrideUntil = t + duration;

    switch (emote) {
      case BotEmote.love:
        _anim(_Prop.blush, [
          _Key(1, 300, Ease.out),
          _Key(1, (duration - 0.6) * 1000, Ease.lin),
          _Key(0, 300, Ease.inOut),
        ]);
        _emit(_PType.heart, 4);
        _anim(_Prop.oy, [_Key(-0.1, 160, Ease.out), _Key(0, 300, Ease.back)]);
        break;
      case BotEmote.surprised:
        _anim(_Prop.oy, [_Key(-0.3, 140, Ease.out), _Key(0, 380, Ease.back)]);
        _anim(_Prop.es, [_Key(1.25, 120, Ease.out), _Key(1, 500, Ease.inOut)]);
        break;
      case BotEmote.proud:
        _emit(_PType.star, 5);
        _anim(_Prop.tilt, [
          _Key(-0.14, 220, Ease.out),
          _Key(-0.14, (duration - 0.5) * 1000, Ease.lin),
          _Key(0, 280, Ease.inOut),
        ]);
        _anim(_Prop.blush, [
          _Key(0.7, 250, Ease.out),
          _Key(0.7, (duration - 0.5) * 1000, Ease.lin),
          _Key(0, 300, Ease.inOut),
        ]);
        break;
      case BotEmote.wink:
        _anim(_Prop.tilt, [
          _Key(0.12, 160, Ease.out),
          _Key(0.12, (duration - 0.4) * 1000, Ease.lin),
          _Key(0, 240, Ease.inOut),
        ]);
        break;
      case BotEmote.yawn:
        _anim(_Prop.sy, [_Key(1.12, 500, Ease.inOut), _Key(1, 500, Ease.inOut)]);
        _anim(_Prop.sx, [_Key(0.94, 500, Ease.inOut), _Key(1, 500, Ease.inOut)]);
        _later(700, () {
          eyeOverride = EyeShape.closed;
          _emit(_PType.z, 2);
        });
        break;
      case BotEmote.happy:
        _anim(_Prop.blush, [_Key(0.6, 200, Ease.out), _Key(0, 600, Ease.inOut)]);
        break;
      case BotEmote.annoyed:
        eyeOverride = EyeShape.line;
        eyeOverrideUntil = t + 0.8;
        _later(60, () => onSound?.call('annoyed'));
        break;
    }
  }

  void _emit(_PType type, int count) {
    for (var i = 0; i < count; i++) {
      final isZ = type == _PType.z;
      _particles.add(_Particle(
        type,
        (_rng.nextDouble() - 0.5) * 0.9 + (isZ ? 0.55 : 0),
        -0.7 - _rng.nextDouble() * 0.2,
        (_rng.nextDouble() - 0.5) * 0.35 + (isZ ? 0.18 : 0),
        -(0.45 + _rng.nextDouble() * 0.35),
        -i * 0.14,
        1.3 + _rng.nextDouble() * 0.5,
        _rng.nextDouble() * math.pi * 2,
        0.15 + _rng.nextDouble() * 0.08,
      ));
    }
  }

  void emitHearts(int n) => _emit(_PType.heart, n);
  void emitStars(int n) => _emit(_PType.star, n);

  /// Vrai tant que quelque chose bouge encore.
  bool get busy {
    return _tweens.isNotEmpty ||
        _particles.isNotEmpty ||
        cfg.bounces ||
        cfg.scans ||
        cfg.breathes ||
        cfg.zz ||
        cfg.sweat ||
        isMini ||
        (tgYaw - yaw).abs() > 0.002 ||
        (tgPitch - pitch).abs() > 0.002 ||
        (tgTilt - tilt).abs() > 0.002 ||
        (tgSy - sy).abs() > 0.002 ||
        (tgSx - sx).abs() > 0.002 ||
        (tgEs - es).abs() > 0.002 ||
        col != colT;
  }

  // ── Tweens ─────────────────────────────────────────────────────────────────

  double _get(_Prop p) {
    switch (p) {
      case _Prop.yaw:
        return yaw;
      case _Prop.pitch:
        return pitch;
      case _Prop.roll:
        return roll;
      case _Prop.tilt:
        return tilt;
      case _Prop.open:
        return open;
      case _Prop.sx:
        return sx;
      case _Prop.sy:
        return sy;
      case _Prop.oy:
        return oy;
      case _Prop.ox:
        return ox;
      case _Prop.tint:
        return tint;
      case _Prop.blush:
        return blush;
      case _Prop.es:
        return es;
      case _Prop.badgeS:
        return badgeS;
    }
  }

  void _set(_Prop p, double v) {
    switch (p) {
      case _Prop.yaw:
        yaw = v;
      case _Prop.pitch:
        pitch = v;
      case _Prop.roll:
        roll = v;
      case _Prop.tilt:
        tilt = v;
      case _Prop.open:
        open = v;
      case _Prop.sx:
        sx = v;
      case _Prop.sy:
        sy = v;
      case _Prop.oy:
        oy = v;
      case _Prop.ox:
        ox = v;
      case _Prop.tint:
        tint = v;
      case _Prop.blush:
        blush = v;
      case _Prop.es:
        es = v;
      case _Prop.badgeS:
        badgeS = v;
    }
  }

  void _anim(_Prop prop, List<_Key> keys, [VoidCallback? onComplete]) {
    _tweens[prop] = _Tween(prop, keys, _get(prop), _nowMs(), onComplete);
    _locks.add(prop);
  }

  // ── Mise à jour ────────────────────────────────────────────────────────────

  void update(double dt) {
    final n = _now();
    final nowMs = _nowMs();

    for (final tw in _tweens.values.toList()) {
      final k = tw.keys[tw.index];
      final p = clamp((nowMs - tw.startMs) / math.max(1, k.durationMs), 0, 1);
      _set(tw.prop, tw.from + (k.target - tw.from) * k.ease(p));
      if (p >= 1) {
        tw.from = k.target;
        tw.index += 1;
        tw.startMs = nowMs;
        if (tw.index >= tw.keys.length) {
          _tweens.remove(tw.prop);
          _locks.remove(tw.prop);
          tw.onComplete?.call();
        }
      }
    }

    final t = n - _t0;
    var ty = lookX * 0.62;
    var tp = lookY * 0.5;

    if (cfg.look != null) {
      ty = ty * 0.35 + cfg.look!.dx * 0.55;
      tp = tp * 0.3 + cfg.look!.dy * 0.5;
    }
    if (cfg.scans) {
      ty = math.sin(t * 2.6) * 0.6;
      tp = -0.06;
    }
    if (state == BotState.sleeping) {
      ty = 0;
      tp = -0.14;
    }
    if (state == BotState.dizzy) ty = math.sin(t * 9) * 0.25;

    // Les mini Fractus ne suivent jamais la souris : ils regardent ailleurs.
    if (isMini && cfg.look == null && !cfg.scans && state != BotState.sleeping && state != BotState.dizzy) {
      if (n > _miniLookNextTime) {
        _miniLookTarget = Offset(-0.88 + _rng.nextDouble() * 1.76, -0.55 + _rng.nextDouble() * 1.0);
        _miniLookNextTime = n + 0.5 + _rng.nextDouble() * 1.5;
      }
      ty = _miniLookTarget.dx * 0.62;
      tp = _miniLookTarget.dy * 0.5;
    }

    tgYaw = ty;
    tgPitch = tp;
    tgTilt = cfg.tilt;

    if (n > waveStart && n < waveUntil) {
      final wt = n - waveStart;
      tgTilt = -0.06 + math.sin(2 * math.pi * 1.2 * wt) * 0.07;
    }

    final bounce = cfg.bounces ? -(math.sin(t * 5.2)).abs() * 0.07 : 0.0;
    final kGen = 1 - math.pow(0.0008, dt).toDouble();
    if (!_locks.contains(_Prop.oy)) oy += (bounce - oy) * kGen;

    if (cfg.breathes) {
      final amp = isMini ? 0.07 : 0.035;
      tgSy = 1 + math.sin(t * 1.8) * amp;
      tgSx = 1 - math.sin(t * 1.8) * amp * 0.57;
    } else if (isMini) {
      tgSy = 1 + math.sin(t * 2.2) * 0.04;
      tgSx = 1 - math.sin(t * 2.2) * 0.02;
    } else {
      tgSy = 1;
      tgSx = 1;
    }

    if (isMini && n > miniNextBehavior) _doMiniBehaviorLoop();

    final kLook = 1 - math.pow(0.0025, dt).toDouble();
    if (!_locks.contains(_Prop.yaw)) yaw += (tgYaw - yaw) * kLook;
    if (!_locks.contains(_Prop.pitch)) pitch += (tgPitch - pitch) * kLook;
    if (!_locks.contains(_Prop.tilt)) tilt += (tgTilt - tilt) * kGen;
    if (!_locks.contains(_Prop.sy)) sy += (tgSy - sy) * kGen;
    if (!_locks.contains(_Prop.sx)) sx += (tgSx - sx) * kGen;
    if (!_locks.contains(_Prop.es)) es += (tgEs - es) * kGen;

    col = _mix(col, colT, 1 - math.pow(0.002, dt).toDouble());

    if (n > _nextBlink) {
      if (state != BotState.sleeping && state != BotState.dizzy) {
        blink();
        if (_rng.nextDouble() < 0.22) _later(230, blink);
      }
      _nextBlink = n + 2.2 + _rng.nextDouble() * 3.2;
    }

    if (eyeOverride != null && n > eyeOverrideUntil) {
      eyeOverride = permanentEye;
      if (permanentEye != null) eyeOverrideUntil = double.infinity;
    }

    if (n - _lastAmbient > 1.3) {
      _lastAmbient = n;
      if (cfg.zz) _emit(_PType.z, 1);
      if (!isMini && cfg.sweat && _rng.nextDouble() < 0.5) _emit(_PType.sweat, 1);
    }

    for (final p in _particles) {
      p.age += dt;
    }
    _particles.removeWhere((p) => p.age >= p.life);

    lastTime = n;
    notifyListeners();
  }

  void _doMiniBehaviorLoop() {
    final n = _now();
    switch (permanentEmote) {
      case BotEmote.happy:
        if (_locks.contains(_Prop.oy)) {
          miniNextBehavior = n + 0.4;
          return;
        }
        _anim(_Prop.oy, [_Key(-0.3, 120, Ease.out), _Key(0.03, 200, Ease.inOut), _Key(0, 160, Ease.back)]);
        _anim(_Prop.sy, [
          _Key(0.82, 80, Ease.out),
          _Key(1.18, 130, Ease.out),
          _Key(0.88, 160, Ease.inOut),
          _Key(1, 200, Ease.back)
        ]);
        _anim(_Prop.sx, [
          _Key(1.15, 80, Ease.out),
          _Key(0.88, 130, Ease.out),
          _Key(1.06, 160, Ease.inOut),
          _Key(1, 200, Ease.back)
        ]);
        miniNextBehavior = n + 2.2 + _rng.nextDouble() * 1.2;
        break;
      case BotEmote.annoyed:
        if (_locks.contains(_Prop.yaw)) {
          miniNextBehavior = n + 0.5;
          return;
        }
        _anim(_Prop.yaw, [
          _Key(-0.65, 50, Ease.out),
          _Key(0.65, 90, Ease.inOut),
          _Key(-0.5, 80, Ease.inOut),
          _Key(0.4, 75, Ease.inOut),
          _Key(-0.2, 70, Ease.inOut),
          _Key(0, 140, Ease.out),
        ]);
        miniNextBehavior = n + 3.0 + _rng.nextDouble() * 2.5;
        break;
      case BotEmote.wink:
        eyeOverride = EyeShape.wink;
        eyeOverrideUntil = n + 0.55;
        _anim(_Prop.tilt, [_Key(0.13, 100, Ease.out), _Key(0.13, 320, Ease.lin), _Key(0, 200, Ease.inOut)]);
        miniNextBehavior = n + 2.2 + _rng.nextDouble() * 2.0;
        break;
      case BotEmote.love:
        _emit(_PType.heart, 2);
        _anim(_Prop.tilt, [_Key(-0.1, 180, Ease.out), _Key(0.1, 340, Ease.inOut), _Key(0, 220, Ease.inOut)]);
        miniNextBehavior = n + 2.6 + _rng.nextDouble() * 1.5;
        break;
      default:
        miniNextBehavior = n + 3.0 + _rng.nextDouble() * 2.0;
    }
  }

  // ── Dessin ─────────────────────────────────────────────────────────────────

  /// Dessine mains, corps, joues, yeux, badge et particules dans un canvas de W×H.
  void draw(ui.Canvas x, double W, double H) {
    final R = W * 0.3;
    final rx = R * 1.14;
    final ry = R * 0.88;
    final cx = W / 2 + ox * R;
    final cy = H / 2 + particleOverhang / 2 + oy * R + R * 0.06;

    _drawHandsBehind(x, R, rx, ry, cx, cy);

    x.save();
    x.translate(cx, cy);
    if (tilt != 0) x.rotate(tilt);
    x.scale(sx, sy);

    final body = _bodyPath(rx, ry, R);
    _drawBody(x, body, R, rx, ry);

    final blushVal = math.max(blush, tint * 0.5);
    if (blushVal > 0.01) {
      x.save();
      x.clipPath(body);
      final yOffset = math.sin(yaw) * rx * 0.8;
      final paint = Paint()..color = const Color(0xFFFF7896).withValues(alpha: 0.5 * blushVal);
      for (final sd in [-1, 1]) {
        x.drawOval(
          Rect.fromCenter(center: Offset(sd * rx * 0.55 + yOffset, ry * 0.2), width: R * 0.34, height: R * 0.2),
          paint,
        );
      }
      x.restore();
    }

    _drawEyes(x, body, R, rx, ry);
    x.restore();

    if (badge != null && badgeS > 0.01) _drawBadge(x, badge!, R, cx, cy);
    _drawParticles(x, R, cx, cy);
  }

  /// Les six sommets de la gemme (pointe en haut et en bas, flancs droits),
  /// dans l'ordre horaire à partir du sommet du haut.
  List<Offset> _gemVertices(double rx, double ry) {
    return [
      Offset(0, -ry * 1.06),
      Offset(rx * 0.98, -ry * 0.46),
      Offset(rx * 0.98, ry * 0.46),
      Offset(0, ry * 1.06),
      Offset(-rx * 0.98, ry * 0.46),
      Offset(-rx * 0.98, -ry * 0.46),
    ];
  }

  /// Le contour : un hexagone aux angles adoucis (courbes entre les milieux
  /// des côtés), pour garder le côté « doudou » malgré les facettes.
  Path _bodyPath(double rx, double ry, double R) {
    final v = _gemVertices(rx, ry);
    const k = 0.34; // part de chaque côté adoucie autour du sommet
    final p = Path();
    for (var i = 0; i < v.length; i++) {
      final prev = v[(i - 1 + v.length) % v.length];
      final cur = v[i];
      final next = v[(i + 1) % v.length];
      final a = Offset.lerp(cur, prev, k)!;
      final b = Offset.lerp(cur, next, k)!;
      if (i == 0) {
        p.moveTo(a.dx, a.dy);
      } else {
        p.lineTo(a.dx, a.dy);
      }
      p.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    return p..close();
  }

  void _drawBody(ui.Canvas x, Path body, double R, double rx, double ry) {
    if (bodyColor != null) {
      // Mini Fractus : aplat uni — pas de dégradé, juste une facette claire.
      x.drawPath(body, Paint()..color = bodyColor!);
      x.save();
      x.clipPath(body);
      x.drawPath(
        _facet(rx, ry, 0),
        Paint()..color = const Color(0x2EFFFFFF),
      );
      x.restore();
      return;
    }

    // Le verre : clair en haut à droite, plus dense en bas à gauche.
    x.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(rx * 0.7, -ry * 0.85),
          Offset(-rx * 0.8, ry * 0.9),
          [_baseTop, _baseBottom],
        ),
    );

    // La teinte de l'état monte depuis le bas, comme une lumière dans la pierre.
    if (tint > 0.01) {
      x.drawPath(
        body,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, ry),
            Offset(0, -ry),
            [col.withValues(alpha: 0.72 * tint), col.withValues(alpha: 0)],
          ),
      );
    }

    // Les facettes : quatre triangles translucides qui partent du cœur.
    x.save();
    x.clipPath(body);
    x.drawPath(_facet(rx, ry, 0), Paint()..color = const Color(0x40FFFFFF)); // haut-gauche : lumière
    x.drawPath(_facet(rx, ry, 1), Paint()..color = _accent.withValues(alpha: 0.10 + 0.08 * (1 - tint))); // haut-droite : accent
    x.drawPath(_facet(rx, ry, 2), Paint()..color = const Color(0x12000000)); // bas-droite : ombre
    x.drawPath(_facet(rx, ry, 3), Paint()..color = const Color(0x1F000000)); // bas-gauche : ombre dense
    // Les arêtes, à peine marquées.
    final edges = Paint()
      ..color = const Color(0x38FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, R * 0.035);
    final v = _gemVertices(rx, ry);
    final heart = Offset(-rx * 0.08, ry * 0.08);
    for (final i in [1, 2, 4, 5]) {
      x.drawLine(heart, Offset.lerp(heart, v[i], 0.92)!, edges);
    }
    x.restore();

    // Ombre vers les bords.
    x.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          R * 1.25,
          [const Color(0x00000000), const Color(0x00000000), const Color(0x33000000)],
          [0.0, 0.6, 1.0],
        ),
    );

    // Reflet en haut à droite.
    x.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(rx * 0.34, -ry * 0.46),
          R * 0.42,
          [const Color(0x8CFFFFFF), const Color(0x00FFFFFF)],
        ),
    );

    // Le liseré : un fin contour qui fait « verre ».
    x.drawPath(
      body,
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, R * 0.04),
    );
  }

  /// Une facette : le triangle (cœur, sommet i, sommet i+1) d'un des quatre
  /// quadrants — 0 haut-gauche, 1 haut-droite, 2 bas-droite, 3 bas-gauche.
  Path _facet(double rx, double ry, int quadrant) {
    final v = _gemVertices(rx, ry);
    final heart = Offset(-rx * 0.08, ry * 0.08);
    final List<Offset> pts;
    switch (quadrant) {
      case 0:
        pts = [heart, v[5], v[0]];
      case 1:
        pts = [heart, v[0], v[1]];
      case 2:
        pts = [heart, v[2], v[3]];
      default:
        pts = [heart, v[3], v[4]];
    }
    return Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..close();
  }

  void _drawEyes(ui.Canvas x, Path body, double R, double rx, double ry) {
    final shape = eyeOverride ?? cfg.eye;

    x.save();
    x.clipPath(body);
    final ink = isMini ? _miniInk : _ink;

    for (final sd in [-1, 1]) {
      final eyeYaw = sd * _eyeSp + yaw;
      var eyePitch = _eyeP + pitch + roll;
      eyePitch = (((eyePitch + math.pi) % (math.pi * 2)) + math.pi * 2) % (math.pi * 2) - math.pi;
      final cp = math.cos(eyePitch);
      if (math.cos(eyeYaw) * cp <= 0.04) continue;

      final ex = math.sin(eyeYaw) * cp * rx;
      final ey = -math.sin(eyePitch) * ry;
      final fx = math.max(0.18, math.cos(eyeYaw));
      final fy = math.max(0.18, cp);
      final eyeMult = isMini ? 1.9 : 1.0;
      final ew = R * _eyeW * es * eyeMult;
      final eh = R * _eyeH * es * eyeMult;

      x.save();
      x.translate(ex, ey);
      x.scale(fx, fy);
      _drawEyeShape(x, shape, ew, eh, sd, ink);
      x.restore();
    }
    x.restore();
  }

  void _drawEyeShape(ui.Canvas x, EyeShape shape, double w, double h, int sd, Color ink) {
    final t = _now();
    final fill = Paint()..color = ink;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (shape) {
      case EyeShape.wide:
        _drawEyeShape(x, EyeShape.pill, w * 1.16, h * 1.12, sd, ink);
        break;
      case EyeShape.pill:
        final hh = math.max(h * open, w * 0.3);
        x.drawPath(_roundRect(-w / 2, -hh / 2, w, hh, math.min(w / 2, hh / 2)), fill);
        break;
      case EyeShape.dot:
        x.drawCircle(Offset.zero, w * 0.45, fill);
        break;
      case EyeShape.line:
        x.rotate(-sd * 0.2);
        x.drawPath(_roundRect(-w * 0.78, -w * 0.21, w * 1.56, w * 0.42, w * 0.21), fill);
        break;
      case EyeShape.flat:
        x.drawPath(_roundRect(-w * 0.72, -w * 0.2, w * 1.44, w * 0.4, w * 0.2), fill);
        break;
      case EyeShape.happy:
        stroke.strokeWidth = w * 0.5;
        x.drawArc(Rect.fromCircle(center: Offset(0, h * 0.18), radius: w * 0.82), math.pi * 1.12,
            math.pi * 0.76, false, stroke);
        break;
      case EyeShape.closed:
        stroke.strokeWidth = w * 0.36;
        x.drawArc(Rect.fromCircle(center: Offset(0, -h * 0.08), radius: w * 0.78), math.pi * 0.15,
            math.pi * 0.70, false, stroke);
        break;
      case EyeShape.spiral:
        stroke.strokeWidth = w * 0.22;
        final p = Path();
        var first = true;
        for (var a = 0.0; a < 4.4 * math.pi; a += 0.2) {
          final r = w * 0.06 + a * w * 0.058;
          final aa = a + t * 9 * sd;
          final px = math.cos(aa) * r;
          final py = math.sin(aa) * r;
          if (first) {
            p.moveTo(px, py);
            first = false;
          } else {
            p.lineTo(px, py);
          }
        }
        x.drawPath(p, stroke);
        break;
      case EyeShape.heart:
        x.drawPath(_heart(w * 1.2), Paint()..color = const Color(0xFFFF4D6D));
        break;
      case EyeShape.star:
        x.rotate(t * 1.5 * sd);
        x.drawPath(_star(w * 1.05, w * 0.46), Paint()..color = const Color(0xFFF7B32B));
        break;
      case EyeShape.tired:
        x.drawPath(_roundRect(-w / 2, -h * 0.02, w, h * 0.38, w / 2), fill);
        x.drawPath(_roundRect(-w * 0.62, -h * 0.1, w * 1.24, w * 0.22, w * 0.11), fill);
        break;
      case EyeShape.wink:
        if (sd < 0) {
          final hh = math.max(h * open, w * 0.3);
          x.drawPath(_roundRect(-w / 2, -hh / 2, w, hh, math.min(w / 2, hh / 2)), fill);
        } else {
          stroke.strokeWidth = w * 0.5;
          x.drawArc(Rect.fromCircle(center: Offset(0, h * 0.18), radius: w * 0.82), math.pi * 1.12,
              math.pi * 0.76, false, stroke);
        }
        break;
    }
  }

  /// Les mains sont derrière le corps — dessinées avant lui, en coordonnées monde.
  void _drawHandsBehind(ui.Canvas x, double R, double rx, double ry, double cx, double cy) {
    final hv = hands;
    if (hv <= 0.01 || isMini) return;
    if (R <= 14) return; // sans intérêt aux tailles compacte / peek

    final n = _now();
    final bodyH = 2 * ry;
    final hew = 0.3 * ry * hv;
    final heh = 0.26 * ry * hv;
    final hwB = rx * sx;
    final hhB = ry * sy;
    final isWaving = n >= waveStart && waveStart > 0 && n < waveUntil;

    for (final sd in [-1, 1]) {
      double localX;
      double localY;
      var handRot = 0.0;

      if (sd > 0 && isWaving) {
        final wt = n - waveStart;
        final rise = math.min(1.0, wt / 0.18);
        final riseEased = 1 - math.pow(1 - rise, 3).toDouble();
        final restX = hwB * 1.08;
        final restY = hhB * 0.7;
        final oscX = math.cos(13 * wt) * 0.06 * bodyH;
        final oscY = -math.sin(13 * wt) * 0.14 * bodyH;
        final waveX = hwB * 1.1 + oscX;
        final waveY = -hhB * 0.15 + oscY;
        localX = restX + (waveX - restX) * riseEased;
        localY = restY + (waveY - restY) * riseEased;
        handRot = (-0.5 + math.sin(13 * wt) * 0.35) * riseEased;
      } else if (sd < 0 && isWaving) {
        final wt = n - waveStart;
        localX = -hwB * 1.08;
        localY = hhB * 0.7 + math.sin(6 * wt) * 0.04 * bodyH;
      } else {
        localX = sd * hwB * 1.08;
        localY = hhB * 0.7;
      }

      final cosT = math.cos(tilt);
      final sinT = math.sin(tilt);
      final worldX = cx + cosT * localX - sinT * localY;
      final worldY = cy + sinT * localX + cosT * localY;

      x.save();
      x.translate(worldX, worldY);
      if (handRot != 0) x.rotate(handRot);
      final rect = Rect.fromCenter(center: Offset.zero, width: hew * 2, height: heh * 2);
      x.drawOval(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(hew * 0.7, -heh * 0.85),
            Offset(-hew * 0.8, heh * 0.9),
            [_baseTop, _baseBottom],
          ),
      );
      x.drawOval(
        rect,
        Paint()
          ..color = const Color(0x14000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      x.restore();
    }
  }

  void _drawBadge(ui.Canvas x, BotBadge badge, double R, double cx, double cy) {
    final bs = badgeS * (isMini ? 1.25 : 1);
    final bx = cx - R * 0.72 * sx;
    final by = cy - R * 0.72 * sy;
    final t = _now();

    x.save();
    x.translate(bx, by);
    x.scale(bs, bs);
    final col = Paint()..color = badge.color;
    final black = Paint()..color = const Color(0xFF000000);
    final white = Paint()..color = const Color(0xFFFFFFFF);

    switch (badge.kind) {
      case BadgeKind.dots:
        if (isMini) {
          final phase = (t * 2.4) % 1;
          final dotR = R * 0.22 * (1 + 0.25 * math.sin(phase * math.pi * 2));
          x.drawCircle(Offset.zero, R * 0.2, black);
          x.drawCircle(Offset.zero, dotR, col);
        } else {
          final pw = R * 0.72;
          final ph = R * 0.36;
          x.drawPath(_roundRect(-pw / 2, -ph / 2, pw, ph, ph / 2), col);
          for (var i = 0; i < 3; i++) {
            final phase = (((t * 2.4 - i * 0.22) % 1) + 1) % 1;
            final dotR = R * 0.055 * (1 + 0.4 * math.max(0.0, math.sin(phase * math.pi * 2)));
            x.drawCircle(Offset((i - 1) * R * 0.18, 0), dotR, white);
          }
        }
        break;
      case BadgeKind.bang:
      case BadgeKind.question:
        x.drawCircle(Offset.zero, R * 0.3, black);
        x.drawCircle(Offset.zero, R * 0.23, col);
        if (!isMini) {
          final tp = TextPainter(
            text: TextSpan(
              text: badge.kind == BadgeKind.bang ? '!' : '?',
              style: TextStyle(
                color: const Color(0xFFFFFFFF),
                fontSize: R * 0.32,
                fontWeight: FontWeight.w900,
                fontFamily: 'Segoe UI',
                height: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(x, Offset(-tp.width / 2, -tp.height / 2 + R * 0.02));
        }
        break;
      case BadgeKind.dot:
        x.drawCircle(Offset.zero, R * 0.2, black);
        x.drawCircle(Offset.zero, R * 0.135, col);
        break;
    }
    x.restore();
  }

  void _drawParticles(ui.Canvas x, double R, double cx, double cy) {
    for (final p in _particles) {
      if (p.age <= 0) continue;
      final k = p.age / p.life;
      final a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8;
      final px = cx + (p.x + p.vx * p.age) * R * 1.3;
      final py = cy + (p.y + p.vy * p.age) * R * 1.3;
      final sz = R * p.size * (1 + k * 0.4);
      final alpha = clamp(a, 0, 1);

      x.save();
      x.translate(px, py);
      switch (p.type) {
        case _PType.heart:
          x.rotate(math.sin(p.age * 6) * 0.3);
          x.drawPath(_heart(sz), Paint()..color = const Color(0xFFFF4D6D).withValues(alpha: alpha));
          break;
        case _PType.star:
          x.rotate(p.rot + p.age * 2);
          x.drawPath(_star(sz, sz * 0.45), Paint()..color = const Color(0xFFF7B32B).withValues(alpha: alpha));
          break;
        case _PType.spark:
          x.rotate(p.rot);
          x.drawPath(_star(sz * 0.8, sz * 0.18), Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha));
          break;
        case _PType.sweat:
          final path = Path()
            ..moveTo(0, -sz)
            ..quadraticBezierTo(sz * 0.8, sz * 0.2, 0, sz * 0.6)
            ..quadraticBezierTo(-sz * 0.8, sz * 0.2, 0, -sz)
            ..close();
          x.drawPath(path, Paint()..color = const Color(0xFF7CC7FF).withValues(alpha: alpha));
          break;
        case _PType.z:
          final tp = TextPainter(
            text: TextSpan(
              text: 'z',
              style: TextStyle(
                color: const Color(0xFFD1DBEB).withValues(alpha: alpha),
                fontSize: sz * 1.9,
                fontWeight: FontWeight.w700,
                fontFamily: 'Segoe UI',
                height: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(x, Offset(-tp.width / 2, -tp.height / 2));
          break;
      }
      x.restore();
    }
  }
}
