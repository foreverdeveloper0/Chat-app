import 'dart:math';

/// Things standing beside (or on) the road.
enum Prop {
  tree,
  bush,
  flower,
  rock,
  fence,
  lamp,
  flag,
  sign,
  chevron,
  cone,
  barrel,
  tyres,
  barrier,
  hay,
  arch,
}

class RoadProp {
  const RoadProp(this.kind, this.offset, [this.variant = 0]);
  final Prop kind;

  /// Across the road: -1 and 1 are its edges.
  final double offset;

  /// Which picture of this kind to draw.
  final int variant;

  /// Props on the tarmac get in the way; the rest only matter off-road.
  bool get onRoad => switch (kind) {
    Prop.cone || Prop.barrel || Prop.tyres || Prop.barrier || Prop.hay => true,
    _ => false,
  };

  /// Whether driving into it off the road is a crash. Bushes, flowers and
  /// flags are soft.
  bool get solid => switch (kind) {
    Prop.tree ||
    Prop.rock ||
    Prop.fence ||
    Prop.lamp ||
    Prop.sign ||
    Prop.chevron => true,
    _ => false,
  };

  /// A heavy thing on the road costs more speed than a light one.
  bool get heavy =>
      kind == Prop.barrel || kind == Prop.barrier || kind == Prop.hay;

  /// Half the prop's width, in road half-widths, for collisions.
  double get halfWidth => switch (kind) {
    Prop.cone => .07,
    Prop.barrel => .09,
    Prop.tyres => .11,
    Prop.hay => .13,
    Prop.barrier => .17,
    Prop.tree => .2,
    Prop.rock => .2,
    Prop.fence => .22,
    Prop.lamp => .06,
    Prop.sign || Prop.chevron => .12,
    _ => 0,
  };
}

class Segment {
  Segment(this.index, this.y1, this.y2, this.curve);
  final int index;

  /// World height at the start and end of the segment.
  final double y1, y2;

  /// How hard the road bends here (negative left, positive right).
  final double curve;
  final props = <RoadProp>[];
}

class Racer {
  Racer(this.id, this.colour, this.z, this.x, {required this.isPlayer});
  final int id;
  final int colour;
  final bool isPlayer;

  /// Distance along the lap (to the car itself; the camera sits [playerZ]
  /// behind the player's) and position across the road (-1..1 on it).
  double z, x;
  double speed = 0;

  /// Laps completed; -1 until the car first crosses the start line
  /// from its grid slot behind it.
  int lap = -1;
  double? finishTime;

  /// For the computer: its cruising pace and preferred line.
  double pace = 1;
  double line = 0;

  /// Steering and braking right now, for drawing.
  double steer = 0;
  bool braking = false, boosting = false;

  /// Seconds left of a spin-out after a hard hit.
  double stun = 0;
}

class RaceInput {
  bool left = false, right = false, brake = false, nitro = false;
}

/// What happened in one update, for sounds and shakes.
class RaceEvents {
  bool bump = false, crash = false, lap = false, finished = false;
}

/// A circuit race seen from behind the player's car.
class RaceGame {
  RaceGame({this.opponents = 3, this.laps = 3, Random? random})
    : rng = random ?? Random() {
    _build();
    // Two-by-two starting grid behind the line; the player starts last,
    // on the left of the back row.
    for (var i = 0; i <= opponents; i++) {
      final slot = i == 0 ? opponents : i - 1;
      final row = slot ~/ 2, col = slot.isEven ? -.45 : .45;
      final r = Racer(
        i,
        i,
        trackLength - (row + 1) * segLen * 4 - (i == 0 ? segLen * 2 : 0),
        col,
        isPlayer: i == 0,
      );
      if (i > 0) {
        r.pace = .86 + .03 * i + rng.nextDouble() * .04;
        r.line = col;
      }
      racers.add(r);
    }
  }

  static const segLen = 200.0;
  static const rumbleLen = 3;
  static const roadWidth = 2000.0;
  static const lanes = 3;
  static const cameraHeight = 1300.0;
  static const cameraDepth = .84; // 1 / tan(fov / 2) for a 100 degree view
  static const playerZ = cameraHeight * cameraDepth;
  static const drawDistance = 260;
  static const maxSpeed = segLen * 60; // one segment per frame at 60 fps
  static const accel = maxSpeed / 5;
  static const braking = -maxSpeed;
  static const decel = -maxSpeed / 5;
  static const offRoadDecel = -maxSpeed / 2;
  static const offRoadLimit = maxSpeed / 4;
  static const centrifugal = .2;

  /// Steering: how fast the wheel turns and returns (per second), and the
  /// sideways speed at full lock, in road half-widths per second.
  static const steerRate = 7.0, steerReturn = 10.0, steerSpeed = 1.5;
  static const carLength = segLen * .9;
  static const carHalfWidth = .17;

  final int opponents, laps;
  final Random rng;

  final segments = <Segment>[];
  double get trackLength => segments.length * segLen;

  final racers = <Racer>[];
  Racer get player => racers.first;

  double time = 0;
  bool started = false;

  /// 0..1 nitro left; it refills slowly.
  double nitro = 1;

  /// Order racers crossed the line in.
  final finishers = <Racer>[];
  bool get over => player.finishTime != null;

  Segment segmentAt(double z) => segments[(z ~/ segLen) % segments.length];

  // ── Track ──

  double _lastY() => segments.isEmpty ? 0 : segments.last.y2;

  void _add(double curve, double y) {
    final y1 = _lastY();
    segments.add(Segment(segments.length, y1, y, curve));
  }

  double _ease(double a, double b, double t) =>
      a + (b - a) * ((-cos(t * pi) / 2) + .5);

  void _road(int enter, int hold, int leave, double curve, double hill) {
    final start = _lastY(), end = start + hill * segLen;
    final total = enter + hold + leave;
    for (var n = 0; n < enter; n++) {
      _add(_ease(0, curve, n / enter), _ease(start, end, n / total));
    }
    for (var n = 0; n < hold; n++) {
      _add(curve, _ease(start, end, (enter + n) / total));
    }
    for (var n = 0; n < leave; n++) {
      _add(
        _ease(curve, 0, n / leave),
        _ease(start, end, (enter + hold + n) / total),
      );
    }
  }

  void _build() {
    _road(20, 30, 20, 0, 0); // start straight
    _road(25, 40, 25, 3, 20);
    _road(25, 30, 25, 0, -15);
    _road(25, 50, 25, -4, 0);
    _road(20, 20, 20, 0, 30);
    _road(30, 40, 30, 5, -20);
    _road(20, 30, 20, -2, 25);
    _road(25, 35, 25, -5, -30);
    _road(20, 40, 20, 3, 10);
    _road(25, 30, 25, 0, -20);
    // Close the loop: ease back down to the starting height.
    final rest = _lastY();
    _road(30, 20, 30, -2, -rest / segLen);

    // Scenery and obstacles.
    final n = segments.length;
    for (final s in segments) {
      final i = s.index;
      if (i == 2) {
        // The start and finish arch, just past the line.
        s.props.add(const RoadProp(Prop.arch, 0));
      }
      if (i == 0 || i == 5) {
        s.props.add(const RoadProp(Prop.flag, -1.3));
        s.props.add(const RoadProp(Prop.flag, 1.3));
      } else if (i % 45 == 20) {
        s.props.add(RoadProp(Prop.flag, i.isEven ? -1.3 : 1.3, 1 + i % 3));
      }
      // Fences run along some stretches, a different kind on each.
      final zone = i ~/ 50;
      if (i % 3 == 0 && zone % 3 != 2 && i > 8) {
        s.props.add(RoadProp(Prop.fence, -1.42, zone % 3 + zone % 2));
        s.props.add(RoadProp(Prop.fence, 1.42, zone % 3 + zone % 2));
      }
      if (i % 12 == 6) {
        s.props.add(RoadProp(Prop.lamp, i % 24 == 6 ? -1.25 : 1.25, zone % 2));
      }
      // Arrows on the outside of the sharper bends.
      if (s.curve.abs() > 2.5 && i % 6 == 0) {
        s.props.add(RoadProp(Prop.chevron, s.curve > 0 ? -1.3 : 1.3));
      } else if (i % 90 == 45) {
        s.props.add(RoadProp(Prop.sign, i.isEven ? -1.3 : 1.3, rng.nextInt(2)));
      }
      for (final side in const [-1, 1]) {
        if (i.isEven && rng.nextDouble() < .55) {
          s.props.add(
            RoadProp(
              Prop.tree,
              side * (1.9 + rng.nextDouble() * 3.4),
              rng.nextInt(8),
            ),
          );
        }
        if (rng.nextDouble() < .35) {
          s.props.add(
            RoadProp(
              Prop.bush,
              side * (1.6 + rng.nextDouble() * 2.2),
              rng.nextInt(8),
            ),
          );
        }
        if (rng.nextDouble() < .45) {
          s.props.add(
            RoadProp(
              Prop.flower,
              side * (1.18 + rng.nextDouble() * 1.6),
              rng.nextInt(8),
            ),
          );
        }
        if (rng.nextDouble() < .06) {
          s.props.add(
            RoadProp(
              Prop.rock,
              side * (1.7 + rng.nextDouble() * 2),
              rng.nextInt(4),
            ),
          );
        }
      }
      // Things on the tarmac to steer round, never near the start.
      if (i > 80 && i < n - 30 && i % 37 == 0) {
        final lane = (rng.nextInt(3) - 1) * .62;
        final kind = const [
          Prop.cone,
          Prop.cone,
          Prop.barrel,
          Prop.tyres,
          Prop.barrier,
          Prop.hay,
        ][rng.nextInt(6)];
        s.props.add(RoadProp(kind, lane, rng.nextInt(3)));
        if (kind == Prop.cone) {
          s.props.add(RoadProp(kind, lane + (lane > 0 ? -.2 : .2)));
        }
      }
    }
  }

  // ── Simulation ──

  double _wrap(double z) {
    final l = trackLength;
    return ((z % l) + l) % l;
  }

  /// Distance raced so far, for standings.
  double progress(Racer r) => r.lap * trackLength + r.z;

  /// Current standings, leader first.
  List<Racer> get standings {
    final list = [...racers]
      ..sort((a, b) {
        final fa = a.finishTime, fb = b.finishTime;
        if (fa != null || fb != null) {
          if (fa == null) return 1;
          if (fb == null) return -1;
          return fa.compareTo(fb);
        }
        return progress(b).compareTo(progress(a));
      });
    return list;
  }

  int positionOf(Racer r) => standings.indexOf(r) + 1;

  RaceEvents update(double dt, RaceInput input) {
    final ev = RaceEvents();
    if (!started) return ev;
    time += dt;
    for (final r in racers) {
      if (r.finishTime != null) {
        // Coast after the flag.
        r.speed = max(0, r.speed + decel * dt);
        r.z = _wrap(r.z + r.speed * dt);
        continue;
      }
      r.isPlayer ? _drivePlayer(r, dt, input, ev) : _driveBot(r, dt);
      final before = r.z;
      r.z = _wrap(r.z + r.speed * dt);
      if (r.z < before) {
        r.lap++;
        if (r.isPlayer && r.lap > 0) ev.lap = true;
        if (r.lap >= laps) {
          r.finishTime = time;
          finishers.add(r);
          if (r.isPlayer) ev.finished = true;
        }
      }
    }
    _collide(ev);
    return ev;
  }

  void _drivePlayer(Racer p, double dt, RaceInput input, RaceEvents ev) {
    final seg = segmentAt(p.z);
    final pct = p.speed / maxSpeed;
    p.stun = max(0, p.stun - dt);
    // The wheel eases over and eases back, so a tap is a gentle nudge and
    // a hold builds into a full turn.
    final want = p.stun > 0
        ? sin(p.stun * 30) * .6
        : (input.left ? -1.0 : (input.right ? 1.0 : 0.0));
    final rate = want == 0 ? steerReturn : steerRate;
    p.steer += (want - p.steer) * (1 - exp(-rate * dt));
    if (want == 0 && p.steer.abs() < .01) p.steer = 0;
    // Sideways speed barely depends on road speed once the car is rolling.
    final grip = min(1.0, pct * 5) * (.55 + .45 * min(1.0, pct));
    p.x += p.steer * steerSpeed * grip * dt;
    // Bends push the car gently outwards.
    p.x -= dt * 2 * pct * pct * seg.curve * centrifugal;

    p.boosting = input.nitro && nitro > 0 && !input.brake;
    p.braking = input.brake;
    final top = p.boosting ? maxSpeed * 1.3 : maxSpeed;
    if (input.brake) {
      p.speed += braking * dt;
    } else if (p.stun > 0) {
      p.speed += decel * dt;
    } else {
      p.speed += (p.boosting ? accel * 1.8 : accel) * dt;
    }
    if (p.boosting) {
      nitro = max(0, nitro - dt / 3.2);
    } else {
      nitro = min(1, nitro + dt / 14);
    }
    if (p.speed > maxSpeed && !p.boosting) p.speed += decel * 1.5 * dt;
    if (p.x.abs() > 1) {
      if (p.speed > offRoadLimit) p.speed += offRoadDecel * dt;
      // Things off the road stop you dead.
      for (final prop in seg.props) {
        if (!prop.solid) continue;
        if ((p.x - prop.offset).abs() < prop.halfWidth + carHalfWidth) {
          p.speed = maxSpeed / 6;
          p.z = _wrap(segmentAt(p.z).index * segLen);
          p.x += p.x > prop.offset ? .1 : -.1;
          ev.crash = true;
          break;
        }
      }
    }
    // Cones and barrels on the road knock speed off and spin you a little.
    for (final prop in seg.props) {
      if (!prop.onRoad) continue;
      if ((p.x - prop.offset).abs() < prop.halfWidth + carHalfWidth &&
          p.stun <= 0) {
        p.speed *= prop.heavy ? .45 : .7;
        p.stun = prop.heavy ? .7 : .35;
        ev.crash = true;
      }
    }
    p.x = p.x.clamp(-3, 3);
    p.speed = p.speed.clamp(0, top);
  }

  void _driveBot(Racer r, double dt) {
    final seg = segmentAt(r.z);
    r.stun = max(0, r.stun - dt);
    // Ease off a little in the sharpest bends.
    final target = maxSpeed * r.pace * (1 - seg.curve.abs() * .012);
    r.speed += (r.speed < target ? accel * .9 : decel) * dt;
    if (r.stun > 0) r.speed = min(r.speed, maxSpeed * .5);

    // Look ahead for anything to steer round.
    var want = r.line;
    for (var i = 1; i < 18; i++) {
      final ahead = segmentAt(r.z + i * segLen);
      for (final prop in ahead.props) {
        if (prop.onRoad && (prop.offset - want).abs() < .35) {
          want = prop.offset > 0 ? prop.offset - .62 : prop.offset + .62;
        }
      }
      for (final o in racers) {
        if (o == r) continue;
        final gap = _wrap(o.z - r.z);
        if (gap > 0 &&
            gap < segLen * 6 &&
            o.speed < r.speed &&
            (o.x - want).abs() < carHalfWidth * 2.2) {
          want = o.x > 0 ? o.x - .55 : o.x + .55;
        }
      }
    }
    want = want.clamp(-.8, .8);
    final dx = (want - r.x);
    final lean = dx.sign * min(1.0, dx.abs() * 4);
    r.steer += (lean - r.steer) * (1 - exp(-8 * dt));
    r.x += dx.clamp(-1.2 * dt, 1.2 * dt);
  }

  void _collide(RaceEvents ev) {
    for (var i = 0; i < racers.length; i++) {
      for (var j = i + 1; j < racers.length; j++) {
        final a = racers[i], b = racers[j];
        if (a.finishTime != null || b.finishTime != null) continue;
        var gap = _wrap(b.z - a.z);
        var behind = a, front = b;
        if (gap > trackLength / 2) {
          gap = trackLength - gap;
          behind = b;
          front = a;
        }
        if (gap > carLength || (a.x - b.x).abs() > carHalfWidth * 2) continue;
        if (behind.speed > front.speed) {
          behind.speed = front.speed * .9;
          // Nudge apart sideways.
          final push = behind.x < front.x ? -.06 : .06;
          behind.x += push;
          front.x -= push * .5;
          if (behind.isPlayer || front.isPlayer) ev.bump = true;
        }
      }
    }
  }

  // ── Computer driver for the player's car (tests and demos) ──

  RaceInput autopilot() {
    final p = player;
    final seg = segmentAt(p.z);
    var want = 0.0;
    for (var i = 1; i < 14; i++) {
      for (final prop in segmentAt(p.z + i * segLen).props) {
        if (prop.onRoad && (prop.offset - want).abs() < .35) {
          want = prop.offset > 0 ? prop.offset - .62 : prop.offset + .62;
        }
      }
    }
    // Lean into bends against the centrifugal drift.
    want -= seg.curve * .04;
    final i = RaceInput();
    if (p.x < want - .05) i.right = true;
    if (p.x > want + .05) i.left = true;
    i.nitro = seg.curve.abs() < 1 && nitro > .5;
    return i;
  }
}
