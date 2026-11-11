import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/snl_layout.dart';

const snlBoardAsset = 'assets/images/snl/board.png';

/// Width / height of the board artwork.
const snlAspect = 921 / 1302;

/// Where the 10x10 grid sits inside the artwork, as fractions of its size.
const _gridLeft = .0239, _gridWidth = .9522, _gridTop = .020, _gridHeight = .963;

/// Width / height of each upright ladder image.
const _ladderAspect = [
  .335, .396, .215, .33, .272, .217, .272, //
  .311, .2, .33, .415, .396, .396, .261,
];

/// Each snake image lies head-left to tail-right: (height / width, head x,
/// head-and-tail y, tail x), the last three as fractions of the image.
const _snakes = [
  (81 / 540, .045, .322, .994),
  (68 / 540, .047, .365, .994),
  (62 / 540, .047, .419, .992),
  (59 / 540, .048, .441, .992),
  (115 / 540, .041, .462, .986),
  (139 / 540, .039, .314, .986),
  (211 / 540, .096, .245, .988),
  (250 / 540, .080, .282, .990),
  (262 / 540, .085, .276, .983),
];

/// Maps squares to pixels for a board drawn at [size].
class SnlGeometry {
  const SnlGeometry(this.size);
  final Size size;

  double get cellW => size.width * _gridWidth / 10;
  double get cellH => size.height * _gridHeight / 10;

  /// Centre of square [n] (1..100).
  Offset centre(int n) {
    final c = snlCell(n);
    return Offset(
      size.width * _gridLeft + (c.x + .5) * cellW,
      size.height * _gridTop + (9 - c.y + .5) * cellH,
    );
  }

  /// Points along the ride from [from] to [to]: straight up a ladder, or
  /// swaying down a snake.
  List<Offset> ride(int from, int to) {
    final a = centre(from), b = centre(to);
    if (to > from) return [a, b];
    final d = b - a, len = d.distance;
    final normal = Offset(-d.dy, d.dx) / len;
    return [
      for (var i = 0; i <= 40; i++)
        a +
            d * (i / 40) +
            normal *
                (math.sin(i / 40 * math.pi * 3) *
                    math.sin(i / 40 * math.pi) *
                    cellW *
                    .22),
    ];
  }
}

/// The board artwork with this match's ladders and snakes laid over it.
class SnlBoardView extends StatelessWidget {
  const SnlBoardView({super.key, required this.layout, required this.size});
  final SnlLayout layout;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final g = SnlGeometry(size);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(snlBoardAsset,
                fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
          // Ladders lie under the snakes.
          for (final p in layout.pieces)
            if (!p.snake) _ladder(g, p),
          for (final p in layout.pieces)
            if (p.snake) _snake(g, p),
        ],
      ),
    );
  }

  Widget _ladder(SnlGeometry g, SnlPiece p) {
    final foot = g.centre(p.from), top = g.centre(p.to);
    final d = top - foot;
    // Rails run a little past both squares.
    final h = d.distance + g.cellH * .5;
    final w = math.min(h * _ladderAspect[p.skin], g.cellW * .62);
    final mid = (foot + top) / 2;
    return Positioned(
      left: mid.dx - w / 2,
      top: mid.dy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: math.atan2(d.dx, -d.dy),
        child: _shadowed(
          Image.asset('assets/images/snl/ladder${p.skin}.png',
              fit: BoxFit.fill, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }

  Widget _snake(SnlGeometry g, SnlPiece p) {
    final (ratio, hx, hy, tx) = _snakes[p.skin];
    final head = g.centre(p.from), tail = g.centre(p.to);
    final d = tail - head;
    final w = d.distance / (tx - hx);
    // Long snakes keep their shape; none grows fatter than a square.
    final h = math.min(w * ratio, g.cellW * 1.05);
    final angle = math.atan2(d.dy, d.dx);
    return Positioned(
      left: head.dx - hx * w,
      top: head.dy - hy * h,
      width: w,
      height: h,
      child: Transform(
        // Pivot on the head; mirror so the snake is never belly-up.
        origin: Offset(hx * w, hy * h),
        transform: Matrix4.identity()
          ..rotateZ(angle)
          ..scaleByDouble(1, angle.abs() > math.pi / 2 ? -1 : 1, 1, 1),
        child: _shadowed(
          Image.asset('assets/images/snl/snake${p.skin}.png',
              fit: BoxFit.fill, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }

  /// A soft drop shadow so pieces sit above the tiles.
  Widget _shadowed(Widget image) => Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(
            offset: const Offset(2, 3),
            child: Opacity(
              opacity: .3,
              child: ColorFiltered(
                colorFilter:
                    const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                child: image,
              ),
            ),
          ),
          image,
        ],
      );
}
