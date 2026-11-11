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

/// Squares on the board artwork are about this much taller than wide.
const snlTall = 1.3;

/// Where the ladders and snakes are for one match.
class SnlLayout {
  SnlLayout(this.pieces)
      : ladders = {for (final p in pieces) if (!p.snake) p.from: p.to},
        snakes = {for (final p in pieces) if (p.snake) p.from: p.to};

  final List<SnlPiece> pieces;

  /// Foot -> top, and head -> tail.
  final Map<int, int> ladders, snakes;

  static const ladderSkins = 4;
  static const snakeSkins = 4;

  /// A fixed board used by the rule tests.
  static final classic = SnlLayout(const [
    SnlPiece(4, 25, 0),
    SnlPiece(13, 46, 1),
    SnlPiece(33, 49, 2),
    SnlPiece(42, 63, 3),
    SnlPiece(50, 69, 0),
    SnlPiece(62, 81, 1),
    SnlPiece(74, 92, 2),
    SnlPiece(27, 5, 0),
    SnlPiece(40, 3, 1),
    SnlPiece(43, 18, 2),
    SnlPiece(54, 31, 3),
    SnlPiece(66, 45, 0),
    SnlPiece(76, 58, 1),
    SnlPiece(89, 53, 2),
    SnlPiece(99, 41, 3),
  ]);

  /// A fresh, fair board. Ladders and snakes run straight from square
  /// centre to square centre, upright or slanting (like 7 to 61), never
  /// share a square, never cross or crowd each other, and one snake always
  /// waits in the last row.
  factory SnlLayout.random([Random? random]) {
    final rng = random ?? Random();
    for (var attempt = 0; attempt < 2000; attempt++) {
      final layout = _tryBuild(rng);
      if (layout != null) return layout;
    }
    return classic;
  }

  static SnlLayout? _tryBuild(Random rng) {
    final pieces = <SnlPiece>[];
    final used = <int>{1, 100};
    // Points sampled along every piece placed so far, in board units.
    final taken = <Point<double>>[];

    int square(int col, int row) => row * 10 + (row.isOdd ? 9 - col : col) + 1;

    bool place(int from, int to, int skin) {
      if (used.contains(from) || used.contains(to)) return false;
      final a = snlCell(from), b = snlCell(to);
      final ax = a.x.toDouble(), ay = a.y * snlTall;
      final bx = b.x.toDouble(), by = b.y * snlTall;
      final line = [
        for (var i = 0; i <= 10; i++)
          Point(ax + (bx - ax) * i / 10, ay + (by - ay) * i / 10),
      ];
      for (final p in line) {
        if (taken.any((q) => q.distanceTo(p) < .92)) return false;
      }
      used..add(from)..add(to);
      taken.addAll(line);
      pieces.add(SnlPiece(from, to, skin));
      return true;
    }

    /// A partner square [rows] up or down and at most [rows] + 1 columns
    /// across, so nothing lies flatter than about 45 degrees.
    int? partner(int col, int row, int rows, {required bool up}) {
      final r = up ? row + rows : row - rows;
      if (r < 0 || r > 9) return null;
      final c = col + rng.nextInt(rows * 2 + 3) - rows - 1;
      if (c < 0 || c > 9) return null;
      return square(c, r);
    }

    // Snakes: heads from the top row down.
    for (final (i, row) in [9, 8, 7, 6, 4, 3].indexed) {
      var ok = false;
      for (var t = 0; t < 150 && !ok; t++) {
        final col = rng.nextInt(10);
        final to = partner(col, row, 2 + rng.nextInt(3), up: false);
        if (to == null) continue;
        ok = place(square(col, row), to, i % snakeSkins);
      }
      if (!ok) return null;
    }
    // Ladders: feet from the bottom rows up.
    for (final (i, row) in [0, 1, 2, 3, 5, 6].indexed) {
      var ok = false;
      for (var t = 0; t < 150 && !ok; t++) {
        final col = rng.nextInt(10);
        final to = partner(col, row, 2 + rng.nextInt(3), up: true);
        if (to == null) continue;
        ok = place(square(col, row), to, i % ladderSkins);
      }
      if (!ok) return null;
    }
    return SnlLayout(pieces);
  }
}
