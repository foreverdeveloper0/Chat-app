import 'dart:math';

import 'package:elite_play_ludo/game/carrom_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CarromGame game([List<int> seats = const [0, 2]]) =>
      CarromGame(seats: seats, random: Random(1));

  /// Runs the physics until everything stops, then applies the rules.
  ShotResult settle(CarromGame g) {
    for (var i = 0; i < 6000 && g.moving; i++) {
      g.step(1 / 120);
    }
    expect(g.moving, isFalse, reason: 'pieces must come to rest');
    return g.finishShot();
  }

  /// Clears the board except the pieces a test places itself.
  void clear(CarromGame g) {
    for (final p in g.pieces) {
      if (p != g.striker) p.pocketed = true;
    }
  }

  CarromPiece put(CarromGame g, PieceKind k, Offset at) =>
      g.pieces.firstWhere((p) => p.kind == k && p.pocketed)
        ..pocketed = false
        ..pos = at;

  test('racks nine white, nine black and the queen without overlaps', () {
    final g = game();
    expect(g.pieces.where((p) => p.kind == PieceKind.white).length, 9);
    expect(g.pieces.where((p) => p.kind == PieceKind.black).length, 9);
    expect(g.queen.pos, Carrom.centre);
    for (final a in g.pieces) {
      for (final b in g.pieces) {
        if (a != b) {
          expect((a.pos - b.pos).distance,
              greaterThanOrEqualTo(a.radius + b.radius - 1e-9));
        }
      }
    }
  });

  test('a shot that pockets nothing passes the turn', () {
    final g = game();
    clear(g);
    expect(g.shoot(const Offset(0, -1), .3), isTrue);
    final r = settle(g);
    expect(r.again, isFalse);
    expect(g.current, 2);
    // The striker is back on the new player's baseline.
    expect(g.striker.pos.dy, closeTo(Carrom.baseNear, 1e-9));
  });

  test('pieces bounce off the cushions and stay on the board', () {
    final g = game();
    g.shoot(const Offset(.3, -1), 1);
    for (var i = 0; i < 6000 && g.moving; i++) {
      g.step(1 / 120);
      for (final p in g.pieces.where((p) => !p.pocketed)) {
        expect(p.pos.dx, inInclusiveRange(Carrom.left, Carrom.right));
        expect(p.pos.dy, inInclusiveRange(Carrom.top, Carrom.bottom));
      }
    }
    expect(g.moving, isFalse);
  });

  test('pocketing your own coin keeps the turn', () {
    final g = game();
    clear(g);
    final hole = Carrom.pockets[0];
    final coin = put(g, PieceKind.white, hole + const Offset(.08, .08));
    g.placeStriker(.5);
    g.shoot(coin.pos - g.striker.pos + const Offset(.012, .012), .7);
    final r = settle(g);
    expect(r.own, 1);
    expect(r.again, isTrue);
    expect(g.current, 0);
    expect(g.pocketed[0], 1);
  });

  test('pocketing the striker is a foul: a coin comes back, turn passes', () {
    final g = game();
    clear(g);
    g.pocketed[0] = 2;
    g.placeStriker(0);
    g.shoot(Carrom.pockets[0] - g.striker.pos, .8);
    final r = settle(g);
    expect(r.foul, isTrue);
    expect(g.pocketed[0], 1);
    expect(g.pieces.where((p) => p.kind == PieceKind.white && !p.pocketed).length, 1);
    expect(g.current, 2);
  });

  test('the queen must be covered, or it returns to the centre', () {
    final g = game();
    clear(g);
    final hole = Carrom.pockets[1];
    put(g, PieceKind.queen, hole + const Offset(-.08, .08));
    g.placeStriker(.5);
    g.shoot(g.queen.pos - g.striker.pos + const Offset(-.012, .012), .7);
    var r = settle(g);
    expect(r.queen, isTrue);
    expect(g.queenPending, 0);
    expect(g.current, 0, reason: 'shoots again to cover');
    // Miss the cover.
    g.shoot(const Offset(0, -1), .2);
    r = settle(g);
    expect(r.queenReturned, isTrue);
    expect(g.queenOnBoard, isTrue);
    expect(g.queenOwner, isNull);
    expect(g.current, 2);
  });

  test('covering the queen and clearing nine coins wins', () {
    final g = game();
    clear(g);
    g
      ..pocketed[0] = 8
      ..queenPending = 0;
    final hole = Carrom.pockets[0];
    final coin = put(g, PieceKind.white, hole + const Offset(.08, .08));
    g.placeStriker(.5);
    g.shoot(coin.pos - g.striker.pos + const Offset(.012, .012), .7);
    final r = settle(g);
    expect(r.covered, isTrue);
    expect(g.queenOwner, 0);
    expect(r.winner, 0);
    expect(g.winnerScore, 9 + 3);
  });

  test('the last coin cannot go down while the queen is unclaimed', () {
    final g = game();
    clear(g);
    put(g, PieceKind.queen, Carrom.centre);
    g.pocketed[0] = 8;
    final hole = Carrom.pockets[0];
    final coin = put(g, PieceKind.white, hole + const Offset(.08, .08));
    g.placeStriker(.5);
    g.shoot(coin.pos - g.striker.pos + const Offset(.012, .012), .7);
    final r = settle(g);
    expect(r.winner, isNull);
    expect(g.pocketed[0], 8);
    expect(g.current, 2);
  });

  test('two players each get their own colour', () {
    final g = game();
    expect(g.teamOf(0), 0);
    expect(g.teamOf(2), 1);
  });

  test('four players: partners share a colour and turns go round', () {
    final g = game([0, 1, 2, 3]);
    expect(g.teamOf(0), g.teamOf(2));
    expect(g.teamOf(1), g.teamOf(3));
    clear(g);
    for (final seat in [1, 2, 3, 0]) {
      g.shoot(CarromGame.forward(g.current), .2);
      settle(g);
      expect(g.current, seat);
    }
  });

  test('computer players finish whole matches', () {
    for (final (seed, seats) in [(3, [0, 2]), (8, [0, 1, 2, 3])]) {
      final g = CarromGame(
          seats: seats, bots: seats.toSet(), random: Random(seed));
      var shots = 0;
      while (g.winner == null && shots < 900) {
        final s = g.botShot();
        g.placeStriker(s.t);
        if (!g.shoot(s.direction, s.power)) {
          g.placeStriker(g.rng.nextDouble());
          continue;
        }
        settle(g);
        shots++;
      }
      expect(g.winner, isNotNull, reason: 'seed $seed after $shots shots');
      expect(g.pocketed[g.winner!], 9);
      expect(g.queenOwner, isNotNull);
    }
  });
}
