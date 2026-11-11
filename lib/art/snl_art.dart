import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/snl_layout.dart';

const snlGridAsset = 'assets/images/snl/grid.jpg';

/// Natural width / height of the framed board. It may be drawn a little
/// squatter than this to use the full width of a short screen.
const snlAspect = .72;

/// The gold frame's thickness as a fraction of the board's width.
const _frame = .022;

/// Front-facing ladder pictures (the others are drawn at an angle).
const _straightLadders = [0, 5, 7, 8];

/// Width / height of each upright ladder image.
const _ladderAspect = [
  .335, .396, .215, .33, .272, .217, .272, //
  .311, .2, .33, .415, .396, .396, .261,
];

/// Maps squares to pixels for a board drawn at [size].
class SnlGeometry {
  const SnlGeometry(this.size);
  final Size size;

  double get frame => size.width * _frame;
  double get cellW => (size.width - frame * 2) / 10;
  double get cellH => (size.height - frame * 2) / 10;

  /// Centre of square [n] (1..100).
  Offset centre(int n) {
    final c = snlCell(n);
    return Offset(frame + (c.x + .5) * cellW, frame + (9 - c.y + .5) * cellH);
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

  Widget _ladder(SnlGeometry g, SnlPiece p) {
    final foot = g.centre(p.from), top = g.centre(p.to);
    final d = top - foot;
    // Rails run a little past both squares.
    final h = d.distance + g.cellH * .36;
    final skin = _straightLadders[p.skin % _straightLadders.length];
    final w = math.min(h * _ladderAspect[skin], g.cellW * .6);
    final mid = (foot + top) / 2 - Offset(g.frame, g.frame);
    return Positioned(
      left: mid.dx - w / 2,
      top: mid.dy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        // Random boards only have upright ladders, so this is zero there.
        angle: math.atan2(d.dx, -d.dy),
        child: _shadowed(
          Image.asset('assets/images/snl/ladder$skin.png',
              fit: BoxFit.fill, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }

  /// A snake is never rotated: its picture is scaled (and mirrored when it
  /// runs the other way) so the head sits on its square and the tail tip on
  /// the square it drops to.
  Widget _snake(SnlGeometry g, SnlPiece p) {
    final skin = snakeSkins[p.skin % snakeSkins.length];
    final (l, t, r, b) = snakeBox(skin, p.from, p.to);
    final tailLeft = snlCell(p.to).x < snlCell(p.from).x ||
        (snlCell(p.to).x == snlCell(p.from).x && p.from.isOdd);
    // The pictures' tails all point right unless noted by their anchors.
    final mirrored = tailLeft != (skin.tx < skin.hx);
    final rect =
        Rect.fromLTRB(l * g.cellW, t * g.cellH, r * g.cellW, b * g.cellH);
    return Positioned.fromRect(
      rect: rect,
      child: Transform.flip(
        flipX: mirrored,
        child: _shadowed(
          Image.asset('assets/images/snl/snake${p.skin % snakeSkins.length}.png',
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
