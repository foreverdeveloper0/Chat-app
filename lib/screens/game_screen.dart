import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/icons.dart';
import '../art/pieces.dart';
import '../game/ludo_controller.dart';
import '../game/ludo_rules.dart';
import '../theme/app_colors.dart';
import '../theme/board_assets.dart';
import '../widgets/game_card.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.title,
    required this.seats,
    required this.bots,
    required this.names,
  });

  final String title;
  final List<int> seats;
  final Set<int> bots;
  final Map<int, String> names;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late LudoController _game;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    _game = LudoController(seats: widget.seats, bots: widget.bots);
    _intro.forward(from: 0).whenComplete(() {
      if (mounted) _game.start();
    });
  }

  void _restart() {
    final old = _game;
    setState(_newGame);
    old.dispose();
  }

  @override
  void dispose() {
    _game.dispose();
    _pulse.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    if (_game.phase == Phase.gameOver) return Navigator.of(context).pop();
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
            child: const Text('Leave', style: TextStyle(color: AppColors.mint)),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -.1),
              radius: 1.1,
              colors: [Color(0xFF232A6B), AppColors.bgBottom],
            ),
          ),
          child: SafeArea(
            child: ListenableBuilder(
              listenable: _game,
              builder: (context, _) => LayoutBuilder(
                builder: (context, box) {
                  final board = math.min(
                      math.min(box.maxWidth, 520.0) - 16, box.maxHeight - 250);
                  return Stack(
                    children: [
                      Column(
                        children: [
                          _Header(
                            title: widget.title,
                            message: _game.message,
                            onBack: _confirmLeave,
                          ),
                          const Spacer(),
                          _panelRow(board, 0, 1),
                          const SizedBox(height: 10),
                          _BoardIntro(
                            intro: _intro,
                            child: _Board(
                                size: board, game: _game, pulse: _pulse),
                          ),
                          const SizedBox(height: 10),
                          _panelRow(board, 3, 2),
                          const Spacer(),
                        ],
                      ),
                      if (_game.winner != null)
                        Positioned.fill(
                          child: _WinOverlay(
                            player: _game.winner!,
                            name: widget.names[_game.winner!] ?? 'Player',
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
    );
  }

  Widget _panelRow(double width, int left, int right) {
    Widget panel(int p, bool mirrored) => Expanded(
          child: widget.seats.contains(p)
              ? _PlayerPanel(
                  player: p,
                  name: widget.names[p] ?? 'Player',
                  game: _game,
                  pulse: _pulse,
                  mirrored: mirrored,
                )
              : const SizedBox(height: 62),
        );
    return SizedBox(
      width: width,
      child: Row(
        children: [panel(left, false), const SizedBox(width: 10), panel(right, true)],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.message, required this.onBack});
  final String title;
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        children: [
          GameCard(
            width: 44,
            height: 44,
            radius: 14,
            onTap: onBack,
            child: const Icon(Icons.arrow_back_rounded, color: AppColors.cream),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppText.title.copyWith(fontSize: 20)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    message,
                    key: ValueKey(message),
                    style: AppText.title.copyWith(
                        fontSize: 13, color: AppColors.mint, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// The board drops in with a spin and a small overshoot.
class _BoardIntro extends StatelessWidget {
  const _BoardIntro({required this.intro, required this.child});
  final Animation<double> intro;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: intro, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (_, child) => Opacity(
        opacity: intro.value.clamp(0, 1),
        child: Transform.rotate(
          angle: (1 - curve.value) * -.6,
          child: Transform.scale(scale: .55 + .45 * curve.value, child: child),
        ),
      ),
    );
  }
}

// ───────────────────────── Board + tokens ─────────────────────────

class _Board extends StatelessWidget {
  const _Board({required this.size, required this.game, required this.pulse});
  final double size;
  final LudoController game;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final rim = size * gridInset;
    final cell = size * gridSize / 15;
    final all = [for (final p in game.seats) ...game.tokens[p]];

    // Tokens sharing a cell shrink and sit side by side.
    final groups = <Offset, List<Token>>{};
    for (final t in all) {
      if (t.progress >= 0 && !t.isHome) {
        final pos = LudoRules.position(t.player, t.index, t.progress);
        groups.putIfAbsent(pos, () => []).add(t);
      }
    }

    final placed = <(Token, Offset, double)>[];
    for (final t in all) {
      var pos = LudoRules.position(t.player, t.index, t.progress);
      var scale = t.inYard ? 1.22 : (t.isHome ? .68 : 1.0);
      final group = groups[pos];
      if (group != null && group.length > 1) {
        final i = group.indexOf(t), n = group.length;
        scale = n > 2 ? .62 : .74;
        pos += Offset((i - (n - 1) / 2) * (n > 2 ? .26 : .34),
            n > 2 ? (i.isEven ? -.1 : .12) : 0);
      }
      placed.add((t, pos, scale));
    }
    // Paint back-to-front; movable tokens always on top.
    placed.sort((a, b) {
      final ma = game.movable.contains(a.$1), mb = game.movable.contains(b.$1);
      if (ma != mb) return ma ? 1 : -1;
      return a.$2.dy.compareTo(b.$2.dy);
    });

    final bw = cell * 1.6, bh = cell * 2.1;
    final active = LudoRules.yardOrigins[game.current];
    final choosing = game.phase == Phase.choosing && game.humanTurn;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .04),
        boxShadow: const [
          BoxShadow(color: Color(0x88000010), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(boardAsset,
                fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
          if (game.phase != Phase.gameOver)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: rim + active.$1 * cell,
              top: rim + active.$2 * cell,
              width: cell * 6,
              height: cell * 6,
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: Tween(begin: .0, end: .3).animate(pulse),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          for (final (t, pos, scale) in placed)
            AnimatedPositioned(
              key: ValueKey(t.player * 4 + t.index),
              duration: Duration(milliseconds: t.inYard ? 480 : 150),
              curve: t.inYard ? Curves.easeInOutCubic : Curves.easeOut,
              left: rim + pos.dx * cell - bw / 2,
              top: rim + pos.dy * cell + cell * .16 - bh * .72,
              width: bw,
              height: bh,
              child: _TokenView(
                token: t,
                progress: t.progress,
                cell: cell,
                scale: scale,
                pulse: pulse,
                movable: game.movable.contains(t),
                onTap: choosing && game.movable.contains(t)
                    ? () => game.move(t)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _TokenView extends StatefulWidget {
  const _TokenView({
    required this.token,
    required this.progress,
    required this.cell,
    required this.scale,
    required this.pulse,
    required this.movable,
    required this.onTap,
  });
  final Token token;
  final int progress;
  final double cell;
  final double scale;
  final Animation<double> pulse;
  final bool movable;
  final VoidCallback? onTap;

  @override
  State<_TokenView> createState() => _TokenViewState();
}

class _TokenViewState extends State<_TokenView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 165),
  );

  @override
  void didUpdateWidget(_TokenView old) {
    super.didUpdateWidget(old);
    if (widget.progress != old.progress && widget.progress >= 0) {
      _hop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = AnimatedBuilder(
      animation: Listenable.merge([_hop, if (widget.movable) widget.pulse]),
      builder: (_, _) {
        final hop = math.sin(_hop.value * math.pi);
        final pulse = widget.movable ? widget.pulse.value : null;
        return LayoutBuilder(builder: (_, box) {
          final foot = Offset(box.maxWidth / 2, box.maxHeight * .72);
          final lift = hop * widget.cell * .5 + (pulse ?? 0) * widget.cell * .16;
          final pw = widget.cell * .86 * widget.scale * (1 + hop * .12);
          final ph = pw / pawnAspect;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TokenBasePainter(
                    color: playerColors[widget.token.player],
                    cell: widget.cell,
                    width: pw,
                    hop: hop,
                    pulse: pulse,
                  ),
                ),
              ),
              Positioned(
                left: foot.dx - pw / 2,
                top: foot.dy - ph * .95 - lift,
                width: pw,
                height: ph,
                child: Image.asset(
                  pawnAssets[widget.token.player],
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            ],
          );
        });
      },
    );
    return GestureDetector(
      behavior: widget.onTap == null
          ? HitTestBehavior.translucent
          : HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: RepaintBoundary(child: view),
    );
  }
}

/// Ground shadow and the pulsing "you can move me" ring under a pawn.
class _TokenBasePainter extends CustomPainter {
  const _TokenBasePainter({
    required this.color,
    required this.cell,
    required this.width,
    required this.hop,
    required this.pulse,
  });
  final Color color;
  final double cell;
  final double width;
  final double hop;
  final double? pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final foot = Offset(size.width / 2, size.height * .72);
    if (pulse != null) {
      final ground = foot - Offset(0, cell * .02);
      final r = cell * (.46 + .2 * pulse!);
      canvas.drawCircle(ground, r,
          Paint()..color = Colors.white.withValues(alpha: .5 - .3 * pulse!));
      canvas.drawCircle(
        ground,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .1
          ..color = color,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(
          center: foot + Offset(width * .05, 0),
          width: width * 1.0,
          height: width * .34),
      Paint()..color = Color.fromRGBO(0, 0, 0, .32 - hop * .16),
    );
  }

  @override
  bool shouldRepaint(_TokenBasePainter old) =>
      old.hop != hop ||
      old.pulse != pulse ||
      old.width != width ||
      old.cell != cell ||
      old.color != color;
}

// ───────────────────────── Player panel + dice ─────────────────────────

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.player,
    required this.name,
    required this.game,
    required this.pulse,
    required this.mirrored,
  });
  final int player;
  final String name;
  final LudoController game;
  final Animation<double> pulse;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final active = game.current == player && game.phase != Phase.gameOver;
    final canRoll =
        active && game.phase == Phase.awaitingRoll && !game.isBot(player);
    final color = playerColors[player];
    final status = !active
        ? 'Home ${game.homeCount(player)}/4'
        : switch (game.phase) {
            Phase.awaitingRoll => game.isBot(player) ? 'Thinking…' : 'Tap to roll',
            Phase.rolling => 'Rolling…',
            Phase.choosing => game.movable.isEmpty
                ? 'No move'
                : (game.isBot(player) ? 'Thinking…' : 'Pick a piece'),
            _ => 'Moving…',
          };

    final children = [
      Image.asset(pawnAssets[player], width: 24, height: 38, fit: BoxFit.contain),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment:
              mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(name,
                  maxLines: 1, style: AppText.title.copyWith(fontSize: 15.5)),
            ),
            const SizedBox(height: 3),
            Text(
              status,
              maxLines: 1,
              style: AppText.title.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? AppColors.mint : const Color(0xFFA9AEDC),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      _Dice(game: game, active: active, canRoll: canRoll, pulse: pulse),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canRoll ? game.roll : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.cardTop, AppColors.cardBottom],
          ),
          border: Border.all(
            color: active ? color : AppColors.cardBorder,
            width: active ? 2.2 : 1.2,
          ),
          boxShadow: [
            if (active)
              BoxShadow(color: color.withValues(alpha: .55), blurRadius: 16),
          ],
        ),
        child: Row(children: mirrored ? children.reversed.toList() : children),
      ),
    );
  }
}

class _Dice extends StatelessWidget {
  const _Dice({
    required this.game,
    required this.active,
    required this.canRoll,
    required this.pulse,
  });
  final LudoController game;
  final bool active;
  final bool canRoll;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    const size = 46.0;
    if (!active) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardInset,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }
    final rolling = game.phase == Phase.rolling;
    Widget dice = AnimatedRotation(
      turns: rolling ? game.rollTick * .21 : 0,
      duration: const Duration(milliseconds: 70),
      child: AnimatedScale(
        scale: rolling ? .82 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: CustomPaint(
          size: const Size.square(size),
          painter: _DicePainter(game.dice),
        ),
      ),
    );
    if (canRoll) {
      dice = ScaleTransition(
        scale: Tween(begin: .92, end: 1.1).animate(
            CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
        child: dice,
      );
    }
    return SizedBox.square(dimension: size, child: dice);
  }
}

class _DicePainter extends CustomPainter {
  const _DicePainter(this.value);
  final int value;

  @override
  void paint(Canvas canvas, Size size) =>
      paintDice(canvas, Offset.zero & size, value);

  @override
  bool shouldRepaint(_DicePainter old) => old.value != value;
}

// ───────────────────────── Win overlay ─────────────────────────

class _WinOverlay extends StatefulWidget {
  const _WinOverlay({
    required this.player,
    required this.name,
    required this.onAgain,
    required this.onHome,
  });
  final int player;
  final String name;
  final VoidCallback onAgain;
  final VoidCallback onHome;

  @override
  State<_WinOverlay> createState() => _WinOverlayState();
}

class _WinOverlayState extends State<_WinOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => ColoredBox(
        color: Color.fromRGBO(8, 9, 32, .78 * v.clamp(0, 1)),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ConfettiPainter(_c)),
              ),
            ),
            Center(child: Transform.scale(scale: v, child: child)),
          ],
        ),
      ),
      child: Container(
        width: 290,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.cardTop, AppColors.cardBottom],
          ),
          border: Border.all(color: playerColors[widget.player], width: 2.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Art(ArtKind.trophy, size: 110),
            const SizedBox(height: 8),
            Text(
              '${widget.name} ${widget.name == 'You' ? 'win' : 'wins'}!',
              textAlign: TextAlign.center,
              style: AppText.title
                  .copyWith(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            _WideButton(label: 'Play again', filled: true, onTap: widget.onAgain),
            const SizedBox(height: 10),
            _WideButton(label: 'Home', filled: false, onTap: widget.onHome),
          ],
        ),
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: filled
              ? const LinearGradient(
                  colors: [Color(0xFF6BF0BD), AppColors.mintDeep])
              : null,
          border: filled ? null : Border.all(color: AppColors.cardBorder, width: 1.5),
        ),
        child: Text(
          label,
          style: AppText.title.copyWith(
              fontSize: 17, color: filled ? AppColors.ink : AppColors.cream),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  static final _bits = () {
    final r = math.Random(7);
    return [
      for (var i = 0; i < 90; i++)
        (
          x: r.nextDouble(),
          phase: r.nextDouble(),
          speed: .6 + r.nextDouble() * .8,
          sway: r.nextDouble() * 2 * math.pi,
          size: 5 + r.nextDouble() * 6,
          color: [...playerColors, AppColors.mint, Colors.white][r.nextInt(6)],
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final b in _bits) {
      final fall = (t.value * b.speed + b.phase) % 1;
      final x = b.x * size.width +
          math.sin(fall * 6 + b.sway) * 18;
      final y = fall * (size.height + 40) - 20;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(fall * 12 + b.sway);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * .55),
        paint..color = b.color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
