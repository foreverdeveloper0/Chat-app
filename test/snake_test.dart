import 'dart:math';

import 'package:elite_play_ludo/game/snake_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SnakeGame game({bool wrap = false, int seed = 1}) =>
      SnakeGame(cols: 9, rows: 9, wrap: wrap, random: Random(seed));

  test('starts three long, heading right, with fruit off the snake', () {
    final g = game();
    expect(g.length, 3);
    expect(g.dir, SnakeDir.right);
    expect(g.body.contains(g.food), isFalse);
    expect(g.inside(g.food), isTrue);
  });

  test('moves one cell per step and keeps its length', () {
    final g = game()..food = const Cell(0, 0);
    final head = g.head;
    g.step();
    expect(g.head, Cell(head.x + 1, head.y));
    expect(g.length, 3);
    expect(g.droppedTail, isNotNull);
  });

  test('eating fruit grows the snake, scores and moves the fruit', () {
    final g = game();
    g.food = Cell(g.head.x + 1, g.head.y);
    final r = g.step();
    expect(r.ate, isTrue);
    expect(g.length, 4);
    expect(g.score, 10);
    expect(g.droppedTail, isNull);
    expect(g.body.contains(g.food), isFalse);
  });

  test('cannot reverse, and two quick turns are both applied', () {
    final g = game()..food = const Cell(0, 0);
    g.turn(SnakeDir.left); // straight back: ignored
    g.step();
    expect(g.dir, SnakeDir.right);
    g
      ..turn(SnakeDir.up)
      ..turn(SnakeDir.left)
      ..turn(SnakeDir.down); // a third is dropped
    g.step();
    expect(g.dir, SnakeDir.up);
    g.step();
    expect(g.dir, SnakeDir.left);
    g.step();
    expect(g.dir, SnakeDir.left);
  });

  test('hitting a wall ends the game', () {
    final g = game()..food = const Cell(0, 0);
    SnakeStep r = SnakeStep();
    for (var i = 0; i < 9 && g.alive; i++) {
      r = g.step();
    }
    expect(g.alive, isFalse);
    expect(r.died, isTrue);
    expect(g.head.x, 8); // stopped at the last cell, not past it
  });

  test('an open arena wraps to the other side instead', () {
    final g = game(wrap: true)..food = const Cell(0, 0);
    for (var i = 0; i < 9; i++) {
      g.step();
    }
    expect(g.alive, isTrue);
    expect(g.head.x, lessThan(4));
  });

  test('running into its own body ends the game', () {
    final g = game();
    // Grow to five so a tight loop bites the body.
    for (var i = 0; i < 2; i++) {
      g.food = Cell(g.head.x + 1, g.head.y);
      g.step();
    }
    g.food = const Cell(0, 0);
    g.turn(SnakeDir.down);
    g.step();
    g.turn(SnakeDir.left);
    g.step();
    g.turn(SnakeDir.up);
    final r = g.step();
    expect(r.died, isTrue);
  });

  test('moving into the cell the tail is leaving is allowed', () {
    final g = game()..food = const Cell(0, 0);
    // Grow to four, then turn in a 2x2 square: the head follows the tail.
    g.food = Cell(g.head.x + 1, g.head.y);
    g.step();
    g.food = const Cell(0, 0);
    for (final d in [SnakeDir.down, SnakeDir.left, SnakeDir.up, SnakeDir.right]) {
      g.turn(d);
      expect(g.step().died, isFalse);
    }
    expect(g.alive, isTrue);
  });

  test('a timed bonus appears every fifth fruit and is worth more', () {
    final g = game(wrap: true);
    SnakeStep r = SnakeStep();
    for (var i = 0; i < SnakeGame.bonusEvery; i++) {
      g.food = g.neighbour(g.head, g.dir)!;
      r = g.step();
    }
    expect(r.bonusSpawned, isTrue);
    expect(g.bonus, isNotNull);
    final before = g.score;
    g.bonus = g.neighbour(g.head, g.dir)!;
    if (g.food == g.bonus) g.food = const Cell(0, 0);
    r = g.step();
    expect(r.ateBonus, isTrue);
    expect(g.score - before, greaterThan(20));
    expect(g.bonus, isNull);
  });

  test('the bonus disappears if it is not eaten in time', () {
    final g = SnakeGame(cols: 9, rows: 9, wrap: true, random: Random(3));
    for (var i = 0; i < SnakeGame.bonusEvery; i++) {
      g.food = g.neighbour(g.head, g.dir)!;
      g.step();
    }
    // Circle away from everything until it times out.
    g.bonus = const Cell(0, 0);
    g.food = const Cell(8, 8);
    var expired = false;
    for (var i = 0; i < SnakeGame.bonusLife + 2 && !expired; i++) {
      if (g.head.y != 4) break;
      expired = g.step().bonusExpired;
    }
    expect(expired, isTrue);
    expect(g.bonus, isNull);
  });

  test('gets faster as it eats, down to a floor', () {
    final g = game(wrap: true);
    final start = g.stepMs;
    g.eaten = 10;
    expect(g.stepMs, lessThan(start));
    g.eaten = 1000;
    expect(g.stepMs, g.speed.minMs);
  });

  test('the self-playing snake eats and survives a long run', () {
    for (final wrap in [false, true]) {
      final g = SnakeGame(cols: 12, rows: 12, wrap: wrap, random: Random(7));
      for (var i = 0; i < 1500 && g.alive && !g.won; i++) {
        final d = g.botMove();
        if (d != null) g.turn(d);
        g.step();
        expect(g.body.toSet().length, g.length, reason: 'no overlap');
        expect(g.body.every(g.inside), isTrue);
      }
      expect(g.eaten, greaterThan(15), reason: 'wrap=$wrap');
    }
  });
}
