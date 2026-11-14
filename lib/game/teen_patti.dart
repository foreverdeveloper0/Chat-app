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

/// The six Teen Patti hands, weakest first.
enum HandRank {
  highCard('High Card'),
  pair('Pair'),
  colour('Colour'),
  sequence('Sequence'),
  pureSequence('Pure Sequence'),
  trail('Trail');

  const HandRank(this.label);
  final String label;
}

/// A three-card hand's kind and a number that orders it against any other
/// hand: the bigger [strength] wins.
({HandRank rank, int strength}) evaluate(List<PlayingCard> cards) {
  assert(cards.length == 3);
  final r = cards.map((c) => c.rank).toList()..sort((a, b) => b - a);
  final flush = cards.every((c) => c.suit == cards.first.suit);
  // A-K-Q is the best run and A-2-3 the second best; then K-Q-J down.
  int? run;
  if (r[0] == 14 && r[1] == 3 && r[2] == 2) {
    run = 13;
  } else if (r[0] - r[1] == 1 && r[1] - r[2] == 1) {
    run = r[0] == 14 ? 14 : r[0] - 1;
  }
  int pack(int a, int b, int c) => a * 225 + b * 15 + c;
  final HandRank rank;
  final int tie;
  if (r[0] == r[2]) {
    rank = HandRank.trail;
    tie = r[0];
  } else if (run != null) {
    rank = flush ? HandRank.pureSequence : HandRank.sequence;
    tie = run;
  } else if (flush) {
    rank = HandRank.colour;
    tie = pack(r[0], r[1], r[2]);
  } else if (r[0] == r[1] || r[1] == r[2]) {
    rank = HandRank.pair;
    final pair = r[1], kicker = r[0] == r[1] ? r[2] : r[0];
    tie = pack(pair, kicker, 0);
  } else {
    rank = HandRank.highCard;
    tie = pack(r[0], r[1], r[2]);
  }
  return (rank: rank, strength: rank.index * 4000 + tie);
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
  List<PlayingCard> cards = [];
  bool seen = false, packed = false, inHand = false;

  /// Chips put into the pot this hand.
  int staked = 0;

  /// Turns taken this hand, and how many of them blind.
  int turns = 0;

  /// What they last did, for the table to show ("Chaal 40").
  String lastAction = '';

  bool get active => inHand && !packed;
  ({HandRank rank, int strength}) get hand => evaluate(cards);
}

enum Move { pack, see, bet, raise, show, sideShow }

/// What a move did, for the table to animate.
class TableEvent {
  TableEvent(this.seat, this.move, {this.amount = 0, this.note = ''});
  final int seat;
  final Move move;
  final int amount;
  final String note;
}

/// How a hand ended.
class Showdown {
  Showdown(this.winner, this.pot, this.revealed, this.reason);
  final Seat winner;
  final int pot;

  /// Seats whose cards are turned over.
  final List<Seat> revealed;
  final String reason;
}

/// Teen Patti for two to five players: boot, blind and seen betting
/// (chaal), pack, side show and show.
class TeenPatti {
  TeenPatti({
    required this.boot,
    required int buyIn,
    int players = 5,
    String you = 'You',
    Random? random,
  }) : rng = random ?? Random(),
       buyIn = buyIn {
    const names = ['Riya', 'Arjun', 'Meera', 'Kabir'];
    const nerves = [.35, .7, .5, .85];
    seats.add(Seat(0, you, buyIn, bot: false));
    for (var i = 1; i < players.clamp(2, 5); i++) {
      seats.add(Seat(i, names[i - 1], buyIn, nerve: nerves[i - 1]));
    }
  }

  final Random rng;
  final int boot, buyIn;
  final seats = <Seat>[];
  Seat get you => seats.first;

  /// The most the pot may reach before everyone left must show.
  int get potLimit => boot * 1024;

  /// The most a blind bet may be.
  int get maxStake => boot * 64;

  int pot = 0;

  /// What a blind player pays to stay in; a seen player pays double.
  int stake = 0;
  int dealer = -1, turn = 0, hands = 0;
  bool playing = false;
  Showdown? result;

  /// A side show the person playing must answer: who asked.
  Seat? sideShowAsk;

  List<Seat> get active => seats.where((s) => s.active).toList();

  // ── Dealing ──

  /// Collects the boot and deals three cards each. Seats that cannot pay
  /// the boot sit out.
  void deal() {
    final deck = [
      for (var s = 0; s < 4; s++)
        for (var r = 2; r <= 14; r++) PlayingCard(r, s),
    ]..shuffle(rng);
    pot = 0;
    stake = boot;
    result = null;
    sideShowAsk = null;
    hands++;
    for (final s in seats) {
      s
        ..cards = []
        ..seen = false
        ..packed = false
        ..staked = 0
        ..turns = 0
        ..lastAction = ''
        ..inHand = s.chips >= boot;
      if (s.inHand) {
        _pay(s, boot);
        s.cards = [deck.removeLast(), deck.removeLast(), deck.removeLast()];
      }
    }
    dealer = _nextIn(dealer, (s) => s.inHand);
    turn = _nextIn(dealer, (s) => s.active);
    playing = active.length > 1;
  }

  int _nextIn(int from, bool Function(Seat) ok) {
    for (var k = 1; k <= seats.length; k++) {
      final i = ((from + k) % seats.length + seats.length) % seats.length;
      if (ok(seats[i])) return i;
    }
    return from < 0 ? 0 : from;
  }

  void _pay(Seat s, int amount) {
    final paid = min(amount, s.chips);
    s.chips -= paid;
    s.staked += paid;
    pot += paid;
  }

  // ── What the player to move may do ──

  Seat get current => seats[turn];

  /// The bet to stay in: the stake when blind, double when seen.
  int callFor(Seat s) => s.seen ? stake * 2 : stake;

  /// The bet to raise: double the call, capped.
  int raiseFor(Seat s) => callFor(s) * 2;
  bool canRaise(Seat s) =>
      stake * 2 <= maxStake && s.chips >= raiseFor(s) && active.length > 1;

  /// A show ends the hand between the last two players.
  bool canShow(Seat s) => active.length == 2;

  /// A seen player may ask the previous player, if also seen, to compare
  /// cards privately while more than two remain.
  Seat? sideShowTarget(Seat s) {
    if (!s.seen || active.length <= 2) return null;
    final prev = seats[_prevActive(s.index)];
    return prev.seen ? prev : null;
  }

  int _prevActive(int from) {
    for (var k = 1; k <= seats.length; k++) {
      final i = ((from - k) % seats.length + seats.length) % seats.length;
      if (seats[i].active) return i;
    }
    return from;
  }

  // ── Moves ──

  /// Looks at their own cards. Does not use up the turn.
  TableEvent see(Seat s) {
    s.seen = true;
    s.lastAction = 'Seen';
    return TableEvent(s.index, Move.see);
  }

  TableEvent pack(Seat s) {
    s.packed = true;
    s.lastAction = 'Packed';
    final ev = TableEvent(s.index, Move.pack);
    _afterMove(s);
    return ev;
  }

  /// Blind bet or chaal; with [raise], double it.
  TableEvent bet(Seat s, {bool raise = false}) {
    final amount = raise && canRaise(s) ? raiseFor(s) : callFor(s);
    if (s.chips < amount) return allIn(s);
    _pay(s, amount);
    stake = s.seen ? amount ~/ 2 : amount;
    s.turns++;
    s.lastAction = '${s.seen ? 'Chaal' : 'Blind'} $amount';
    final ev = TableEvent(
      s.index,
      raise ? Move.raise : Move.bet,
      amount: amount,
    );
    _afterMove(s);
    return ev;
  }

  /// Cannot cover the bet: put in what is left and turn everyone's cards.
  TableEvent allIn(Seat s) {
    final amount = s.chips;
    _pay(s, amount);
    s.lastAction = 'All in $amount';
    final ev = TableEvent(s.index, Move.show, amount: amount, note: 'All in');
    _showdown(active, '${s.name} is all in');
    return ev;
  }

  /// Pays for a show against the one other player left. The asker loses a
  /// tie.
  TableEvent show(Seat s) {
    final amount = min(callFor(s), s.chips);
    _pay(s, amount);
    s.lastAction = 'Show $amount';
    final ev = TableEvent(s.index, Move.show, amount: amount);
    _showdown(active, '${s.name} asked for a show', asker: s);
    return ev;
  }

  /// Pays the chaal and asks the previous player for a side show. A
  /// computer player answers at once; the person playing is asked through
  /// [sideShowAsk].
  TableEvent sideShow(Seat s) {
    final target = sideShowTarget(s)!;
    final amount = callFor(s);
    if (s.chips < amount) return allIn(s);
    _pay(s, amount);
    stake = amount ~/ 2;
    s.turns++;
    s.lastAction = 'Side show';
    final ev = TableEvent(
      s.index,
      Move.sideShow,
      amount: amount,
      note: target.name,
    );
    if (!target.bot) {
      sideShowAsk = s;
      return ev;
    }
    // A computer player agrees when it likes its cards.
    final accept = target.hand.strength > 4000 || rng.nextDouble() < .35;
    answerSideShow(accept, asker: s, target: target);
    return ev;
  }

  /// The answer to a side show. If accepted the weaker hand packs (the
  /// asker on a tie). Returns who packed, if anyone.
  Seat? answerSideShow(bool accept, {Seat? asker, Seat? target}) {
    asker ??= sideShowAsk!;
    target ??= you;
    sideShowAsk = null;
    Seat? out;
    if (accept) {
      out = asker.hand.strength > target.hand.strength ? target : asker;
      out
        ..packed = true
        ..lastAction = 'Lost side show';
    } else {
      target.lastAction = 'Refused';
    }
    _afterMove(asker);
    return out;
  }

  void _afterMove(Seat s) {
    if (result != null) return;
    final left = active;
    if (left.length == 1) {
      _finish(left.first, const [], 'Everyone else packed');
      return;
    }
    if (pot >= potLimit) {
      _showdown(left, 'Pot limit reached');
      return;
    }
    turn = _nextIn(s.index, (x) => x.active);
  }

  void _showdown(List<Seat> among, String reason, {Seat? asker}) {
    var best = among.first;
    for (final s in among.skip(1)) {
      final a = s.hand.strength, b = best.hand.strength;
      // On a tie the one who asked for the show loses.
      if (a > b || (a == b && best == asker)) best = s;
    }
    _finish(best, among, reason);
  }

  void _finish(Seat winner, List<Seat> revealed, String reason) {
    result = Showdown(winner, pot, revealed, reason);
    winner.chips += pot;
    playing = false;
  }

  /// Gives a computer player that has run out a fresh stack, so the table
  /// stays full. Returns who was topped up.
  List<Seat> rebuyBots() {
    final out = <Seat>[];
    for (final s in seats) {
      if (s.bot && s.chips < boot * 4) {
        s.chips = buyIn;
        out.add(s);
      }
    }
    return out;
  }

  // ── The computer ──

  /// Plays the current computer player's turn.
  List<TableEvent> botTurn() {
    final s = current;
    final events = <TableEvent>[];
    // Play blind for a turn or three, the bolder the longer.
    if (!s.seen) {
      final blindTurns = 1 + (s.nerve * 3).round();
      if (s.turns >= blindTurns || rng.nextDouble() < .15) {
        events.add(see(s));
      } else {
        events.add(bet(s, raise: rng.nextDouble() < s.nerve * .25));
        return events;
      }
    }
    final h = s.hand;
    // 0..1: how good the hand is among all hands, roughly.
    final quality = switch (h.rank) {
      HandRank.trail => 1.0,
      HandRank.pureSequence => .97,
      HandRank.sequence => .9,
      HandRank.colour => .8,
      HandRank.pair => .5 + (h.strength % 4000) / 3375 * .2,
      HandRank.highCard => (h.strength % 4000) / 3375 * .42,
    };
    final bluff = rng.nextDouble() < s.nerve * .12;
    final pressure = (callFor(s) / max(1, s.chips)).clamp(0.0, 1.0);
    final left = active.length;

    if (s.chips < callFor(s)) {
      events.add(quality > .35 || bluff ? allIn(s) : pack(s));
      return events;
    }
    // Weak cards: fold more readily the dearer it gets.
    final floor = .2 + pressure * .5 + s.turns * .025 - s.nerve * .08;
    if (quality < floor && !bluff) {
      // With two left, a cheap show beats folding a middling hand.
      if (left == 2 && quality > .3 && pressure < .2) {
        events.add(show(s));
      } else {
        events.add(pack(s));
      }
      return events;
    }
    if (left == 2) {
      // Strong hands keep building the pot for a while, then show.
      final patience = quality > .78 ? 3 + (s.nerve * 3).round() : 1;
      if (s.turns >= patience || pot > potLimit ~/ 3) {
        events.add(show(s));
        return events;
      }
    } else {
      final target = sideShowTarget(s);
      if (target != null &&
          target.bot &&
          quality > .45 &&
          quality < .85 &&
          rng.nextDouble() < .3) {
        events.add(sideShow(s));
        return events;
      }
    }
    final raise =
        canRaise(s) &&
        (quality > .75 ? rng.nextDouble() < .55 + s.nerve * .3 : bluff);
    events.add(bet(s, raise: raise));
    return events;
  }
}
