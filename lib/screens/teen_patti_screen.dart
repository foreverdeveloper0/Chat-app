import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/coins.dart';
import '../game/sounds.dart';
import '../game/teen_patti.dart';
import '../theme/app_colors.dart';
import '../widgets/game_hud.dart';

/// Play chips for the card table. They last while the app is open.
abstract final class PokerWallet {
  static int chips = 50000;
  static const freeChips = 10000;
}

/// Teen Patti at a table of two to five: you and computer players.
class TeenPattiScreen extends StatefulWidget {
  const TeenPattiScreen({
    super.key,
    required this.boot,
    required this.buyIn,
    this.players = 5,
  });

  final int boot, buyIn, players;

  @visibleForTesting
  static TeenPatti? debugGame;

  @override
  State<TeenPattiScreen> createState() => _TeenPattiScreenState();
}

class _TeenPattiScreenState extends State<TeenPattiScreen> {
  late TeenPatti _game;
  final _timers = <Timer>[];
  final _chips = <_FlyingChip>[];
  int _chipId = 0;
  Size _size = Size.zero;

  /// Cards are dealt face down; the hand starts once they have landed.
  bool _dealing = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    PokerWallet.chips -= widget.buyIn;
    _game = TeenPatti(
      boot: widget.boot,
      buyIn: widget.buyIn,
      players: widget.players,
    );
    TeenPattiScreen.debugGame = _game;
    _later(500, _deal);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _cashOut();
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
    if (_game.you.chips < _game.boot) {
      _outOfChips();
      return;
    }
    _game.rebuyBots();
    setState(() {
      _game.deal();
      _dealing = true;
    });
    Sounds.play(Sfx.diceRoll);
    for (final s in _game.seats.where((s) => s.inHand)) {
      _fly(s.index, toPot: true);
    }
    _later(1300, () {
      setState(() => _dealing = false);
      _advance();
    });
  }

  /// Moves the hand on: the result, a question for you, a computer
  /// player's turn, or yours.
  void _advance() {
    final g = _game;
    if (!g.playing) {
      _finish();
      return;
    }
    if (g.sideShowAsk != null) {
      _askSideShow(g.sideShowAsk!);
      return;
    }
    final s = g.current;
    if (!s.bot) {
      HapticFeedback.selectionClick();
      Sounds.play(Sfx.turn);
      return;
    }
    _later(850 + math.Random().nextInt(700), () {
      final events = g.botTurn();
      setState(() {});
      for (final e in events) {
        _react(e);
      }
      _later(350, _advance);
    });
  }

  /// Sound and chips for a move.
  void _react(TableEvent e) {
    switch (e.move) {
      case Move.pack:
        Sounds.play(Sfx.tap);
      case Move.see:
        Sounds.play(Sfx.diceLand);
      case Move.bet || Move.raise || Move.show || Move.sideShow:
        if (e.amount > 0) {
          _fly(e.seat, toPot: true);
          Sounds.play(Sfx.pocket);
        }
    }
  }

  void _finish() {
    final r = _game.result!;
    setState(() {});
    final won = !r.winner.bot;
    _later(700, () {
      for (var i = 0; i < 6; i++) {
        _later(i * 70, () => _fly(r.winner.index, toPot: false));
      }
      Sounds.play(won ? Sfx.win : Sfx.rank);
      if (won) HapticFeedback.heavyImpact();
    });
    _later(r.revealed.isEmpty ? 2600 : 4200, _deal);
  }

  void _act(TableEvent Function() move) {
    final g = _game;
    if (!g.playing || _dealing || g.current.bot || g.sideShowAsk != null) {
      return;
    }
    final e = move();
    setState(() {});
    _react(e);
    // Looking at your cards does not use up the turn.
    if (e.move != Move.see) _later(350, _advance);
  }

  Future<void> _askSideShow(Seat asker) async {
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => _Dialog(
        title: 'Side show?',
        body:
            '${asker.name} wants to compare cards with you. '
            'The weaker hand packs.',
        actions: [
          ('REFUSE', const Color(0xFFC0392B), () => Navigator.pop(d, false)),
          ('ACCEPT', const Color(0xFF1FA35C), () => Navigator.pop(d, true)),
        ],
      ),
    );
    if (!mounted) return;
    final out = _game.answerSideShow(accept ?? false);
    setState(() {});
    if (out != null) Sounds.play(out.bot ? Sfx.bonus : Sfx.lifeLost);
    _later(500, _advance);
  }

  Future<void> _outOfChips() async {
    final stay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => _Dialog(
        title: 'Out of chips',
        body:
            'You need at least ${formatCoins(_game.boot)} for the boot. '
            'Take ${formatCoins(PokerWallet.freeChips)} free chips and '
            'keep playing?',
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

  /// Where each seat's avatar sits: you at the bottom, the others round
  /// the sides.
  Offset _spot(int seat) {
    final w = _size.width, h = _size.height;
    if (seat == 0) return Offset(w * .5, h * .725);
    final spots = switch (_game.seats.length) {
      2 => const [(.87, .33)],
      3 => const [(.13, .33), (.87, .33)],
      4 => const [(.13, .51), (.13, .33), (.87, .33)],
      _ => const [(.13, .51), (.13, .33), (.87, .33), (.87, .51)],
    };
    final (x, y) = spots[seat - 1];
    return Offset(w * x, h * y);
  }

  Offset get _potAt => Offset(_size.width * .5, _size.height * .43);
  Offset get _dealerAt => Offset(_size.width * .5, _size.height * .2);

  void _fly(int seat, {required bool toPot}) {
    if (!mounted || _size == Size.zero) return;
    final at = _spot(seat);
    setState(() {
      _chips.add(
        _FlyingChip(_chipId++, toPot ? at : _potAt, toPot ? _potAt : at),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C0838),
      body: LayoutBuilder(
        builder: (context, box) {
          _size = box.biggest;
          final w = _size.width, h = _size.height;
          final g = _game;
          return Stack(
            fit: StackFit.expand,
            children: [
              const RepaintBoundary(
                child: CustomPaint(painter: _TablePainter()),
              ),
              // The dealer, behind the table's top edge.
              Positioned(
                left: w * .24,
                width: w * .52,
                top: h * .215 - w * .52 * 312 / 420,
                child: Image.asset('assets/images/poker/dealer.png'),
              ),
              _pot(g),
              for (final s in g.seats) ..._seat(s),
              ..._yourCards(g),
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
                      left: p.dx - 11,
                      top: p.dy - 11 - math.sin(t * math.pi) * 26,
                      child: child!,
                    );
                  },
                  child: const _Chip(size: 22),
                ),
              if (g.result != null) _resultBanner(g.result!),
              SafeArea(child: _topBar(g)),
              SafeArea(child: _actions(g)),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar(TeenPatti g) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RoundButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
        const Spacer(),
        _pill(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Chip(size: 18),
              const SizedBox(width: 6),
              Text(
                formatCoins(g.you.chips),
                key: const ValueKey('my-chips'),
                style: _text(15),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _pill(Text('BOOT ${formatCoins(g.boot)}', style: _text(13))),
      ],
    ),
  );

  Widget _pot(TeenPatti g) => Positioned(
    left: 0,
    right: 0,
    top: _size.height * .43 - 34,
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < math.min(5, 1 + g.pot ~/ (g.boot * 8)); i++)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: _Chip(size: 20),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xAA06240F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.goldTrim, width: 1.2),
          ),
          child: Text(
            'POT  ${formatCoins(g.pot)}',
            key: const ValueKey('pot'),
            style: _text(16, const Color(0xFFFFE28A)),
          ),
        ),
        const SizedBox(height: 4),
        if (g.playing)
          Text(
            'Blind ${formatCoins(g.stake)}  ·  Chaal ${formatCoins(g.stake * 2)}',
            style: _text(11, const Color(0xCCFFFFFF), FontWeight.w500),
          ),
      ],
    ),
  );

  /// A seat: avatar, name, chips, what they last did, and (for the
  /// computer players) their three cards.
  List<Widget> _seat(Seat s) {
    final g = _game;
    final at = _spot(s.index);
    final turn = g.playing && !_dealing && g.turn == s.index;
    final winner = g.result?.winner == s;
    final left = at.dx < _size.width / 2;
    const r = 27.0;
    final colours = const [
      Color(0xFF7FD8FF),
      Color(0xFFFF7AA8),
      Color(0xFF7CFFCB),
      Color(0xFFFFB86B),
      Color(0xFFC79BFF),
    ];
    final reveal = g.result?.revealed.contains(s) ?? false;
    return [
      Positioned(
        left: at.dx - 46,
        top: at.dy - r - 2,
        width: 92,
        child: Opacity(
          opacity: s.packed || !s.inHand ? .45 : 1,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: r * 2,
                height: r * 2,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color.lerp(colours[s.index], Colors.white, .3)!,
                      Color.lerp(colours[s.index], Colors.black, .45)!,
                    ],
                  ),
                  border: Border.all(
                    color: turn || winner
                        ? const Color(0xFFFFF1B8)
                        : AppColors.goldTrim,
                    width: turn || winner ? 3.5 : 2,
                  ),
                  boxShadow: [
                    if (turn || winner)
                      const BoxShadow(
                        color: Color(0xCCFFD45A),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: Text(
                  s.name.characters.first,
                  style: _text(24, const Color(0xFF1C0838)),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xEE2A0F45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.goldTrim, width: 1.2),
                  ),
                  child: Column(
                    children: [
                      Text(shortName(s.name, 8), style: _text(11.5)),
                      Text(
                        formatCoins(s.chips),
                        style: _text(11, const Color(0xFFFFE28A)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Dealer button.
      if (g.dealer == s.index)
        Positioned(
          left: at.dx + (left ? -r - 8 : r - 10),
          top: at.dy - r - 6,
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Text('D', style: _text(11, const Color(0xFF1C0838))),
          ),
        ),
      // What they last did.
      if (s.lastAction.isNotEmpty && s.inHand)
        Positioned(
          // Yours sits beside you, clear of your cards.
          left: at.dx - 50 + (s.index == 0 ? 84 : 0),
          width: 100,
          top: s.index == 0 ? at.dy - 10 : at.dy - r - 24,
          child: Center(
            child: Container(
              key: ValueKey('action-${s.index}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: s.packed
                    ? const Color(0xDD5A1A1A)
                    : const Color(0xDD0E1440),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(s.lastAction, style: _text(10.5)),
            ),
          ),
        ),
      // Computer players' cards, towards the middle of the table.
      if (s.bot && s.inHand)
        for (var i = 0; i < s.cards.length; i++)
          _dealt(
            key: 'c-${g.hands}-${s.index}-$i',
            order: s.index * 3 + i,
            to: Offset(at.dx + (left ? 44 : -44 - 56) + i * 16, at.dy - 20),
            child: Opacity(
              opacity: s.packed ? .4 : 1,
              child: _CardView(card: s.cards[i], faceUp: reveal, width: 28),
            ),
          ),
      if (s.bot && s.active && g.playing)
        Positioned(
          left: at.dx + (left ? 44 : -44 - 56),
          width: 60,
          top: at.dy + 22,
          child: Center(
            child: Text(
              s.seen ? 'SEEN' : 'BLIND',
              style: _text(
                9.5,
                s.seen ? const Color(0xFF7CFFCB) : const Color(0xFFFFE28A),
              ),
            ),
          ),
        ),
      if (reveal && s.bot)
        Positioned(
          left: at.dx + (left ? 30 : -30 - 88),
          width: 88,
          top: at.dy + 22,
          child: Center(child: _handTag(s)),
        ),
    ];
  }

  Widget _handTag(Seat s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xEE0E1440),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.goldTrim),
    ),
    child: Text(s.hand.rank.label, style: _text(10, const Color(0xFFFFE28A))),
  );

  /// Your three cards, large, in front of you.
  List<Widget> _yourCards(TeenPatti g) {
    final you = g.you;
    if (!you.inHand) return const [];
    final w = _size.width, h = _size.height;
    const cw = 58.0;
    final faceUp = you.seen || (g.result?.revealed.contains(you) ?? false);
    return [
      for (var i = 0; i < you.cards.length; i++)
        _dealt(
          key: 'c-${g.hands}-0-$i',
          order: i,
          to: Offset(w / 2 - cw * 1.5 - 6 + i * (cw + 6), h * .575),
          child: GestureDetector(
            onTap: () {
              if (!you.seen) _act(() => g.see(you));
            },
            child: Opacity(
              opacity: you.packed ? .45 : 1,
              child: _CardView(card: you.cards[i], faceUp: faceUp, width: cw),
            ),
          ),
        ),
      if (faceUp)
        Positioned(
          left: 0,
          right: 0,
          top: h * .575 - 22,
          child: Center(child: _handTag(you)),
        ),
    ];
  }

  /// A card that flies in from the dealer when the hand is dealt.
  Widget _dealt({
    required String key,
    required int order,
    required Offset to,
    required Widget child,
  }) {
    const total = 1100.0;
    final start = (order * 55 / total).clamp(0.0, .7);
    return TweenAnimationBuilder<double>(
      key: ValueKey(key),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
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

  Widget _resultBanner(Showdown r) {
    final won = !r.winner.bot;
    return Positioned(
      left: 0,
      right: 0,
      top: _size.height * .43 - 34,
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey('result-${_game.hands}'),
          tween: Tween(begin: .6, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          builder: (context, s, c) => Transform.scale(scale: s, child: c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: won
                    ? const [Color(0xFF1FA35C), Color(0xFF0E6B3A)]
                    : const [Color(0xFF3A2AA0), Color(0xFF1B1460)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE28A), width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x99000000), blurRadius: 12),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  won ? 'YOU WIN!' : '${r.winner.name} wins',
                  key: const ValueKey('result'),
                  style: _text(20, const Color(0xFFFFE28A)),
                ),
                Text('+${formatCoins(r.pot)}', style: _text(16)),
                Text(
                  r.revealed.isEmpty
                      ? r.reason
                      : '${r.winner.hand.rank.label}  ·  ${r.reason}',
                  style: _text(10.5, const Color(0xCCFFFFFF), FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(TeenPatti g) {
    final you = g.you;
    final mine = g.playing && !_dealing && g.turn == 0 && g.sideShowAsk == null;
    final String status;
    if (!g.playing) {
      status = g.result == null ? 'Dealing…' : 'Next hand coming up…';
    } else if (_dealing) {
      status = 'Dealing…';
    } else if (you.packed) {
      status = 'You packed. Watching the hand…';
    } else if (!you.inHand) {
      status = 'Sitting out this hand';
    } else if (mine) {
      status = you.seen ? 'Your turn' : 'Your turn — tap your cards to see';
    } else {
      status = "${g.current.name}'s turn…";
    }
    final call = g.callFor(you), raise = g.raiseFor(you);
    final target = mine ? g.sideShowTarget(you) : null;
    final short = you.chips < call;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status,
              key: const ValueKey('status'),
              style: _text(12.5, const Color(0xFFE8D9FF), FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _btn('PACK', const Color(0xFFC0392B), mine, () {
                  _act(() => g.pack(you));
                }),
                if (!you.seen)
                  _btn('SEE', const Color(0xFF2E6BE0), mine, () {
                    _act(() => g.see(you));
                  }),
                if (target != null)
                  _btn('SIDE SHOW', const Color(0xFF8E44AD), mine, () {
                    _act(() => g.sideShow(you));
                  }),
                if (g.playing && g.canShow(you))
                  _btn(
                    'SHOW ${formatCoins(math.min(call, you.chips))}',
                    const Color(0xFFE67E22),
                    mine,
                    () => _act(() => g.show(you)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _btn(
                  short
                      ? 'ALL IN ${formatCoins(you.chips)}'
                      : '${you.seen ? 'CHAAL' : 'BLIND'} ${formatCoins(call)}',
                  const Color(0xFF1FA35C),
                  mine,
                  () => _act(() => g.bet(you)),
                  big: true,
                ),
                _btn(
                  'RAISE ${formatCoins(raise)}',
                  const Color(0xFFD4A017),
                  mine && g.playing && g.canRaise(you),
                  () => _act(() => g.bet(you, raise: true)),
                  big: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(
    String label,
    Color colour,
    bool enabled,
    VoidCallback onTap, {
    bool big = false,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : .35,
          child: Container(
            height: big ? 50 : 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(colour, Colors.white, .22)!,
                  colour,
                  Color.lerp(colour, Colors.black, .3)!,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFE28A), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 5,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(label, style: _text(big ? 15.5 : 13.5)),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _pill(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xDD2A0F45),
      borderRadius: BorderRadius.circular(16),
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

/// The room and the table: purple walls with glowing arcs, a wooden and
/// gold rim, and green felt.
class _TablePainter extends CustomPainter {
  const _TablePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final all = Offset.zero & size;
    canvas.drawRect(
      all,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.25),
          radius: 1.1,
          colors: [Color(0xFF6A1FA8), Color(0xFF3A0F6B), Color(0xFF14052B)],
          stops: [0, .55, 1],
        ).createShader(all),
    );
    // Faint suit pattern on the wall.
    final rnd = math.Random(3);
    for (var y = 0.0; y < h; y += 46) {
      for (var x = (y ~/ 46).isEven ? 0.0 : 23.0; x < w; x += 46) {
        _CardPainter._suit(
          canvas,
          rnd.nextInt(4),
          Offset(x + 10, y + 12),
          13,
          const Color(0x12FFFFFF),
        );
      }
    }
    // Glowing arcs in the corners.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final (cx, cy) in const [
      (0.0, 0.0),
      (1.0, 0.0),
      (0.0, 1.0),
      (1.0, 1.0),
    ]) {
      for (var i = 0; i < 2; i++) {
        arc.color = Color.fromRGBO(255, 150, 230, i == 0 ? .5 : .2);
        canvas.drawCircle(Offset(w * cx, h * cy), w * (.2 + i * .07), arc);
      }
    }

    final table = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * .05, h * .19, w * .95, h * .745),
      Radius.circular(w * .38),
    );
    // Purple glow under the table.
    canvas.drawRRect(
      table.inflate(10),
      Paint()
        ..color = const Color(0x88D04BFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    // Wood, then the gold rail, then felt.
    canvas.drawRRect(
      table,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A4A22), Color(0xFF4A2410), Color(0xFF7A3E1C)],
        ).createShader(table.outerRect),
    );
    final rail = table.deflate(w * .022);
    canvas.drawRRect(
      rail,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF1B8),
            Color(0xFFE3B341),
            Color(0xFF9A6A00),
            Color(0xFFFFD45A),
          ],
          stops: [0, .3, .75, 1],
        ).createShader(rail.outerRect),
    );
    final felt = rail.deflate(w * .02);
    canvas.drawRRect(
      felt,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.15),
          radius: .85,
          colors: [Color(0xFF2FB35A), Color(0xFF168A3C), Color(0xFF0A5A26)],
          stops: [0, .6, 1],
        ).createShader(felt.outerRect),
    );
    // Shadow just inside the rail, and a betting line.
    canvas.drawRRect(
      felt.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = const Color(0x33000000),
    );
    canvas.drawRRect(
      felt.deflate(w * .07),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x44FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_TablePainter old) => false;
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
