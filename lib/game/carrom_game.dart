import 'dart:math';
import 'dart:ui' show Offset;

enum PieceKind { white, black, queen, striker }

class CarromPiece {
  CarromPiece(this.kind, this.pos);
  final PieceKind kind;
  Offset pos;
  Offset vel = Offset.zero;
  bool pocketed = false;

  /// Seconds since it dropped into a pocket (for the sink animation).
  double sink = 0;

  double get radius =>
      kind == PieceKind.striker ? Carrom.strikerR : Carrom.coinR;
  double get mass => kind == PieceKind.striker ? 2.6 : 1;
}

/// Board measurements, as fractions of the board picture's edge.
abstract final class Carrom {
  static const left = .110, right = .890, top = .1165, bottom = .8835;
  static const centre = Offset(.5, .5);
  static const coinR = .021, strikerR = .029;

  /// The inner edge of the black ring round the centre: the racked coins
  /// must all sit inside it.
  static const centreRing = .114;
  static const pockets = [
    Offset(.1252, .1292),
    Offset(.8757, .1300),
    Offset(.1238, .8589),
    Offset(.8777, .8593),
  ];
  static const pocketR = .039;

  /// Baselines: distance of each from its own edge, and their extent.
  static const baseNear = .2030, baseFar = .7940;
  static const baseFrom = .2616, baseTo = .7376;

  /// Fastest a striker can be shot, in board widths per second.
  static const maxSpeed = 3.3;
}

/// What happened in the shot that just came to rest.
class ShotResult {
  int own = 0, theirs = 0;
  bool queen = false, foul = false, covered = false, queenReturned = false;
  bool again = false;
  int? winner; // team
}

/// What a physics step produced, for sounds.
class StepEvents {
  double hit = 0; // strongest impact this step
  int pocketed = 0;
}

/// A carrom match: physics, turns and rules.
///
/// Seats sit bottom (0), right (1), top (2) and left (3). With two players
/// seats 0 and 2 play; with four, seats 0+2 (white) face seats 1+3 (black).
class CarromGame {
  CarromGame({required this.seats, this.bots = const {}, Random? random})
      : rng = random ?? Random(),
        current = seats.first {
    _rack();
    placeStriker(.5);
  }

  final List<int> seats;
  final Set<int> bots;
  final Random rng;

  final pieces = <CarromPiece>[];
  late final CarromPiece striker;

  int current;
  bool moving = false;

  /// Coins each team (0 white, 1 black) has pocketed and kept.
  final pocketed = [0, 0];

  /// Team that pocketed and covered the queen.
  int? queenOwner;

  /// Team that pocketed the queen and must cover it with its next shot.
  int? queenPending;
  int? winner;
  int shots = 0;

  /// Striker position along the current player's baseline, 0 (their left)
  /// to 1 (their right).
  double strikerT = .5;

  final _shot = _Tally();

  /// White (0) or black (1). Partners sit opposite each other in a
  /// four-player game; with two players each has a colour of their own.
  int teamOf(int seat) =>
      seats.length == 2 ? seats.indexOf(seat) : (seat.isEven ? 0 : 1);
  int get team => teamOf(current);
  bool isBot(int seat) => bots.contains(seat);
  PieceKind colourOf(int team) => team == 0 ? PieceKind.white : PieceKind.black;
  CarromPiece get queen => pieces.firstWhere((p) => p.kind == PieceKind.queen);
  bool get queenOnBoard => !queen.pocketed;
  int remaining(int team) => 9 - pocketed[team];

  void _rack() {
    // A hair of space between neighbours so no two coins ever overlap.
    const gap = Carrom.coinR * 2.06;
    pieces.add(CarromPiece(PieceKind.queen, Carrom.centre));
    for (var i = 0; i < 6; i++) {
      final a = i * pi / 3 + pi / 6;
      pieces.add(CarromPiece(i.isEven ? PieceKind.white : PieceKind.black,
          Carrom.centre + Offset(cos(a), sin(a)) * gap));
    }
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6 + pi / 6;
      final r = i.isEven ? gap * 2 : gap * sqrt(3);
      pieces.add(CarromPiece(i.isEven ? PieceKind.white : PieceKind.black,
          Carrom.centre + Offset(cos(a), sin(a)) * r));
    }
    striker = CarromPiece(PieceKind.striker, Carrom.centre);
    pieces.add(striker);
  }

  /// Where the striker sits for [seat] at [t] along its baseline.
  static Offset baseline(int seat, double t) {
    const a = Carrom.baseFrom, b = Carrom.baseTo;
    return switch (seat) {
      0 => Offset(a + (b - a) * t, Carrom.baseFar),
      1 => Offset(Carrom.baseFar, b - (b - a) * t),
      2 => Offset(b - (b - a) * t, Carrom.baseNear),
      _ => Offset(Carrom.baseNear, a + (b - a) * t),
    };
  }

  /// "Forward" (into the board) for [seat].
  static Offset forward(int seat) => const [
        Offset(0, -1),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(1, 0),
      ][seat];

  void placeStriker(double t) {
    if (moving) return;
    strikerT = t.clamp(0, 1);
    striker
      ..pocketed = false
      ..sink = 0
      ..vel = Offset.zero
      ..pos = baseline(current, strikerT);
  }

  /// False while the striker overlaps a coin on the baseline.
  bool get strikerFree => !pieces.any((p) =>
      p != striker &&
      !p.pocketed &&
      (p.pos - striker.pos).distance < p.radius + striker.radius + .001);

  /// Shoots the striker along [direction] with [power] from 0 to 1.
  bool shoot(Offset direction, double power) {
    if (moving || winner != null || !strikerFree) return false;
    final d = direction.distance;
    if (d < 1e-6 || power < .04) return false;
    striker.vel = direction / d * (Carrom.maxSpeed * power.clamp(0, 1));
    moving = true;
    shots++;
    _shot.reset();
    return true;
  }

  // ── Physics ──

  StepEvents step(double dt) {
    final ev = StepEvents();
    for (final p in pieces) {
      if (p.pocketed && p.sink < 1) p.sink += dt;
    }
    if (!moving) return ev;
    var fastest = 0.0;
    for (final p in pieces) {
      if (!p.pocketed) fastest = max(fastest, p.vel.distance);
    }
    final n = max(1, (fastest * dt / (Carrom.coinR * .45)).ceil());
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      _substep(h, ev);
    }
    if (!pieces.any((p) => !p.pocketed && p.vel != Offset.zero)) {
      moving = false;
    }
    return ev;
  }

  void _substep(double h, StepEvents ev) {
    for (final p in pieces) {
      if (p.pocketed || p.vel == Offset.zero) continue;
      p.pos += p.vel * h;
      // Sliding friction plus a little drag.
      final v = p.vel.distance;
      final nv = v - (.34 + .85 * v) * h;
      p.vel = nv < .012 ? Offset.zero : p.vel * (nv / v);

      for (final hole in Carrom.pockets) {
        if ((p.pos - hole).distance < Carrom.pocketR) {
          p
            ..pocketed = true
            ..sink = 0
            ..vel = Offset.zero
            ..pos = hole;
          ev.pocketed++;
          _shot.add(p.kind);
          break;
        }
      }
      if (p.pocketed) continue;

      // Cushions.
      const bounce = .78;
      final r = p.radius;
      var x = p.pos.dx, y = p.pos.dy, vx = p.vel.dx, vy = p.vel.dy;
      if (x < Carrom.left + r && vx < 0) {
        x = Carrom.left + r;
        ev.hit = max(ev.hit, -vx);
        vx = -vx * bounce;
      } else if (x > Carrom.right - r && vx > 0) {
        x = Carrom.right - r;
        ev.hit = max(ev.hit, vx);
        vx = -vx * bounce;
      }
      if (y < Carrom.top + r && vy < 0) {
        y = Carrom.top + r;
        ev.hit = max(ev.hit, -vy);
        vy = -vy * bounce;
      } else if (y > Carrom.bottom - r && vy > 0) {
        y = Carrom.bottom - r;
        ev.hit = max(ev.hit, vy);
        vy = -vy * bounce;
      }
      p
        ..pos = Offset(x, y)
        ..vel = Offset(vx, vy);
    }

    // Piece against piece.
    for (var i = 0; i < pieces.length; i++) {
      final a = pieces[i];
      if (a.pocketed) continue;
      for (var j = i + 1; j < pieces.length; j++) {
        final b = pieces[j];
        if (b.pocketed) continue;
        final d = b.pos - a.pos;
        final dist = d.distance, minDist = a.radius + b.radius;
        if (dist >= minDist || dist < 1e-9) continue;
        final n = d / dist;
        final total = a.mass + b.mass;
        // Push them apart, then exchange momentum along the normal.
        final overlap = minDist - dist;
        a.pos -= n * (overlap * b.mass / total);
        b.pos += n * (overlap * a.mass / total);
        final rel = (b.vel - a.vel);
        final along = rel.dx * n.dx + rel.dy * n.dy;
        if (along >= 0) continue;
        final impulse = -(1 + .93) * along / (1 / a.mass + 1 / b.mass);
        a.vel -= n * (impulse / a.mass);
        b.vel += n * (impulse / b.mass);
        ev.hit = max(ev.hit, -along);
      }
    }
  }

  // ── Rules ──

  /// Call once everything has come to rest after a shot.
  ShotResult finishShot() {
    final r = ShotResult();
    final me = team, them = 1 - me;
    final mine = _shot.count(colourOf(me)), other = _shot.count(colourOf(them));
    r
      ..own = mine
      ..theirs = other
      ..queen = _shot.queen
      ..foul = _shot.striker;

    // Opponent coins stay down whatever else happened.
    pocketed[them] += other;

    if (r.foul) {
      // Everything of mine from this shot comes back, plus one as penalty.
      for (var i = 0; i < mine; i++) {
        _respot(colourOf(me));
      }
      if (pocketed[me] > 0) {
        pocketed[me]--;
        _respot(colourOf(me));
      }
      if (_shot.queen) _respot(PieceKind.queen);
      if (queenPending == me) {
        _respot(PieceKind.queen);
        queenPending = null;
        r.queenReturned = true;
      }
    } else {
      pocketed[me] += mine;
      if (queenPending == me) {
        if (mine > 0) {
          queenOwner = me;
          r.covered = true;
        } else {
          _respot(PieceKind.queen);
          r.queenReturned = true;
        }
        queenPending = null;
      }
      if (_shot.queen) {
        if (mine > 0) {
          queenOwner = me;
          r.covered = true;
        } else {
          queenPending = me;
        }
      }
      r.again = mine > 0 || _shot.queen;
    }

    // A side cannot finish while the queen is still unclaimed: its last
    // coin goes back to the centre.
    for (final t in [me, them]) {
      if (pocketed[t] >= 9) {
        if (queenOwner != null) {
          winner ??= t;
        } else {
          pocketed[t]--;
          _respot(colourOf(t));
          if (t == me) r.again = false;
        }
      }
    }
    r.winner = winner;

    if (winner == null) {
      if (!r.again) {
        current = seats[(seats.indexOf(current) + 1) % seats.length];
      }
      placeStriker(.5);
      // Slide off any coin resting on the baseline.
      for (var i = 0; i < 20 && !strikerFree; i++) {
        placeStriker(.5 + (i.isEven ? 1 : -1) * (i ~/ 2 + 1) * .05);
      }
    } else {
      striker.pocketed = true;
      striker.sink = 1;
    }
    return r;
  }

  /// Points for the winner: a point per opponent coin left, three for
  /// holding the queen.
  int get winnerScore => winner == null
      ? 0
      : remaining(1 - winner!) + (queenOwner == winner ? 3 : 0);

  /// Puts a pocketed piece of [kind] back as near the centre as it fits.
  void _respot(PieceKind kind) {
    final p = pieces.lastWhere((p) => p.kind == kind && p.pocketed,
        orElse: () => pieces.first);
    if (!p.pocketed) return;
    for (var ring = 0; ring < 12; ring++) {
      final steps = ring == 0 ? 1 : ring * 6;
      for (var i = 0; i < steps; i++) {
        final a = i * 2 * pi / steps;
        final at = Carrom.centre +
            Offset(cos(a), sin(a)) * (ring * Carrom.coinR * 2.1);
        final free = !pieces.any((q) =>
            q != p &&
            !q.pocketed &&
            (q.pos - at).distance < q.radius + p.radius + .002);
        if (free) {
          p
            ..pocketed = false
            ..sink = 0
            ..vel = Offset.zero
            ..pos = at;
          return;
        }
      }
    }
  }

  // ── Computer player ──

  /// The computer's choice: where to put the striker, where to aim, how hard.
  ({double t, Offset direction, double power}) botShot() {
    final me = team;
    final wantQueen = queenOnBoard &&
        queenPending == null &&
        (remaining(me) <= 1 || rng.nextDouble() < .25);
    final onlyQueen = queenOnBoard && queenPending == null && remaining(me) <= 1;
    final targets = [
      for (final p in pieces)
        if (!p.pocketed &&
            ((p.kind == colourOf(me) && !onlyQueen) ||
                (p.kind == PieceKind.queen && wantQueen)))
          p,
    ];
    final fwd = forward(current);
    ({double t, Offset direction, double power})? best;
    var bestScore = -1e9;

    bool blocked(Offset a, Offset b, double width, Set<CarromPiece> skip) {
      final d = b - a, len = d.distance;
      if (len < 1e-6) return false;
      final n = d / len;
      for (final q in pieces) {
        if (q.pocketed || skip.contains(q)) continue;
        final rel = q.pos - a;
        final along = rel.dx * n.dx + rel.dy * n.dy;
        if (along < 0 || along > len) continue;
        final off = (rel.dx * n.dy - rel.dy * n.dx).abs();
        if (off < width + q.radius) return true;
      }
      return false;
    }

    for (final coin in targets) {
      for (final hole in Carrom.pockets) {
        final toHole = hole - coin.pos, run = toHole.distance;
        if (run < 1e-6) continue;
        final aim = toHole / run;
        // Where the striker must be at the moment of contact.
        final ghost = coin.pos - aim * (Carrom.coinR + Carrom.strikerR);
        if (blocked(coin.pos, hole, Carrom.coinR * .9, {coin, striker})) continue;
        for (var i = 0; i <= 10; i++) {
          final t = i / 10;
          final from = baseline(current, t);
          final path = ghost - from, reach = path.distance;
          if (reach < .03) continue;
          final dir = path / reach;
          // Only shoot forwards, and not at too thin a cut.
          if (dir.dx * fwd.dx + dir.dy * fwd.dy < .12) continue;
          final cut = dir.dx * aim.dx + dir.dy * aim.dy;
          if (cut < .45) continue;
          if (pieces.any((q) =>
              q != striker &&
              !q.pocketed &&
              (q.pos - from).distance < q.radius + Carrom.strikerR + .002)) {
            continue;
          }
          if (blocked(from, ghost, Carrom.strikerR * .95, {coin, striker})) {
            continue;
          }
          final score = cut * 2 - reach * .5 - run * .9 +
              (coin.kind == PieceKind.queen ? .3 : 0) +
              rng.nextDouble() * .15;
          if (score > bestScore) {
            bestScore = score;
            final power =
                ((.30 + reach * .32 + run * .5) / cut.clamp(.5, 1)).clamp(.3, .95);
            best = (t: t, direction: dir, power: power);
          }
        }
      }
    }

    if (best != null) {
      // A human-sized aiming error.
      final wobble = (rng.nextDouble() - .5) * .028;
      final d = best.direction;
      return (
        t: best.t,
        direction: Offset(d.dx * cos(wobble) - d.dy * sin(wobble),
            d.dx * sin(wobble) + d.dy * cos(wobble)),
        power: best.power,
      );
    }
    // Nothing clean: break things up by hitting the nearest target hard.
    for (var tries = 0; tries < 30; tries++) {
      final t = rng.nextDouble();
      final from = baseline(current, t);
      if (pieces.any((q) =>
          q != striker &&
          !q.pocketed &&
          (q.pos - from).distance < q.radius + Carrom.strikerR + .002)) {
        continue;
      }
      final pool = targets.isEmpty
          ? [for (final p in pieces) if (!p.pocketed && p != striker) p]
          : targets;
      final at = pool.isEmpty
          ? Carrom.centre
          : pool[rng.nextInt(pool.length)].pos;
      var dir = at - from;
      if (dir.distance < .02) dir = fwd;
      return (t: t, direction: dir, power: .55 + rng.nextDouble() * .35);
    }
    return (t: .5, direction: fwd, power: .7);
  }
}

class _Tally {
  int white = 0, black = 0;
  bool queen = false, striker = false;

  void reset() {
    white = black = 0;
    queen = striker = false;
  }

  void add(PieceKind k) {
    switch (k) {
      case PieceKind.white:
        white++;
      case PieceKind.black:
        black++;
      case PieceKind.queen:
        queen = true;
      case PieceKind.striker:
        striker = true;
    }
  }

  int count(PieceKind k) => k == PieceKind.white ? white : black;
}
