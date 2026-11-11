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
    final input = RaceInput();
    for (var i = 0; i < 60 * 8; i++) {
      g.player.x = 0;
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
    final input = RaceInput()..nitro = true;
    var fastest = 0.0;
    for (var i = 0; i < 60 * 4; i++) {
      g.player.x = 0;
      g.update(1 / 60, input);
      fastest = max(fastest, g.player.speed);
    }
    expect(fastest, greaterThan(RaceGame.maxSpeed * 1.2));
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
}
