import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/coins.dart';
import '../game/holdem.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';

/// Play chips for the card table. They last while the app is open.
/// How much may be brought to a table with small blind [sb]: from 20 to
/// 200 big blinds, 100 being the usual stack.
({int min, int usual, int max}) buyInRange(int sb) =>
    (min: sb * 40, usual: sb * 200, max: sb * 400);

abstract final class PokerWallet {
  /// 10 lakh crore to start with.
  static int chips = 10000000000000;
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

/// The supplied table picture is 1870 x 841; everything is placed in its
/// coordinates. Seat centres: you at the bottom, then clockwise.
const _art = Size(1870, 841);
const _seatSpots = [
  Offset(935, 656),
  Offset(178, 548),
  Offset(270, 226),
  Offset(1440, 226),
  Offset(1502, 548),
];

/// Sizes, in the picture's coordinates.
const _avatar = 86.0, _myAvatar = 86.0;
const _plate = Size(262, 52), _myPlate = Size(290, 54);

/// Community cards: their width, and where the middle one sits.
const _boardCard = 112.0, _boardGap = 134.0;
const _boardAt = Offset(935, 452);

/// A little air under the table.
const _bar = 6.0;

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

  /// The last second of your turn that ticked.
  int _lastTick = 0;

  /// The raise panel is open.
  bool _raising = false;

  /// Counts down the turn of whoever is to act; yours ends in a check or
  /// a fold.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 20))
        // Your last five seconds tick.
        ..addListener(() {
          final left = ((1 - _clock.value) * 20).ceil();
          if (_myTurn && left <= 5 && left > 0 && left != _lastTick) {
            _lastTick = left;
            Sounds.play(Sfx.pokerTick);
            HapticFeedback.lightImpact();
          }
        })
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
      buyIn: buyInRange(widget.smallBlind).usual,
      yourChips: widget.buyIn,
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
    Sounds.play(Sfx.pokerDeal);
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
        if (g.playing) Sounds.play(Sfx.pokerCard);
        _later(450, _advance);
      });
      return;
    }
    final s = g.current;
    _lastTick = 0;
    _clock.forward(from: 0);
    if (!s.bot) {
      // The buttons may already be up and the raise panel open: leave
      // what you have chosen alone.
      if (!_raising) {
        setState(() => _raiseTo = g.raiseRange(s)?.min ?? 0);
      }
      HapticFeedback.selectionClick();
      Sounds.play(Sfx.pokerTurn);
      return;
    }
    _later(800 + math.Random().nextInt(700), () {
      // Only ever play the seat this turn was for.
      if (!g.playing || g.awaitingStreet || g.current != s) return;
      final before = s.total;
      g.botTurn();
      setState(() {});
      _react(s, s.total - before);
      _later(350, _advance);
    });
  }

  /// Sound and chips for a move.
  void _react(Seat s, int paid) {
    if (paid > 0) _fly(s.index, toPot: true);
    // Each move has its own sound.
    final a = s.lastAction;
    Sounds.play(
      a.startsWith('Fold')
          ? Sfx.pokerFold
          : a.startsWith('Check')
          ? Sfx.pokerCheck
          : a.startsWith('All in')
          ? Sfx.pokerAllIn
          : a.startsWith('Call')
          ? Sfx.pokerCall
          : Sfx.pokerRaise,
    );
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
      Sounds.play(won ? Sfx.pokerWin : Sfx.pokerLose);
      _later(350, () => Sounds.play(Sfx.pokerChips));
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
    // The buttons are up a moment before the turn is announced. Drop
    // anything still queued for it, so the hand moves on exactly once.
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    move(you);
    _clock.stop();
    setState(() => _raising = false);
    _react(you, you.total - before);
    _later(350, _advance);
  }

  /// Busted: buy in again from the account, or take free chips when the
  /// account cannot cover the table's minimum.
  Future<void> _outOfChips() async {
    final range = buyInRange(widget.smallBlind);
    final bank = PokerWallet.chips;
    final canRebuy = bank >= range.min;
    final amount = canRebuy
        ? math.min(range.usual, bank)
        : PokerWallet.freeChips;
    final stay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => _Dialog(
        title: 'Out of chips',
        body: canRebuy
            ? 'Bring ${formatCoins(amount)} more from your account '
                  '(${formatCoins(bank)}) and keep playing?'
            : 'Your account is empty too. Take '
                  '${formatCoins(amount)} free chips and keep playing?',
        actions: [
          ('LEAVE', const Color(0xFF2A3A9A), () => Navigator.pop(d, false)),
          (
            canRebuy ? 'BUY IN' : 'FREE CHIPS',
            const Color(0xFF1FA35C),
            () => Navigator.pop(d, true),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (stay ?? false) {
      setState(() {
        if (canRebuy) PokerWallet.chips -= amount;
        _game.you.chips += amount;
      });
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

  Offset get _potAt => _at(935, 322);
  Offset get _dealerAt => _at(935, 250);

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
          // The picture is shown whole, above a strip for the buttons.
          final pad = MediaQuery.paddingOf(context);
          final room = size.height - _bar - pad.bottom;
          _k = math.min(size.width / _art.width, room / _art.height);
          _origin = Offset(
            (size.width - _art.width * _k) / 2,
            math.max(0, (room - _art.height * _k) / 2),
          );
          final g = _game;
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
                  child: const _Chip(size: 22),
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

  Widget _topBar(Holdem g) {
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      left: pad.left + 10,
      right: pad.right + 10,
      top: pad.top + 6,
      child: Row(
        children: [
          _roundButton(
            Icons.arrow_back_rounded,
            () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          // Chips on the table.
          _pill(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Chip(size: 16),
                const SizedBox(width: 6),
                Text(
                  _short(g.you.chips),
                  key: const ValueKey('my-chips'),
                  style: _text(12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Chips kept in the account.
          _pill(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 15,
                  color: Color(0xFFFFE28A),
                ),
                const SizedBox(width: 5),
                Text(
                  _short(PokerWallet.chips),
                  key: const ValueKey('bank'),
                  style: _text(12, const Color(0xFFFFE28A)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(child: _status(g)),
          const Spacer(),
          _pill(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.paid_rounded,
                  size: 15,
                  color: Color(0xFFFFD45F),
                ),
                const SizedBox(width: 5),
                Text(
                  'BLINDS ${_short(g.smallBlind)} / ${_short(g.bigBlind)}',
                  style: _text(11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _roundButton(Icons.menu_rounded, _menu, key: const ValueKey('menu')),
        ],
      ),
    );
  }

  String _short(int v) => formatCoins(v).replaceAll(' Crore', ' Cr');

  Widget _roundButton(IconData icon, VoidCallback onTap, {Key? key}) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5A2A9A), Color(0xFF2A0F55)],
            ),
            border: Border.all(color: const Color(0xFFFFD45F), width: 1.3),
          ),
          child: Icon(icon, size: 19, color: Colors.white),
        ),
      );

  /// Sound on or off, or leave the table.
  Future<void> _menu() => showDialog<void>(
    context: context,
    builder: (d) => ValueListenableBuilder(
      valueListenable: Sounds.muted,
      builder: (context, muted, _) => _Dialog(
        title: 'Menu',
        body: 'Sound is ${muted ? 'off' : 'on'}.',
        actions: [
          (
            muted ? 'SOUND ON' : 'SOUND OFF',
            const Color(0xFF2E6BE0),
            () => Sounds.muted.value = !muted,
          ),
          (
            'LEAVE',
            const Color(0xFFC0392B),
            () {
              Navigator.pop(d);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    ),
  );

  /// Whose turn it is, or what the table is waiting for.
  Widget _status(Holdem g) {
    final you = g.you;
    final mine = _myTurn;
    final String status;
    if (!g.playing) {
      status = g.result == null ? 'Dealing…' : 'Next hand…';
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
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: status.isEmpty ? 0 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: mine ? const Color(0xEE1FA35C) : const Color(0xCC14052B),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          status,
          key: const ValueKey('status'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _text(11.5, Colors.white, FontWeight.w600),
        ),
      ),
    );
  }

  /// The pot: a stack of chips on a wide gold-rimmed plate.
  Widget _potLabel(Holdem g) => _place(
    _potAt,
    Container(
      padding: const EdgeInsets.all(1.8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF1B8), Color(0xFFE3B341), Color(0xFF9A6A00)],
        ),
        borderRadius: BorderRadius.circular(40 * _k),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 8)],
      ),
      child: Container(
        height: 62 * _k,
        padding: EdgeInsets.fromLTRB(14 * _k, 0, 34 * _k, 0),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1326), Color(0xFF07040C)],
          ),
          borderRadius: BorderRadius.circular(38 * _k),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChipStack(
              amount: math.max(g.pot, g.bigBlind * 4),
              bigBlind: g.bigBlind,
              size: 44 * _k,
              columns: 1,
            ),
            SizedBox(width: 16 * _k),
            Text('POT', style: _text(26 * _k)),
            SizedBox(width: 14 * _k),
            Text(
              formatCoins(g.pot),
              key: const ValueKey('pot'),
              style: _text(34 * _k, const Color(0xFFFFE28A)),
            ),
          ],
        ),
      ),
    ),
    width: 600,
  );

  /// The five community cards, each exactly on its place.
  List<Widget> _board(Holdem g) {
    final cw = _boardCard * _k;
    return [
      for (var i = 0; i < g.board.length; i++)
        _dealt(
          key: 'b-${g.hands}-$i',
          order: i < 3 ? i : 0,
          to:
              _at(_boardAt.dx + (i - 2) * _boardGap, _boardAt.dy) -
              Offset(cw / 2, cw * .7),
          child: _CardView(card: g.board[i], faceUp: true, width: cw),
        ),
    ];
  }

  static const _colours = [
    Color(0xFF4FB8FF),
    Color(0xFFFF6FA3),
    Color(0xFF45E0A8),
    Color(0xFFFFA94D),
    Color(0xFFB58CFF),
  ];

  // Everything about a seat is placed from the seat's own centre.

  double _radius(Seat s) => (s.index == 0 ? _myAvatar : _avatar) * _k;

  /// The centre of the name plate: under a rival's avatar and a little to
  /// its right; beside yours.
  Offset _plateAt(Seat s) =>
      _spot(s.index) +
      (s.index == 0 ? const Offset(0, 160) : const Offset(0, 152)) * _k;

  /// The back of a seat: a computer player's two cards behind the upper
  /// right of the avatar, then the avatar with its turn ring.
  List<Widget> _seat(Seat s) {
    final g = _game;
    final at = _spot(s.index);
    final turn = _myTurnOf(s);
    final r = g.result;
    final winner = r?.winnings.containsKey(s) ?? false;
    final radius = _radius(s);
    final reveal = r?.revealed.contains(s) ?? false;
    final dim = s.folded || !s.inHand;
    final cardW = (reveal ? 84 : 64) * _k;
    final cardsAt =
        at + (reveal ? const Offset(150, -48) : const Offset(128, -44)) * _k;
    return [
      if (s.bot && s.inHand)
        for (var i = 0; i < s.hole.length; i++)
          _dealt(
            key: 'c-${g.hands}-${s.index}-$i',
            order: s.index * 2 + i,
            to:
                cardsAt +
                Offset(
                  (i - .5) * cardW * (reveal ? 1.04 : .5) - cardW / 2,
                  -cardW * .7,
                ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: s.folded ? 0 : 1,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 250),
                scale: s.folded ? .5 : 1,
                child: Transform.rotate(
                  angle: reveal ? 0 : .22 + (i - .5) * .26,
                  child: _CardView(
                    card: s.hole[i],
                    faceUp: reveal,
                    width: cardW,
                  ),
                ),
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
                    // Out of the hand: the colour drains away.
                    dim ? const Color(0xFF6E6E80) : _colours[s.index],
                    s.name.characters.first,
                    dim: dim,
                  ),
                ),
              ),
              if (s.folded) _foldMark(radius),
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

  /// Marks a folded player: the word across the middle of the greyed
  /// profile, on a dark band.
  Widget _foldMark(double radius) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 220),
    builder: (context, t, child) => Opacity(opacity: t, child: child),
    child: ClipOval(
      child: SizedBox(
        width: radius * 1.84,
        height: radius * 1.84,
        child: Center(
          child: Container(
            width: double.infinity,
            height: radius * .62,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xE61A1A26), Color(0xE6000000)],
              ),
              border: Border.symmetric(
                horizontal: BorderSide(color: Color(0x88FFFFFF), width: .8),
              ),
            ),
            child: Text(
              'FOLD',
              style: _text(
                radius * .4,
                const Color(0xFFF2F2F7),
              ).copyWith(letterSpacing: radius * .08),
            ),
          ),
        ),
      ),
    ),
  );

  /// The front of a seat, drawn over the cards: the name plate (name on
  /// the left, chips on the right), the dealer button, and the badge that
  /// says what the player did.
  List<Widget> _seatFront(Seat s) {
    final g = _game;
    final at = _spot(s.index);
    final turn = _myTurnOf(s);
    final radius = _radius(s);
    final me = s.index == 0;
    final plate = (me ? _myPlate : _plate) * _k;
    final badge = _badge(s);
    return [
      _place(
        _plateAt(s),
        Container(
          width: plate.width,
          height: plate.height,
          padding: EdgeInsets.symmetric(horizontal: 22 * _k),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5A2590), Color(0xFF2A0F4A), Color(0xFF160726)],
              stops: [0, .5, 1],
            ),
            borderRadius: BorderRadius.circular(plate.height / 2),
            border: Border.all(
              color: turn ? Colors.white : const Color(0xFFFFD45F),
              width: turn ? 1.8 : 1.3,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), blurRadius: 4),
            ],
          ),
          // Chips only: the name has its own tag above the picture.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Chip(size: 27 * _k),
                SizedBox(width: 9 * _k),
                Text(
                  formatCoins(s.chips),
                  maxLines: 1,
                  style: _text(27 * _k, const Color(0xFFFFE28A)),
                ),
              ],
            ),
          ),
        ),
        width: 500,
      ),
      // The name, on its own tag over the top of the picture.
      _place(
        at + Offset(0, -radius - 4 * _k),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * _k, vertical: 3 * _k),
          decoration: BoxDecoration(
            color: const Color(0xF0170722),
            borderRadius: BorderRadius.circular(20 * _k),
            border: Border.all(
              color: turn ? Colors.white : const Color(0xAAFFD45F),
              width: 1,
            ),
          ),
          child: Text(
            shortName(s.name, 9),
            style: _text(24 * _k, Colors.white, FontWeight.w600),
          ),
        ),
        width: 200,
      ),
      // Dealer button, at the avatar's lower right.
      if (g.dealer == s.index)
        _place(
          // Yours sits to the left of your picture, clear of your cards.
          at +
              (me
                  ? Offset(-radius - 26 * _k, radius * .2)
                  : Offset(radius * .78, radius * .62)),
          Container(
            width: 44 * _k,
            height: 44 * _k,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFF8A8A9A), width: 1),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 3),
              ],
            ),
            child: Text('D', style: _text(24 * _k, const Color(0xFF1C0838))),
          ),
          width: 60,
        ),
      if (badge != null)
        _place(
          // Under the picture, just above the chips; yours sits beside
          // your picture, since your cards are under it.
          me
              ? at + Offset(radius + 104 * _k, radius * .1)
              : at + Offset(0, radius + 22 * _k),
          badge,
          width: 240,
        ),
    ];
  }

  /// The badge on a profile: the move and, under it, the amount (blind,
  /// call, bet, raise, all in); or check, fold, the hand shown, a win.
  Widget? _badge(Seat s) {
    final g = _game, r = g.result;
    if (!s.inHand) return null;
    String top, bottom = '';
    var fill = const Color(0xFF14101C), edge = const Color(0xFFFFD45F);
    final won = r?.winnings[s];
    // A folded player's picture already says so.
    if (s.folded) return null;
    if (r != null && r.revealed.contains(s)) {
      top = r.values[s]!.rank.label;
      if (won != null) bottom = '+${formatCoins(won)}';
    } else if (won != null) {
      top = 'Win';
      bottom = '+${formatCoins(won)}';
    } else if (s.index == 0 && g.board.length >= 3 && s.bet == 0) {
      // Between bets, yours shows what you hold so far.
      top = evaluate([...s.hole, ...g.board]).rank.label;
    } else {
      final a = s.lastAction;
      if (a.isEmpty || !g.playing) return null;
      final amount = s.bet > 0 ? formatCoins(s.bet) : '';
      if (a.startsWith('All in')) {
        (top, bottom, fill) = ('All in', amount, const Color(0xFF5A1018));
        edge = const Color(0xFFFF6B6B);
      } else if (a.startsWith('Raise') || a.startsWith('Bet')) {
        (top, bottom) = (a.startsWith('Raise') ? 'Raise' : 'Bet', amount);
        fill = const Color(0xFF4A3306);
      } else if (a.startsWith('Call')) {
        (top, bottom, fill) = ('Call', amount, const Color(0xFF0B4A22));
        edge = const Color(0xFF6BE08A);
      } else if (a.startsWith('Check')) {
        top = 'Check';
        fill = const Color(0xFF0E3A2A);
      } else if (a.startsWith('SB')) {
        (top, bottom) = ('Small Blind', amount);
      } else {
        (top, bottom) = ('Big Blind', amount);
      }
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey('badge-${s.index}-$top-$bottom'),
      tween: Tween(begin: .6, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      // A small pill of smoked glass, tinted by the move.
      child: Container(
        key: ValueKey('action-${s.index}'),
        padding: EdgeInsets.symmetric(horizontal: 14 * _k, vertical: 3 * _k),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(fill, Colors.white, .28)!.withValues(alpha: .72),
              fill.withValues(alpha: .72),
            ],
          ),
          borderRadius: BorderRadius.circular(20 * _k),
          border: Border.all(color: edge.withValues(alpha: .75), width: .9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(top, style: _text(20 * _k, Colors.white, FontWeight.w600)),
            if (bottom.isNotEmpty) ...[
              SizedBox(width: 9 * _k),
              Text(
                bottom.replaceAll(' Crore', ' Cr'),
                style: _text(20 * _k, const Color(0xFFFFE9A8)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _myTurnOf(Seat s) {
    final g = _game;
    return g.playing && !_dealing && !g.awaitingStreet && g.turn == s.index;
  }

  /// Your two cards, face up, standing just above your name plate.
  List<Widget> _yourCards(Holdem g) {
    final you = g.you;
    if (!you.inHand || you.hole.isEmpty) return const [];
    final cw = 100 * _k;
    // Their lower edge tucks a little behind the plate.
    // Centred under your picture, their lower edge behind the chips.
    final bottom = _plateAt(you) + Offset(0, 14 * _k);
    return [
      for (var i = 0; i < 2; i++)
        _dealt(
          key: 'c-${g.hands}-0-$i',
          order: i,
          to: bottom + Offset((i - .5) * cw * .86 - cw / 2, -cw * 1.4),
          // Folded: your cards stay where they are, drained to grey.
          child: ColorFiltered(
            colorFilter: you.folded
                ? const ColorFilter.matrix(<double>[
                    .18, .36, .06, 0, 0, //
                    .18, .36, .06, 0, 0, //
                    .18, .36, .06, 0, 0, //
                    0, 0, 0, 1, 0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
            child: Transform.rotate(
              angle: (i - .5) * .2,
              child: _CardView(card: you.hole[i], faceUp: true, width: cw),
            ),
          ),
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
      _at(935, 292),
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

  /// FOLD, CHECK or CALL, and RAISE along the bottom, under the table.
  /// They are always there, dimmed when it is not your turn. RAISE opens a
  /// panel to choose the amount.
  Widget _actions(Holdem g) {
    final you = g.you;
    final mine = _myTurn;
    final size = MediaQuery.sizeOf(context);
    final call = g.toCall(you);
    final range = mine ? g.raiseRange(you) : null;
    // Your profile and plate sit in the middle; the buttons flank them on
    // the same line: FOLD on the left, CHECK / CALL and RAISE on the right.
    final plate = _plateAt(you);
    final bw = 226 * _k, bh = (104 * _k).clamp(36.0, 50.0), gap = 12 * _k;
    final top = math.min(plate.dy - bh / 2, size.height - bh - 4);
    final leftEdge = plate.dx - _myPlate.width / 2 * _k - gap;
    final rightEdge = plate.dx + _myPlate.width / 2 * _k + gap;
    // Only while it is your turn.
    if (!mine) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned(
          left: leftEdge - bw,
          top: top,
          child: KeyedSubtree(
            key: const ValueKey('fold-btn'),
            child: _btn(
              'FOLD',
              Icons.close_rounded,
              const Color(0xFFD42B3A),
              mine,
              () => _act(g.fold),
              bw,
              bh,
            ),
          ),
        ),
        Positioned(
          left: rightEdge,
          top: top,
          child: KeyedSubtree(
            key: const ValueKey('call-btn'),
            child: _btn(
              call == 0
                  ? 'CHECK'
                  : call >= you.chips
                  ? 'ALL IN ${_short(call)}'
                  : 'CALL ${_short(call)}',
              Icons.check_rounded,
              const Color(0xFF17A04E),
              mine,
              () => _act(g.call),
              bw,
              bh,
            ),
          ),
        ),
        Positioned(
          left: rightEdge + bw + gap,
          top: top,
          child: KeyedSubtree(
            key: const ValueKey('raise-btn'),
            child: _btn(
              g.currentBet == 0 ? 'BET' : 'RAISE',
              Icons.arrow_upward_rounded,
              const Color(0xFFE09A12),
              range != null,
              () => setState(() => _raising = !_raising),
              bw,
              bh,
            ),
          ),
        ),
        if (_raising && range != null)
          Positioned(
            // Over the RAISE button, kept on the screen.
            right: math.max(8, size.width - (rightEdge + bw * 2 + gap)),
            bottom: size.height - top + 6,
            child: _raisePanel(g, range),
          ),
      ],
    );
  }

  /// Choose how much to raise to: a slider, quick amounts and a confirm.
  Widget _raisePanel(Holdem g, ({int min, int max}) range) {
    final to = _raiseTo.clamp(range.min, range.max);
    void set(num v) =>
        setState(() => _raiseTo = v.round().clamp(range.min, range.max));
    final step = g.bigBlind;
    final allIn = to >= range.max;
    return Container(
      key: const ValueKey('raise-panel'),
      width: 300,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF24A1A7A), Color(0xF21A0832)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD45F), width: 1.6),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 14)],
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
                style: _text(22, const Color(0xFFFFE28A)),
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
                          : range.min + ((v - range.min) / step).round() * step;
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
              _mini('½ POT', () => set(g.currentBet + g.pot ~/ 2), wide: true),
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
                border: Border.all(color: const Color(0xFFFFF1B8), width: 1.5),
              ),
              child: Text(
                allIn
                    ? 'ALL IN ${_short(to)}'
                    : '${g.currentBet == 0 ? 'BET' : 'RAISE TO'} ${_short(to)}',
                style: _text(15, const Color(0xFF2A1400)),
              ),
            ),
          ),
        ],
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

  /// A glossy pill button with an icon, edged in gold.
  Widget _btn(
    String label,
    IconData icon,
    Color colour,
    bool enabled,
    VoidCallback onTap,
    double width,
    double height,
  ) => AnimatedOpacity(
    duration: const Duration(milliseconds: 150),
    opacity: enabled ? 1 : .4,
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(1.8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF1B8), Color(0xFFE3B341), Color(0xFF9A6A00)],
          ),
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(colour, Colors.white, .3)!,
                colour,
                Color.lerp(colour, Colors.black, .35)!,
              ],
              stops: const [0, .45, 1],
            ),
            borderRadius: BorderRadius.circular(height / 2 - 1.5),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(label, style: _text(16)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _pill(Widget child) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3D1763), Color(0xFF1B0930)],
      ),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFFFD45F), width: 1.3),
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
  const _Chip({required this.size, this.colour = const Color(0xFFD81E3A)});
  final double size;
  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ChipPainter(colour)),
  );
}

/// A casino chip seen from above: a coloured disc with white edge inlays,
/// a fine ring and a bright centre.
class _ChipPainter extends CustomPainter {
  const _ChipPainter(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    canvas.drawCircle(
      c + Offset(0, r * .14),
      r,
      Paint()..color = const Color(0x77000000),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.4),
          colors: [
            Color.lerp(colour, Colors.white, .35)!,
            colour,
            Color.lerp(colour, Colors.black, .45)!,
          ],
          stops: const [0, .6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Six white inlays round the edge.
    final inlay = Paint()
      ..color = const Color(0xFFFDFBF4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .3;
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * .84),
        i * math.pi / 3 - .2,
        .4,
        false,
        inlay,
      );
    }
    canvas.drawCircle(
      c,
      r * .64,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .07
        ..color = const Color(0xFFFFE28A),
    );
    canvas.drawCircle(
      c,
      r * .56,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(colour, Colors.white, .5)!,
            Color.lerp(colour, Colors.black, .15)!,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * .56)),
    );
    // A star in the middle.
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final d = r * (i.isEven ? .36 : .15);
      final p = c + Offset(math.cos(a), math.sin(a)) * d;
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(star..close(), Paint()..color = const Color(0xFFFFF1B8));
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.colour != colour;
}

/// Chip colours by value, dearest first, in big blinds.
const _denominations = [
  (100.0, Color(0xFF1B1B26)), // black
  (25.0, Color(0xFF7B2FD0)), // purple
  (5.0, Color(0xFF1FA35C)), // green
  (1.0, Color(0xFFD81E3A)), // red
  (0.0, Color(0xFF2E6BE0)), // blue, for the small change
];

/// An amount as neat stacks of chips, side by side.
class _ChipStack extends StatelessWidget {
  const _ChipStack({
    required this.amount,
    required this.bigBlind,
    this.size = 18,
    this.columns = 3,
  });
  final int amount, bigBlind, columns;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Break the amount into chips, a few stacks of at most six.
    final stacks = <(Color, int)>[];
    var left = amount / bigBlind;
    for (final (value, colour) in _denominations) {
      if (stacks.length >= columns) break;
      final n = value == 0 ? (left > 0 ? 1 : 0) : (left / value).floor();
      if (n <= 0) continue;
      stacks.add((colour, math.min(6, n)));
      left -= n * value;
    }
    if (stacks.isEmpty) stacks.add((_denominations[3].$2, 1));
    final lift = size * .2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (colour, n) in stacks)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * .04),
            child: SizedBox(
              width: size,
              height: size * .62 + lift * (n - 1) + size * .2,
              child: Stack(
                children: [
                  for (var i = 0; i < n; i++)
                    Positioned(
                      left: 0,
                      bottom: i * lift,
                      // Seen at a slant, like chips on a table.
                      child: Transform(
                        transform: Matrix4.diagonal3Values(1, .62, 1),
                        alignment: Alignment.bottomCenter,
                        child: _Chip(size: size, colour: colour),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
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
    // Rank and suit side by side at the top, so both read even when only
    // the top of the card shows; a large suit fills the rest.
    tp.paint(canvas, Offset(w * .09, h * .035));
    _suit(canvas, c.suit, Offset(w * .73, h * .17), w * .36, ink);
    _suit(canvas, c.suit, Offset(w * .5, h * .66), w * .58, ink);
  }

  /// A suit symbol centred on [at], [s] wide.
  static void _suit(Canvas canvas, int suit, Offset at, double s, Color ink) {
    final p = Paint()..color = ink;
    final r = s / 2;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Two round lobes meeting in a notch, drawn down to a point.
    Path heart() => Path()
      ..moveTo(0, r)
      ..cubicTo(-r * .35, r * .55, -r, r * .15, -r, -r * .4)
      ..arcToPoint(Offset(0, -r * .4), radius: Radius.circular(r * .5))
      ..arcToPoint(Offset(r, -r * .4), radius: Radius.circular(r * .5))
      ..cubicTo(r, r * .15, r * .35, r * .55, 0, r)
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
    if (dim) canvas.drawCircle(c, r, Paint()..color = const Color(0x55101018));
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
