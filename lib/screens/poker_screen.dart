import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/coins.dart';
import '../game/holdem.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../widgets/game_hud.dart';

/// Play chips for the card table. They last while the app is open.
abstract final class PokerWallet {
  static int chips = 50000;
  static const freeChips = 10000;
}

/// Texas Hold'em at a table of two to five: you and computer players.
/// The table is laid out sideways, so the phone is turned to landscape
/// while this screen is open.
class PokerScreen extends StatefulWidget {
  const PokerScreen({
    super.key,
    required this.smallBlind,
    required this.buyIn,
    this.players = 5,
  });

  final int smallBlind, buyIn, players;

  @visibleForTesting
  static Holdem? debugGame;

  @override
  State<PokerScreen> createState() => _PokerScreenState();
}

/// The supplied table picture is 1807 x 870; everything is placed in its
/// coordinates. Seat centres: you at the bottom, then clockwise.
const _art = Size(1807, 870);
const _seatSpots = [
  Offset(897, 713),
  Offset(254, 585),
  Offset(301, 253),
  Offset(1491, 253),
  Offset(1537, 585),
];

/// From a seat's centre to the picture's label under it and to its "+".
const _labelOffset = Offset(9, 88), _badgeOffset = Offset(97, 24);

/// Which of the picture's seats a table of [n] uses, by seat index.
List<int> _seating(int n) => switch (n) {
  2 => const [0, 3],
  3 => const [0, 2, 3],
  4 => const [0, 1, 2, 3],
  _ => const [0, 1, 2, 3, 4],
};

class _PokerScreenState extends State<PokerScreen>
    with SingleTickerProviderStateMixin {
  late Holdem _game;
  final _timers = <Timer>[];
  final _chips = <_FlyingChip>[];
  int _chipId = 0;

  /// Maps the picture's coordinates onto the screen.
  double _k = 1;
  Offset _origin = Offset.zero;

  bool _dealing = false, _left = false;

  /// The street bet your RAISE button would make.
  int _raiseTo = 0;

  /// The raise panel is open.
  bool _raising = false;

  /// Counts down the turn of whoever is to act; yours ends in a check or
  /// a fold.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 20))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _myTurn) {
            _act(
              (you) =>
                  _game.toCall(you) == 0 ? _game.call(you) : _game.fold(you),
            );
          }
        });

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    PokerWallet.chips -= widget.buyIn;
    _game = Holdem(
      smallBlind: widget.smallBlind,
      buyIn: widget.buyIn,
      players: widget.players,
    );
    PokerScreen.debugGame = _game;
    _later(700, _deal);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _clock.dispose();
    _cashOut();
    // Back to the app's upright layout.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Chips left on the table go back to the wallet, once.
  void _cashOut() {
    if (_left) return;
    _left = true;
    PokerWallet.chips += _game.you.chips;
  }

  void _later(int ms, VoidCallback f) {
    late Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (mounted) f();
    });
    _timers.add(t);
  }

  // ── Flow ──

  void _deal() {
    final g = _game;
    if (g.you.chips < g.bigBlind) {
      _outOfChips();
      return;
    }
    g.rebuyBots();
    setState(() {
      g.deal();
      _dealing = true;
    });
    Sounds.play(Sfx.diceRoll);
    _fly(g.smallBlindSeat, toPot: true);
    _fly(g.bigBlindSeat, toPot: true);
    _later(1200, () {
      setState(() => _dealing = false);
      _advance();
    });
  }

  /// Moves the hand on: the result, the next street, a computer player's
  /// turn, or yours.
  void _advance() {
    final g = _game;
    if (!g.playing) {
      _clock.stop();
      _finish();
      return;
    }
    if (g.awaitingStreet) {
      _clock.stop();
      _later(650, () {
        setState(g.nextStreet);
        if (g.playing) Sounds.play(Sfx.diceLand);
        _later(450, _advance);
      });
      return;
    }
    final s = g.current;
    _clock.forward(from: 0);
    if (!s.bot) {
      setState(() {
        _raiseTo = g.raiseRange(s)?.min ?? 0;
        _raising = false;
      });
      HapticFeedback.selectionClick();
      Sounds.play(Sfx.turn);
      return;
    }
    _later(800 + math.Random().nextInt(700), () {
      final before = s.total;
      g.botTurn();
      setState(() {});
      _react(s, s.total - before);
      _later(350, _advance);
    });
  }

  /// Sound and chips for a move.
  void _react(Seat s, int paid) {
    if (paid > 0) {
      _fly(s.index, toPot: true);
      Sounds.play(Sfx.pocket);
    } else {
      Sounds.play(Sfx.tap);
    }
  }

  void _finish() {
    final r = _game.result!;
    setState(() {});
    final won = r.winnings.containsKey(_game.you);
    _later(600, () {
      for (final w in r.winnings.keys) {
        for (var i = 0; i < 5; i++) {
          _later(i * 70, () => _fly(w.index, toPot: false));
        }
      }
      Sounds.play(won ? Sfx.win : Sfx.rank);
      if (won) HapticFeedback.heavyImpact();
    });
    _later(r.revealed.isEmpty ? 2600 : 4600, _deal);
  }

  bool get _myTurn {
    final g = _game;
    return g.playing && !_dealing && !g.awaitingStreet && g.turn == 0;
  }

  void _act(void Function(Seat you) move) {
    if (!_myTurn) return;
    final you = _game.you, before = you.total;
    move(you);
    _clock.stop();
    setState(() => _raising = false);
    _react(you, you.total - before);
    _later(350, _advance);
  }

  Future<void> _outOfChips() async {
    final stay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => _Dialog(
        title: 'Out of chips',
        body:
            'You need at least ${formatCoins(_game.bigBlind)} for the big '
            'blind. Take ${formatCoins(PokerWallet.freeChips)} free chips '
            'and keep playing?',
        actions: [
          ('LEAVE', const Color(0xFF2A3A9A), () => Navigator.pop(d, false)),
          ('FREE CHIPS', const Color(0xFF1FA35C), () => Navigator.pop(d, true)),
        ],
      ),
    );
    if (!mounted) return;
    if (stay ?? false) {
      setState(() => _game.you.chips += PokerWallet.freeChips);
      _later(400, _deal);
    } else {
      Navigator.of(context).pop();
    }
  }

  // ── Layout ──

  /// A point of the table picture, on the screen.
  Offset _at(double x, double y) => _origin + Offset(x, y) * _k;
  Offset _spot(int seat) {
    final p = _seatSpots[_seating(_game.seats.length)[seat]];
    return _at(p.dx, p.dy);
  }

  /// Which way the middle of the table is from a seat: 1 right, -1 left.
  double _inward(int seat) =>
      _seatSpots[_seating(_game.seats.length)[seat]].dx < _art.width / 2
      ? 1
      : -1;

  Offset get _potAt => _at(903, 345);
  Offset get _dealerAt => _at(903, 250);

  void _fly(int seat, {required bool toPot}) {
    if (!mounted) return;
    final at = _spot(seat);
    setState(() {
      _chips.add(
        _FlyingChip(_chipId++, toPot ? at : _potAt, toPot ? _potAt : at),
      );
    });
  }

  Widget _place(Offset centre, Widget child, {double? width}) => Positioned(
    left: centre.dx - (width ?? 400) / 2,
    top: centre.dy,
    width: width ?? 400,
    child: FractionalTranslation(
      translation: const Offset(0, -.5),
      child: Center(child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C0838),
      body: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          // The picture is shown whole, centred.
          _k = math.min(size.width / _art.width, size.height / _art.height);
          _origin = Offset(
            (size.width - _art.width * _k) / 2,
            (size.height - _art.height * _k) / 2,
          );
          final g = _game;
          final used = _seating(g.seats.length);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Fill the edges with the picture's own purple.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.2,
                    colors: [Color(0xFF5A1A96), Color(0xFF1C0838)],
                  ),
                ),
              ),
              Positioned(
                left: _origin.dx,
                top: _origin.dy,
                width: _art.width * _k,
                height: _art.height * _k,
                child: Image.asset(
                  'assets/images/poker/table.jpg',
                  fit: BoxFit.fill,
                ),
              ),
              // Seats nobody sits at keep the picture's empty chair.
              for (var i = 0; i < 5; i++)
                if (!used.contains(i)) _emptySeat(_seatSpots[i]),
              ..._board(g),
              _potLabel(g),
              for (final s in g.seats) ..._seat(s),
              ..._yourCards(g),
              for (final s in g.seats) ..._seatFront(s),
              for (final c in _chips)
                TweenAnimationBuilder<double>(
                  key: ValueKey(c.id),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 480),
                  curve: Curves.easeOutCubic,
                  onEnd: () => setState(() => _chips.remove(c)),
                  builder: (context, t, child) {
                    final p = Offset.lerp(c.from, c.to, t)!;
                    return Positioned(
                      left: p.dx - 9,
                      top: p.dy - 9 - math.sin(t * math.pi) * 20,
                      child: child!,
                    );
                  },
                  child: const _Chip(size: 18),
                ),
              if (g.result != null) _resultBanner(g.result!),
              _topBar(g),
              _actions(g),
            ],
          );
        },
      ),
    );
  }

  /// Covers the picture's "Invite" label on a seat that is not in use.
  Widget _emptySeat(Offset spot) => _place(
    _at(spot.dx + _labelOffset.dx, spot.dy + _labelOffset.dy),
    Container(
      width: 236 * _k,
      height: 66 * _k,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF2A0F45),
        borderRadius: BorderRadius.circular(33 * _k),
        border: Border.all(color: AppColors.goldTrim, width: 1.2),
      ),
      child: Text('Empty', style: _text(30 * _k, const Color(0x99FFFFFF))),
    ),
  );

  Widget _topBar(Holdem g) => Positioned(
    left: 10,
    right: 10,
    top: 8,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RoundButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        _pill(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Chip(size: 16),
              const SizedBox(width: 6),
              Text(
                formatCoins(g.you.chips),
                key: const ValueKey('my-chips'),
                style: _text(13),
              ),
            ],
          ),
        ),
        const Spacer(),
        _pill(
          Text(
            'BLINDS ${formatCoins(g.smallBlind)}/${formatCoins(g.bigBlind)}',
            style: _text(12),
          ),
        ),
      ],
    ),
  );

  Widget _potLabel(Holdem g) => _place(
    _potAt,
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xBB06240F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.goldTrim, width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Chip(size: 14),
          const SizedBox(width: 6),
          Text(
            'POT  ${formatCoins(g.pot)}',
            key: const ValueKey('pot'),
            style: _text(13, const Color(0xFFFFE28A)),
          ),
        ],
      ),
    ),
  );

  /// The five community cards, on the picture's dashed places.
  List<Widget> _board(Holdem g) {
    const xs = [598.0, 750.0, 903.0, 1058.0, 1215.0];
    final cw = 118 * _k;
    return [
      for (var i = 0; i < g.board.length; i++)
        _dealt(
          key: 'b-${g.hands}-$i',
          order: i < 3 ? i : 0,
          to: _at(xs[i], 463) - Offset(cw / 2, cw * .7),
          child: _CardView(card: g.board[i], faceUp: true, width: cw),
        ),
    ];
  }

  /// A seat: avatar over the picture's silhouette, name and chips over its
  /// label, the bet, and (for the computer players) their two cards.
  static const _colours = [
    Color(0xFF4FB8FF),
    Color(0xFFFF6FA3),
    Color(0xFF45E0A8),
    Color(0xFFFFA94D),
    Color(0xFFB58CFF),
  ];

  /// The back of a seat: the avatar on the picture's ring, the turn
  /// timer, and a computer player's two cards tucked behind its corner.
  List<Widget> _seat(Seat s) {
    final g = _game;
    final at = _spot(s.index);
    final turn = _myTurnOf(s);
    final r = g.result;
    final winner = r?.winnings.containsKey(s) ?? false;
    final inward = _inward(s.index);
    final radius = 92 * _k;
    final reveal = r?.revealed.contains(s) ?? false;
    final dim = s.folded || !s.inHand;
    final cardW = (reveal ? 84 : 62) * _k;
    // Hidden cards peek out from the avatar's upper inner corner; shown
    // cards are laid towards the middle of the table.
    final cardsAt = reveal
        ? at + Offset(inward * 215 * _k, -8 * _k)
        : at + Offset(inward * 108 * _k, -52 * _k);
    return [
      if (s.bot && s.inHand)
        for (var i = 0; i < s.hole.length; i++)
          _dealt(
            key: 'c-${g.hands}-${s.index}-$i',
            order: s.index * 2 + i,
            to:
                cardsAt +
                Offset(
                  (i - .5) * cardW * (reveal ? 1.04 : .55) - cardW / 2,
                  -cardW * .7,
                ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: s.folded ? 0 : 1,
              child: Transform.rotate(
                angle: reveal ? 0 : inward * .28 + (i - .5) * .3,
                child: _CardView(card: s.hole[i], faceUp: reveal, width: cardW),
              ),
            ),
          ),
      _place(
        at,
        SizedBox(
          width: radius * 2 + 14,
          height: radius * 2 + 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (winner)
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xEEFFD45A),
                        blurRadius: 18,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: CustomPaint(
                  painter: _AvatarPainter(
                    _colours[s.index],
                    s.name.characters.first,
                    dim: dim,
                  ),
                ),
              ),
              // The turn timer runs round the ring.
              if (turn)
                AnimatedBuilder(
                  animation: _clock,
                  builder: (context, _) => CustomPaint(
                    size: Size.square(radius * 2 + 12),
                    painter: _TimerPainter(1 - _clock.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  /// The front of a seat, drawn over the cards: name and chips on the
  /// picture's label, the dealer or blind button, the last action and the
  /// chips bet.
  List<Widget> _seatFront(Seat s) {
    final g = _game;
    final at = _spot(s.index);
    final turn = _myTurnOf(s);
    final r = g.result;
    final inward = _inward(s.index);
    final reveal = r?.revealed.contains(s) ?? false;
    final badge = g.dealer == s.index
        ? 'D'
        : g.playing && g.smallBlindSeat == s.index
        ? 'SB'
        : g.playing && g.bigBlindSeat == s.index
        ? 'BB'
        : '';
    final betAt = s.index == 0
        ? at + Offset(0, -150 * _k)
        : at + Offset(inward * 215 * _k, 70 * _k);
    final won = r?.winnings[s];
    return [
      _place(
        at + _labelOffset * _k,
        Container(
          width: 238 * _k,
          height: 68 * _k,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF4A1A6E), Color(0xFF1E0A35)],
            ),
            borderRadius: BorderRadius.circular(34 * _k),
            border: Border.all(
              color: turn ? const Color(0xFFFFF1B8) : const Color(0xFFE3B341),
              width: turn ? 2 : 1.4,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x88000000), blurRadius: 4),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(shortName(s.name, 7), style: _text(29 * _k)),
                SizedBox(width: 12 * _k),
                _Chip(size: 26 * _k),
                SizedBox(width: 6 * _k),
                Text(
                  formatCoins(s.chips),
                  style: _text(29 * _k, const Color(0xFFFFE28A)),
                ),
              ],
            ),
          ),
        ),
      ),
      // Dealer or blind button, over the picture's "+".
      _place(
        at + _badgeOffset * _k,
        Container(
          width: 64 * _k,
          height: 64 * _k,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-.3, -.4),
              colors: badge == 'D'
                  ? const [Colors.white, Color(0xFFCFCFE0)]
                  : badge.isEmpty
                  ? const [Color(0xFF5A2A86), Color(0xFF2A0F45)]
                  : const [Color(0xFF4F7BFF), Color(0xFF1B2A9A)],
            ),
            border: Border.all(color: const Color(0xFFFFE28A), width: 1.6),
          ),
          child: badge.isEmpty
              ? _Chip(size: 32 * _k)
              : Text(
                  badge,
                  style: _text(
                    26 * _k,
                    badge == 'D' ? const Color(0xFF1C0838) : Colors.white,
                  ),
                ),
        ),
        width: 80,
      ),
      // What they last did.
      if (s.lastAction.isNotEmpty && s.inHand && won == null)
        _place(
          at + Offset(0, -118 * _k),
          Container(
            key: ValueKey('action-${s.index}'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: s.folded
                  ? const Color(0xEE5A1A1A)
                  : const Color(0xEE0E1440),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0x66FFFFFF), width: .8),
            ),
            child: Text(s.lastAction, style: _text(10)),
          ),
          width: 140,
        ),
      if (won != null)
        _place(
          at + Offset(0, -118 * _k),
          Text(
            '+${formatCoins(won)}',
            style: _text(15, const Color(0xFFFFE28A)).copyWith(
              shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
          width: 140,
        ),
      // Chips bet on this street.
      if (s.bet > 0 && g.playing)
        _place(
          betAt,
          Container(
            padding: const EdgeInsets.fromLTRB(3, 2, 8, 2),
            decoration: BoxDecoration(
              color: const Color(0xAA06240F),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Chip(size: 14),
                const SizedBox(width: 4),
                Text(formatCoins(s.bet), style: _text(11)),
              ],
            ),
          ),
          width: 120,
        ),
      if (reveal && s.bot)
        _place(
          at + Offset(inward * 215 * _k, 62 * _k),
          _handTag(r!.values[s]!.rank.label),
          width: 160,
        ),
    ];
  }

  bool _myTurnOf(Seat s) {
    final g = _game;
    return g.playing && !_dealing && !g.awaitingStreet && g.turn == s.index;
  }

  Widget _handTag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xEE0E1440),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.goldTrim),
    ),
    child: Text(label, style: _text(10, const Color(0xFFFFE28A))),
  );

  /// Your two cards, face up and fanned over the lower half of your
  /// avatar; your name and chips sit in front of them.
  List<Widget> _yourCards(Holdem g) {
    final you = g.you;
    if (!you.inHand || you.hole.isEmpty) return const [];
    final cw = 134 * _k;
    final at = _spot(0) + Offset(0, 56 * _k);
    final made = g.board.length >= 3 && !you.folded
        ? evaluate([...you.hole, ...g.board]).rank.label
        : null;
    return [
      for (var i = 0; i < 2; i++)
        _dealt(
          key: 'c-${g.hands}-0-$i',
          order: i,
          to: at + Offset((i - .5) * cw * .78 - cw / 2, -cw * .7),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: you.folded ? .35 : 1,
            child: Transform.rotate(
              angle: (i - .5) * .22,
              child: _CardView(card: you.hole[i], faceUp: true, width: cw),
            ),
          ),
        ),
      if (made != null)
        _place(
          _spot(0) + Offset(-185 * _k, -60 * _k),
          _handTag(made),
          width: 160,
        ),
    ];
  }

  /// A card that flies in from the dealer.
  Widget _dealt({
    required String key,
    required int order,
    required Offset to,
    required Widget child,
  }) {
    final start = (order * .07).clamp(0.0, .7);
    return TweenAnimationBuilder<double>(
      key: ValueKey(key),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Interval(start, math.min(1, start + .3), curve: Curves.easeOut),
      builder: (context, t, c) {
        final p = Offset.lerp(_dealerAt, to, t)!;
        return Positioned(
          left: p.dx,
          top: p.dy,
          child: Opacity(opacity: t == 0 ? 0 : 1, child: c),
        );
      },
      child: child,
    );
  }

  Widget _resultBanner(HandResult r) {
    final g = _game;
    final won = r.winnings.containsKey(g.you);
    final w = r.winner;
    final split = r.winnings.length > 1;
    final hand = r.values[w]?.rank.label;
    return _place(
      _at(903, 300),
      TweenAnimationBuilder<double>(
        key: ValueKey('result-${g.hands}'),
        tween: Tween(begin: .6, end: 1),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutBack,
        builder: (context, s, c) => Transform.scale(scale: s, child: c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: won
                  ? const [Color(0xFF1FA35C), Color(0xFF0E6B3A)]
                  : const [Color(0xFF3A2AA0), Color(0xFF1B1460)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFE28A), width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), blurRadius: 10),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                split
                    ? 'Split pot'
                    : won
                    ? 'YOU WIN  +${formatCoins(r.winnings[w]!)}'
                    : '${w.name} wins  +${formatCoins(r.winnings[w]!)}',
                key: const ValueKey('result'),
                style: _text(15, const Color(0xFFFFE28A)),
              ),
              Text(
                hand ?? 'Everyone else folded',
                style: _text(10.5, Colors.white, FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// On your turn: FOLD on the left, CHECK / CALL and RAISE on the
  /// right. RAISE opens a panel to choose the amount.
  Widget _actions(Holdem g) {
    final you = g.you;
    final mine = _myTurn;
    final call = g.toCall(you);
    final range = mine ? g.raiseRange(you) : null;
    final String status;
    if (!g.playing) {
      status = g.result == null ? 'Dealing…' : 'Next hand coming up…';
    } else if (_dealing) {
      status = 'Dealing…';
    } else if (you.folded) {
      status = 'You folded';
    } else if (!you.inHand) {
      status = 'Sitting out';
    } else if (mine) {
      status = 'Your turn';
    } else if (g.awaitingStreet) {
      status = '';
    } else {
      status = "${g.current.name}'s turn…";
    }
    return Stack(
      children: [
        // Status, top centre-left, clear of the buttons.
        Positioned(
          left: 215,
          top: 14,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: status.isEmpty ? 0 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: mine ? const Color(0xEE1FA35C) : const Color(0xCC14052B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                status,
                key: const ValueKey('status'),
                style: _text(12, Colors.white, FontWeight.w600),
              ),
            ),
          ),
        ),
        if (mine) ...[
          // Hugging your seat: FOLD just left of it, the rest just right.
          Positioned(
            left: _mySide(-1) - _btnWidth,
            bottom: 10,
            child: _btn('FOLD', const Color(0xFFC0392B), true, () {
              _act(g.fold);
            }),
          ),
          Positioned(
            left: _mySide(1),
            bottom: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _btn(
                  call == 0
                      ? 'CHECK'
                      : call >= you.chips
                      ? 'ALL IN ${formatCoins(call)}'
                      : 'CALL ${formatCoins(call)}',
                  const Color(0xFF1FA35C),
                  true,
                  () => _act(g.call),
                ),
                if (range != null) ...[
                  const SizedBox(width: 8),
                  _btn(
                    g.currentBet == 0 ? 'BET' : 'RAISE',
                    const Color(0xFFD4A017),
                    true,
                    () => setState(() => _raising = !_raising),
                    icon: _raising
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                  ),
                ],
              ],
            ),
          ),
          if (_raising && range != null) _raisePanel(g, range),
        ],
      ],
    );
  }

  static const _btnWidth = 104.0;

  /// The screen x just beside your seat's label: [side] -1 left, 1 right.
  double _mySide(int side) =>
      _spot(0).dx + _labelOffset.dx * _k + side * (125 * _k + 14);

  /// Choose how much to raise to: a slider, quick amounts and a confirm.
  Widget _raisePanel(Holdem g, ({int min, int max}) range) {
    final to = _raiseTo.clamp(range.min, range.max);
    void set(num v) =>
        setState(() => _raiseTo = v.round().clamp(range.min, range.max));
    final step = g.bigBlind;
    final allIn = to >= range.max;
    return Positioned(
      left: _mySide(1),
      bottom: 64,
      child: Container(
        key: const ValueKey('raise-panel'),
        width: 300,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF24A1A7A), Color(0xF21A0832)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE3B341), width: 1.6),
          boxShadow: const [
            BoxShadow(color: Color(0xAA000000), blurRadius: 14),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _Chip(size: 20),
                const SizedBox(width: 8),
                Text(
                  formatCoins(to),
                  key: const ValueKey('raise-to'),
                  style: _text(24, const Color(0xFFFFE28A)),
                ),
                if (allIn) ...[
                  const SizedBox(width: 8),
                  Text('ALL IN', style: _text(12, const Color(0xFFFF8A8A))),
                ],
              ],
            ),
            Row(
              children: [
                _mini('−', () => set(to - step)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      activeTrackColor: const Color(0xFFFFD45A),
                      inactiveTrackColor: const Color(0x55FFFFFF),
                      thumbColor: const Color(0xFFFFF1B8),
                      overlayColor: const Color(0x33FFD45A),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 10,
                      ),
                    ),
                    child: Slider(
                      min: range.min.toDouble(),
                      max: math.max(range.max, range.min + 1).toDouble(),
                      value: to.toDouble(),
                      onChanged: (v) {
                        // Snap to whole big blinds, except at the ends.
                        final snapped = v >= range.max
                            ? range.max
                            : range.min +
                                  ((v - range.min) / step).round() * step;
                        set(snapped);
                      },
                    ),
                  ),
                ),
                _mini('+', () => set(to + step)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _mini('MIN', () => set(range.min), wide: true),
                _mini(
                  '½ POT',
                  () => set(g.currentBet + g.pot ~/ 2),
                  wide: true,
                ),
                _mini('POT', () => set(g.currentBet + g.pot), wide: true),
                _mini('ALL IN', () => set(range.max), wide: true),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              key: const ValueKey('raise-confirm'),
              onTap: () => _act((you) => g.raiseTo(you, to)),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFD45A),
                      Color(0xFFD4A017),
                      Color(0xFF9A6A00),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFFF1B8),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  allIn
                      ? 'ALL IN ${formatCoins(to)}'
                      : '${g.currentBet == 0 ? 'BET' : 'RAISE TO'} '
                            '${formatCoins(to)}',
                  style: _text(15, const Color(0xFF2A1400)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String label, VoidCallback onTap, {bool wide = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: wide ? 62 : 32,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xEE3A1A60),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.goldTrim),
          ),
          child: Text(label, style: _text(wide ? 11 : 17)),
        ),
      );

  Widget _btn(
    String label,
    Color colour,
    bool enabled,
    VoidCallback onTap, {
    IconData? icon,
  }) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: _btnWidth,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(colour, Colors.white, .25)!,
            colour,
            Color.lerp(colour, Colors.black, .32)!,
          ],
        ),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFFFE28A), width: 1.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: _text(14.5)),
              if (icon != null) Icon(icon, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _pill(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xDD2A0F45),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: AppColors.goldTrim, width: 1.4),
    ),
    child: child,
  );
}

TextStyle _text(
  double size, [
  Color colour = Colors.white,
  FontWeight weight = FontWeight.w700,
]) => TextStyle(
  fontFamily: AppText.family,
  fontWeight: weight,
  fontSize: size,
  height: 1.15,
  color: colour,
);

class _FlyingChip {
  _FlyingChip(this.id, this.from, this.to);
  final int id;
  final Offset from, to;
}

/// A gold casino chip.
class _Chip extends StatelessWidget {
  const _Chip({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-.3, -.4),
        colors: [Color(0xFFFFF1B8), Color(0xFFE3B341), Color(0xFF9A6A00)],
      ),
      border: Border.all(color: const Color(0xFFFFF7D6), width: size * .09),
      boxShadow: const [
        BoxShadow(
          color: Color(0x88000000),
          blurRadius: 3,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Center(
      child: Container(
        width: size * .45,
        height: size * .45,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF9A6A00), width: 1),
        ),
      ),
    ),
  );
}

/// A playing card, face up or showing its back, flipping between the two.
class _CardView extends StatelessWidget {
  const _CardView({
    required this.card,
    required this.faceUp,
    required this.width,
  });
  final PlayingCard card;
  final bool faceUp;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, a) => AnimatedBuilder(
        animation: a,
        builder: (context, c) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scaleByDouble(a.value, 1, 1, 1),
          child: c,
        ),
        child: child,
      ),
      child: SizedBox(
        key: ValueKey(faceUp),
        width: width,
        height: width * 1.4,
        child: CustomPaint(painter: _CardPainter(faceUp ? card : null)),
      ),
    );
  }
}

class _CardPainter extends CustomPainter {
  const _CardPainter(this.card);

  /// Null paints the back.
  final PlayingCard? card;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(w * .12),
    );
    canvas.drawRRect(
      rr.shift(const Offset(0, 1.5)),
      Paint()..color = const Color(0x66000000),
    );
    final c = card;
    if (c == null) {
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB3202E), Color(0xFF6E0F1A)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawRRect(
        rr.deflate(w * .08),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .035
          ..color = const Color(0xFFFFE28A),
      );
      // A diamond lattice.
      canvas.save();
      canvas.clipRRect(rr.deflate(w * .12));
      final line = Paint()
        ..color = const Color(0x55FFE28A)
        ..strokeWidth = 1;
      final step = w * .22;
      for (var x = -h; x < w + h; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x + h, h), line);
        canvas.drawLine(Offset(x, h), Offset(x + h, 0), line);
      }
      canvas.restore();
      return;
    }
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFEDE8F5)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFB9A8D6),
    );
    final ink = c.red ? const Color(0xFFD81E2C) : const Color(0xFF15131E);
    final tp = TextPainter(
      text: TextSpan(
        text: c.label,
        style: TextStyle(
          fontFamily: AppText.family,
          fontWeight: FontWeight.w700,
          fontSize: w * (c.rank == 10 ? .36 : .42),
          height: 1,
          color: ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w * .1, h * .06));
    _suit(canvas, c.suit, Offset(w * .26, h * .48), w * .2, ink);
    _suit(canvas, c.suit, Offset(w * .62, h * .68), w * .5, ink);
  }

  /// A suit symbol centred on [at], [s] wide.
  static void _suit(Canvas canvas, int suit, Offset at, double s, Color ink) {
    final p = Paint()..color = ink;
    final r = s / 2;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    Path heart() => Path()
      ..moveTo(0, r * .9)
      ..cubicTo(-r * 1.6, -r * .2, -r * .7, -r * 1.3, 0, -r * .45)
      ..cubicTo(r * .7, -r * 1.3, r * 1.6, -r * .2, 0, r * .9)
      ..close();
    void stem() => canvas.drawPath(
      Path()
        ..moveTo(0, r * .1)
        ..lineTo(r * .32, r)
        ..lineTo(-r * .32, r)
        ..close(),
      p,
    );
    switch (suit) {
      case 1:
        canvas.drawPath(heart(), p);
      case 2:
        canvas.drawPath(
          Path()
            ..moveTo(0, -r)
            ..lineTo(r * .75, 0)
            ..lineTo(0, r)
            ..lineTo(-r * .75, 0)
            ..close(),
          p,
        );
      case 0:
        canvas.save();
        canvas.translate(0, -r * .15);
        canvas.scale(1, -1);
        canvas.drawPath(heart(), p);
        canvas.restore();
        stem();
      default:
        canvas.drawCircle(Offset(0, -r * .48), r * .42, p);
        canvas.drawCircle(Offset(-r * .5, r * .15), r * .42, p);
        canvas.drawCircle(Offset(r * .5, r * .15), r * .42, p);
        stem();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPainter old) => old.card != card;
}

/// A small card-table dialog with gold-rimmed buttons.
class _Dialog extends StatelessWidget {
  const _Dialog({
    required this.title,
    required this.body,
    required this.actions,
  });
  final String title, body;
  final List<(String, Color, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: Colors.transparent,
      child: Container(
        width: 290,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4A1A7A), Color(0xFF220A40)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.goldTrim, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: _text(22, const Color(0xFFFFE28A))),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: _text(13.5, Colors.white, FontWeight.w500),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final (label, colour, onTap) in actions)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: onTap,
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colour,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFFE28A),
                              width: 1.5,
                            ),
                          ),
                          child: Text(label, style: _text(14)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A player's picture: a coloured disc with a head and shoulders, the
/// initial on the chest, inside a gold ring.
class _AvatarPainter extends CustomPainter {
  const _AvatarPainter(this.colour, this.initial, {required this.dim});
  final Color colour;
  final String initial;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    final disc = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.2, -.5),
          colors: [
            Color.lerp(colour, Colors.white, .45)!,
            colour,
            Color.lerp(colour, Colors.black, .55)!,
          ],
          stops: const [0, .55, 1],
        ).createShader(disc),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(disc.deflate(r * .06)));
    final body = Paint()..color = Color.lerp(colour, Colors.black, .62)!;
    // Shoulders and head.
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(0, r * .95),
        width: r * 1.7,
        height: r * 1.5,
      ),
      body,
    );
    canvas.drawCircle(c + Offset(0, -r * .2), r * .38, body);
    canvas.drawCircle(
      c + Offset(-r * .1, -r * .3),
      r * .12,
      Paint()..color = const Color(0x22FFFFFF),
    );
    canvas.restore();
    // Gold ring with a bright upper edge.
    canvas.drawCircle(
      c,
      r - r * .04,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .09
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF1B8), Color(0xFFE3B341), Color(0xFF9A6A00)],
        ).createShader(disc),
    );
    if (dim) canvas.drawCircle(c, r, Paint()..color = const Color(0x99140528));
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.dim != dim || old.colour != colour || old.initial != initial;
}

/// The time left for a turn, as an arc that shrinks and turns red.
class _TimerPainter extends CustomPainter {
  const _TimerPainter(this.left);
  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * left,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          const Color(0xFFFF3B3B),
          const Color(0xFF6BFF8A),
          left,
        )!,
    );
  }

  @override
  bool shouldRepaint(_TimerPainter old) => old.left != left;
}
