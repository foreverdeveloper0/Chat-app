import 'dart:async';
import 'dart:math';

import 'package:elite_play_ludo/game/ludo_controller.dart';
import 'package:elite_play_ludo/game/ludo_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('track is a closed loop of 52 adjacent cells', () {
    expect(LudoRules.track.toSet().length, 52);
    for (var i = 0; i < 52; i++) {
      final a = LudoRules.track[i], b = LudoRules.track[(i + 1) % 52];
      expect(max((a.$1 - b.$1).abs(), (a.$2 - b.$2).abs()), 1,
          reason: 'gap after cell $i');
    }
  });

  test('each home column continues from the last track cell', () {
    for (var p = 0; p < 4; p++) {
      final last = LudoRules.track[LudoRules.trackIndex(p, 50)];
      final first = LudoRules.homeColumns[p].first;
      expect((last.$1 - first.$1).abs() + (last.$2 - first.$2).abs(), 1);
    }
  });

  test('move rules', () {
    expect(LudoRules.canMove(-1, 5), isFalse);
    expect(LudoRules.canMove(-1, 6), isTrue);
    expect(LudoRules.canMove(53, 3), isTrue);
    expect(LudoRules.canMove(53, 4), isFalse);
  });

  test('capture sends the opponent home and grants another turn', () async {
    final c = LudoController(seats: [0, 1], speed: 0, random: Random(1));
    c.tokens[0][0].progress = 2; // red, track index 2
    c.tokens[1][0].progress = 44; // green, track index (13+44)%52 = 5
    await c.roll(forced: 3);
    if (c.phase == Phase.choosing) await c.move(c.tokens[0][0]);
    expect(c.tokens[0][0].progress, 5);
    expect(c.tokens[1][0].progress, LudoRules.yard);
    expect(c.current, 0);
    expect(c.phase, Phase.awaitingRoll);
    c.dispose();
  });

  test('tokens on a safe cell are not captured', () async {
    final c = LudoController(seats: [0, 1], speed: 0, random: Random(1));
    c.tokens[0][0].progress = 5;
    c.tokens[1][0].progress = 47; // track index 8, a star cell
    await c.roll(forced: 3);
    if (c.phase == Phase.choosing) await c.move(c.tokens[0][0]);
    expect(c.tokens[1][0].progress, 47);
    expect(c.current, 1);
    c.dispose();
  });

  test('finishing order: the match goes on until one player is left', () async {
    final c = LudoController(
        seats: [3, 0, 1, 2], bots: {0, 1, 2, 3}, speed: 0, random: Random(5));
    final done = Completer<void>();
    c.addListener(() {
      if (c.phase == Phase.gameOver && !done.isCompleted) done.complete();
    });
    c.start();
    await done.future.timeout(const Duration(seconds: 60));
    expect(c.finished.toSet(), {0, 1, 2, 3});
    expect(c.winner, c.finished.first);
    for (final p in c.finished.take(3)) {
      expect(c.homeCount(p), 4);
    }
    expect(c.rankOf(c.finished[1]), 2);
    c.dispose();
  });

  test('a player who leaves is skipped and the last one standing wins', () async {
    final c = LudoController(seats: [0, 1, 2], speed: 0, random: Random(2));
    c.leave(1);
    expect(c.active, [0, 2]);
    await c.roll(forced: 3); // red has no move, turn passes over green
    expect(c.current, 2);
    c.leave(2);
    expect(c.phase, Phase.gameOver);
    expect(c.winner, 0);
    c.dispose();
  });

  test('a full bot game always finishes with a winner', () async {
    for (final seed in [1, 2, 3]) {
      final c = LudoController(
          seats: [3, 0, 1, 2], bots: {0, 1, 2, 3}, speed: 0, random: Random(seed));
      final done = Completer<void>();
      c.addListener(() {
        if (c.phase == Phase.gameOver && !done.isCompleted) done.complete();
      });
      c.start();
      await done.future.timeout(const Duration(seconds: 30));
      expect(c.winner, isNotNull);
      expect(c.homeCount(c.winner!), 4);
      for (final p in c.seats) {
        for (final t in c.tokens[p]) {
          expect(t.progress, inInclusiveRange(-1, 56));
        }
      }
      c.dispose();
    }
  });
}
