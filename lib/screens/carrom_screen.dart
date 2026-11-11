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

  /// Recent striker positions while it is moving, for its light trail.
  final _trail = <Offset>[];

  /// Where and when the last shot was fired, for the launch burst.
  Offset? _burstAt;
  double _burstTime = -10;
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
    if (_game.moving && !_game.striker.pocketed) {
      _trail.add(_game.striker.pos);
      if (_trail.length > 14) _trail.removeAt(0);
    } else if (_trail.isNotEmpty) {
      _trail.removeAt(0);
    }
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
      if (_game.shoot(shot.direction, shot.power)) {
        _fired();
      } else {
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
    if (_game.shoot(aim.$1, aim.$2)) _fired();
  }

  void _fired() {
    _burstAt = _game.striker.pos;
    _burstTime = _clock;
    _trail.clear();
    Sounds.play(Sfx.hit);
    HapticFeedback.lightImpact();
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
              // Full width: the outer gold rim may run a hair past the
              // screen edges so the playing surface is as big as possible.
              final board = math.min(
                  math.min(box.maxWidth, 520.0) * 1.05, box.maxHeight - 250);
              return Stack(
                clipBehavior: Clip.hardEdge,
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
                      SizedBox(
                        width: box.maxWidth,
                        height: board,
                        child: OverflowBox(
                          maxWidth: board,
                          minWidth: board,
                          child: _board(board),
                        ),
                      ),
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
                            trail: _trail,
                            burstAt: _burstAt,
                            burstAge: _clock - _burstTime,
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
                            // While aiming, the striker eases back along the
                            // pull like a drawn slingshot.
                            final aim = _humanTurn ? _aim : null;
                            final at = p == _game.striker && aim != null
                                ? p.pos - aim.$1 * (aim.$2 * Carrom.strikerR * .55)
                                : p.pos;
                            return Positioned(
                              left: at.dx * size - d / 2,
                              top: at.dy * size - d / 2,
                              width: d,
                              height: d,
                              child: _Puck(kind: p.kind),
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

/// Shadows, the live-striker ring, the aim guide (with its predicted
/// bounce and first contact), the power dial, the launch burst and the
/// striker's light trail, all in board coordinates.
class _TablePainter extends CustomPainter {
  const _TablePainter({
    required this.game,
    required this.aim,
    required this.ready,
    required this.time,
    required this.trail,
    required this.burstAt,
    required this.burstAge,
  });
  final CarromGame game;
  final (Offset, double)? aim;
  final bool ready;
  final double time;
  final List<Offset> trail;
  final Offset? burstAt;
  final double burstAge;

  static const _cool = Color(0xFF45E3A6),
      _warm = Color(0xFFFFD23A),
      _hot = Color(0xFFFF4D4D);

  Color _powerColour(double p) => p < .5
      ? Color.lerp(_cool, _warm, p * 2)!
      : Color.lerp(_warm, _hot, (p - .5) * 2)!;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final shadow = Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .007);
    for (final p in game.pieces) {
      if (p.pocketed) continue;
      canvas.drawCircle(
          (p.pos + Offset(.003, p.radius * .45)) * s, p.radius * s * 1.05, shadow);
    }

    // Light trail behind a moving striker.
    for (var i = 0; i < trail.length; i++) {
      final k = (i + 1) / trail.length;
      canvas.drawCircle(
        trail[i] * s,
        Carrom.strikerR * s * (.35 + .6 * k),
        Paint()
          ..color = const Color(0xFF7FB2FF).withValues(alpha: .28 * k)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .006),
      );
    }

    // Launch burst: two expanding rings and a flash.
    if (burstAt != null && burstAge < .45) {
      final t = burstAge / .45, at = burstAt! * s;
      final r = Carrom.strikerR * s;
      canvas.drawCircle(
        at,
        r * (1 + t * 2.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .35 * (1 - t)
          ..color = const Color(0xFFFFE28A).withValues(alpha: 1 - t),
      );
      canvas.drawCircle(
        at,
        r * (1 + t * 3.4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .15 * (1 - t)
          ..color = Colors.white.withValues(alpha: .7 * (1 - t)),
      );
      if (t < .3) {
        canvas.drawCircle(
          at,
          r * 1.6,
          Paint()
            ..color = Colors.white.withValues(alpha: .35 * (1 - t / .3))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .8),
        );
      }
    }

    if (!ready) return;
    final r = Carrom.strikerR * s;
    final free = game.strikerFree;
    final a = aim;
    final at = (a == null
            ? game.striker.pos
            : game.striker.pos - a.$1 * (a.$2 * Carrom.strikerR * .55)) *
        s;

    if (a == null) {
      // Breathing halo and a slow spinning dashed ring on the live striker.
      final c = free ? const Color(0xFFFFE28A) : _hot;
      canvas.drawCircle(
        at,
        r * 1.55,
        Paint()
          ..color = c.withValues(alpha: .18 + .1 * math.sin(time * 4))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .6),
      );
      final ring = Rect.fromCircle(center: at, radius: r * 1.32);
      final dash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * .13
        ..color = c;
      for (var i = 0; i < 8; i++) {
        canvas.drawArc(ring, time * 1.6 + i * math.pi / 4, math.pi / 7, false, dash);
      }
      return;
    }

    final (dir, power) = a;
    final colour = _powerColour(power);

    // Predicted path: the first piece it would meet, or the first cushion
    // it would bounce off and where it would go next.
    final from = game.striker.pos;
    double? hitT;
    CarromPiece? hitPiece;
    for (final p in game.pieces) {
      if (p == game.striker || p.pocketed) continue;
      final rel = p.pos - from;
      final along = rel.dx * dir.dx + rel.dy * dir.dy;
      if (along <= 0) continue;
      final off2 = rel.distanceSquared - along * along;
      final reach = Carrom.strikerR + p.radius;
      if (off2 > reach * reach) continue;
      final t = along - math.sqrt(reach * reach - off2);
      if (hitT == null || t < hitT) {
        hitT = t;
        hitPiece = p;
      }
    }
    double wallT = double.infinity;
    var bounce = dir;
    final lo = Carrom.left + Carrom.strikerR, hi = Carrom.right - Carrom.strikerR;
    final top = Carrom.top + Carrom.strikerR, bot = Carrom.bottom - Carrom.strikerR;
    if (dir.dx > 1e-6) {
      final t = (hi - from.dx) / dir.dx;
      if (t < wallT) (wallT, bounce) = (t, Offset(-dir.dx, dir.dy));
    } else if (dir.dx < -1e-6) {
      final t = (lo - from.dx) / dir.dx;
      if (t < wallT) (wallT, bounce) = (t, Offset(-dir.dx, dir.dy));
    }
    if (dir.dy > 1e-6) {
      final t = (bot - from.dy) / dir.dy;
      if (t < wallT) (wallT, bounce) = (t, Offset(dir.dx, -dir.dy));
    } else if (dir.dy < -1e-6) {
      final t = (top - from.dy) / dir.dy;
      if (t < wallT) (wallT, bounce) = (t, Offset(dir.dx, -dir.dy));
    }
    final firstLeg = math.min(hitT ?? double.infinity, wallT);

    // Moving dots along the guide (they flow in the shot direction).
    void dots(Offset start, Offset d, double len, double fade0) {
      const gap = .03;
      final shift = (time * .09) % gap;
      for (var t = shift; t < len; t += gap) {
        final k = (1 - t / len) * fade0;
        canvas.drawCircle(
          (start + d * t) * s,
          s * (.0042 + .0018 * k),
          Paint()..color = Colors.white.withValues(alpha: .25 + .6 * k),
        );
      }
    }

    dots(from + dir * Carrom.strikerR, dir, firstLeg - Carrom.strikerR, 1);
    if (hitT != null && hitT <= wallT) {
      // Ghost striker at the contact point, and the line the piece will take.
      final contact = from + dir * hitT;
      canvas.drawCircle(
        contact * s,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * .004
          ..color = Colors.white.withValues(alpha: .85),
      );
      final push = hitPiece!.pos - contact;
      final n = push / push.distance;
      final p0 = hitPiece.pos * s;
      canvas.drawLine(
        p0 + n * (hitPiece.radius * s),
        p0 + n * (s * (.06 + .12 * power)),
        Paint()
          ..strokeWidth = s * .006
          ..strokeCap = StrokeCap.round
          ..color = colour.withValues(alpha: .9),
      );
    } else if (wallT.isFinite) {
      final hit = from + dir * wallT;
      canvas.drawCircle(hit * s, s * .007, Paint()..color = Colors.white);
      dots(hit, bounce, .22, .55);
    }

    // The arrow: a glowing, tapered shaft whose length is the power.
    final len = s * (.07 + .2 * power);
    final base = at + dir * (r * 1.15);
    final tip = base + dir * len;
    final side = Offset(-dir.dy, dir.dx);
    final shaft = Path()
      ..moveTo(base.dx + side.dx * s * .005, base.dy + side.dy * s * .005)
      ..lineTo(tip.dx + side.dx * s * .012, tip.dy + side.dy * s * .012)
      ..lineTo(tip.dx + side.dx * s * .026, tip.dy + side.dy * s * .026)
      ..lineTo(tip.dx + dir.dx * s * .04, tip.dy + dir.dy * s * .04)
      ..lineTo(tip.dx - side.dx * s * .026, tip.dy - side.dy * s * .026)
      ..lineTo(tip.dx - side.dx * s * .012, tip.dy - side.dy * s * .012)
      ..lineTo(base.dx - side.dx * s * .005, base.dy - side.dy * s * .005)
      ..close();
    canvas.drawPath(
      shaft,
      Paint()
        ..color = colour.withValues(alpha: .65)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .012),
    );
    canvas.drawPath(
      shaft,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, colour],
        ).createShader(Rect.fromPoints(base, tip + dir * s * .04)),
    );
    canvas.drawPath(
      shaft,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .0025
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xCC1A1030),
    );

    // Power dial wrapped round the striker.
    final dial = Rect.fromCircle(center: at, radius: r * 1.45);
    canvas.drawArc(
      dial,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .28
        ..color = const Color(0x8C0F1136),
    );
    final start = math.atan2(-dir.dy, -dir.dx) - power * math.pi;
    canvas.drawArc(
      dial,
      start,
      power * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * .28
        ..shader = SweepGradient(
          colors: const [_cool, _warm, _hot],
          transform: GradientRotation(start),
        ).createShader(dial),
    );

    // Elastic band from the striker back toward the finger.
    final back = at - dir * (r + s * .2 * power);
    final band = Paint()
      ..strokeWidth = s * .005
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .6);
    canvas.drawLine(at - dir * r + side * r * .6, back, band);
    canvas.drawLine(at - dir * r - side * r * .6, back, band);
    canvas.drawCircle(back, s * .009, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TablePainter old) => true;
}

/// A piece seen from just above: its round face sitting on a short
/// coloured side, so it reads as a thick disc rather than a flat sticker.
class _Puck extends StatelessWidget {
  const _Puck({required this.kind});
  final PieceKind kind;

  static const _side = {
    PieceKind.white: (Color(0xFFC81E2A), Color(0xFF6E0A10)),
    PieceKind.black: (Color(0xFF2A2A2E), Color(0xFF050506)),
    PieceKind.queen: (Color(0xFFA0101C), Color(0xFF4A0208)),
    PieceKind.striker: (Color(0xFF1F4FD6), Color(0xFF0A1F66)),
  };

  @override
  Widget build(BuildContext context) {
    final (light, dark) = _side[kind]!;
    return LayoutBuilder(builder: (context, box) {
      final d = box.maxWidth, depth = d * .13;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // The side band, peeking out below the face.
          Positioned(
            left: 0,
            top: depth,
            width: d,
            height: d,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [dark, light, dark],
                  stops: const [0, .45, 1],
                ),
                border: Border(
                  bottom: BorderSide(
                      color: const Color(0xFFE3B341), width: d * .025),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Image.asset(_pieceAsset[kind]!,
                filterQuality: FilterQuality.medium),
          ),
        ],
      );
    });
  }
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
