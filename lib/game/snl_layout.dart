import 'dart:math';

/// A ladder (from < to) or a snake (from > to), and which artwork it wears.
class SnlPiece {
  const SnlPiece(this.from, this.to, this.skin);
  final int from, to, skin;
  bool get snake => to < from;
}

/// Column and row (from the bottom) of square [n]; the numbers wind up the
/// board from the bottom-left corner.
Point<int> snlCell(int n) {
  final row = (n - 1) ~/ 10;
  final col = (n - 1) % 10;
  return Point(row.isOdd ? 9 - col : col, row);
}

/// One snake picture: its size in pixels, where its head and tail tip are
/// (as fractions of the picture), and the (rows down, columns across) drops
/// it can make while keeping its natural upright shape.
class SnakeSkin {
  const SnakeSkin(this.w, this.h, this.hx, this.hy, this.tx, this.ty, this.fits);
  final double w, h, hx, hy, tx, ty;
  final List<(int, int)> fits;
}

const snakeSkins = [
  SnakeSkin(354, 420, .202, .116, .975, .998, [(2, 2)]),
  SnakeSkin(420, 414, .149, .108, .988, .937, [(2, 3)]),
  SnakeSkin(207, 420, .649, .116, .498, .998, [(2, 0), (3, 0)]),
];

/// Squares on the board artwork are this much taller than they are wide.
const snlTall = 1.3;

/// The picture's box for a snake from [head] to [tail], in board units
/// (columns across, visual rows down): left, top, right, bottom.
(double, double, double, double) snakeBox(SnakeSkin s, int head, int tail) {
  final a = snlCell(head), b = snlCell(tail);
  final rows = (a.y - b.y).toDouble(), cols = (b.x - a.x).toDouble();
  final sy = rows / ((s.ty - s.hy) * s.h);
  final natural = (s.tx - s.hx) * s.w;
  // Mirror or stretch sideways so the tail lands on its square.
  final sx = cols != 0
      ? cols / natural
      : sy * snlTall * (head.isEven ? 1 : -1);
  final x0 = a.x + .5 - s.hx * s.w * sx, x1 = x0 + s.w * sx;
  final top = (9 - a.y) + .5 - s.hy * s.h * sy;
  return (min(x0, x1), top, max(x0, x1), top + s.h * sy);
}

/// Where the ladders and snakes are for one match.
class SnlLayout {
  SnlLayout(this.pieces)
      : ladders = {for (final p in pieces) if (!p.snake) p.from: p.to},
        snakes = {for (final p in pieces) if (p.snake) p.from: p.to};

  final List<SnlPiece> pieces;

  /// Foot -> top, and head -> tail.
  final Map<int, int> ladders, snakes;

  static const ladderSkins = 14;

  /// A fixed board used by the rule tests.
  static final classic = SnlLayout(const [
    SnlPiece(4, 25, 0),
    SnlPiece(13, 46, 1),
    SnlPiece(33, 49, 2),
    SnlPiece(42, 63, 3),
    SnlPiece(50, 69, 4),
    SnlPiece(62, 81, 5),
    SnlPiece(74, 92, 6),
    SnlPiece(27, 5, 0),
    SnlPiece(40, 3, 1),
    SnlPiece(43, 18, 2),
    SnlPiece(54, 31, 0),
    SnlPiece(66, 45, 1),
    SnlPiece(76, 58, 0),
    SnlPiece(89, 53, 2),
    SnlPiece(99, 41, 1),
  ]);

  /// A fresh, fair board. Ladders stand straight up their column; every
  /// snake keeps its natural upright shape, fits wholly inside the board and
  /// keeps clear of the others. One snake always waits in the last row.
  factory SnlLayout.random([Random? random]) {
    final rng = random ?? Random();
    for (var attempt = 0; attempt < 3000; attempt++) {
      final layout = _tryBuild(rng);
      if (layout != null) return layout;
    }
    return classic;
  }

  static SnlLayout? _tryBuild(Random rng) {
    final pieces = <SnlPiece>[];
    final used = <int>{1, 100};
    final boxes = <(double, double, double, double)>[];
    final ladderSkin = List.generate(ladderSkins, (i) => i)..shuffle(rng);
    final skinOrder = List.generate(snakeSkins.length, (i) => i)..shuffle(rng);

    int square(int col, int row) => row * 10 + (row.isOdd ? 9 - col : col) + 1;
    bool clear((double, double, double, double) box) {
      for (final o in boxes) {
        if (box.$1 < o.$3 && o.$1 < box.$3 && box.$2 < o.$4 && o.$2 < box.$4) {
          return false;
        }
      }
      return true;
    }

    // Snakes: heads from the top row down.
    var n = 0;
    for (final row in [9, 8, 6, 5, 3]) {
      var ok = false;
      for (var i = 0; i < 160 && !ok; i++) {
        // Each snake gets its own picture; only after many misses does
        // it borrow another one.
        final skin = skinOrder[(n + i ~/ 60) % snakeSkins.length];
        final s = snakeSkins[skin];
        final (rows, cols) = s.fits[rng.nextInt(s.fits.length)];
        if (row - rows < 0) continue;
        final col = rng.nextInt(10);
        final tailCol = col + (rng.nextBool() ? cols : -cols);
        if (tailCol < 0 || tailCol > 9) continue;
        final from = square(col, row), to = square(tailCol, row - rows);
        if (used.contains(from) || used.contains(to)) continue;
        final box = snakeBox(s, from, to);
        // The whole picture stays on the playing grid...
        if (box.$1 < -.05 || box.$3 > 10.05 || box.$2 < -.1 || box.$4 > 10.1) {
          continue;
        }
        // ...and its core keeps off every other piece.
        final w = box.$3 - box.$1, h = box.$4 - box.$2;
        final core = (
          box.$1 + w * .06,
          box.$2 + h * .04,
          box.$3 - w * .06,
          box.$4 - h * .04,
        );
        if (!clear(core)) continue;
        boxes.add(core);
        used..add(from)..add(to);
        pieces.add(SnlPiece(from, to, skin));
        ok = true;
      }
      if (!ok) return null;
      n++;
    }

    // Ladders: straight up one column, feet spread from the bottom rows up.
    for (final row in [0, 1, 2, 3, 5, 6]) {
      var ok = false;
      for (var i = 0; i < 80 && !ok; i++) {
        final col = rng.nextInt(10);
        final rise = 1 + rng.nextInt(3);
        if (row + rise > 9) continue;
        final from = square(col, row), to = square(col, row + rise);
        if (used.contains(from) || used.contains(to)) continue;
        final box = (
          col + .12,
          (9 - row - rise) + .2,
          col + .88,
          (9 - row) + .8,
        );
        if (!clear(box)) continue;
        boxes.add(box);
        used..add(from)..add(to);
        pieces.add(SnlPiece(
            from, to, ladderSkin[pieces.where((p) => !p.snake).length]));
        ok = true;
      }
      if (!ok) return null;
    }
    return SnlLayout(pieces);
  }
}
