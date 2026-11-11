import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../art/icons.dart';
import '../game/carrom_game.dart';
import '../game/coins.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../widgets/game_hud.dart';

const _pieceAsset = {
  PieceKind.white: 'assets/images/carrom/white.png',
  PieceKind.black: 'assets/images/carrom/black.png',
  PieceKind.queen: 'assets/images/carrom/queen.png',
  PieceKind.striker: 'assets/images/carrom/striker.png',
};

/// A carrom match. Slide the striker along your line, pull back anywhere on
/// the board to aim and set the power, let go to shoot.
class CarromScreen extends StatefulWidget {
  const CarromScreen({
    super.key,
    required this.seats,
    required this.bots,
    required this.names,
    this.entry = 1000,
    this.roomId = '000000',
  });

  final List<int> seats;
  final Set<int> bots;
  final Map<int, String> names;
  final int entry;
  final String roomId;

  /// The match on screen, for widget tests.
  @visibleForTesting
  static CarromGame? debugGame;

  @override
  State<CarromScreen> createState() => _CarromScreenState();
}

class _CarromScreenState extends State<CarromScreen>
    with SingleTickerProviderStateMixin {
  late CarromGame _game;
  late final Ticker _ticker;
  final _frame = ValueNotifier(0);
  Duration _last = Duration.zero;

  /// Seat shown at the bottom of the screen, and the board's rotation.
  int _viewSeat = 0;
  double _turns = 0;

  // Aiming: where the finger went down and where it is now (board units).
  Offset? _dragFrom, _dragTo;
  Timer? _botTimer;
  double _lastHit = 0, _clock = 0;
  String _note = '';
  Timer? _noteTimer;

  int get _prize => widget.entry * widget.seats.length;
  bool get _humanTurn =>
      !_game.isBot(_game.current) && !_game.moving && _game.winner == null;

  @override
  void initState() {
    super.initState();
    _newGame();
    _ticker = createTicker(_onTick)..start();
  }

  void _newGame() {
    _game = CarromGame(seats: widget.seats, bots: widget.bots);
    CarromScreen.debugGame = _game;
    _dragFrom = _dragTo = null;
    _note = '';
    Sounds.play(Sfx.start);
    _afterTurn();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _noteTimer?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, .034);
    _last = elapsed;
    _clock += dt;
    final wasMoving = _game.moving;
    final ev = _game.step(dt);
    if (ev.hit > .12 && _clock - _lastHit > .07) {
      _lastHit = _clock;
      Sounds.play(Sfx.hit);
    }
    if (ev.pocketed > 0) {
      Sounds.play(Sfx.pocket);
      HapticFeedback.mediumImpact();
    }
    if (wasMoving && !_game.moving) _onRest();
    _frame.value++;
  }

  void _say(String text) {
    _noteTimer?.cancel();
    setState(() => _note = text);
    _noteTimer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _note = '');
    });
  }

  void _onRest() {
    final shooter = _game.current;
    final r = _game.finishShot();
    final name = shortName(widget.names[shooter] ?? 'Player');
    if (r.winner != null) {
      Sounds.play(Sfx.win);
    } else if (r.foul) {
      Sounds.play(Sfx.lifeLost);
      _say('Foul! Striker pocketed');
    } else if (r.covered) {
      Sounds.play(Sfx.bonus);
      _say('$name covered the Queen!');
    } else if (r.queenReturned) {
      _say('Queen not covered — back to centre');
    } else if (r.queen) {
      Sounds.play(Sfx.rank);
      _say('Queen! Pocket a coin to cover it');
    } else if (r.own > 0) {
      Sounds.play(Sfx.home);
    }
    _afterTurn();
  }

  /// Turns the board to the next human, or lets the computer play.
  void _afterTurn() {
    final seat = _game.current;
    if (_game.winner == null && !_game.isBot(seat) && seat != _viewSeat) {
      // Always spin the short way round.
      var d = (seat - _viewSeat) % 4;
      if (d == 3) d = -1;
      _turns += d / 4;
      _viewSeat = seat;
    }
    if (mounted) setState(() {});
    _botTimer?.cancel();
    if (_game.winner == null && _game.isBot(seat)) {
      _botTimer = Timer(const Duration(milliseconds: 900), _botPlay);
    }
  }

  void _botPlay() {
    if (!mounted || _game.moving || _game.winner != null) return;
    final shot = _game.botShot();
    _game.placeStriker(shot.t);
    setState(() {});
    _botTimer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      if (!_game.shoot(shot.direction, shot.power)) {
        // The spot was blocked after all: try another.
        _game.placeStriker(_game.rng.nextDouble());
        _botTimer = Timer(const Duration(milliseconds: 200), _botPlay);
      }
    });
  }

  // ── Aiming ──

  /// Shot direction (board units) and power 0..1 from the current pull.
  (Offset, double)? get _aim {
    final a = _dragFrom, b = _dragTo;
    if (a == null || b == null) return null;
    final pull = a - b; // slingshot: shoot away from the pull
    final len = pull.distance;
    if (len < .015) return null;
    return (pull / len, ((len - .015) / .30).clamp(0.0, 1.0));
  }

  void _release() {
    final aim = _aim;
    setState(() => _dragFrom = _dragTo = null);
    if (aim == null || !_humanTurn) return;
    if (!_game.strikerFree) return _say('Move the striker off the coin');
    if (_game.shoot(aim.$1, aim.$2)) Sounds.play(Sfx.tap);
  }

  Future<void> _confirmLeave() async {
    if (_game.winner != null) return Navigator.of(context).pop();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Leave game?', style: AppText.title.copyWith(fontSize: 22)),
        content: Text('Your current match will be lost.',
            style: AppText.title.copyWith(
                fontSize: 15, fontWeight: FontWeight.w400, height: 1.3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay', style: TextStyle(color: AppColors.cream)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Leave', style: TextStyle(color: AppColors.goldSoft)),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: LudoBackdrop(
          child: SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final board = math.min(
                  math.min(box.maxWidth, 520.0) - 8, box.maxHeight - 300);
              return Stack(
                children: [
                  Column(
                    children: [
                      GameHeader(
                        prize: _prize,
                        entry: widget.entry,
                        roomId: widget.roomId,
                        onBack: _confirmLeave,
                      ),
                      const SizedBox(height: 8),
                      _scoreBar(),
                      const Spacer(),
                      _board(board),
                      const Spacer(),
                      _controls(board),
                      const SizedBox(height: 10),
                    ],
                  ),
                  if (_game.winner != null)
                    Positioned.fill(child: _result()),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _scoreBar() {
    Widget side(int team) {
      final seats = [for (final s in widget.seats) if (_game.teamOf(s) == team) s];
      final active = _game.team == team && _game.winner == null;
      final right = team == 1;
      final coin = Image.asset(_pieceAsset[_game.colourOf(team)]!,
          width: 30, height: 30);
      final info = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment:
            right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          for (final s in seats)
            Text(
              shortName(widget.names[s] ?? 'Player', 10),
              style: AppText.title.copyWith(
                fontSize: seats.length > 1 ? 11.5 : 14,
                height: 1.15,
                color: _game.current == s && _game.winner == null
                    ? AppColors.goldSoft
                    : AppColors.cream,
              ),
            ),
        ],
      );
      final score = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_game.pocketed[team]}',
              style: AppText.title.copyWith(fontSize: 22, height: 1)),
          Text('/9',
              style: AppText.title.copyWith(
                  fontSize: 12, color: const Color(0xFF9EA9DC))),
          if (_game.queenOwner == team || _game.queenPending == team) ...[
            const SizedBox(width: 4),
            Opacity(
              opacity: _game.queenOwner == team ? 1 : .55,
              child: Image.asset(_pieceAsset[PieceKind.queen]!,
                  width: 18, height: 18),
            ),
          ],
        ],
      );
      final children = [coin, const SizedBox(width: 7), Expanded(child: info), score];
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE62E3380), Color(0xE612143F)],
            ),
            border: Border.all(
              color: active ? AppColors.goldSoft : const Color(0xFF5A61AE),
              width: active ? 2 : 1.2,
            ),
            boxShadow: [
              if (active) const BoxShadow(color: Color(0x99EBCB7A), blurRadius: 12),
            ],
          ),
          child: Row(children: right ? children.reversed.toList() : children),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [side(0), const SizedBox(width: 8), side(1)]),
    );
  }

  Widget _board(double size) {
    return AnimatedRotation(
      turns: _turns,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          if (!_humanTurn) return;
          setState(() => _dragFrom = _dragTo = d.localPosition / size);
        },
        onPanUpdate: (d) {
          if (_dragFrom != null) {
            setState(() => _dragTo = d.localPosition / size);
          }
        },
        onPanEnd: (_) => _release(),
        onPanCancel: () => setState(() => _dragFrom = _dragTo = null),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset('assets/images/carrom/board.png',
                    fit: BoxFit.fill, filterQuality: FilterQuality.medium),
              ),
              Positioned.fill(
                child: ValueListenableBuilder(
                  valueListenable: _frame,
                  builder: (_, _, _) => Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TablePainter(
                            game: _game,
                            aim: _humanTurn ? _aim : null,
                            ready: _humanTurn,
                            time: _clock,
                          ),
                        ),
                      ),
                      for (final p in _game.pieces)
                        if (!p.pocketed || p.sink < .22)
                          () {
                            // A pocketed piece shrinks away into the hole.
                            final k = p.pocketed
                                ? (1 - p.sink / .22).clamp(0.0, 1.0)
                                : 1.0;
                            final d = p.radius * 2 * size * k;
                            return Positioned(
                              left: p.pos.dx * size - d / 2,
                              top: p.pos.dy * size - d / 2,
                              width: d,
                              height: d,
                              child: Image.asset(_pieceAsset[p.kind]!,
                                  filterQuality: FilterQuality.medium),
                            );
                          }(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Power meter, the striker slider and a line of help or news.
  Widget _controls(double width) {
    final aim = _humanTurn ? _aim : null;
    final power = aim?.$2 ?? 0;
    final bot = _game.winner == null && _game.isBot(_game.current);
    final hint = _note.isNotEmpty
        ? _note
        : bot
            ? '${shortName(widget.names[_game.current] ?? 'Computer')} is playing…'
            : aim != null
                ? 'Power ${(power * 100).round()}%'
                : 'Slide to place • pull back on the board to shoot';
    return SizedBox(
      width: width - 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 18,
            child: Text(hint,
                maxLines: 1,
                style: AppText.title.copyWith(
                    fontSize: 12.5,
                    color: _note.isNotEmpty
                        ? AppColors.goldSoft
                        : const Color(0xFFC9CFF5))),
          ),
          const SizedBox(height: 6),
          // Power meter.
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xCC0F1136),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF5A61AE)),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: power.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(colors: [
                    Color(0xFF45E3A6),
                    Color(0xFFFFD23A),
                    Color(0xFFFF4D4D),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _StrikerSlider(
            value: _game.strikerT,
            enabled: _humanTurn,
            blocked: !_game.strikerFree,
            onChanged: (t) => setState(() => _game.placeStriker(t)),
          ),
        ],
      ),
    );
  }

  Widget _result() {
    final team = _game.winner!;
    final names = [
      for (final s in widget.seats)
        if (_game.teamOf(s) == team) widget.names[s] ?? 'Player',
    ];
    final you = names.contains('You');
    return ColoredBox(
      color: const Color(0xC7080920),
      child: Center(
        child: Container(
          width: 290,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.cardTop, AppColors.cardBottom],
            ),
            border: Border.all(color: AppColors.goldSoft, width: 2.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Art(ArtKind.trophy, size: 92),
              const SizedBox(height: 6),
              Text(
                you
                    ? (names.length > 1 ? 'Your team wins!' : 'You win!')
                    : '${names.map((n) => shortName(n, 10)).join(' & ')} ${names.length > 1 ? 'win' : 'wins'}!',
                textAlign: TextAlign.center,
                style: AppText.title
                    .copyWith(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${_game.winnerScore} points'
                '${_game.queenOwner == team ? ' (with the Queen)' : ''}',
                style: AppText.title
                    .copyWith(fontSize: 14.5, color: const Color(0xFFC9CFF5)),
              ),
              const SizedBox(height: 4),
              Text('+${formatCoins(_prize)}',
                  style: AppText.title.copyWith(
                      fontSize: 20, color: const Color(0xFFFFE28A))),
              const SizedBox(height: 14),
              _wide('Play again', true, () => setState(_newGame)),
              const SizedBox(height: 10),
              _wide('Home', false, () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wide(String label, bool filled, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: filled
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: AppColors.goldGradient,
                  )
                : null,
            border: filled
                ? null
                : Border.all(color: AppColors.cardBorder, width: 1.5),
          ),
          child: Text(label,
              style: AppText.title.copyWith(
                  fontSize: 16.5,
                  color: filled ? const Color(0xFF3A2500) : AppColors.cream)),
        ),
      );
}

/// Shadows under the pieces, the glow around a ready striker and the aim
/// guide, all in board coordinates.
class _TablePainter extends CustomPainter {
  const _TablePainter({
    required this.game,
    required this.aim,
    required this.ready,
    required this.time,
  });
  final CarromGame game;
  final (Offset, double)? aim;
  final bool ready;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final shadow = Paint()
      ..color = const Color(0x59000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .006);
    for (final p in game.pieces) {
      if (p.pocketed) continue;
      canvas.drawCircle(
          (p.pos + const Offset(.004, .006)) * s, p.radius * s, shadow);
    }
    if (!ready) return;
    final at = game.striker.pos * s, r = Carrom.strikerR * s;
    final free = game.strikerFree;
    // A breathing ring shows whose striker is live (red if it is blocked).
    canvas.drawCircle(
      at,
      r * (1.25 + .08 * math.sin(time * 5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .16
        ..color = (free ? const Color(0xFFFFE28A) : const Color(0xFFFF4D4D))
            .withValues(alpha: .9),
    );
    final a = aim;
    if (a == null) return;
    final (dir, power) = a;
    // Dotted guide, then a solid arrow whose length is the power.
    final dot = Paint()..color = const Color(0xCCFFFFFF);
    for (var i = 1; i <= 16; i++) {
      canvas.drawCircle(at + dir * (r + i * s * .028), s * .0045, dot);
    }
    final tip = at + dir * (r + s * (.05 + .22 * power));
    final line = Paint()
      ..strokeWidth = s * .012
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(
          const Color(0xFF45E3A6), const Color(0xFFFF4D4D), power)!;
    canvas.drawLine(at + dir * r, tip, line);
    final side = Offset(-dir.dy, dir.dx);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx + dir.dx * s * .03, tip.dy + dir.dy * s * .03)
        ..lineTo(tip.dx + side.dx * s * .018, tip.dy + side.dy * s * .018)
        ..lineTo(tip.dx - side.dx * s * .018, tip.dy - side.dy * s * .018)
        ..close(),
      Paint()..color = line.color,
    );
    // The pull-back band behind the striker.
    canvas.drawLine(
      at,
      at - dir * (s * .30 * power + r),
      Paint()
        ..strokeWidth = s * .006
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x99FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_TablePainter old) => true;
}

/// Slides the striker along the baseline.
class _StrikerSlider extends StatelessWidget {
  const _StrikerSlider({
    required this.value,
    required this.enabled,
    required this.blocked,
    required this.onChanged,
  });
  final double value;
  final bool enabled, blocked;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    const thumb = 46.0;
    return LayoutBuilder(builder: (context, box) {
      final track = box.maxWidth - thumb;
      void move(Offset local) =>
          onChanged(((local.dx - thumb / 2) / track).clamp(0.0, 1.0));
      return Opacity(
        opacity: enabled ? 1 : .45,
        child: GestureDetector(
          key: const ValueKey('striker-slider'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled ? (d) => move(d.localPosition) : null,
          onHorizontalDragUpdate: enabled ? (d) => move(d.localPosition) : null,
          onTapDown: enabled ? (d) => move(d.localPosition) : null,
          child: SizedBox(
            height: thumb + 4,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0F1136), Color(0xFF2E3380)],
                    ),
                    border: Border.all(color: AppColors.goldTrim, width: 1.4),
                  ),
                ),
                Positioned(
                  left: value * track,
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: blocked
                              ? const Color(0xCCFF4D4D)
                              : const Color(0xAAEBCB7A),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Image.asset(_pieceAsset[PieceKind.striker]!),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
