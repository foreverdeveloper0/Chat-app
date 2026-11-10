import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/pieces.dart';
import '../game/ludo_controller.dart';
import '../game/ludo_rules.dart';
import '../theme/board_assets.dart';

/// The home page's showpiece: the real board, tilted in perspective, with
/// four bots playing an endless match on it.
class LiveBoard extends StatefulWidget {
  const LiveBoard({super.key});

  @override
  State<LiveBoard> createState() => _LiveBoardState();
}

class _LiveBoardState extends State<LiveBoard> {
  late LudoController _game;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _game = LudoController(
      seats: const [3, 0, 1, 2],
      bots: const {0, 1, 2, 3},
      haptics: false,
      random: math.Random(),
    );
    // Listen only after the field is set: starting the match notifies.
    _game
      ..addListener(_onChange)
      ..start();
  }

  void _onChange() {
    if (!mounted) return;
    if (_game.phase == Phase.gameOver) {
      // Deal a fresh match once this one is over.
      final old = _game;
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        old
          ..removeListener(_onChange)
          ..dispose();
        setState(_start);
      });
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold the match still while another page covers the home page.
    _game.paused = !TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    _game
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final b = size.width * .76; // flat board edge
      final centre = Offset(size.width * .52, size.height * .45);
      final m = Matrix4.identity()
        ..translateByDouble(centre.dx, centre.dy, 0, 1)
        ..setEntry(3, 2, .0011)
        ..rotateX(-.92)
        ..rotateZ(-.13)
        ..translateByDouble(-b / 2, -b / 2, 0, 1);

      Offset project(Offset cells) => MatrixUtils.transformPoint(
          m,
          Offset((gridInset + gridSize * cells.dx / 15) * b,
              (gridInset + gridSize * cells.dy / 15) * b));

      // Lay the pawns out, nudging those that share a square apart.
      final sharing = <Offset, int>{};
      final placed = <(Token, Offset, double)>[];
      for (final p in _game.seats) {
        for (final t in _game.tokens[p]) {
          var cells = LudoRules.position(t.player, t.index, t.progress);
          if (t.progress >= 0 && !t.isHome) {
            final n = sharing.update(cells, (v) => v + 1, ifAbsent: () => 0);
            cells += Offset(n * .34 - (n > 0 ? .17 : 0), 0);
          }
          final foot = project(cells);
          // Pawns nearer the viewer are drawn a little larger.
          final depth = ((foot.dy / size.height) - .1).clamp(0.0, 1.0);
          placed.add((t, foot, .8 + depth * .5));
        }
      }
      placed.sort((a, b) => a.$2.dy.compareTo(b.$2.dy));

      final pw = b * .062;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BoardBasePainter(m, b)),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Transform(
              transform: m,
              child: Image.asset(boardAsset,
                  width: b,
                  height: b,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium),
            ),
          ),
          for (final (t, foot, scale) in placed)
            AnimatedPositioned(
              key: ValueKey(t.player * 4 + t.index),
              duration: Duration(milliseconds: t.inYard ? 420 : 150),
              curve: Curves.easeOut,
              left: foot.dx - pw * scale / 2,
              top: foot.dy - pw * scale / pawnAspect * .93,
              width: pw * scale,
              height: pw * scale / pawnAspect,
              child: _HopPawn(player: t.player, progress: t.progress),
            ),
          // The match's dice, thrown beside the near corner of the board
          // and glowing in the colour of whoever is on turn.
          Positioned(
            left: size.width * .7,
            top: size.height * .76,
            child: _DemoDice(
              value: _game.dice,
              phase: _game.phase,
              color: playerColors[_game.current],
              size: size.width * .16,
            ),
          ),
        ],
      );
    });
  }
}

/// Ground shadow and the board's extruded gold side under the tilted image.
class _BoardBasePainter extends CustomPainter {
  const _BoardBasePainter(this.m, this.b);
  final Matrix4 m;
  final double b;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = b * .012;
    final frame = RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, b - inset * 2, b - inset * 2),
        Radius.circular(b * .045));
    canvas.save();
    canvas.translate(0, b * .1);
    canvas.transform(m.storage);
    canvas.drawRRect(
      frame.inflate(b * .02),
      Paint()
        ..color = const Color(0x88000010)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, b * .06),
    );
    canvas.restore();
    final depth = (b * .05).round();
    for (var i = depth; i > 0; i--) {
      canvas.save();
      canvas.translate(0, i.toDouble());
      canvas.transform(m.storage);
      canvas.drawRRect(
        frame,
        Paint()
          ..color = Color.lerp(const Color(0xFF6B4708), const Color(0xFFC08A1E),
              1 - i / depth)!,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BoardBasePainter old) => old.b != b || old.m != m;
}

/// A pawn that hops each time it advances a square.
class _HopPawn extends StatefulWidget {
  const _HopPawn({required this.player, required this.progress});
  final int player;
  final int progress;

  @override
  State<_HopPawn> createState() => _HopPawnState();
}

class _HopPawnState extends State<_HopPawn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 165),
  );

  @override
  void didUpdateWidget(_HopPawn old) {
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
    return AnimatedBuilder(
      animation: _hop,
      child: Image.asset(pawnAssets[widget.player],
          fit: BoxFit.fill, filterQuality: FilterQuality.medium),
      builder: (context, child) {
        final h = math.sin(_hop.value * math.pi);
        return FractionalTranslation(
          translation: Offset(0, -h * .32),
          child: Transform.scale(scale: 1 + h * .14, child: child),
        );
      },
    );
  }
}

/// The demo's dice: tossed up, tumbling as a real cube, landing with a
/// bounce on the rolled face, exactly like the dice in a match.
class _DemoDice extends StatefulWidget {
  const _DemoDice({
    required this.value,
    required this.phase,
    required this.color,
    required this.size,
  });
  final int value;
  final Phase phase;
  final Color color;
  final double size;

  @override
  State<_DemoDice> createState() => _DemoDiceState();
}

class _DemoDiceState extends State<_DemoDice>
    with SingleTickerProviderStateMixin {
  static const _airMs = LudoController.rollTicks * LudoController.rollTickMs;
  static const _totalMs = _airMs + LudoController.landMs;
  static const _air = _airMs / _totalMs;

  late final AnimationController _toss = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
    value: 1,
  );

  @override
  void didUpdateWidget(_DemoDice old) {
    super.didUpdateWidget(old);
    if (widget.phase == Phase.rolling && old.phase != Phase.rolling) {
      _toss.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _toss.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _toss,
      builder: (_, _) {
        final t = _toss.value;
        final flying = t < _air;
        final a = flying ? t / _air : 1.0;
        final l = flying ? 0.0 : (t - _air) / (1 - _air);
        final arc = 4 * a * (1 - a);
        final rebound = flying ? 0.0 : math.sin(l * math.pi) * (1 - l) * .2;
        final lift = (flying ? arc : rebound) * size * 1.1;
        final left = math.pow(1 - a, 1.6).toDouble();
        final squash =
            flying ? 0.0 : math.sin(l * math.pi * 2.5) * (1 - l) * .18;
        return SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Coloured glow on the ground; it tightens as the dice rises.
              Transform.scale(
                scale: 1 - arc * .35,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: size * .9,
                  height: size * .9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: widget.color.withValues(alpha: .75),
                          blurRadius: size * .4),
                    ],
                  ),
                ),
              ),
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(0, -lift, 0, 1)
                  ..scaleByDouble((1 + arc * .3) * (1 + squash),
                      (1 + arc * .3) * (1 - squash), 1, 1),
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _DicePainter(
                    widget.value,
                    rx: left * 4 * math.pi,
                    ry: left * 3 * math.pi,
                    rz: left * math.pi,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DicePainter extends CustomPainter {
  const _DicePainter(this.value, {this.rx = 0, this.ry = 0, this.rz = 0});
  final int value;
  final double rx, ry, rz;

  @override
  void paint(Canvas canvas, Size size) {
    if (rx == 0 && ry == 0 && rz == 0) {
      paintDice(canvas, Offset.zero & size, value, angle: -.14);
    } else {
      paintDice3D(canvas, size.center(Offset(0, -size.height * .04)),
          size.width * .78, value, rx: rx, ry: ry, rz: rz);
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) =>
      old.value != value || old.rx != rx || old.ry != ry || old.rz != rz;
}
