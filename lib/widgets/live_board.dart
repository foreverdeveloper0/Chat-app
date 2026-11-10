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
              child: Image.asset(pawnAssets[t.player],
                  fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            ),
          // The dice of the match, tinted by whose turn it is.
          Positioned(
            left: size.width * .02,
            top: size.height * .66,
            child: _DemoDice(
              value: _game.dice,
              rolling: _game.phase == Phase.rolling,
              color: playerColors[_game.current],
              size: size.width * .19,
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

class _DemoDice extends StatelessWidget {
  const _DemoDice({
    required this.value,
    required this.rolling,
    required this.color,
    required this.size,
  });
  final int value;
  final bool rolling;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: rolling ? 1 : 0,
      duration: Duration(milliseconds: rolling ? 600 : 0),
      curve: Curves.easeOut,
      child: AnimatedScale(
        scale: rolling ? 1.18 : 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: .7), blurRadius: 18),
            ],
          ),
          child: CustomPaint(painter: _DicePainter(value)),
        ),
      ),
    );
  }
}

class _DicePainter extends CustomPainter {
  const _DicePainter(this.value);
  final int value;

  @override
  void paint(Canvas canvas, Size size) =>
      paintDice(canvas, Offset.zero & size, value, angle: -.18);

  @override
  bool shouldRepaint(_DicePainter old) => old.value != value;
}
