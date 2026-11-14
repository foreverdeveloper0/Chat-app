import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/coins.dart';
import '../game/holdem.dart';
import '../game/poker_wallet.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../widgets/poker_buyin.dart';

export '../game/poker_wallet.dart';

/// How the table is when you sit down at it.
enum PokerStart {
  /// A match is already under way, or the table is waiting to start.
  auto,

  /// The table waits for players: a countdown of up to 20 seconds.
  wait,

  /// A hand is already running; you join from the next one.
  running,

  /// Straight into a new hand.
  now,
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
    this.tableName = 'Table',
    this.start = PokerStart.auto,
  });

  final int smallBlind, buyIn, players;
  final String tableName;
  final PokerStart start;

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
  Offset(300, 545),
  Offset(300, 232),
  Offset(1570, 232),
  Offset(1570, 545),
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

  /// You stood up (or ran out of chips): the SIT DOWN button shows.
  bool _standing = false;
  String _standingWhy = '';

  /// The table has been cleared between hands: no cards, pot or badges.
  bool _cleared = false;

  /// The countdown before the next hand, in seconds left and in all.
  int _wait = 0, _waitTotal = 0;
  String _waitLabel = '';
  Timer? _waitTimer;

  /// For a hand set up before you arrived: its number and how many board
  /// cards were already out, so those appear at once instead of flying in.
  int _warmHand = -1, _warmBoard = 0;

  /// Whether the device asks for less motion.
  bool _still = false;

  final _rng = math.Random();

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
    // Sitting down: a match is already running, or the table is waiting
    // to start (never for more than 20 seconds).
    final start = widget.start != PokerStart.auto
        ? widget.start
        : widget.players >= 3 && _rng.nextDouble() < .6
        ? PokerStart.running
        : PokerStart.wait;
    switch (start) {
      case PokerStart.now || PokerStart.auto:
        _later(700, _deal);
      case PokerStart.wait:
        _later(
          400,
          () => _countdown(8 + _rng.nextInt(13), 'Match starting', _deal),
        );
      case PokerStart.running:
        _later(300, _joinRunning);
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _waitTimer?.cancel();
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

  /// A countdown on the table: [label], then [done] after [seconds].
  void _countdown(int seconds, String label, VoidCallback done) {
    _waitTimer?.cancel();
    setState(() {
      _wait = seconds;
      _waitTotal = seconds;
      _waitLabel = label;
    });
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_wait <= 1) {
        t.cancel();
        setState(() => _wait = 0);
        done();
      } else {
        setState(() => _wait--);
      }
    });
  }

  /// Chips of yours that are left on the table while you are standing go
  /// back to the account.
  void _collect() {
    final you = _game.you;
    // Only while you are standing; waiting for the next hand is not that.
    if (!_standing || you.chips == 0) return;
    if (_game.playing && you.live) return;
    PokerWallet.chips += you.chips;
    you.chips = 0;
  }

  /// A match that was already under way when you sat down: the first
  /// round of betting is over, the flop is out, and you wait for the next
  /// hand.
  void _joinRunning() {
    final g = _game;
    g.you.away = true;
    if (!g.deal()) {
      g.you.away = false;
      _countdown(8 + _rng.nextInt(13), 'Match starting', _deal);
      return;
    }
    var guard = 0;
    while (g.playing && g.street == Street.preflop && guard++ < 80) {
      g.awaitingStreet ? g.nextStreet() : g.botTurn();
    }
    setState(() {
      _warmHand = g.hands;
      _warmBoard = g.board.length;
      _cleared = false;
    });
    _advance();
  }

  void _deal() {
    final g = _game;
    // Out of chips: you stand up, and may buy in again.
    if (!g.you.away && g.you.chips < g.bigBlind) _bust();
    g.rebuyBots();
    var dealt = false;
    setState(() {
      _cleared = false;
      dealt = g.deal();
      _dealing = dealt;
    });
    if (!dealt) {
      // Fewer than two players with chips: wait for someone to sit.
      _later(1500, _deal);
      return;
    }
    Sounds.play(Sfx.pokerDeal);
    _fly(g.smallBlindSeat, toPot: true);
    _fly(g.bigBlindSeat, toPot: true);
    final cards = g.seats.where((s) => s.inHand).length * 2;
    _later(cards * 110 + 800, () {
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
        if (!g.playing) {
          _later(450, _advance);
          return;
        }
        // The flop comes out one card at a time; the turn and river singly.
        final n = g.street == Street.flop ? 3 : 1;
        for (var i = 0; i < n; i++) {
          _later(i * 320 + 150, () => Sounds.play(Sfx.pokerCard));
        }
        _later(n == 3 ? 1500 : 900, _advance);
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
    final g = _game;
    final r = g.result!;
    setState(() {});
    final won = r.winnings.containsKey(g.you);
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
    // Show the result, clear the table, count down to the next hand.
    _later(r.revealed.isEmpty ? 2600 : 4400, () {
      _collect();
      // Somebody who arrived mid-hand is dealt in from here.
      if (!_standing) g.you.away = false;
      setState(() => _cleared = true);
      _countdown(_standing ? 5 : 4, 'Next hand', _deal);
    });
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

  /// Out of chips: you stand up, and can buy in again from the account.
  void _bust() {
    final g = _game;
    _standing = true;
    _standingWhy = 'Out of chips';
    g.you.away = true;
    _collect();
    if (mounted) setState(() {});
  }

  /// Stands you up: your chips go back to the account and you watch.
  /// Standing in the middle of a hand folds you.
  void _standUp() {
    final g = _game, you = g.you;
    if (_standing) return;
    final inPlay = g.playing && you.live && !you.allIn;
    if (inPlay) {
      // Drop anything queued for your turn; the hand is re-driven below.
      for (final t in _timers) {
        t.cancel();
      }
      _timers.clear();
      _clock.stop();
    }
    g.standUp(you);
    _standing = true;
    _collect();
    setState(() {
      _standingWhy = 'You are standing';
      _raising = false;
      if (inPlay) _dealing = false;
    });
    if (inPlay) _advance();
  }

  /// Sits you back down: choose a buy-in from the account.
  Future<void> _sit() async {
    if (!_standing) return;
    final range = buyInRange(widget.smallBlind);
    if (PokerWallet.chips < range.min) {
      final take = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (d) => _Dialog(
          title: 'Account empty',
          body:
              'You need at least ${_short(range.min)} to sit here. Take '
              '${_short(PokerWallet.freeChips)} free chips?',
          actions: [
            ('NO', const Color(0xFF2A3A9A), () => Navigator.pop(d, false)),
            (
              'FREE CHIPS',
              const Color(0xFF1FA35C),
              () => Navigator.pop(d, true),
            ),
          ],
        ),
      );
      if (!(take ?? false) || !mounted) return;
      setState(() => PokerWallet.chips += PokerWallet.freeChips);
      if (PokerWallet.chips < range.min) return;
    }
    if (!mounted) return;
    final amount = await showBuyIn(
      context,
      widget.tableName,
      widget.smallBlind,
    );
    if (amount == null || !mounted) return;
    PokerWallet.chips -= amount;
    Sounds.play(Sfx.pokerChips);
    setState(() {
      _game.sitDown(_game.you, amount);
      _standing = false;
    });
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
          _still = MediaQuery.disableAnimationsOf(context);
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
              // Five places for the community cards, each the size of a card.
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SlotsPainter([
                      for (var i = 0; i < 5; i++)
                        Rect.fromCenter(
                          center: _at(
                            _boardAt.dx + (i - 2) * _boardGap,
                            _boardAt.dy,
                          ),
                          width: _boardCard * _k,
                          height: _boardCard * 1.4 * _k,
                        ),
                    ]),
                  ),
                ),
              ),
              if (_wait > 0) _countdownRing(),
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
              if (g.result != null && !_cleared) _resultBanner(g.result!),
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
                  _standing ? '—' : _short(g.you.chips),
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
          // Takes all the room between, so the right-hand buttons sit in
          // the corner.
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: _status(g)),
          ),
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

  /// Stand up or sit down, sound on or off, or leave the table.
  Future<void> _menu() => showDialog<void>(
    context: context,
    builder: (d) => ValueListenableBuilder(
      valueListenable: Sounds.muted,
      builder: (context, muted, _) => _Dialog(
        title: 'Menu',
        body: _standing
            ? 'You are standing. Your chips are in your account.'
            : 'Sound is ${muted ? 'off' : 'on'}.',
        actions: [
          if (_standing)
            (
              'SIT DOWN',
              const Color(0xFF1FA35C),
              () {
                Navigator.pop(d);
                _sit();
              },
            )
          else
            (
              'STAND UP',
              const Color(0xFF2E6BE0),
              () {
                Navigator.pop(d);
                _standUp();
              },
            ),
          (
            muted ? 'SOUND ON' : 'SOUND OFF',
            const Color(0xFF7B4FD0),
            () => Sounds.muted.value = !muted,
          ),
          (
            'LEAVE TABLE',
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
    if (_standing) {
      status = _standingWhy;
    } else if (_wait > 0) {
      status = '$_waitLabel…';
    } else if (!g.playing) {
      status = g.seats.where((s) => s.chips > 0 && !s.away).length < 2
          ? 'Waiting for players…'
          : 'Dealing…';
    } else if (_dealing) {
      status = 'Dealing…';
    } else if (you.away) {
      status = 'Hand in progress — you play the next one';
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

  /// The table's countdown, in the middle of the felt: a ring that runs
  /// down, the seconds left, and what it is counting to.
  Widget _countdownRing() {
    final d = 132 * _k;
    return _place(
      _at(_boardAt.dx, _boardAt.dy),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: const ValueKey('table-countdown'),
            width: d,
            height: d,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xF0301048), Color(0xF00B0416)],
                    ),
                    border: Border.all(
                      color: const Color(0x88FFD45F),
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x99000000), blurRadius: 10),
                    ],
                  ),
                ),
                // Runs down smoothly through each second.
                TweenAnimationBuilder<double>(
                  key: ValueKey('ring-$_wait'),
                  tween: Tween(
                    begin: _wait / _waitTotal,
                    end: (_wait - 1) / _waitTotal,
                  ),
                  duration: Duration(seconds: _still ? 0 : 1),
                  builder: (context, v, _) => CustomPaint(
                    size: Size.square(d),
                    painter: _RingPainter(v.clamp(0.0, 1.0)),
                  ),
                ),
                Text(
                  '$_wait',
                  key: const ValueKey('countdown-seconds'),
                  style: _text(56 * _k, const Color(0xFFFFE28A)),
                ),
              ],
            ),
          ),
          SizedBox(height: 10 * _k),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 18 * _k,
              vertical: 5 * _k,
            ),
            decoration: BoxDecoration(
              color: const Color(0xE6170722),
              borderRadius: BorderRadius.circular(20 * _k),
              border: Border.all(color: const Color(0x88FFD45F), width: .9),
            ),
            child: Text(
              _waitLabel.toUpperCase(),
              style: _text(
                21 * _k,
                const Color(0xFFFFE28A),
                FontWeight.w600,
              ).copyWith(letterSpacing: 1.5),
            ),
          ),
        ],
      ),
      width: 420,
    );
  }

  /// The pot: a heap of chips beside the total, on a gold-rimmed plate
  /// with a glow behind it.
  Widget _potLabel(Holdem g) => _place(
    _potAt,
    Container(
      padding: EdgeInsets.all(3 * _k),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF6C8), Color(0xFFE3B341), Color(0xFF7A5200)],
        ),
        borderRadius: BorderRadius.circular(48 * _k),
        boxShadow: const [
          BoxShadow(color: Color(0x66FFD45A), blurRadius: 22, spreadRadius: 1),
          BoxShadow(color: Color(0xAA000000), blurRadius: 8),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(3 * _k),
        decoration: BoxDecoration(
          color: const Color(0xFF07040C),
          borderRadius: BorderRadius.circular(45 * _k),
        ),
        child: Container(
          height: 84 * _k,
          padding: EdgeInsets.fromLTRB(22 * _k, 0, 40 * _k, 0),
          decoration: BoxDecoration(
            gradient: const RadialGradient(
              center: Alignment(-.5, -.6),
              radius: 1.6,
              colors: [Color(0xFF3B2160), Color(0xFF1A0C2E), Color(0xFF07040C)],
            ),
            borderRadius: BorderRadius.circular(42 * _k),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChipStack(
                amount: math.max(g.pot, g.bigBlind * 4),
                bigBlind: g.bigBlind,
                size: 52 * _k,
                columns: 3,
              ),
              SizedBox(width: 22 * _k),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'TOTAL POT',
                    style: _text(
                      19 * _k,
                      const Color(0xFFD9C3FF),
                    ).copyWith(letterSpacing: 3 * _k),
                  ),
                  Container(
                    width: 150 * _k,
                    height: 1.5,
                    margin: EdgeInsets.symmetric(vertical: 2 * _k),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x00FFD45A),
                          Color(0xFFFFD45A),
                          Color(0x00FFD45A),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    formatCoins(_cleared ? 0 : g.pot),
                    key: const ValueKey('pot'),
                    style: _text(42 * _k, const Color(0xFFFFE28A)).copyWith(
                      shadows: const [
                        Shadow(color: Color(0xAA000000), blurRadius: 4),
                        Shadow(color: Color(0x66FFB300), blurRadius: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    width: 640,
  );

  /// The five community cards, each exactly on its place. They fly out
  /// from the dealer one at a time (the flop three, a third of a second
  /// apart) face down, and turn over where they land.
  List<Widget> _board(Holdem g) {
    if (_cleared) return const [];
    final cw = _boardCard * _k;
    return [
      for (var i = 0; i < g.board.length; i++)
        () {
          final now = g.hands == _warmHand && i < _warmBoard;
          final delay = i < 3 ? i * 320 : 0;
          return _dealt(
            key: 'b-${g.hands}-$i',
            delay: delay,
            instant: now,
            to:
                _at(_boardAt.dx + (i - 2) * _boardGap, _boardAt.dy) -
                Offset(cw / 2, cw * .7),
            child: _FlipIn(
              card: g.board[i],
              width: cw,
              after: delay + 460 + 60,
              instant: now || _still,
            ),
          );
        }(),
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
      (s.index == 0 ? const Offset(0, 160) : const Offset(0, 122)) * _k;

  /// Which way the middle of the table lies from a seat: 1 for the left
  /// side, -1 for the right.
  double _inward(int seat) =>
      _spot(seat).dx < _origin.dx + _art.width * _k / 2 ? 1 : -1;

  /// Milliseconds before [s]'s [card]th card leaves the dealer: one card
  /// to each player in turn, twice round the table.
  int _dealDelay(Seat s, int card) {
    final g = _game;
    final order = [
      for (var k = 1; k <= g.seats.length; k++)
        g.seats[(g.dealer + k) % g.seats.length],
    ].where((x) => x.inHand).toList();
    final place = order.contains(s) ? order.indexOf(s) : 0;
    return (card * order.length + place) * 110;
  }

  /// The back of a seat: a computer player's two cards beside the avatar
  /// (always on the side nearest the table), then the avatar with its
  /// turn ring.
  List<Widget> _seat(Seat s) {
    final g = _game;
    final at = _spot(s.index);
    final turn = _myTurnOf(s);
    final r = g.result;
    final standing = s.index == 0 && _standing;
    final folded = s.folded && !_cleared && !standing;
    final winner = (r?.winnings.containsKey(s) ?? false) && !_cleared;
    final inward = _inward(s.index);
    final radius = _radius(s);
    final reveal = (r?.revealed.contains(s) ?? false) && !_cleared;
    final me = s.index == 0;
    final dim = folded || (!s.inHand && !(me && !_standing)) && !_cleared;
    final cardW = (reveal ? 84 : 64) * _k;
    final cardsAt =
        at + Offset((reveal ? 150 : 128) * inward, reveal ? -48 : -44) * _k;
    final warm = g.hands == _warmHand;
    return [
      if (s.bot && s.inHand && !_cleared)
        for (var i = 0; i < s.hole.length; i++)
          _dealt(
            key: 'c-${g.hands}-${s.index}-$i',
            delay: _dealDelay(s, i),
            instant: warm,
            to:
                cardsAt +
                Offset(
                  (i - .5) * cardW * (reveal ? 1.04 : .5) * inward - cardW / 2,
                  -cardW * .7,
                ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: folded ? 0 : 1,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 250),
                scale: folded ? .5 : 1,
                child: Transform.rotate(
                  // Fanned the same way on both sides of the table.
                  angle: reveal ? 0 : inward * (.22 + (i - .5) * .26),
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
                child: me && _standing
                    // An empty chair.
                    ? CustomPaint(painter: const _EmptySeatPainter())
                    : CustomPaint(
                        painter: _AvatarPainter(
                          // Out of the hand: the colour drains away.
                          dim ? const Color(0xFF6E6E80) : _colours[s.index],
                          s.name.characters.first,
                          dim: dim,
                        ),
                      ),
              ),
              if (folded) _foldMark(radius),
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
            child: me && _standing
                ? Text(
                    'Empty seat',
                    style: _text(
                      26 * _k,
                      const Color(0xFFB8A3D6),
                      FontWeight.w500,
                    ),
                  )
                : Row(
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
      if (!(me && _standing))
        _place(
          at + Offset(0, -radius - 4 * _k),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * _k,
              vertical: 3 * _k,
            ),
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
      if (g.dealer == s.index && !(me && _standing))
        _place(
          // Yours sits to the left of your picture, clear of your cards.
          at +
              (me
                  ? Offset(-radius - 26 * _k, radius * .2)
                  : Offset(radius * .82, -radius * .6)),
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
          // Rivals: across the lower part of the picture; yours
          // sits beside your picture, since your cards are under it.
          me
              ? at + Offset(radius + 104 * _k, radius * .1)
              : at + Offset(0, radius * .56),
          // Never wider than the picture it sits on.
          me
              ? badge
              : SizedBox(
                  width: radius * 1.8,
                  child: FittedBox(fit: BoxFit.scaleDown, child: badge),
                ),
          width: 240,
        ),
    ];
  }

  /// The badge on a profile: the move and, under it, the amount (blind,
  /// call, bet, raise, all in); or check, fold, the hand shown, a win.
  Widget? _badge(Seat s) {
    final g = _game, r = g.result;
    if (_cleared) return null;
    String top, bottom = '';
    var fill = const Color(0xFF14101C), edge = const Color(0xFFFFD45F);
    final won = r?.winnings[s];
    if (!s.inHand) {
      return null;
    } else if (s.folded) {
      // A folded player's picture already says so.
      return null;
    } else if (won != null) {
      top = 'Win';
      bottom = '+${formatCoins(won)}';
    } else if (r != null) {
      return null;
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
        (top, bottom) = (s.index == 0 ? 'Small Blind' : 'SB', amount);
      } else {
        (top, bottom) = (s.index == 0 ? 'Big Blind' : 'BB', amount);
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

  /// Your two cards, standing above your chips. They come from the dealer
  /// face down, in turn with everyone else's, and turn over as they land.
  List<Widget> _yourCards(Holdem g) {
    final you = g.you;
    if (!you.inHand || you.hole.isEmpty || _cleared || _standing) {
      return const [];
    }
    final cw = 100 * _k;
    // Centred under your picture, their lower edge behind the chips.
    final bottom = _plateAt(you) + Offset(0, 14 * _k);
    final warm = g.hands == _warmHand;
    return [
      for (var i = 0; i < 2; i++)
        _dealt(
          key: 'c-${g.hands}-0-$i',
          delay: _dealDelay(you, i),
          instant: warm,
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
              child: _FlipIn(
                card: you.hole[i],
                width: cw,
                after: _dealDelay(you, i) + 460 + 120,
                instant: warm || _still,
              ),
            ),
          ),
        ),
    ];
  }

  /// A card that flies out of the dealer after [delay] milliseconds,
  /// spinning and growing as it goes, and lands at [to]. With [instant]
  /// (or reduced motion) it is simply there.
  Widget _dealt({
    required String key,
    required int delay,
    required Offset to,
    required Widget child,
    bool instant = false,
  }) {
    if (instant || _still) {
      return Positioned(
        key: ValueKey(key),
        left: to.dx,
        top: to.dy,
        child: child,
      );
    }
    const fly = 460;
    final total = delay + fly;
    return TweenAnimationBuilder<double>(
      key: ValueKey(key),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, c) {
        final p = Offset.lerp(_dealerAt, to, t)!;
        return Positioned(
          left: p.dx,
          top: p.dy,
          child: Opacity(
            opacity: t == 0 ? 0 : 1,
            child: Transform.rotate(
              angle: (1 - t) * -1.2,
              child: Transform.scale(scale: .5 + .5 * t, child: c),
            ),
          ),
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
    // Standing: one button to sit down again.
    if (_standing) {
      return Stack(
        children: [
          Positioned(
            left: rightEdge,
            top: top,
            child: KeyedSubtree(
              key: const ValueKey('sit-btn'),
              child: _btn(
                'SIT DOWN',
                Icons.event_seat_rounded,
                const Color(0xFFE09A12),
                true,
                _sit,
                bw * 1.15,
                bh,
              ),
            ),
          ),
        ],
      );
    }
    // Otherwise only while it is your turn.
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

  Widget _dialogButton(String label, Color colour, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE28A), width: 1.5),
          ),
          child: Text(label, style: _text(14)),
        ),
      );

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
            if (actions.length > 2)
              for (final (label, colour, onTap) in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _dialogButton(label, colour, onTap),
                )
            else
              Row(
                children: [
                  for (final (label, colour, onTap) in actions)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _dialogButton(label, colour, onTap),
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

/// A card that starts face down and turns over after [after] milliseconds
/// (at once with [instant]).
class _FlipIn extends StatefulWidget {
  const _FlipIn({
    required this.card,
    required this.width,
    required this.after,
    this.instant = false,
  });
  final PlayingCard card;
  final double width;
  final int after;
  final bool instant;

  @override
  State<_FlipIn> createState() => _FlipInState();
}

class _FlipInState extends State<_FlipIn> {
  late bool _up = widget.instant;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!_up) {
      _timer = Timer(Duration(milliseconds: widget.after), () {
        if (mounted) setState(() => _up = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _CardView(card: widget.card, faceUp: _up, width: widget.width);
}

/// A ring that is full at 1 and empties clockwise to 0.
class _RingPainter extends CustomPainter {
  const _RingPainter(this.left);
  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.width * .06);
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .075
        ..color = const Color(0x33FFFFFF),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * left,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .075
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [Color(0xFFFFF1B8), Color(0xFFE3B341), Color(0xFFFFD45F)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.left != left;
}

/// The five places for the community cards: a sunken, card-sized pocket
/// with a dashed gold edge and a faint suit, and FLOP, TURN and RIVER
/// written under them, so it is plain where the cards will land.
class _SlotsPainter extends CustomPainter {
  const _SlotsPainter(this.slots);
  final List<Rect> slots;

  static const _suits = [0, 1, 3, 2, 0];

  static void _dashed(Canvas canvas, RRect rr, Paint paint, double dash) {
    for (final m in (Path()..addRRect(rr)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash * 1.8) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < slots.length; i++) {
      final r = slots[i];
      final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * .12));
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66000000), Color(0x26000000)],
          ).createShader(r),
      );
      // A lit lower lip, so the pocket looks sunk into the felt.
      canvas.drawRRect(
        rr.shift(const Offset(0, 1.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x22FFFFFF),
      );
      _dashed(
        canvas,
        rr.deflate(1.4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, r.width * .016)
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xBBFFD45F),
        r.width * .07,
      );
      _CardPainter._suit(
        canvas,
        _suits[i % _suits.length],
        r.center,
        r.width * .4,
        const Color(0x22FFFFFF),
      );
    }
    if (slots.length < 5) return;
    void caption(String text, Rect a, Rect b) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w600,
            fontSize: math.max(8.0, a.width * .15),
            letterSpacing: 2,
            color: const Color(0x88FFE295),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = a.bottom + a.width * .14, cx = (a.left + b.right) / 2;
      final line = Paint()
        ..color = const Color(0x44FFD45F)
        ..strokeWidth = 1;
      final gap = tp.width / 2 + 7;
      canvas.drawLine(Offset(a.left, y), Offset(cx - gap, y), line);
      canvas.drawLine(Offset(cx + gap, y), Offset(b.right, y), line);
      tp.paint(canvas, Offset(cx - tp.width / 2, y - tp.height / 2));
    }

    caption('FLOP', slots[0], slots[2]);
    caption('TURN', slots[3], slots[3]);
    caption('RIVER', slots[4], slots[4]);
  }

  @override
  bool shouldRepaint(_SlotsPainter old) =>
      old.slots.length != slots.length ||
      (slots.isNotEmpty && old.slots.first != slots.first);
}

/// An empty chair: a dark disc with a dashed gold ring and a plus.
class _EmptySeatPainter extends CustomPainter {
  const _EmptySeatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF3A1A5A), Color(0xFF14052B)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final ring = Path()..addOval(Rect.fromCircle(center: c, radius: r * .93));
    for (final m in ring.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 22) {
        canvas.drawPath(
          m.extractPath(d, math.min(d + 12, m.length)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .06
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xCCFFD45F),
        );
      }
    }
    final plus = Paint()
      ..strokeWidth = r * .12
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD45F);
    canvas.drawLine(c + Offset(-r * .3, 0), c + Offset(r * .3, 0), plus);
    canvas.drawLine(c + Offset(0, -r * .3), c + Offset(0, r * .3), plus);
  }

  @override
  bool shouldRepaint(_EmptySeatPainter old) => false;
}
