import 'dart:math';
import 'dart:ui' show Color, Offset, Size;

/// The fruits there are pictures for, and the colour of their juice.
const fruitKinds = [
  ('banana', Color(0xFFFAD13C)),
  ('blood_orange', Color(0xFFC0262A)),
  ('cantaloupe', Color(0xFFF59A3A)),
  ('coconut', Color(0xFFF5F0E6)),
  ('dragon_fruit', Color(0xFFEE3A8C)),
  ('green_apple', Color(0xFFD8E59A)),
  ('guava', Color(0xFFF47766)),
  ('kiwi', Color(0xFF7CC242)),
  ('lemon', Color(0xFFF5D84E)),
  ('lime', Color(0xFFB7D24E)),
  ('mango', Color(0xFFF89B10)),
  ('orange', Color(0xFFFA9C22)),
  ('papaya', Color(0xFFF57A2A)),
  ('passion_fruit', Color(0xFFF2B428)),
  ('peach', Color(0xFFF0A040)),
  ('pear', Color(0xFFEDE3B0)),
  ('pineapple', Color(0xFFF7D13A)),
  ('pink_grapefruit', Color(0xFFF0645A)),
  ('plum', Color(0xFFE0B040)),
  ('pomegranate', Color(0xFFC8202E)),
  ('red_apple', Color(0xFFF3DFA8)),
  ('star_fruit', Color(0xFFF5C83A)),
  ('strawberry', Color(0xFFF03C3C)),
  ('watermelon', Color(0xFFE8282A)),
];

enum FruitMode {
  /// Three lives: a fruit that falls uncut costs one, a bomb ends the game.
  classic,

  /// Sixty seconds to cut as much as possible; a bomb costs points.
  timed,
}

/// A bomb: cutting it ends a classic game.
const bombKind = -1;

/// A poison flask: cutting it costs a life (or points).
const poisonKind = -2;

/// A fruit, a bomb or a poison flask in the air.
class Flyer {
  Flyer(this.kind, this.pos, this.vel, this.radius, this.spin);

  /// Index into [fruitKinds], or [bombKind] / [poisonKind].
  final int kind;
  bool get bomb => kind == bombKind;
  bool get poison => kind == poisonKind;
  bool get fruit => kind >= 0;
  Offset pos, vel;
  final double radius, spin;
  double angle = 0;
}

/// One half of a cut fruit, tumbling away.
class Half {
  Half(
    this.kind,
    this.right,
    this.pos,
    this.vel,
    this.angle,
    this.spin,
    this.size,
  );
  final int kind;
  final bool right;
  Offset pos, vel;
  double angle;
  final double spin, size;
}

/// A drop of juice in the air.
class Drop {
  Drop(this.pos, this.vel, this.colour, this.size, this.life);
  Offset pos, vel;
  final Color colour;
  final double size, life;
  double age = 0;
}

/// A juice stain on the board, fading.
class Stain {
  Stain(this.pos, this.colour, this.size, this.seed);
  final Offset pos;
  final Color colour;
  final double size;
  final int seed;
  double age = 0;
  static const life = 3.0;
}

/// Points or a combo message floating up where it was earned.
class Popup {
  Popup(this.pos, this.text, this.big);
  final Offset pos;
  final String text;
  final bool big;
  double age = 0;
  static const life = 1.0;
}

/// The bright streak left where the blade went through something.
class Slash {
  Slash(this.pos, this.angle, this.length);
  final Offset pos;
  final double angle, length;
  double age = 0;
  static const life = .28;
}

/// What happened, for sounds and shakes.
class FruitEvents {
  int cut = 0, missed = 0, combo = 0, launched = 0;
  bool bomb = false, poison = false, over = false;
}

/// The game: fruit thrown up from the bottom of a [size] board, cut by
/// swipes.
class FruitGame {
  FruitGame({this.mode = FruitMode.classic, Random? random})
    : rng = random ?? Random();

  final FruitMode mode;
  final Random rng;

  Size size = const Size(400, 800);

  final flyers = <Flyer>[];
  final halves = <Half>[];
  final drops = <Drop>[];
  final stains = <Stain>[];
  final popups = <Popup>[];
  final slashes = <Slash>[];

  int score = 0, cut = 0, bestCombo = 0;
  int lives = 3;
  double time = 0;
  static const timedLength = 60.0;
  double get timeLeft => max(0, timedLength - time);

  bool started = false, over = false;

  /// Why it ended: a bomb, no lives left, or the clock.
  String? endedBy;

  /// Seconds since the last bomb went off, for the flash.
  double sinceBomb = 99;
  Offset bombAt = Offset.zero;

  /// Seconds since poison was cut, for the green flash.
  double sincePoison = 99;

  double _nextWave = .6;

  // The swipe in progress: how many fruits it has cut, and where.
  int _swipeCut = 0;
  Offset _swipeAt = Offset.zero;

  double get gravity => size.height * 1.15;

  void resize(Size s) => size = s;

  // ── Simulation ──

  FruitEvents update(double dt) {
    final ev = FruitEvents();
    sinceBomb += dt;
    sincePoison += dt;
    for (final d in drops) {
      d.age += dt;
      d.vel += Offset(0, gravity * .8 * dt);
      d.pos += d.vel * dt;
    }
    drops.removeWhere((d) => d.age >= d.life);
    for (final s in stains) {
      s.age += dt;
    }
    stains.removeWhere((s) => s.age >= Stain.life);
    for (final p in popups) {
      p.age += dt;
    }
    popups.removeWhere((p) => p.age >= Popup.life);
    for (final sl in slashes) {
      sl.age += dt;
    }
    slashes.removeWhere((sl) => sl.age >= Slash.life);
    for (final h in halves) {
      h.vel += Offset(0, gravity * dt);
      h.pos += h.vel * dt;
      h.angle += h.spin * dt;
    }
    halves.removeWhere((h) => h.pos.dy - h.size > size.height);
    if (!started || over) {
      // Whatever is still in the air keeps falling.
      for (final f in flyers) {
        f.vel += Offset(0, gravity * dt);
        f.pos += f.vel * dt;
      }
      flyers.removeWhere((f) => f.pos.dy - f.radius > size.height);
      return ev;
    }

    time += dt;
    if (mode == FruitMode.timed && time >= timedLength) {
      _end('time', ev);
      return ev;
    }

    _nextWave -= dt;
    if (_nextWave <= 0) {
      ev.launched += _wave();
      // Waves come faster as the game goes on.
      _nextWave = max(.7, 1.5 - time / 80) + rng.nextDouble() * .45;
    }

    for (final f in flyers) {
      f.vel += Offset(0, gravity * dt);
      f.pos += f.vel * dt;
      f.angle += f.spin * dt;
    }
    final fallen = flyers
        .where((f) => f.vel.dy > 0 && f.pos.dy - f.radius > size.height)
        .toList();
    for (final f in fallen) {
      flyers.remove(f);
      if (!f.fruit || mode != FruitMode.classic) continue;
      ev.missed++;
      lives--;
      popups.add(Popup(Offset(f.pos.dx, size.height - 40), '✕', true));
      if (lives <= 0) {
        _end('lives', ev);
        break;
      }
    }
    return ev;
  }

  void _end(String why, FruitEvents ev) {
    over = true;
    endedBy = why;
    ev.over = true;
    bestCombo = max(bestCombo, _swipeCut);
  }

  /// Throw a wave of fruit (and maybe a bomb or poison) up from the
  /// bottom.
  int _wave() {
    final level = time / 20;
    final most = min(6, 2 + level.floor() + (rng.nextDouble() < .35 ? 1 : 0));
    final count = 1 + rng.nextInt(most);
    final bombChance = mode == FruitMode.timed
        ? .14
        : (time < 4 ? 0.0 : min(.2, .08 + time / 400));
    final poisonChance = time < 6 ? 0.0 : min(.14, .06 + time / 600);
    var hazards = 0;
    for (var i = 0; i < count; i++) {
      var kind = rng.nextInt(fruitKinds.length);
      if (hazards < (time > 40 ? 2 : 1)) {
        final roll = rng.nextDouble();
        if (roll < bombChance) {
          kind = bombKind;
          hazards++;
        } else if (roll < bombChance + poisonChance) {
          kind = poisonKind;
          hazards++;
        }
      }
      launch(kind);
    }
    return count;
  }

  /// Throw one fruit (or [bombKind] / [poisonKind]) up from the bottom.
  Flyer launch(int kind, {double? x, double? apex}) {
    final w = size.width, h = size.height;
    final r = w * (kind < 0 ? .095 : .1 + rng.nextDouble() * .025);
    final x0 = x ?? w * (.15 + rng.nextDouble() * .7);
    final top = apex ?? h * (.12 + rng.nextDouble() * .3);
    final vy = -sqrt(2 * gravity * (h + r - top));
    final flight = -2 * vy / gravity;
    // Drift towards the middle so fruit stays on the board.
    final target = w * (.25 + rng.nextDouble() * .5);
    final vx = (target - x0) / flight;
    final f = Flyer(
      kind,
      Offset(x0, h + r),
      Offset(vx, vy),
      r,
      (rng.nextDouble() - .5) * 6,
    );
    flyers.add(f);
    return f;
  }

  // ── Cutting ──

  /// The blade moved from [a] to [b]. Cuts whatever it crossed.
  FruitEvents slice(Offset a, Offset b) {
    final ev = FruitEvents();
    if (!started || over) return ev;
    final d = b - a;
    if (d.distance < 3) return ev;
    for (final f in [...flyers]) {
      if (_distToSegment(f.pos, a, b) > f.radius * .92) continue;
      flyers.remove(f);
      slashes.add(Slash(f.pos, atan2(d.dy, d.dx), f.radius * 3.2));
      if (f.bomb) {
        _explode(f, ev);
        if (over) return ev;
        continue;
      }
      if (f.poison) {
        _poisoned(f, ev);
        if (over) return ev;
        continue;
      }
      _cut(f, d);
      ev.cut++;
      _swipeCut++;
      _swipeAt = f.pos;
    }
    if (ev.cut > 0) {
      score += ev.cut;
      cut += ev.cut;
    }
    return ev;
  }

  /// The finger lifted: a swipe that cut three or more earns a combo.
  FruitEvents endSwipe() {
    final ev = FruitEvents();
    if (_swipeCut >= 3 && !over) {
      ev.combo = _swipeCut;
      score += _swipeCut;
      popups.add(Popup(_swipeAt, '$_swipeCut FRUIT COMBO  +$_swipeCut', true));
    }
    bestCombo = max(bestCombo, _swipeCut);
    _swipeCut = 0;
    return ev;
  }

  void _explode(Flyer f, FruitEvents ev) {
    ev.bomb = true;
    sinceBomb = 0;
    bombAt = f.pos;
    for (var i = 0; i < 30; i++) {
      final a = rng.nextDouble() * pi * 2;
      final s = 200 + rng.nextDouble() * 500;
      drops.add(
        Drop(
          f.pos,
          Offset(cos(a), sin(a)) * s,
          i.isEven ? const Color(0xFFFFC233) : const Color(0xFFFF5A1F),
          3 + rng.nextDouble() * 4,
          .5 + rng.nextDouble() * .4,
        ),
      );
    }
    if (mode == FruitMode.classic) {
      _end('bomb', ev);
    } else {
      score = max(0, score - 10);
      popups.add(Popup(f.pos, '-10', true));
    }
    popups.add(Popup(f.pos, 'BOOM!', true));
  }

  void _poisoned(Flyer f, FruitEvents ev) {
    ev.poison = true;
    sincePoison = 0;
    for (var i = 0; i < 22; i++) {
      final a = rng.nextDouble() * pi * 2;
      final s = 150 + rng.nextDouble() * 350;
      drops.add(
        Drop(
          f.pos,
          Offset(cos(a), sin(a)) * s,
          i.isEven ? const Color(0xFF6BFF3A) : const Color(0xFFB04BFF),
          3 + rng.nextDouble() * 4,
          .5 + rng.nextDouble() * .4,
        ),
      );
    }
    stains.add(
      Stain(
        f.pos,
        const Color(0xFF5BD62A),
        f.radius * 1.8,
        rng.nextInt(1 << 20),
      ),
    );
    if (mode == FruitMode.classic) {
      lives--;
      popups.add(Popup(f.pos, 'POISON!  -1 LIFE', true));
      if (lives <= 0) _end('poison', ev);
    } else {
      score = max(0, score - 5);
      popups.add(Popup(f.pos, 'POISON!  -5', true));
    }
  }

  void _cut(Flyer f, Offset dir) {
    // Cut along the swipe; halves fly apart either side of it.
    var d = dir / dir.distance;
    if (d.dy < 0) d = -d;
    final n = Offset(-d.dy, d.dx); // the left side of a downward cut
    final angle = atan2(d.dy, d.dx) - pi / 2;
    final size = f.radius * 2.3;
    for (final right in [false, true]) {
      final side = right ? -1.0 : 1.0;
      halves.add(
        Half(
          f.kind,
          right,
          f.pos + n * (f.radius * .3 * side),
          f.vel * .55 + n * (160 * side) + d * 60,
          angle,
          f.spin + side * (2 + rng.nextDouble() * 2),
          size,
        ),
      );
    }
    final juice = fruitKinds[f.kind].$2;
    for (var i = 0; i < 16; i++) {
      final a = rng.nextDouble() * pi * 2;
      final s = 120 + rng.nextDouble() * 380;
      drops.add(
        Drop(
          f.pos,
          Offset(cos(a), sin(a)) * s + d * 120,
          juice,
          2.5 + rng.nextDouble() * 4.5,
          .45 + rng.nextDouble() * .35,
        ),
      );
    }
    stains.add(Stain(f.pos, juice, f.radius * 1.6, rng.nextInt(1 << 20)));
    if (stains.length > 14) stains.removeAt(0);
    popups.add(Popup(f.pos, '+1', false));
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    var t = len2 == 0
        ? 0.0
        : ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}
