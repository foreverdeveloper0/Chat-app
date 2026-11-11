import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../art/snake_art.dart';
import '../game/best_scores.dart';
import '../game/snake_game.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../widgets/game_hud.dart';

/// Dev aid: `--dart-define=LUDO_AUTOPLAY=true` lets the snake steer itself.
const _autoplay = bool.fromEnvironment('LUDO_AUTOPLAY');

enum _Stage { countdown, playing, paused, dying, over }

/// Classic Snake: swipe, use the pad or the arrow keys to steer.
class SnakeScreen extends StatefulWidget {
  const SnakeScreen({super.key, required this.speed, required this.wrap});
  final SnakeSpeed speed;

  /// Open arena (the snake passes through the edges) instead of walls.
  final bool wrap;

  /// The game on screen, for widget tests.
  @visibleForTesting
  static SnakeGame? debugGame;

  @override
  State<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends State<SnakeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _beat = .7; // seconds per countdown number

  late final SnakeGame _game =
      SnakeGame(wrap: widget.wrap, speed: widget.speed);
  final _view = SnakeView();
  final _focus = FocusNode();
  late final Ticker _ticker;

  Duration _last = Duration.zero;
  double _acc = 0; // milliseconds into the current step
  double _phase = 0; // seconds into the countdown or the crash
  _Stage _stage = _Stage.countdown;
  int _count = 3;
  int _best = 0;
  bool _newBest = false;
  SnakeStep? _pending; // eaten in the rules, not yet reached on screen
  Offset _swipe = Offset.zero;

  @override
  void initState() {
    super.initState();
    SnakeScreen.debugGame = _game;
    WidgetsBinding.instance.addObserver(this);
    BestScores.snake(widget.speed, widget.wrap).then((v) {
      if (mounted) setState(() => _best = v);
    });
    Sounds.play(Sfx.turn);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focus.dispose();
    _view.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _stage == _Stage.playing) {
      setState(() => _stage = _Stage.paused);
    }
  }

  // ── Game loop ──

  void _onTick(Duration elapsed) {
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, .05);
    _last = elapsed;
    switch (_stage) {
      case _Stage.countdown:
        _phase += dt;
        final n = 3 - (_phase / _beat).floor();
        if (n != _count) {
          Sounds.play(n > 0 ? Sfx.turn : Sfx.start);
          setState(() => _count = n);
        }
        if (_phase >= _beat * 3 + .45) {
          _acc = 0;
          setState(() => _stage = _Stage.playing);
        }
      case _Stage.playing:
        _acc += dt * 1000;
        while (_stage == _Stage.playing && _acc >= _game.stepMs) {
          _acc -= _game.stepMs;
          _step();
        }
        if (_stage == _Stage.playing) {
          _view.t = (_acc / _game.stepMs).clamp(0, 1);
          // The bite lands when the head is most of the way onto the fruit.
          if (_pending != null && _view.t >= .55) _bite();
        }
      case _Stage.dying:
        _phase += dt;
        _view.lunge = _phase < .26 ? math.sin(math.pi * _phase / .26) : 0;
        _view.flash = (1 - _phase / .5).clamp(0, 1);
        if (_phase >= 1.1) setState(() => _stage = _Stage.over);
      case _Stage.paused || _Stage.over:
        break;
    }
    _view.tick(dt);
  }

  void _step() {
    if (_pending != null) _bite();
    if (_autoplay) {
      final d = _game.botMove();
      if (d != null) _game.turn(d);
    }
    final r = _game.step();
    if (r.died) {
      _stage = _Stage.dying;
      _phase = 0;
      _view.t = 1;
      Sounds.play(Sfx.crash);
      HapticFeedback.heavyImpact();
      _saveBest();
      setState(() {});
      return;
    }
    if (r.ate || r.ateBonus) {
      _pending = r;
      _view.ghost = (at: r.at!, kind: r.kind, bonus: r.ateBonus);
      // The next fruit pops in once this one has been swallowed.
      if (r.ate) _view.foodBorn = _view.time + _game.stepMs * .00055;
    }
    if (r.bonusSpawned) {
      _view.bonusBorn = _view.time;
      Sounds.play(Sfx.turn);
    }
    if (r.won) {
      _bite();
      _saveBest();
      setState(() => _stage = _Stage.over);
    }
  }

  void _bite() {
    final r = _pending!;
    _pending = null;
    _view.ghost = null;
    Sounds.play(r.ateBonus ? Sfx.bonus : Sfx.eat);
    HapticFeedback.lightImpact();
    _view.burst(r.at!, r.ateBonus ? bonusColor : fruitColors[r.kind],
        '+${r.gained}');
    setState(() {}); // score and length changed
  }

  void _saveBest() {
    BestScores.submitSnake(widget.speed, widget.wrap, _game.score).then((beat) {
      if (mounted && beat) {
        setState(() {
          _newBest = true;
          _best = _game.score;
        });
      }
    });
  }

  void _restart() {
    _game.reset();
    _view.reset();
    _pending = null;
    _acc = 0;
    _phase = 0;
    _newBest = false;
    Sounds.play(Sfx.turn);
    setState(() {
      _count = 3;
      _stage = _Stage.countdown;
    });
  }

  void _togglePause() {
    if (_stage == _Stage.playing) {
      setState(() => _stage = _Stage.paused);
    } else if (_stage == _Stage.paused) {
      setState(() => _stage = _Stage.playing);
    }
    Sounds.play(Sfx.tap);
  }

  // ── Input ──

  void _turn(SnakeDir d) {
    if (_stage == _Stage.playing || _stage == _Stage.countdown) _game.turn(d);
  }

  void _onPan(DragUpdateDetails d) {
    _swipe += d.delta;
    if (_swipe.distance < 16) return;
    _turn(_swipe.dx.abs() > _swipe.dy.abs()
        ? (_swipe.dx > 0 ? SnakeDir.right : SnakeDir.left)
        : (_swipe.dy > 0 ? SnakeDir.down : SnakeDir.up));
    _swipe = Offset.zero;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final dir = switch (key) {
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => SnakeDir.up,
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyS => SnakeDir.down,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.keyA => SnakeDir.left,
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.keyD => SnakeDir.right,
      _ => null,
    };
    if (dir != null) {
      _turn(dir);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyP) {
      _togglePause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final over = _stage == _Stage.over;
    return PopScope(
      // The first back press only pauses a running game.
      canPop: _stage != _Stage.playing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stage == _Stage.playing) _togglePause();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _swipe = Offset.zero,
            onPanUpdate: _onPan,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.2),
                  radius: 1.2,
                  colors: [Color(0xFF14306A), AppColors.bgTop, AppColors.bgBottom],
                  stops: [0, .5, 1],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final board = math.min(
                        math.min(box.maxWidth, 520.0) - 16, box.maxHeight - 300);
                    return Stack(
                      children: [
                        Column(
                          children: [
                            _header(),
                            const SizedBox(height: 8),
                            _chips(),
                            const Spacer(),
                            _board(board),
                            const Spacer(),
                            _DPad(onDir: _turn),
                            const SizedBox(height: 10),
                          ],
                        ),
                        if (over)
                          Positioned.fill(
                            child: _OverCard(
                              won: _game.won,
                              score: _game.score,
                              best: _best,
                              newBest: _newBest,
                              length: _game.length,
                              fruits: _game.eaten,
                              onAgain: _restart,
                              onHome: () => Navigator.of(context).pop(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        children: [
          RoundButton(
            icon: Icons.arrow_back_rounded,
            // Pauses a running game first; a second tap leaves.
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GoldPlaque(
              children: [
                PlaqueStat('SCORE', '${_game.score}',
                    color: const Color(0xFFFFE28A)),
                PlaqueStat('BEST', '${math.max(_best, _game.score)}'),
                PlaqueStat('LENGTH', '${_game.length}'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RoundButton(
            icon: _stage == _Stage.paused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
            onTap: _togglePause,
            lit: _stage == _Stage.paused,
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    Widget chip(IconData icon, String text) => Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.cardInset,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.goldSoft),
              const SizedBox(width: 5),
              Text(text, style: AppText.title.copyWith(fontSize: 12.5)),
            ],
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip(Icons.speed_rounded, widget.speed.label),
        const SizedBox(width: 8),
        chip(widget.wrap ? Icons.all_inclusive_rounded : Icons.crop_square_rounded,
            widget.wrap ? 'Open' : 'Walls'),
        const SizedBox(width: 8),
        chip(Icons.star_rounded, 'Level ${_game.level}'),
        const SizedBox(width: 8),
        ValueListenableBuilder(
          valueListenable: Sounds.muted,
          builder: (_, muted, _) => GestureDetector(
            onTap: () => Sounds.muted.value = !muted,
            child: chip(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                muted ? 'Off' : 'On'),
          ),
        ),
      ],
    );
  }

  Widget _board(double size) {
    final field = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: SnakeFieldPainter(
            cols: _game.cols, rows: _game.rows, wrap: _game.wrap),
      ),
    );
    return AnimatedBuilder(
      animation: _view,
      // A crash rattles the whole board for a moment.
      builder: (_, child) => Transform.translate(
        offset: Offset(
          math.sin(_view.time * 95) * _view.flash * 7,
          math.cos(_view.time * 80) * _view.flash * 5,
        ),
        child: child,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .04),
          boxShadow: const [
            BoxShadow(color: Color(0x6645E3A6), blurRadius: 26),
            BoxShadow(
                color: Color(0x99000010), blurRadius: 24, offset: Offset(0, 12)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            field,
            RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size),
                painter: SnakeScenePainter(_game, _view),
              ),
            ),
            if (_stage == _Stage.countdown)
              KeyedSubtree(
                key: const ValueKey('countdown'),
                child: _Countdown(
                    key: ValueKey(_count), value: _count, size: size),
              ),
            if (_stage == _Stage.paused)
              _PausedCard(
                onResume: _togglePause,
                onRestart: _restart,
                onHome: () => Navigator.of(context).pop(),
              ),
          ],
        ),
      ),
    );
  }
}

/// A number (then "GO!") that pops in over the board.
class _Countdown extends StatelessWidget {
  const _Countdown({super.key, required this.value, required this.size});
  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final go = value <= 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.scale(scale: .4 + .6 * v, child: child),
      ),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: AppColors.goldGradient,
        ).createShader(r),
        child: Text(
          go ? 'GO!' : '$value',
          style: AppText.title.copyWith(
            fontSize: size * (go ? .26 : .36),
            fontWeight: FontWeight.w700,
            height: 1,
            shadows: const [Shadow(color: Color(0xCC000010), blurRadius: 18)],
          ),
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
        child: Text(
          label,
          style: AppText.title.copyWith(
            fontSize: 16.5,
            color: filled ? const Color(0xFF3A2500) : AppColors.cream,
          ),
        ),
      ),
    );
  }
}

BoxDecoration _cardBox(Color border) => BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.cardTop, AppColors.cardBottom],
      ),
      border: Border.all(color: border, width: 2),
      boxShadow: const [
        BoxShadow(color: Color(0xAA000010), blurRadius: 24, offset: Offset(0, 10)),
      ],
    );

class _PausedCard extends StatelessWidget {
  const _PausedCard({
    required this.onResume,
    required this.onRestart,
    required this.onHome,
  });
  final VoidCallback onResume, onRestart, onHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: _cardBox(AppColors.goldTrim),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Paused', style: AppText.title.copyWith(fontSize: 24)),
          const SizedBox(height: 14),
          _CardButton(label: 'Resume', onTap: onResume, filled: true),
          const SizedBox(height: 8),
          _CardButton(label: 'Restart', onTap: onRestart),
          const SizedBox(height: 8),
          _CardButton(label: 'Home', onTap: onHome),
        ],
      ),
    );
  }
}

class _OverCard extends StatelessWidget {
  const _OverCard({
    required this.won,
    required this.score,
    required this.best,
    required this.newBest,
    required this.length,
    required this.fruits,
    required this.onAgain,
    required this.onHome,
  });
  final bool won, newBest;
  final int score, best, length, fruits;
  final VoidCallback onAgain, onHome;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Text(label,
                  style: AppText.title.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9EA9DC))),
              const Spacer(),
              Text(value, style: AppText.title.copyWith(fontSize: 16)),
            ],
          ),
        );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => ColoredBox(
        color: Color.fromRGBO(4, 6, 22, .78 * v.clamp(0, 1)),
        child: Center(child: Transform.scale(scale: v, child: child)),
      ),
      child: Container(
        width: 290,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: _cardBox(AppColors.goldTrim),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(won ? 'You filled the board!' : 'Game Over',
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(fontSize: 26)),
            const SizedBox(height: 8),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: AppColors.goldGradient,
              ).createShader(r),
              child: Text('$score',
                  style: AppText.title.copyWith(
                      fontSize: 58, fontWeight: FontWeight.w700, height: 1.05)),
            ),
            if (newBest)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6BF0BD), AppColors.mintDeep]),
                ),
                child: Text('NEW BEST!',
                    style: AppText.title.copyWith(
                        fontSize: 13, letterSpacing: 1, color: AppColors.ink)),
              ),
            const SizedBox(height: 10),
            row('Best', '${math.max(best, score)}'),
            row('Length', '$length'),
            row('Fruit eaten', '$fruits'),
            const SizedBox(height: 14),
            _CardButton(label: 'Play again', onTap: onAgain, filled: true),
            const SizedBox(height: 8),
            _CardButton(label: 'Home', onTap: onHome),
          ],
        ),
      ),
    );
  }
}

/// Four big arrow keys for players who would rather tap than swipe.
class _DPad extends StatelessWidget {
  const _DPad({required this.onDir});
  final ValueChanged<SnakeDir> onDir;

  @override
  Widget build(BuildContext context) {
    Widget key(SnakeDir d, IconData icon) =>
        _PadKey(key: ValueKey('pad-${d.name}'), icon: icon, onDown: () => onDir(d));
    const gap = SizedBox(width: 12, height: 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        key(SnakeDir.up, Icons.keyboard_arrow_up_rounded),
        gap,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            key(SnakeDir.left, Icons.keyboard_arrow_left_rounded),
            gap,
            key(SnakeDir.down, Icons.keyboard_arrow_down_rounded),
            gap,
            key(SnakeDir.right, Icons.keyboard_arrow_right_rounded),
          ],
        ),
      ],
    );
  }
}

class _PadKey extends StatefulWidget {
  const _PadKey({super.key, required this.icon, required this.onDown});
  final IconData icon;
  final VoidCallback onDown;

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Steer on touch down, not on release: it has to feel instant.
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        widget.onDown();
        setState(() => _down = true);
      },
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? .9 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: 62,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _down
                  ? const [AppColors.royal, AppColors.royalDeep]
                  : const [Color(0xFF26347E), Color(0xFF111A4A)],
            ),
            border: Border.all(
                color: _down ? const Color(0xFF8FA8FF) : AppColors.cardBorder,
                width: 1.4),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x80020310), blurRadius: 8, offset: Offset(0, 4)),
            ],
          ),
          child: Icon(widget.icon, size: 38, color: AppColors.goldSoft),
        ),
      ),
    );
  }
}
