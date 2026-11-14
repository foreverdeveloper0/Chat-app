import 'dart:math';

import 'package:elite_play_ludo/game/teen_patti.dart';
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

int _s(String s) => evaluate(_h(s)).strength;

void main() {
  test('hands are named correctly', () {
    expect(evaluate(_h('7S 7H 7D')).rank, HandRank.trail);
    expect(evaluate(_h('QH KH AH')).rank, HandRank.pureSequence);
    expect(evaluate(_h('2S 3H AD')).rank, HandRank.sequence);
    expect(evaluate(_h('2C 9C KC')).rank, HandRank.colour);
    expect(evaluate(_h('9S 9H KD')).rank, HandRank.pair);
    expect(evaluate(_h('2S 9H KD')).rank, HandRank.highCard);
    // K-A-2 is not a run.
    expect(evaluate(_h('KS AH 2D')).rank, HandRank.highCard);
  });

  test('hands are ordered by the Teen Patti rules', () {
    final order = [
      '2S 3H 5D', // lowest high card
      'AS KH JD', // best high card
      '2S 2H 3D', // lowest pair
      'AS AH KD', // best pair
      '2C 3C 5C', // lowest colour
      'AC KC JC', // best colour
      '2S 3H 4D', // lowest run
      'KS QH JD',
      'AS 2H 3D', // second best run
      'AS KH QD', // best run
      '2H 3H 4H', // lowest pure run
      'AH KH QH', // best pure run
      '2S 2H 2D', // lowest trail
      'AS AH AD', // best trail
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        _s(order[i]),
        greaterThan(_s(order[i - 1])),
        reason: '${order[i]} should beat ${order[i - 1]}',
      );
    }
    // A pair is decided by the pair first, then the kicker.
    expect(_s('3S 3H 2D'), greaterThan(_s('2S 2H AD')));
    expect(_s('9S 9H KD'), greaterThan(_s('9D 9C QD')));
    // Suits never break a tie.
    expect(_s('AS KH JD'), _s('AC KD JS'));
  });

  TeenPatti game({int players = 5, int seed = 1}) =>
      TeenPatti(boot: 10, buyIn: 1000, players: players, random: Random(seed));

  test('the deal takes the boot and gives three cards each', () {
    final g = game()..deal();
    expect(g.pot, 50);
    expect(g.stake, 10);
    for (final s in g.seats) {
      expect(s.cards.length, 3);
      expect(s.chips, 990);
    }
    final all = g.seats.expand((s) => s.cards).map((c) => '$c').toSet();
    expect(all.length, 15);
    expect(g.turn, (g.dealer + 1) % 5);
  });

  test('blind pays the stake, seen pays double, a raise doubles the stake', () {
    final g = game(players: 3)..deal();
    final a = g.current;
    g.bet(a); // blind 10
    expect(a.staked, 20);
    expect(g.stake, 10);
    final b = g.current;
    g.see(b);
    expect(g.callFor(b), 20);
    g.bet(b, raise: true); // seen raise 40 -> stake 20
    expect(b.staked, 50);
    expect(g.stake, 20);
    final c = g.current;
    expect(g.callFor(c), 20); // blind matches the new stake
    g.bet(c);
    expect(g.pot, 30 + 10 + 40 + 20);
  });

  test('when everyone else packs the last player takes the pot', () {
    final g = game(players: 3)..deal();
    g.pack(g.current);
    g.pack(g.current);
    expect(g.playing, isFalse);
    final w = g.result!.winner;
    expect(w.chips, 1000 - 10 + 30);
    expect(g.result!.revealed, isEmpty);
    expect(g.seats.fold(0, (t, s) => t + s.chips), 3000);
  });

  test('a show between the last two: best hand wins, asker loses a tie', () {
    final g = game(players: 2)..deal();
    final a = g.current, b = g.seats[1 - a.index];
    a.cards = _h('AS KH QD');
    b.cards = _h('2S 2H 2D');
    g.see(a);
    g.show(a);
    expect(g.result!.winner, b);
    expect(g.result!.revealed.length, 2);
    expect(a.chips + b.chips, 2000);

    final t = game(players: 2)..deal();
    final x = t.current, y = t.seats[1 - x.index];
    x.cards = _h('AS KH JD');
    y.cards = _h('AC KD JS');
    t.show(x);
    expect(t.result!.winner, y);
  });

  test('side show: the weaker of the two packs, or it is refused', () {
    final g = game(players: 3, seed: 3)..deal();
    final a = g.current;
    g.see(a);
    g.bet(a);
    final b = g.current;
    g.see(b);
    a.cards = _h('2S 3H 5D');
    b.cards = _h('KS KH 4D');
    expect(g.sideShowTarget(b), a);
    // Force the answer rather than leave it to the computer's mood.
    g.sideShowAsk = b;
    final out = g.answerSideShow(true, asker: b, target: a);
    expect(out, a);
    expect(a.packed, isTrue);
    expect(g.playing, isTrue);
    expect(g.active.length, 2);
  });

  test('a player who cannot cover the bet goes all in and cards are shown', () {
    final g = game(players: 2)..deal();
    final a = g.current;
    a.chips = 5;
    g.bet(a);
    expect(g.result, isNotNull);
    expect(a.staked, 15);
    expect(g.result!.revealed.length, 2);
  });

  test('computer players play whole hands and chips are conserved', () {
    for (var seed = 0; seed < 30; seed++) {
      final g = game(seed: seed);
      // The person playing is driven by the computer logic too here.
      for (var hand = 0; hand < 12; hand++) {
        final before = g.seats.fold(0, (t, s) => t + s.chips);
        g.deal();
        var guard = 0;
        while (g.playing) {
          expect(guard++, lessThan(400), reason: 'hand never ended');
          if (g.sideShowAsk != null) {
            g.answerSideShow(true);
            continue;
          }
          final s = g.current;
          expect(s.active, isTrue);
          g.botTurn();
        }
        expect(g.result, isNotNull);
        final total = g.seats.fold(0, (t, s) => t + s.chips);
        expect(total, before, reason: 'chips appeared or vanished');
        expect(g.seats.every((s) => s.chips >= 0), isTrue);
        g.rebuyBots();
        if (g.you.chips < g.boot) g.you.chips = 1000;
      }
    }
  });

  test('the pot limit forces a showdown', () {
    final g = TeenPatti(boot: 10, buyIn: 1000000, players: 2, random: Random(2))
      ..deal();
    var guard = 0;
    while (g.playing) {
      expect(guard++, lessThan(2000));
      g.bet(g.current, raise: true);
    }
    expect(g.result!.revealed.length, 2);
    expect(g.result!.pot, greaterThanOrEqualTo(g.potLimit));
  });
}
