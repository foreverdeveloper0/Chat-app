import 'dart:math';

import 'package:elite_play_ludo/game/race_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RaceGame game([int opponents = 3]) =>
      RaceGame(opponents: opponents, laps: 2, random: Random(1))
        ..started = true;

  test('the track is a smooth closed loop', () {
    final g = game();
    expect(g.segments.length, greaterThan(500));
    for (var i = 1; i < g.segments.length; i++) {
      expect(g.segments[i].y1, closeTo(g.segments[i - 1].y2, 1e-6));
    }
    // It ends close to where it starts.
    expect((g.segments.last.y2 - g.segments.first.y1).abs(), lessThan(400));
    expect(g.segments[2].props.any((p) => p.kind == Prop.arch), isTrue);
  });

  test('four racers on the grid, the player at the back', () {
    final g = game();
    expect(g.racers.length, 4);
    expect(g.positionOf(g.player), 4);
  });

  test('accelerates to top speed and the brake slows it', () {
    final g = game(0);
    // An empty road, so nothing knocks speed off along the way.
    for (final seg in g.segments) {
      seg.props.removeWhere((p) => p.onRoad || p.pickup);
    }
    final input = RaceInput()..gas = true;
    for (var i = 0; i < 60 * 8; i++) {
      // Between two lanes, clear of anything lying on the road.
      g.player.x = .31;
      g.update(1 / 60, input);
    }
    expect(g.player.speed, closeTo(RaceGame.maxSpeed, RaceGame.maxSpeed * .02));
    input.brake = true;
    for (var i = 0; i < 30; i++) {
      g.update(1 / 60, input);
    }
    expect(g.player.speed, lessThan(RaceGame.maxSpeed * .6));
  });

  test('driving off the road slows the car right down', () {
    final g = game(0);
    g.player.speed = RaceGame.maxSpeed;
    for (var i = 0; i < 120; i++) {
      g.player.x = 2.2;
      g.update(1 / 60, RaceInput());
    }
    expect(g.player.speed, lessThanOrEqualTo(RaceGame.offRoadLimit * 1.05));
  });

  test('nitro goes past top speed and runs out', () {
    final g = game(0);
    g.player.speed = RaceGame.maxSpeed;
    final input = RaceInput()
      ..gas = true
      ..nitro = true;
    var fastest = 0.0;
    for (var i = 0; i < 60 * 4; i++) {
      // Between two lanes, clear of obstacles and nitro bottles.
      g.player.x = .31;
      g.update(1 / 60, input);
      fastest = max(fastest, g.player.speed);
    }
    expect(fastest, greaterThan(RaceGame.maxSpeed * 1.15));
    expect(g.nitro, 0);
  });

  test('a full race: everyone finishes and the standings are set', () {
    for (final seed in [1, 2]) {
      final g = RaceGame(opponents: 3, laps: 2, random: Random(seed))
        ..started = true;
      var laps = 0;
      for (var i = 0; i < 60 * 600 && g.finishers.length < 4; i++) {
        final ev = g.update(1 / 60, g.autopilot());
        if (ev.lap) laps++;
      }
      expect(g.finishers.length, 4, reason: 'seed $seed');
      expect(laps, 2);
      expect(g.player.finishTime, isNotNull);
      final order = g.standings;
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i].finishTime!,
          greaterThanOrEqualTo(order[i - 1].finishTime!),
        );
      }
    }
  });

  test('the car waits for the gas, and the brake backs it up', () {
    final g = RaceGame(opponents: 0, random: Random(3))..started = true;
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60, RaceInput());
    }
    expect(g.player.speed, 0);
    final back = RaceInput()..brake = true;
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60, back);
    }
    expect(g.player.speed, lessThan(0));
    expect(g.player.speed, greaterThanOrEqualTo(-RaceGame.reverseLimit));
    expect(g.player.lap, -1);
  });

  test('the verge holds the car and it can steer back on', () {
    final g = RaceGame(opponents: 0, random: Random(3))..started = true;
    final out = RaceInput()
      ..gas = true
      ..right = true;
    for (var i = 0; i < 600; i++) {
      g.update(1 / 60, out);
    }
    expect(g.player.x, lessThanOrEqualTo(RaceGame.verge));
    expect(g.player.speed, greaterThan(0));
    final home = RaceInput()
      ..gas = true
      ..left = true;
    for (var i = 0; i < 90; i++) {
      g.update(1 / 60, home);
    }
    expect(g.player.x, lessThan(1));
  });

  test('an obstacle is hit once and coins are collected', () {
    final g = RaceGame(opponents: 0, random: Random(3))..started = true;
    final seg = g.segments.firstWhere((s) => s.props.any((p) => p.onRoad));
    final prop = seg.props.firstWhere((p) => p.onRoad);
    final p = g.player
      ..z = seg.index * RaceGame.segLen + 1
      ..x = prop.offset
      ..speed = 10;
    var crashes = 0;
    for (var i = 0; i < 200; i++) {
      p
        ..z = seg.index * RaceGame.segLen + 1
        ..x = prop.offset;
      if (g.update(1 / 60, RaceInput()).crash) crashes++;
    }
    expect(crashes, 1);

    final coinSeg = g.segments.firstWhere(
      (s) => s.props.any((p) => p.kind == Prop.coin),
    );
    final coin = coinSeg.props.firstWhere((p) => p.kind == Prop.coin);
    p
      ..stun = 0
      ..z = coinSeg.index * RaceGame.segLen + 1
      ..x = coin.offset;
    g.update(1 / 60, RaceInput());
    expect(g.coins, 1);
  });

  test('with no steering the car keeps to the road through every bend', () {
    final g = RaceGame(opponents: 0, laps: 1, random: Random(5))
      ..started = true;
    for (final seg in g.segments) {
      seg.props.removeWhere((p) => p.onRoad);
    }
    g.player.x = .95;
    final input = RaceInput()..gas = true;
    var worst = 0.0;
    for (var i = 0; i < 60 * 120 && !g.over; i++) {
      g.update(1 / 60, input);
      if (i > 120) worst = max(worst, g.player.x.abs());
    }
    expect(g.over, isTrue);
    expect(worst, lessThan(1));
  });
}
