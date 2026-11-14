import 'dart:math';
import 'dart:ui';

import 'package:elite_play_ludo/game/fruit_game.dart';
import 'package:flutter_test/flutter_test.dart';

FruitGame _game(FruitMode mode) => FruitGame(mode: mode, random: Random(2))
  ..resize(const Size(400, 800))
  ..started = true;

/// Advances the game in small steps.
void _run(FruitGame g, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    g.update(1 / 60);
  }
}

void main() {
  test('fruit is thrown up, peaks on the board and falls back', () {
    final g = _game(FruitMode.classic);
    final f = g.launch(3, x: 200, apex: 250);
    var highest = f.pos.dy;
    for (var i = 0; i < 60 * 3 && g.flyers.contains(f); i++) {
      g.update(1 / 60);
      highest = min(highest, f.pos.dy);
    }
    expect(highest, closeTo(250, 15));
    expect(g.flyers.contains(f), isFalse);
  });

  test('a swipe across a fruit cuts it into two halves with juice', () {
    final g = _game(FruitMode.classic);
    final f = g.launch(23, x: 200, apex: 300);
    _run(g, .5);
    final ev = g.slice(
      f.pos - const Offset(80, 0),
      f.pos + const Offset(80, 0),
    );
    expect(ev.cut, 1);
    expect(g.score, 1);
    expect(g.flyers, isEmpty);
    expect(g.halves.length, 2);
    expect(g.drops, isNotEmpty);
    expect(g.stains.length, 1);
  });

  test('a swipe that misses cuts nothing', () {
    final g = _game(FruitMode.classic);
    final f = g.launch(0, x: 100, apex: 300);
    _run(g, .5);
    final ev = g.slice(
      f.pos + const Offset(0, 120),
      f.pos + const Offset(80, 140),
    );
    expect(ev.cut, 0);
    expect(g.flyers, contains(f));
  });

  test('three fruits in one swipe make a combo', () {
    final g = _game(FruitMode.classic);
    for (final x in [100.0, 200.0, 300.0]) {
      g.launch(5, x: x, apex: 300).vel = Offset.zero;
    }
    for (final f in g.flyers) {
      f.pos = Offset(f.pos.dx, 400);
    }
    final ev = g.slice(const Offset(50, 400), const Offset(350, 400));
    expect(ev.cut, 3);
    final end = g.endSwipe();
    expect(end.combo, 3);
    expect(g.score, 6);
    expect(g.bestCombo, 3);
  });

  test('classic: a bomb ends the game', () {
    final g = _game(FruitMode.classic);
    final b = g.launch(-1, x: 200, apex: 300);
    _run(g, .5);
    final ev = g.slice(
      b.pos - const Offset(60, 0),
      b.pos + const Offset(60, 0),
    );
    expect(ev.bomb, isTrue);
    expect(g.over, isTrue);
    expect(g.endedBy, 'bomb');
  });

  test('classic: three missed fruits end the game', () {
    final g = _game(FruitMode.classic);
    var missed = 0;
    for (var i = 0; i < 60 * 60 && !g.over; i++) {
      missed += g.update(1 / 60).missed;
    }
    expect(g.over, isTrue);
    expect(g.endedBy, anyOf('lives', 'bomb', 'poison'));
    if (g.endedBy == 'lives') expect(missed, 3);
    expect(g.lives, lessThanOrEqualTo(0));
  });

  test('timed: the clock ends it and a bomb only costs points', () {
    final g = _game(FruitMode.timed)..score = 15;
    final b = g.launch(-1, x: 200, apex: 300);
    _run(g, .5);
    g.slice(b.pos - const Offset(60, 0), b.pos + const Offset(60, 0));
    expect(g.over, isFalse);
    expect(g.score, 5);
    _run(g, FruitGame.timedLength);
    expect(g.over, isTrue);
    expect(g.endedBy, 'time');
    expect(g.lives, 3);
  });

  test('waves keep coming and grow', () {
    final g = _game(FruitMode.timed);
    var early = 0, late = 0;
    for (var i = 0; i < 60 * 59; i++) {
      final n = g.update(1 / 60).launched;
      if (g.time < 15) early += n;
      if (g.time > 44) late += n;
    }
    expect(early, greaterThan(4));
    expect(late, greaterThan(early));
  });

  test('the halves fly apart on the sides they were cut from', () {
    final g = _game(FruitMode.classic);
    final f = g.launch(11, x: 200, apex: 300)
      ..pos = const Offset(200, 400)
      ..vel = Offset.zero;
    g.slice(f.pos - const Offset(0, 80), f.pos + const Offset(0, 80));
    final left = g.halves.firstWhere((h) => !h.right);
    final right = g.halves.firstWhere((h) => h.right);
    expect(left.pos.dx, lessThan(200));
    expect(right.pos.dx, greaterThan(200));
    expect(left.vel.dx, lessThan(0));
    expect(right.vel.dx, greaterThan(0));
    expect(g.slashes, isNotEmpty);
  });

  test('poison costs a life in classic and points in timed', () {
    final g = _game(FruitMode.classic);
    final p = g.launch(poisonKind, x: 200, apex: 300)
      ..pos = const Offset(200, 400)
      ..vel = Offset.zero;
    final ev = g.slice(
      p.pos - const Offset(60, 0),
      p.pos + const Offset(60, 0),
    );
    expect(ev.poison, isTrue);
    expect(g.lives, 2);
    expect(g.over, isFalse);
    expect(g.score, 0);

    final t = _game(FruitMode.timed)..score = 8;
    final q = t.launch(poisonKind, x: 200, apex: 300)
      ..pos = const Offset(200, 400)
      ..vel = Offset.zero;
    t.slice(q.pos - const Offset(60, 0), q.pos + const Offset(60, 0));
    expect(t.score, 3);
    expect(t.lives, 3);
  });

  test('a dropped poison flask costs nothing', () {
    final g = _game(FruitMode.classic);
    g.launch(poisonKind, x: 200, apex: 300);
    g.launch(bombKind, x: 100, apex: 300);
    var missed = 0;
    for (var i = 0; i < 60 * 3; i++) {
      missed += g.update(1 / 60).missed;
      g.flyers.removeWhere((f) => f.fruit);
    }
    expect(missed, 0);
    expect(g.lives, 3);
  });
}
