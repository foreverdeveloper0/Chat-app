import 'dart:async';
import 'dart:math';

import 'package:elite_play_ludo/game/dice_game.dart';
import 'package:elite_play_ludo/game/snl_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SnlController game([List<int> seats = const [0, 1]]) =>
      SnlController(seats: seats, speed: 0, random: Random(1));

  test('board is consistent: no square is both a foot/head and an end', () {
    final starts = {...SnlController.ladders.keys, ...SnlController.snakes.keys};
    final ends = {...SnlController.ladders.values, ...SnlController.snakes.values};
    expect(starts.length, SnlController.ladders.length + SnlController.snakes.length);
    expect(starts.intersection(ends), isEmpty);
    expect(starts.contains(1) || starts.contains(100), isFalse);
    SnlController.ladders.forEach((a, b) => expect(b, greaterThan(a)));
    SnlController.snakes.forEach((a, b) => expect(b, lessThan(a)));
  });

  test('a roll moves that many squares and passes the turn', () async {
    final g = game();
    await g.roll(forced: 2);
    expect(g.position[0], 3);
    expect(g.current, 1);
  });

  test('landing on a ladder climbs it', () async {
    final g = game();
    await g.roll(forced: 3); // 1 -> 4, ladder to 25
    expect(g.position[0], 25);
    expect(g.climbs[0], 1);
  });

  test('landing on a snake slides down', () async {
    final g = game()..position[0] = 24;
    await g.roll(forced: 3); // 27 -> 5
    expect(g.position[0], 5);
    expect(g.bites[0], 1);
  });

  test('a six earns another roll', () async {
    final g = game()..position[0] = 10;
    await g.roll(forced: 6);
    expect(g.position[0], 16);
    expect(g.current, 0);
    expect(g.phase, Phase.awaitingRoll);
  });

  test('the finish needs an exact roll', () async {
    final g = game()..position[0] = 97;
    await g.roll(forced: 5);
    expect(g.position[0], 97);
    expect(g.current, 1);
    g.current = 0;
    g.phase = Phase.awaitingRoll;
    await g.roll(forced: 3);
    expect(g.position[0], 100);
    expect(g.winner, 0);
    expect(g.phase, Phase.gameOver);
  });

  test('a full bot match ends with everyone ranked', () async {
    final g = SnlController(
        seats: [3, 0, 1, 2], bots: {0, 1, 2, 3}, speed: 0, random: Random(4));
    final done = Completer<void>();
    g.addListener(() {
      if (g.phase == Phase.gameOver && !done.isCompleted) done.complete();
    });
    g.start();
    await done.future.timeout(const Duration(seconds: 60));
    expect(g.finished.toSet(), {0, 1, 2, 3});
    for (final p in g.finished.take(3)) {
      expect(g.position[p], 100);
    }
    g.dispose();
  });
}
