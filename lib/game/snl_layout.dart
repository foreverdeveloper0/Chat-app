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

/// Where the ladders and snakes are for one match.
class SnlLayout {
  SnlLayout(this.pieces)
      : ladders = {for (final p in pieces) if (!p.snake) p.from: p.to},
        snakes = {for (final p in pieces) if (p.snake) p.from: p.to};

  final List<SnlPiece> pieces;

  /// Foot -> top, and head -> tail.
  final Map<int, int> ladders, snakes;

  static const ladderSkins = 14;

  /// Slim snake artwork that stretches cleanly between two squares.
  static const snakeSkins = 6;

  /// Squares are taller than they are wide on the board artwork.
  static const _tall = 1.42;

  /// The fixed board used by the rule tests.
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
    SnlPiece(54, 31, 3),
    SnlPiece(66, 45, 4),
    SnlPiece(76, 58, 5),
    SnlPiece(89, 53, 0),
    SnlPiece(99, 41, 1),
  ]);

  /// A fresh, fair board: six ladders and seven snakes spread over the
  /// rows, never sharing a square, never on 1 or 100, never crossing or
  /// crowding each other, with a snake lurking in the last row.
  factory SnlLayout.random([Random? random]) {
    final rng = random ?? Random();
    for (var attempt = 0; attempt < 400; attempt++) {
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
    final ladderSkin = List.generate(ladderSkins, (i) => i)..shuffle(rng);
    final snakeSkin = List.generate(snakeSkins, (i) => i)..shuffle(rng);

    bool place(int from, int to) {
      if (from < 2 || to < 2 || from > 99 || to > 99) return false;
      if (used.contains(from) || used.contains(to)) return false;
      final a = snlCell(from), b = snlCell(to);
      final ax = a.x.toDouble(), ay = a.y * _tall;
      final bx = b.x.toDouble(), by = b.y * _tall;
      final span = sqrt(pow(ax - bx, 2) + pow(ay - by, 2));
      if (span < 2 || span > 7.5) return false;
      // A snake's curves need room on both sides, so it never runs along
      // the outer columns; a ladder there is fine as long as it is upright.
      final edge = (a.x == 0 || a.x == 9) && (b.x == 0 || b.x == 9);
      if (to < from ? (a.x + b.x < 2 || a.x + b.x > 16) : (edge && a.x != b.x)) {
        return false;
      }
      final line = [
        for (var i = 0; i <= 8; i++)
          Point(ax + (bx - ax) * i / 8, ay + (by - ay) * i / 8),
      ];
      // Keep clear of everything already on the board.
      for (final p in line) {
        if (taken.any((q) => q.distanceTo(p) < .95)) return false;
      }
      final count = pieces.where((p) => p.snake == (to < from)).length;
      final skin = to > from
          ? ladderSkin[count % ladderSkins]
          : snakeSkin[count % snakeSkins];
      used..add(from)..add(to);
      taken.addAll(line);
      pieces.add(SnlPiece(from, to, skin));
      return true;
    }

    int square(int col, int row) => row * 10 + (row.isOdd ? 9 - col : col) + 1;

    // Snakes first (the top-row one must fit): heads from the top down.
    for (final row in [9, 8, 7, 6, 5, 3, 2]) {
      var ok = false;
      for (var i = 0; i < 60 && !ok; i++) {
        final col = rng.nextInt(10);
        final drop = 1 + rng.nextInt(row == 9 ? 4 : 3);
        if (row - drop < 0) continue;
        final tail = (col + rng.nextInt(7) - 3).clamp(0, 9);
        ok = place(square(col, row), square(tail, row - drop));
      }
      if (!ok) return null;
    }
    // Ladders: feet spread from the bottom rows up.
    for (final row in [0, 1, 2, 4, 5, 6]) {
      var ok = false;
      for (var i = 0; i < 60 && !ok; i++) {
        final col = rng.nextInt(10);
        final rise = 1 + rng.nextInt(3);
        if (row + rise > 9) continue;
        final top = (col + rng.nextInt(5) - 2).clamp(0, 9);
        ok = place(square(col, row), square(top, row + rise));
      }
      if (!ok) return null;
    }
    return SnlLayout(pieces);
  }
}
