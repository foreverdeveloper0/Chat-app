import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/snl_layout.dart';

const snlBoardAsset = 'assets/images/snl/board.png';

/// Width / height of the board artwork (crown and frame included).
const snlAspect = 941 / 1447;

/// Where the 10x10 grid sits inside the artwork, as fractions of its size.
const _gridLeft = .0319, _gridWidth = .9394, _gridTop = .0919, _gridHeight = .8528;

/// Width / height of each upright ladder image.
const _ladderAspect = [
  .335, .396, .215, .33, .272, .217, .272, //
  .311, .2, .33, .415, .396, .396, .261,
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
          // Nothing may spill over the gold frame: pieces are clipped to
          // the playing grid. Ladders lie under the snakes.
          Positioned.fill(
            child: ClipRRect(
              clipper: _GridClipper(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
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
    final w = math.min(h * _ladderAspect[p.skin], g.cellW * .66);
    final mid = (foot + top) / 2;
    return Positioned(
      left: mid.dx - w / 2,
      top: mid.dy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        // Random boards only have upright ladders, so this is zero there.
        angle: math.atan2(d.dx, -d.dy),
        child: _shadowed(
          Image.asset('assets/images/snl/ladder${p.skin}.png',
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
    final rect = Rect.fromLTRB(
      size.width * _gridLeft + l * g.cellW,
      size.height * _gridTop + t * g.cellH,
      size.width * _gridLeft + r * g.cellW,
      size.height * _gridTop + b * g.cellH,
    );
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

class _GridClipper extends CustomClipper<RRect> {
  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * _gridLeft, size.height * _gridTop,
            size.width * _gridWidth, size.height * _gridHeight),
        Radius.circular(size.width * .03),
      );

  @override
  bool shouldReclip(_GridClipper old) => false;
}
