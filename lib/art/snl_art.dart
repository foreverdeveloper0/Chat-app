import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/snl_layout.dart';

const snlGridAsset = 'assets/images/snl/grid.jpg';

/// Natural width / height of the framed board. It may be drawn a little
/// squatter than this to use the full width of a short screen.
const snlAspect = .72;

/// The gold frame's thickness as a fraction of the board's width.
const _frame = .022;

/// Width / height of the four front-facing ladder pictures.
const _ladderAspect = [.335, .217, .311, .2];
const _ladderFiles = [0, 5, 7, 8];

/// Each slim snake lies head-left to tail-right: (height / width, head x,
/// head-and-tail y, tail x), the last three as fractions of the picture.
const _snakes = [
  (92 / 600, .045, .322, .994),
  (76 / 600, .047, .365, .994),
  (69 / 600, .047, .419, .992),
  (71 / 600, .048, .441, .992),
];

/// The grid artwork's tiles are not all the same size (the 1 and 100
/// squares are wider), so these are the measured tile edges, as fractions
/// of the grid picture, left to right and top to bottom.
const _colEdges = [
  0.0, 108 / 884, 196 / 884, 290 / 884, 373 / 884, 462 / 884, //
  542 / 884, 633 / 884, 713 / 884, 804 / 884, 1.0,
];
const _rowEdges = [
  0.0, 155 / 1234, 281 / 1234, 414 / 1234, 532 / 1234, 657 / 1234, //
  767 / 1234, 885 / 1234, 986 / 1234, 1105 / 1234, 1.0,
];

/// Maps squares to pixels for a board drawn at [size].
class SnlGeometry {
  const SnlGeometry(this.size);
  final Size size;

  double get frame => size.width * _frame;
  double get gridW => size.width - frame * 2;
  double get gridH => size.height - frame * 2;
  double get cellW => gridW / 10;
  double get cellH => gridH / 10;

  /// Centre of square [n] (1..100), on the real tile.
  Offset centre(int n) {
    final c = snlCell(n);
    final row = 9 - c.y;
    return Offset(
      frame + (_colEdges[c.x] + _colEdges[c.x + 1]) / 2 * gridW,
      frame + (_rowEdges[row] + _rowEdges[row + 1]) / 2 * gridH,
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
    final grid = Rect.fromLTWH(
        g.frame, g.frame, size.width - g.frame * 2, size.height - g.frame * 2);
    return Container(
      width: size.width,
      height: size.height,
      // A plain gold frame hugging the grid: no crown, no ornaments.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(g.frame * 2.2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF3B8),
            Color(0xFFE3B341),
            Color(0xFFFFE28A),
            Color(0xFF9C6B0E),
            Color(0xFFE9C46A),
          ],
          stops: [0, .3, .55, .82, 1],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x99000010), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: grid,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(g.frame * 1.2),
              // Pieces are clipped to the grid so nothing spills over the
              // frame. Ladders lie under the snakes.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Image.asset(snlGridAsset,
                        fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  ),
                  for (final p in layout.pieces)
                    if (!p.snake) _ladder(g, p),
                  for (final p in layout.pieces)
                    if (p.snake) _snake(g, p),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A ladder runs straight from the middle of its foot square to the
  /// middle of its top square, upright or slanting.
  Widget _ladder(SnlGeometry g, SnlPiece p) {
    final foot = g.centre(p.from), top = g.centre(p.to);
    final d = top - foot;
    final skin = p.skin % _ladderFiles.length;
    // Rails run a little past both squares.
    final h = d.distance + g.cellH * .4;
    final w = math.min(h * _ladderAspect[skin], g.cellW * .52);
    final mid = (foot + top) / 2 - Offset(g.frame, g.frame);
    return Positioned(
      left: mid.dx - w / 2,
      top: mid.dy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: math.atan2(d.dx, -d.dy),
        child: _shadowed(
          Image.asset('assets/images/snl/ladder${_ladderFiles[skin]}.png',
              fit: BoxFit.fill, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }

  /// A slim snake lies along the line from its head square to its tail
  /// square, head first, and is mirrored when it heads left so it is never
  /// belly-up.
  Widget _snake(SnlGeometry g, SnlPiece p) {
    final (ratio, hx, hy, tx) = _snakes[p.skin % _snakes.length];
    final head = g.centre(p.from) - Offset(g.frame, g.frame);
    final tail = g.centre(p.to) - Offset(g.frame, g.frame);
    final d = tail - head;
    final w = d.distance / (tx - hx);
    // Slim, but never so thin that the head is hard to see.
    final h = (w * ratio).clamp(g.cellW * .36, g.cellW * .5);
    final angle = math.atan2(d.dy, d.dx);
    return Positioned(
      left: head.dx - hx * w,
      top: head.dy - hy * h,
      width: w,
      height: h,
      child: Transform(
        origin: Offset(hx * w, hy * h),
        transform: Matrix4.identity()
          ..rotateZ(angle)
          ..scaleByDouble(1, angle.abs() > math.pi / 2 ? -1 : 1, 1, 1),
        child: _shadowed(
          Image.asset('assets/images/snl/snake${p.skin % _snakes.length}.png',
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
