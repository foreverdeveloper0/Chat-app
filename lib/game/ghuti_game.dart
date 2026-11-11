import 'dart:math';
import 'dart:ui' show Offset;

/// A point on the board: column 0..4, row -2..6 (rows -2 and -1 are the
/// top triangle, 0..4 the square, 5 and 6 the bottom triangle).
typedef Pt = Point<int>;

/// One move: a step to a neighbour, or one or more jumps in a row, each
/// taking the piece it leaps over.
class GhutiMove {
  const GhutiMove(this.path, this.captured);

  /// Points the piece visits, starting where it stands.
  final List<Pt> path;
  final List<Pt> captured;
  Pt get from => path.first;
  Pt get to => path.last;
  bool get isCapture => captured.isNotEmpty;
}

/// Sholo Guti (16 pieces each) on the 37-point board.
///
/// Pieces move one step along a line to an empty neighbouring point, or
/// jump straight over an adjacent enemy piece to the empty point beyond it,
/// taking it. After a capture the same piece may keep jumping. A player who
/// has lost every piece, or cannot move, loses.
class GhutiGame {
  GhutiGame({this.bots = const {}, Random? random})
      : rng = random ?? Random() {
    for (final p in points) {
      if (p.y >= 3) board[p] = 0;
      if (p.y <= 1) board[p] = 1;
    }
  }

  /// Player 0 starts at the bottom and moves first; player 1 is at the top.
  final Set<int> bots;
  final Random rng;

  /// Who stands where (absent = empty).
  final board = <Pt, int>{};
  int current = 0;
  int? winner;

  /// True when the game ended without a winner (long stalemate).
  bool draw = false;

  /// A piece that has just captured and may jump again, if any.
  Pt? chaining;

  /// Moves since the last capture; the game is drawn after [drawAfter].
  int quiet = 0;
  static const drawAfter = 80;

  static final List<Pt> points = [
    for (final c in [0, 2, 4]) Pt(c, -2),
    for (final c in [1, 2, 3]) Pt(c, -1),
    for (var r = 0; r < 5; r++)
      for (var c = 0; c < 5; c++) Pt(c, r),
    for (final c in [1, 2, 3]) Pt(c, 5),
    for (final c in [0, 2, 4]) Pt(c, 6),
  ];

  /// Every straight line on the board, as its points in order.
  static final List<List<Pt>> lines = () {
    final set = points.toSet();
    final out = <List<Pt>>[];
    // Rows.
    for (var r = -2; r <= 6; r++) {
      final row = [for (final p in points) if (p.y == r) p]
        ..sort((a, b) => a.x.compareTo(b.x));
      if (row.length > 1) out.add(row);
    }
    // Columns: the middle one runs through both triangles.
    for (var c = 0; c < 5; c++) {
      final col = [
        for (var r = c == 2 ? -2 : 0; r <= (c == 2 ? 6 : 4); r++) Pt(c, r),
      ];
      out.add(col);
    }
    // Diagonals through the even points, continuing into the triangles.
    for (final dir in [1, -1]) {
      for (var k = -8; k <= 8; k += 2) {
        final diag = [
          for (final p in points)
            if ((p.x + p.y).isEven && (dir == 1 ? p.x - p.y : p.x + p.y) == k) p,
        ]..sort((a, b) => a.y.compareTo(b.y));
        // Only consecutive diagonal steps count.
        var run = <Pt>[];
        for (final p in diag) {
          if (run.isNotEmpty &&
              ((p.x - run.last.x).abs() != 1 || p.y - run.last.y != 1)) {
            if (run.length > 1) out.add(run);
            run = [];
          }
          run.add(p);
        }
        if (run.length > 1) out.add(run);
      }
    }
    assert(out.every((l) => l.every(set.contains)));
    return out;
  }();

  /// For each point, its neighbours and what lies beyond each (if anything).
  static final Map<Pt, List<(Pt, Pt?)>> _links = () {
    final m = <Pt, List<(Pt, Pt?)>>{for (final p in points) p: []};
    for (final l in lines) {
      for (var i = 0; i < l.length; i++) {
        if (i + 1 < l.length) {
          m[l[i]]!.add((l[i + 1], i + 2 < l.length ? l[i + 2] : null));
        }
        if (i - 1 >= 0) {
          m[l[i]]!.add((l[i - 1], i - 2 >= 0 ? l[i - 2] : null));
        }
      }
    }
    return m;
  }();

  static List<Pt> neighbours(Pt p) => [for (final (n, _) in _links[p]!) n];

  int count(int player) => board.values.where((v) => v == player).length;
  bool isBot(int player) => bots.contains(player);

  /// Single jumps available to the piece on [p].
  List<(Pt, Pt)> _jumps(Pt p, Map<Pt, int> b) {
    final me = b[p];
    return [
      for (final (over, land) in _links[p]!)
        if (land != null &&
            b[over] != null &&
            b[over] != me &&
            !b.containsKey(land))
          (over, land),
    ];
  }

  /// Every legal move for [player]: steps and full capture chains.
  List<GhutiMove> movesFor(int player, [Map<Pt, int>? on]) {
    final b = on ?? board;
    final out = <GhutiMove>[];
    for (final p in b.keys.toList()) {
      if (b[p] != player) continue;
      for (final n in neighbours(p)) {
        if (!b.containsKey(n)) out.add(GhutiMove([p, n], const []));
      }
      void chain(Map<Pt, int> state, List<Pt> path, List<Pt> taken) {
        final here = path.last;
        final jumps = _jumps(here, state);
        for (final (over, land) in jumps) {
          final next = Map.of(state)
            ..remove(here)
            ..remove(over)
            ..[land] = player;
          final p2 = [...path, land], t2 = [...taken, over];
          out.add(GhutiMove(p2, t2));
          chain(next, p2, t2);
        }
      }

      chain(b, [p], []);
    }
    return out;
  }

  /// Destinations for the piece on [from] this turn: steps (unless it is in
  /// the middle of a chain) and single jumps, each with what it captures.
  List<(Pt, Pt?)> targets(Pt from) {
    if (winner != null || draw || board[from] != current) return const [];
    if (chaining != null && chaining != from) return const [];
    return [
      if (chaining == null)
        for (final n in neighbours(from))
          if (!board.containsKey(n)) (n, null),
      for (final (over, land) in _jumps(from, board)) (land, over),
    ];
  }

  /// Plays one step or one jump. Returns the captured point, if any.
  /// After a jump the turn stays with the player while that piece can jump
  /// again; call [endTurn] to stop early.
  Pt? play(Pt from, Pt to) {
    final t = targets(from).where((t) => t.$1 == to);
    if (t.isEmpty) throw StateError('illegal move');
    final over = t.first.$2;
    board
      ..remove(from)
      ..[to] = current;
    if (over == null) {
      quiet++;
      _pass();
      return null;
    }
    board.remove(over);
    quiet = 0;
    if (count(1 - current) == 0) {
      winner = current;
      chaining = null;
      return over;
    }
    if (_jumps(to, board).isNotEmpty) {
      chaining = to;
    } else {
      _pass();
    }
    return over;
  }

  /// Ends a capture chain early.
  void endTurn() {
    if (chaining != null) _pass();
  }

  void _pass() {
    chaining = null;
    current = 1 - current;
    if (movesFor(current).isEmpty) {
      winner = 1 - current;
    } else if (quiet >= drawAfter) {
      draw = true;
    }
  }

  // ── Computer player ──

  /// The computer's whole move (a step, or a full capture chain).
  GhutiMove botMove() {
    final me = current, them = 1 - me;
    final moves = movesFor(me);
    GhutiMove? best;
    var bestScore = -1e9;
    for (final m in moves) {
      final b = Map.of(board)..remove(m.from);
      for (final c in m.captured) {
        b.remove(c);
      }
      b[m.to] = me;
      // What the opponent could take back straight away.
      var reply = 0;
      for (final r in movesFor(them, b)) {
        reply = max(reply, r.captured.length);
      }
      // Pieces kept together and moving forward are safer and stronger.
      final ahead = me == 0 ? m.from.y - m.to.y : m.to.y - m.from.y;
      var friends = 0;
      for (final n in neighbours(m.to)) {
        if (b[n] == me) friends++;
      }
      final score = m.captured.length * 10 -
          reply * 9 +
          ahead * .6 +
          friends * .4 +
          rng.nextDouble() * .5;
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    return best!;
  }

  /// Board position of [p] as a fraction of the board picture.
  static Offset spot(Pt p) => _spots[(p.x, p.y)]!;

  static const _spots = {
  (0, -2): Offset(0.0335, 0.0156),
  (2, -2): Offset(0.5006, 0.0156),
  (4, -2): Offset(0.9665, 0.0162),
  (1, -1): Offset(0.2254, 0.1230),
  (2, -1): Offset(0.4994, 0.1230),
  (3, -1): Offset(0.7734, 0.1230),
  (0, 0): Offset(0.0335, 0.2615),
  (1, 0): Offset(0.2682, 0.2615),
  (2, 0): Offset(0.5006, 0.2615),
  (3, 0): Offset(0.7306, 0.2615),
  (4, 0): Offset(0.9665, 0.2622),
  (0, 1): Offset(0.0335, 0.3864),
  (1, 1): Offset(0.2682, 0.3870),
  (2, 1): Offset(0.4994, 0.3876),
  (3, 1): Offset(0.7295, 0.3864),
  (4, 1): Offset(0.9653, 0.3864),
  (0, 2): Offset(0.0335, 0.5125),
  (1, 2): Offset(0.2682, 0.5137),
  (2, 2): Offset(0.5006, 0.5131),
  (3, 2): Offset(0.7306, 0.5137),
  (4, 2): Offset(0.9653, 0.5137),
  (0, 3): Offset(0.0335, 0.6386),
  (1, 3): Offset(0.2694, 0.6386),
  (2, 3): Offset(0.4994, 0.6380),
  (3, 3): Offset(0.7318, 0.6380),
  (4, 3): Offset(0.9653, 0.6392),
  (0, 4): Offset(0.0324, 0.7628),
  (1, 4): Offset(0.2682, 0.7622),
  (2, 4): Offset(0.4994, 0.7622),
  (3, 4): Offset(0.7318, 0.7628),
  (4, 4): Offset(0.9653, 0.7622),
  (1, 5): Offset(0.2659, 0.8808),
  (2, 5): Offset(0.4994, 0.8808),
  (3, 5): Offset(0.7329, 0.8801),
  (0, 6): Offset(0.0798, 0.9794),
  (2, 6): Offset(0.4994, 0.9800),
  (4, 6): Offset(0.9168, 0.9788),
  };
}
