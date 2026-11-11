import 'dart:collection';
import 'dart:math';

typedef Cell = Point<int>;

enum SnakeDir {
  up(0, -1),
  right(1, 0),
  down(0, 1),
  left(-1, 0);

  const SnakeDir(this.dx, this.dy);
  final int dx, dy;

  SnakeDir get opposite => SnakeDir.values[(index + 2) % 4];

  /// Heading in radians, with "right" as zero and angles growing clockwise.
  double get angle => (index - 1) * pi / 2;
}

enum SnakeSpeed {
  easy('Easy', 190, 110),
  normal('Normal', 140, 80),
  hard('Hard', 100, 60);

  const SnakeSpeed(this.label, this.startMs, this.minMs);
  final String label;

  /// Milliseconds per step at the start, and the fastest it ever gets.
  final int startMs, minMs;
}

/// What happened during one [SnakeGame.step].
class SnakeStep {
  bool ate = false;
  bool ateBonus = false;
  bool died = false;
  bool won = false;
  bool bonusSpawned = false;
  bool bonusExpired = false;

  /// Points earned, where, and which fruit it was.
  int gained = 0;
  Cell? at;
  int kind = 0;
}

/// Classic Snake on a grid: eat fruit to grow and score, never run into
/// yourself, and (unless the arena is open) never run into a wall.
class SnakeGame {
  SnakeGame({
    this.cols = 15,
    this.rows = 15,
    this.wrap = false,
    this.speed = SnakeSpeed.normal,
    Random? random,
  }) : _rng = random ?? Random() {
    reset();
  }

  static const fruitKinds = 4;

  /// A timed bonus appears after every this many fruits...
  static const bonusEvery = 5;

  /// ...and stays for this many steps.
  static const bonusLife = 45;

  final int cols, rows;

  /// Open arena: leaving one edge brings the snake back on the other.
  final bool wrap;
  final SnakeSpeed speed;
  final Random _rng;

  /// Cells from head to tail.
  List<Cell> body = [];
  SnakeDir dir = SnakeDir.right;
  final _turns = ListQueue<SnakeDir>();

  Cell food = const Cell(0, 0);
  int foodKind = 0;
  Cell? bonus;
  int bonusSteps = 0;

  int score = 0;
  int eaten = 0;
  int steps = 0;
  bool alive = true;
  bool won = false;

  /// The cell the tail left in the last step; null if the snake grew.
  Cell? droppedTail;

  void reset() {
    final y = rows ~/ 2, x = cols ~/ 2 - 1;
    body = [Cell(x, y), Cell(x - 1, y), Cell(x - 2, y)];
    dir = SnakeDir.right;
    _turns.clear();
    bonus = null;
    bonusSteps = 0;
    score = 0;
    eaten = 0;
    steps = 0;
    alive = true;
    won = false;
    droppedTail = null;
    _placeFood();
  }

  Cell get head => body.first;
  int get length => body.length;
  int get level => 1 + eaten ~/ bonusEvery;

  /// The snake speeds up a little with every fruit.
  int get stepMs => max(speed.minMs, speed.startMs - eaten * 2);

  /// Queues a turn. Reversing onto yourself is ignored, and up to two
  /// turns are remembered so quick double swipes both count.
  void turn(SnakeDir d) {
    final last = _turns.isEmpty ? dir : _turns.last;
    if (d == last || d == last.opposite) return;
    if (_turns.length < 2) _turns.add(d);
  }

  bool inside(Cell c) => c.x >= 0 && c.y >= 0 && c.x < cols && c.y < rows;

  /// The cell one move from [from], or null if that is a wall.
  Cell? neighbour(Cell from, SnakeDir d) {
    var c = Cell(from.x + d.dx, from.y + d.dy);
    if (wrap) c = Cell((c.x + cols) % cols, (c.y + rows) % rows);
    return inside(c) ? c : null;
  }

  SnakeStep step() {
    final out = SnakeStep();
    if (!alive || won) return out;
    if (_turns.isNotEmpty) dir = _turns.removeFirst();

    final next = neighbour(head, dir);
    final grows = next != null && (next == food || next == bonus);
    // The tail moves out of the way unless the snake is growing.
    final blocked = grows ? body : body.take(body.length - 1);
    if (next == null || blocked.contains(next)) {
      alive = false;
      out.died = true;
      return out;
    }

    steps++;
    body.insert(0, next);
    droppedTail = grows ? null : body.removeLast();

    if (next == food) {
      eaten++;
      out
        ..ate = true
        ..gained = 10
        ..at = next
        ..kind = foodKind;
      score += out.gained;
      if (!_placeFood()) {
        won = true;
        out.won = true;
        return out;
      }
      if (eaten % bonusEvery == 0 && bonus == null) {
        bonus = _freeCell();
        bonusSteps = bonusLife;
        out.bonusSpawned = bonus != null;
      }
    } else if (next == bonus) {
      // Worth more the sooner it is grabbed.
      out
        ..ateBonus = true
        ..gained = 20 + bonusSteps
        ..at = next;
      score += out.gained;
      bonus = null;
    }

    if (bonus != null && --bonusSteps <= 0) {
      bonus = null;
      out.bonusExpired = true;
    }
    return out;
  }

  Cell? _freeCell() {
    final free = [
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < cols; x++)
          if (!body.contains(Cell(x, y)) &&
              Cell(x, y) != bonus &&
              Cell(x, y) != food)
            Cell(x, y),
    ];
    return free.isEmpty ? null : free[_rng.nextInt(free.length)];
  }

  bool _placeFood() {
    // Park the old fruit off the board so its cell counts as free.
    food = const Cell(-1, -1);
    final cell = _freeCell();
    if (cell == null) return false;
    food = cell;
    foodKind = _rng.nextInt(fruitKinds);
    return true;
  }

  // ── Self-playing snake (used by the home page demo) ──

  /// Cells reachable from [from] without crossing the body.
  int _room(Cell from, Set<Cell> walls) {
    final seen = {from};
    final queue = ListQueue<Cell>()..add(from);
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      for (final d in SnakeDir.values) {
        final n = neighbour(c, d);
        if (n != null && !walls.contains(n) && seen.add(n)) queue.add(n);
      }
    }
    return seen.length;
  }

  /// A sensible next heading: the shortest safe route to the fruit, or
  /// failing that the move that leaves the most room.
  SnakeDir? botMove() {
    final walls = body.take(body.length - 1).toSet();
    final target = bonus ?? food;

    // Breadth-first search from the head, remembering the first move.
    final first = <Cell, SnakeDir>{};
    final queue = ListQueue<Cell>();
    for (final d in SnakeDir.values) {
      if (d == dir.opposite) continue;
      final n = neighbour(head, d);
      if (n != null && !walls.contains(n) && !first.containsKey(n)) {
        first[n] = d;
        queue.add(n);
      }
    }
    SnakeDir? toFood;
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      if (c == target) {
        toFood = first[c];
        break;
      }
      for (final d in SnakeDir.values) {
        final n = neighbour(c, d);
        if (n != null && !walls.contains(n) && !first.containsKey(n)) {
          first[n] = first[c]!;
          queue.add(n);
        }
      }
    }

    SnakeDir? best;
    var bestRoom = -1;
    for (final d in SnakeDir.values) {
      if (d == dir.opposite) continue;
      final n = neighbour(head, d);
      if (n == null || walls.contains(n)) continue;
      final room = _room(n, {...walls, head});
      // Take the route to the fruit only if it does not box the snake in.
      if (d == toFood && room >= length) return d;
      if (room > bestRoom) {
        bestRoom = room;
        best = d;
      }
    }
    return best;
  }
}
