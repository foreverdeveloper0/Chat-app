import 'dart:math';

import 'package:elite_play_ludo/game/holdem.dart';
import 'package:flutter_test/flutter_test.dart';

List<PlayingCard> _h(String s) => [
  for (final t in s.split(' '))
    PlayingCard(switch (t.substring(0, t.length - 1)) {
      'A' => 14,
      'K' => 13,
      'Q' => 12,
      'J' => 11,
      final n => int.parse(n),
    }, 'SHDC'.indexOf(t[t.length - 1])),
];

void main() {
  test('five-card hands are named and ordered', () {
    final order = [
      ('7S 5H 4D 3C 2S', HandRank.highCard),
      ('AS KH QD JC 9S', HandRank.highCard),
      ('2S 2H 5D 4C 3S', HandRank.pair),
      ('AS AH KD QC JS', HandRank.pair),
      ('3S 3H 2D 2C 4S', HandRank.twoPair),
      ('AS AH KD KC QS', HandRank.twoPair),
      ('2S 2H 2D 4C 3S', HandRank.trips),
      ('AS 2H 3D 4C 5S', HandRank.straight), // the wheel is the lowest
      ('2S 3H 4D 5C 6S', HandRank.straight),
      ('10S JH QD KC AS', HandRank.straight),
      ('2H 3H 4H 5H 7H', HandRank.flush),
      ('AH KH QH JH 9H', HandRank.flush),
      ('2S 2H 2D 3C 3S', HandRank.fullHouse),
      ('AS AH AD KC KS', HandRank.fullHouse),
      ('2S 2H 2D 2C 3S', HandRank.quads),
      ('AD 2D 3D 4D 5D', HandRank.straightFlush),
      ('10C JC QC KC AC', HandRank.straightFlush),
    ];
    var last = -1;
    for (final (cards, rank) in order) {
      final v = evaluate5(_h(cards));
      expect(v.rank, rank, reason: cards);
      expect(v.strength, greaterThan(last), reason: cards);
      last = v.strength;
    }
    // Kickers decide equal pairs; suits never do.
    expect(
      evaluate5(_h('KS KH AD 3C 2S')).strength,
      greaterThan(evaluate5(_h('KD KC QD JC 10S')).strength),
    );
    expect(
      evaluate5(_h('AS KH QD JC 9S')).strength,
      evaluate5(_h('AC KD QS JH 9D')).strength,
    );
  });

  test('the best five of seven cards are used', () {
    expect(evaluate(_h('AH KH 2H 7H 9H 9S 9D')).rank, HandRank.flush);
    expect(evaluate(_h('9C 9H 2H 7H 7S 9S 3D')).rank, HandRank.fullHouse);
    expect(evaluate(_h('AS 2D 3H 4C 5S KD KH')).rank, HandRank.straight);
  });

  Holdem game({int players = 5, int seed = 1, int buyIn = 2000}) => Holdem(
    smallBlind: 10,
    buyIn: buyIn,
    players: players,
    random: Random(seed),
  );

  test('the deal posts blinds and gives two cards each', () {
    final g = game()..deal();
    expect(g.pot, 30);
    expect(g.currentBet, 20);
    expect(g.smallBlindSeat, (g.dealer + 1) % 5);
    expect(g.bigBlindSeat, (g.dealer + 2) % 5);
    expect(g.turn, (g.dealer + 3) % 5);
    expect(g.seats.every((s) => s.hole.length == 2), isTrue);
    expect(g.seats.expand((s) => s.hole).map((c) => '$c').toSet().length, 10);
    // Heads-up the dealer is the small blind and acts first.
    final h = game(players: 2)..deal();
    expect(h.smallBlindSeat, h.dealer);
    expect(h.turn, h.dealer);
  });

  test('a round of calls and a check moves on to the flop, turn and river', () {
    final g = game(players: 3)..deal();
    g.call(g.current); // dealer calls
    g.call(g.current); // small blind completes
    expect(g.awaitingStreet, isFalse);
    expect(g.turn, g.bigBlindSeat); // the big blind has the option
    g.call(g.current); // checks
    expect(g.awaitingStreet, isTrue);
    g.nextStreet();
    expect(g.street, Street.flop);
    expect(g.board.length, 3);
    expect(g.pot, 60);
    expect(g.turn, g.smallBlindSeat); // first left of the dealer
    for (final want in [Street.turn, Street.river]) {
      for (var i = 0; i < 3; i++) {
        g.call(g.current);
      }
      g.nextStreet();
      expect(g.street, want);
    }
    expect(g.board.length, 5);
    for (var i = 0; i < 3; i++) {
      g.call(g.current);
    }
    g.nextStreet();
    expect(g.result, isNotNull);
    expect(g.result!.revealed.length, 3);
    expect(g.seats.fold(0, (t, s) => t + s.chips), 6000);
  });

  test('a raise reopens the betting and sets the minimum re-raise', () {
    final g = game(players: 3)..deal();
    final a = g.current;
    expect(g.raiseRange(a)!.min, 40);
    g.raiseTo(a, 100); // a raise of 80
    expect(g.currentBet, 100);
    final b = g.current;
    expect(g.toCall(b), 90);
    expect(g.raiseRange(b)!.min, 180);
    g.call(b);
    g.fold(g.current);
    expect(g.awaitingStreet, isTrue);
    expect(g.pot, 100 + 100 + 20);
  });

  test('everyone folding gives the pot to the last player, cards unseen', () {
    final g = game(players: 3)..deal();
    final bb = g.seats[g.bigBlindSeat];
    g.fold(g.current);
    g.fold(g.current);
    expect(g.playing, isFalse);
    expect(g.result!.winner, bb);
    expect(g.result!.revealed, isEmpty);
    expect(bb.chips, 2010);
  });

  test('side pots: a short all-in wins only what it can match', () {
    final g = game(players: 3)..deal();
    final short = g.seats[g.dealer]..chips = 100;
    final a = g.seats[g.smallBlindSeat], b = g.seats[g.bigBlindSeat];
    short.hole = _h('AS AH');
    a.hole = _h('KS KH');
    b.hole = _h('QS QH');
    g.raiseTo(short, 100); // all in
    g.raiseTo(a, 600);
    g.call(b);
    expect(g.awaitingStreet, isTrue);
    // A board that helps nobody.
    g.nextStreet();
    g.board
      ..clear()
      ..addAll(_h('2D 7C 9D'));
    while (g.playing) {
      if (g.awaitingStreet) {
        g.nextStreet();
        if (g.board.length == 4) g.board[3] = _h('3C').first;
        if (g.board.length == 5) g.board[4] = _h('4S').first;
      } else {
        g.call(g.current);
      }
    }
    final r = g.result!;
    expect(r.winnings[short], 300); // 100 from each of three
    expect(r.winnings[a], 1000); // the side pot between the other two
    expect(r.winnings[b], isNull);
  });

  test('a tie splits the pot', () {
    final g = game(players: 2)..deal();
    g.seats[0].hole = _h('AS 2D');
    g.seats[1].hole = _h('AH 2C');
    g.call(g.current);
    g.call(g.current);
    g.nextStreet();
    g.board
      ..clear()
      ..addAll(_h('KS KD 9C'));
    while (g.playing) {
      if (g.awaitingStreet) {
        g.nextStreet();
        if (g.board.length == 4) g.board[3] = _h('8H').first;
        if (g.board.length == 5) g.board[4] = _h('7S').first;
      } else {
        g.call(g.current);
      }
    }
    expect(g.result!.winnings.values.toList(), [20, 20]);
    expect(g.seats.every((s) => s.chips == 2000), isTrue);
  });

  test('computer players play whole hands and chips are conserved', () {
    for (var seed = 0; seed < 40; seed++) {
      final g = game(seed: seed);
      for (var hand = 0; hand < 15; hand++) {
        final before = g.seats.fold(0, (t, s) => t + s.chips);
        if (!g.deal()) break;
        var guard = 0;
        while (g.playing) {
          expect(guard++, lessThan(500), reason: 'hand never ended');
          if (g.awaitingStreet) {
            g.nextStreet();
            continue;
          }
          expect(g.current.canAct, isTrue);
          g.botTurn();
        }
        expect(g.result, isNotNull);
        expect(g.board.length, anyOf(0, 3, 4, 5));
        expect(g.seats.fold(0, (t, s) => t + s.chips), before);
        expect(g.seats.every((s) => s.chips >= 0), isTrue);
        g.rebuyBots();
        if (g.you.chips < g.bigBlind) g.you.chips = 2000;
      }
    }
  });

  test('you sit down with what you chose; the others with the usual stack', () {
    final g = Holdem(
      smallBlind: 10,
      buyIn: 2000,
      yourChips: 650,
      players: 4,
      random: Random(1),
    );
    expect(g.you.chips, 650);
    expect(g.seats.skip(1).every((s) => s.chips == 2000), isTrue);
    // Only computer players are topped up.
    g.you.chips = 0;
    g.seats[1].chips = 0;
    expect(g.rebuyBots(), [g.seats[1]]);
    expect(g.you.chips, 0);
  });
}
