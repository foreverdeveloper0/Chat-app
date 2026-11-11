import 'dart:math';

import 'package:elite_play_ludo/game/ghuti_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('37 points, 16 pieces each, the middle row empty', () {
    final g = GhutiGame();
    expect(GhutiGame.points.length, 37);
    expect(g.count(0), 16);
    expect(g.count(1), 16);
    for (var c = 0; c < 5; c++) {
      expect(g.board.containsKey(Pt(c, 2)), isFalse);
    }
    for (final p in GhutiGame.points) {
      expect(GhutiGame.spot(p), isNotNull);
    }
  });

  test('links match the board: the centre has eight, odd points four', () {
    Set<Pt> n(int c, int r) => GhutiGame.neighbours(Pt(c, r)).toSet();
    expect(n(2, 2).length, 8);
    expect(n(1, 2), {Pt(0, 2), Pt(2, 2), Pt(1, 1), Pt(1, 3)});
    // The apex joins the grid to its triangle.
    expect(n(2, 0), containsAll([Pt(1, -1), Pt(2, -1), Pt(3, -1)]));
    expect(n(0, -2), {Pt(2, -2), Pt(1, -1)});
    for (final p in GhutiGame.points) {
      for (final q in GhutiGame.neighbours(p)) {
        expect(GhutiGame.neighbours(q), contains(p), reason: '$p-$q');
      }
    }
  });

  test('opening moves only go into the empty middle row', () {
    final g = GhutiGame();
    final moves = g.movesFor(0);
    expect(moves, isNotEmpty);
    expect(moves.every((m) => m.to.y == 2 && !m.isCapture), isTrue);
  });

  test('a jump captures, and a chain may continue', () {
    final g = GhutiGame()..board.clear();
    g.board
      ..[Pt(2, 4)] = 0
      ..[Pt(2, 3)] = 1
      ..[Pt(2, 1)] = 1
      ..[Pt(4, 4)] = 1; // keeps player 1 alive
    expect(g.targets(Pt(2, 4)), contains((Pt(2, 2), Pt(2, 3))));
    final taken = g.play(Pt(2, 4), Pt(2, 2));
    expect(taken, Pt(2, 3));
    expect(g.board.containsKey(Pt(2, 3)), isFalse);
    // Can jump again over (2,1) to (2,0): still our turn, only that piece.
    expect(g.current, 0);
    expect(g.chaining, Pt(2, 2));
    expect(g.targets(Pt(2, 2)).map((t) => t.$1), [Pt(2, 0)]);
    g.play(Pt(2, 2), Pt(2, 0));
    expect(g.count(1), 1);
    expect(g.current, 1);
  });

  test('a chain can be ended early', () {
    final g = GhutiGame()..board.clear();
    g.board
      ..[Pt(2, 4)] = 0
      ..[Pt(2, 3)] = 1
      ..[Pt(2, 1)] = 1;
    g.play(Pt(2, 4), Pt(2, 2));
    g.endTurn();
    expect(g.current, 1);
    expect(g.chaining, isNull);
  });

  test('taking the last piece wins; having no move loses', () {
    final g = GhutiGame()..board.clear();
    g.board
      ..[Pt(2, 4)] = 0
      ..[Pt(2, 3)] = 1;
    g.play(Pt(2, 4), Pt(2, 2));
    expect(g.winner, 0);

    final h = GhutiGame()..board.clear();
    // Player 1 boxed into the top corner.
    h.board
      ..[Pt(0, -2)] = 1
      ..[Pt(2, -2)] = 0
      ..[Pt(1, -1)] = 0
      ..[Pt(3, 3)] = 0;
    // Block the jumps too.
    h.board
      ..[Pt(4, -2)] = 0
      ..[Pt(2, 0)] = 0;
    h.play(Pt(3, 3), Pt(3, 2));
    expect(h.winner, 0);
  });

  test('a long game without captures is a draw', () {
    final g = GhutiGame()..board.clear();
    g.board
      ..[Pt(0, 4)] = 0
      ..[Pt(4, 0)] = 1;
    for (var i = 0; i < GhutiGame.drawAfter && !g.draw; i++) {
      final m = g.movesFor(g.current).firstWhere((m) => !m.isCapture);
      g.play(m.from, m.to);
    }
    expect(g.draw, isTrue);
  });

  test('computer players finish games', () {
    for (final seed in [1, 2, 3, 4]) {
      final g = GhutiGame(bots: {0, 1}, random: Random(seed));
      var moves = 0;
      while (g.winner == null && !g.draw && moves < 2000) {
        final m = g.botMove();
        for (var i = 1; i < m.path.length; i++) {
          g.play(m.path[i - 1], m.path[i]);
        }
        if (g.chaining != null) g.endTurn();
        moves++;
      }
      expect(g.winner != null || g.draw, isTrue, reason: 'seed $seed');
    }
  });
}
