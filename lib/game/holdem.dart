import 'dart:math';

/// A playing card: [rank] 2..14 (11 jack, 12 queen, 13 king, 14 ace) and
/// [suit] 0 spades, 1 hearts, 2 diamonds, 3 clubs.
class PlayingCard {
  const PlayingCard(this.rank, this.suit);
  final int rank, suit;

  bool get red => suit == 1 || suit == 2;
  String get label => switch (rank) {
    14 => 'A',
    13 => 'K',
    12 => 'Q',
    11 => 'J',
    _ => '$rank',
  };

  @override
  String toString() => '$label${'SHDC'[suit]}';
}

/// Poker hands, weakest first.
enum HandRank {
  highCard('High Card'),
  pair('Pair'),
  twoPair('Two Pair'),
  trips('Three of a Kind'),
  straight('Straight'),
  flush('Flush'),
  fullHouse('Full House'),
  quads('Four of a Kind'),
  straightFlush('Straight Flush');

  const HandRank(this.label);
  final String label;
}

typedef HandValue = ({HandRank rank, int strength});

/// Values exactly five cards. The bigger [strength] wins.
HandValue evaluate5(List<PlayingCard> c) {
  final ranks = c.map((x) => x.rank).toList()..sort((a, b) => b - a);
  final flush = c.every((x) => x.suit == c.first.suit);
  // How many of each rank, most first, then highest first.
  final count = <int, int>{};
  for (final r in ranks) {
    count[r] = (count[r] ?? 0) + 1;
  }
  final groups = count.keys.toList()
    ..sort((a, b) {
      final d = count[b]! - count[a]!;
      return d != 0 ? d : b - a;
    });
  int? straightHigh;
  if (count.length == 5) {
    if (ranks[0] - ranks[4] == 4) {
      straightHigh = ranks[0];
    } else if (ranks[0] == 14 && ranks[1] == 5) {
      straightHigh = 5; // the wheel: A-2-3-4-5
    }
  }
  final shape = groups.map((r) => count[r]!).toList();
  final HandRank rank;
  var kickers = groups;
  if (straightHigh != null && flush) {
    rank = HandRank.straightFlush;
    kickers = [straightHigh];
  } else if (shape[0] == 4) {
    rank = HandRank.quads;
  } else if (shape[0] == 3 && shape[1] == 2) {
    rank = HandRank.fullHouse;
  } else if (flush) {
    rank = HandRank.flush;
  } else if (straightHigh != null) {
    rank = HandRank.straight;
    kickers = [straightHigh];
  } else if (shape[0] == 3) {
    rank = HandRank.trips;
  } else if (shape[0] == 2 && shape[1] == 2) {
    rank = HandRank.twoPair;
  } else if (shape[0] == 2) {
    rank = HandRank.pair;
  } else {
    rank = HandRank.highCard;
  }
  var strength = rank.index;
  for (var i = 0; i < 5; i++) {
    strength = strength * 15 + (i < kickers.length ? kickers[i] : 0);
  }
  return (rank: rank, strength: strength);
}

/// The best five-card hand among five to seven cards.
HandValue evaluate(List<PlayingCard> cards) {
  assert(cards.length >= 5);
  final n = cards.length;
  HandValue? best;
  for (var a = 0; a < n - 4; a++) {
    for (var b = a + 1; b < n - 3; b++) {
      for (var c = b + 1; c < n - 2; c++) {
        for (var d = c + 1; d < n - 1; d++) {
          for (var e = d + 1; e < n; e++) {
            final v = evaluate5([
              cards[a],
              cards[b],
              cards[c],
              cards[d],
              cards[e],
            ]);
            if (best == null || v.strength > best.strength) best = v;
          }
        }
      }
    }
  }
  return best!;
}

/// Someone at the table.
class Seat {
  Seat(this.index, this.name, this.chips, {this.bot = true, this.nerve = .5});
  final int index;
  final String name;
  final bool bot;

  /// For the computer: 0 cautious .. 1 loves to bluff and raise.
  final double nerve;

  int chips;
  List<PlayingCard> hole = [];
  bool inHand = false, folded = false, acted = false;

  /// Chips bet on this street, and in the whole hand.
  int bet = 0, total = 0;

  /// What they last did, for the table to show ("Raise 400").
  String lastAction = '';

  bool get live => inHand && !folded;
  bool get allIn => live && chips == 0;
  bool get canAct => live && chips > 0;
}

enum Street { preflop, flop, turn, river, showdown }

/// How a hand ended.
class HandResult {
  HandResult(this.winnings, this.revealed, this.values);

  /// What each winner collected.
  final Map<Seat, int> winnings;

  /// Seats whose cards are turned over (empty when everyone else folded).
  final List<Seat> revealed;

  /// The hands of those who showed.
  final Map<Seat, HandValue> values;

  Seat get winner =>
      winnings.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// No-limit Texas Hold'em for two to five players.
class Holdem {
  Holdem({
    required this.smallBlind,
    required this.buyIn,
    int players = 5,
    String you = 'You',
    Random? random,
  }) : rng = random ?? Random() {
    const names = ['Riya', 'Arjun', 'Meera', 'Kabir'];
    const nerves = [.35, .7, .5, .85];
    seats.add(Seat(0, you, buyIn, bot: false));
    for (var i = 1; i < players.clamp(2, 5); i++) {
      seats.add(Seat(i, names[i - 1], buyIn, nerve: nerves[i - 1]));
    }
  }

  final Random rng;
  final int smallBlind, buyIn;
  int get bigBlind => smallBlind * 2;
  final seats = <Seat>[];
  Seat get you => seats.first;

  final board = <PlayingCard>[];
  var _deck = <PlayingCard>[];
  Street street = Street.preflop;
  int dealer = -1, smallBlindSeat = 0, bigBlindSeat = 0, turn = 0, hands = 0;

  /// The bet to match on this street, and the smallest legal raise.
  int currentBet = 0, minRaise = 0;
  int _raises = 0;

  /// True while a hand is in progress.
  bool playing = false;

  /// The betting round is over: call [nextStreet] to deal on.
  bool awaitingStreet = false;
  HandResult? result;

  int get pot => seats.fold(0, (t, s) => t + s.total);
  List<Seat> get live => seats.where((s) => s.live).toList();
  Seat get current => seats[turn];

  // ── Dealing ──

  /// Posts the blinds and deals two cards each. Returns false when fewer
  /// than two players have chips.
  bool deal() {
    for (final s in seats) {
      s
        ..hole = []
        ..folded = false
        ..acted = false
        ..bet = 0
        ..total = 0
        ..lastAction = ''
        ..inHand = s.chips > 0;
    }
    board.clear();
    result = null;
    awaitingStreet = false;
    if (seats.where((s) => s.inHand).length < 2) {
      playing = false;
      return false;
    }
    hands++;
    _deck = [
      for (var s = 0; s < 4; s++)
        for (var r = 2; r <= 14; r++) PlayingCard(r, s),
    ]..shuffle(rng);
    street = Street.preflop;
    dealer = _next(dealer, (s) => s.inHand);
    final inHand = seats.where((s) => s.inHand).length;
    // Heads-up the dealer posts the small blind.
    smallBlindSeat = inHand == 2 ? dealer : _next(dealer, (s) => s.inHand);
    bigBlindSeat = _next(smallBlindSeat, (s) => s.inHand);
    _pay(seats[smallBlindSeat], smallBlind);
    seats[smallBlindSeat].lastAction = 'SB $smallBlind';
    _pay(seats[bigBlindSeat], bigBlind);
    seats[bigBlindSeat].lastAction = 'BB $bigBlind';
    currentBet = bigBlind;
    minRaise = bigBlind;
    _raises = 0;
    for (var k = 0; k < 2; k++) {
      for (final s in seats.where((s) => s.inHand)) {
        s.hole.add(_deck.removeLast());
      }
    }
    playing = true;
    turn = _next(bigBlindSeat, (s) => s.canAct);
    _settle(from: bigBlindSeat);
    return true;
  }

  int _next(int from, bool Function(Seat) ok) {
    for (var k = 1; k <= seats.length; k++) {
      final i = ((from + k) % seats.length + seats.length) % seats.length;
      if (ok(seats[i])) return i;
    }
    return from < 0 ? 0 : from;
  }

  void _pay(Seat s, int amount) {
    final paid = min(amount, s.chips);
    s.chips -= paid;
    s.bet += paid;
    s.total += paid;
  }

  // ── What the player to move may do ──

  int toCall(Seat s) => min(max(0, currentBet - s.bet), s.chips);

  /// The smallest and largest street bet [s] may raise to, or null when
  /// they cannot raise.
  ({int min, int max})? raiseRange(Seat s) {
    final most = s.bet + s.chips;
    if (!s.canAct || most <= currentBet) return null;
    // Nobody left to raise against.
    if (seats.where((x) => x.canAct && x != s).isEmpty) return null;
    return (min: min(currentBet + minRaise, most), max: most);
  }

  // ── Moves ──

  void fold(Seat s) {
    s
      ..folded = true
      ..acted = true
      ..lastAction = 'Fold';
    _settle(from: s.index);
  }

  /// Check when there is nothing to call, otherwise call (all in if short).
  void call(Seat s) {
    final amount = toCall(s);
    _pay(s, amount);
    s
      ..acted = true
      ..lastAction = amount == 0
          ? 'Check'
          : s.chips == 0
          ? 'All in'
          : 'Call $amount';
    _settle(from: s.index);
  }

  /// Raises the street bet to [to] (clamped to what is legal).
  void raiseTo(Seat s, int to) {
    final range = raiseRange(s);
    if (range == null) {
      call(s);
      return;
    }
    to = to.clamp(range.min, range.max);
    final first = currentBet == 0;
    _pay(s, to - s.bet);
    if (to - currentBet >= minRaise) minRaise = to - currentBet;
    currentBet = to;
    _raises++;
    for (final o in seats) {
      if (o != s) o.acted = false;
    }
    s
      ..acted = true
      ..lastAction = s.chips == 0
          ? 'All in $to'
          : '${first ? 'Bet' : 'Raise'} $to';
    _settle(from: s.index);
  }

  /// After a move: someone wins, the round ends, or the next player is up.
  void _settle({required int from}) {
    final left = live;
    if (left.length == 1) {
      _award(reveal: false);
      return;
    }
    final waiting = seats.where(
      (s) => s.canAct && (!s.acted || s.bet < currentBet),
    );
    if (waiting.isEmpty) {
      awaitingStreet = true;
      return;
    }
    turn = _next(from, (s) => s.canAct && (!s.acted || s.bet < currentBet));
  }

  /// Deals the next street, or shows the hands after the river.
  void nextStreet() {
    if (!playing || !awaitingStreet) return;
    for (final s in seats) {
      s
        ..bet = 0
        ..acted = false;
      if (s.live && !s.allIn) s.lastAction = '';
    }
    currentBet = 0;
    minRaise = bigBlind;
    _raises = 0;
    switch (street) {
      case Street.preflop:
        street = Street.flop;
        board.addAll([for (var i = 0; i < 3; i++) _deck.removeLast()]);
      case Street.flop:
        street = Street.turn;
        board.add(_deck.removeLast());
      case Street.turn:
        street = Street.river;
        board.add(_deck.removeLast());
      case Street.river || Street.showdown:
        street = Street.showdown;
        _award(reveal: true);
        return;
    }
    // With at most one player able to bet, the board just runs out.
    if (seats.where((s) => s.canAct).length < 2) return;
    awaitingStreet = false;
    turn = _next(dealer, (s) => s.canAct);
  }

  /// Splits the pot, side pots included.
  void _award({required bool reveal}) {
    final contenders = live;
    final values = <Seat, HandValue>{
      if (reveal)
        for (final s in contenders) s: evaluate([...s.hole, ...board]),
    };
    final winnings = <Seat, int>{};
    final levels =
        seats.map((s) => s.total).where((t) => t > 0).toSet().toList()..sort();
    var prev = 0;
    for (final level in levels) {
      var amount = 0;
      for (final s in seats) {
        amount += min(s.total, level) - min(s.total, prev);
      }
      var eligible = contenders.where((s) => s.total >= level).toList();
      // Chips nobody left can claim go to those still in.
      if (eligible.isEmpty) eligible = contenders;
      List<Seat> winners;
      if (reveal) {
        final best = eligible.map((s) => values[s]!.strength).reduce(max);
        winners = eligible.where((s) => values[s]!.strength == best).toList();
      } else {
        winners = eligible;
      }
      final share = amount ~/ winners.length;
      for (final w in winners) {
        winnings[w] = (winnings[w] ?? 0) + share;
      }
      // An odd chip goes to the first winner left of the dealer.
      final odd = amount - share * winners.length;
      if (odd > 0) {
        final first = seats[_next(dealer, winners.contains)];
        winnings[first] = winnings[first]! + odd;
      }
      prev = level;
    }
    winnings.forEach((s, v) => s.chips += v);
    result = HandResult(winnings, reveal ? contenders : const [], values);
    playing = false;
    awaitingStreet = false;
  }

  /// Gives a computer player that has run out a fresh stack. Returns who
  /// was topped up.
  List<Seat> rebuyBots() {
    final out = <Seat>[];
    for (final s in seats) {
      if (s.bot && s.chips < bigBlind) {
        s.chips = buyIn;
        out.add(s);
      }
    }
    return out;
  }

  // ── The computer ──

  /// 0..1: how good [s]'s cards are right now.
  double quality(Seat s) {
    final a = s.hole[0], b = s.hole[1];
    final hi = max(a.rank, b.rank), lo = min(a.rank, b.rank);
    if (board.isEmpty) {
      if (hi == lo) return .55 + hi / 14 * .45;
      var q = (hi + lo) / 28 * .6;
      if (a.suit == b.suit) q += .08;
      if (hi - lo <= 2) q += .05;
      if (hi == 14) q += .08;
      return q.clamp(0.0, 1.0);
    }
    final v = evaluate([...s.hole, ...board]);
    final boardOnly = board.length >= 5 ? evaluate(board).rank : null;
    // A hand the board makes for everyone is worth little.
    if (boardOnly == v.rank && v.rank.index <= HandRank.twoPair.index) {
      return .2;
    }
    var q = switch (v.rank) {
      HandRank.highCard => hi >= 13 ? .22 : .12,
      HandRank.pair => () {
        final top = board.map((c) => c.rank).reduce(max);
        if (hi == lo) return hi > top ? .72 : .5;
        if (hi == top || lo == top) return .66;
        final paired = board.any((c) => c.rank == hi || c.rank == lo);
        return paired ? .45 : .25;
      }(),
      HandRank.twoPair => .8,
      HandRank.trips => .86,
      HandRank.straight => .9,
      HandRank.flush => .93,
      _ => .98,
    };
    // Four to a flush with cards still to come.
    if (board.length < 5 && v.rank.index < HandRank.flush.index) {
      for (var suit = 0; suit < 4; suit++) {
        final n = [...s.hole, ...board].where((c) => c.suit == suit).length;
        if (n == 4 && s.hole.any((c) => c.suit == suit)) q += .18;
      }
    }
    return q.clamp(0.0, 1.0);
  }

  /// Plays the current computer player's turn.
  void botTurn() {
    final s = current;
    final q = quality(s);
    final call_ = toCall(s);
    final p = pot;
    final range = raiseRange(s);
    final bluff = rng.nextDouble() < s.nerve * .1;
    final mayRaise = range != null && _raises < 3;

    void raise(double potShare) {
      final size = max(minRaise, (p * potShare).round());
      // Round to a tidy number of small blinds.
      var to = currentBet + size;
      to -= to % smallBlind;
      raiseTo(s, to);
    }

    if (board.isEmpty) {
      final blinds = call_ / bigBlind;
      if (q > .78 && mayRaise && rng.nextDouble() < .7 + s.nerve * .2) {
        raise(.9);
      } else if (q > .5 || (q > .36 && blinds <= 2) || blinds == 0) {
        if (call_ > 0 && blinds > 6 && q < .7 && !bluff) {
          fold(s);
        } else {
          call(s);
        }
      } else if (bluff && mayRaise && call_ <= bigBlind) {
        raise(.8);
      } else if (blinds <= 1 && rng.nextDouble() < .35 + s.nerve * .4) {
        call(s);
      } else {
        fold(s);
      }
      return;
    }
    final price = call_ / max(1, p);
    if (q > .82) {
      if (mayRaise && rng.nextDouble() < .65 + s.nerve * .25) {
        raise(.55 + rng.nextDouble() * .35);
      } else {
        call(s);
      }
    } else if (q > .58) {
      if (call_ == 0 && mayRaise && rng.nextDouble() < .45 + s.nerve * .3) {
        raise(.5);
      } else if (price <= .7) {
        call(s);
      } else {
        fold(s);
      }
    } else if (q > .3) {
      if (call_ == 0) {
        bluff && mayRaise ? raise(.5) : call(s);
      } else if (price <= .28) {
        call(s);
      } else {
        fold(s);
      }
    } else if (call_ == 0) {
      bluff && mayRaise ? raise(.6) : call(s);
    } else if (bluff && price < .2) {
      call(s);
    } else {
      fold(s);
    }
  }
}
