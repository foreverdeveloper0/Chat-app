import 'dart:ui';

/// Board geometry and movement rules for a classic 4-player Ludo board.
///
/// Players: 0 red (top-left), 1 green (top-right), 2 yellow (bottom-right),
/// 3 blue (bottom-left). A token's `progress` is:
///   -1        in the yard
///   0..50     on the shared track (0 is the player's start cell)
///   51..55    in the player's home column
///   56        home
abstract final class LudoRules {
  static const yard = -1;
  static const lastTrack = 50;
  static const home = 56;

  /// The 52 shared cells as (column, row), clockwise from red's start cell.
  static const track = <(int, int)>[
    (1, 6), (2, 6), (3, 6), (4, 6), (5, 6), //
    (6, 5), (6, 4), (6, 3), (6, 2), (6, 1), (6, 0), //
    (7, 0), //
    (8, 0), (8, 1), (8, 2), (8, 3), (8, 4), (8, 5), //
    (9, 6), (10, 6), (11, 6), (12, 6), (13, 6), (14, 6), //
    (14, 7), //
    (14, 8), (13, 8), (12, 8), (11, 8), (10, 8), (9, 8), //
    (8, 9), (8, 10), (8, 11), (8, 12), (8, 13), (8, 14), //
    (7, 14), //
    (6, 14), (6, 13), (6, 12), (6, 11), (6, 10), (6, 9), //
    (5, 8), (4, 8), (3, 8), (2, 8), (1, 8), (0, 8), //
    (0, 7), //
    (0, 6),
  ];

  static const startIndex = [0, 13, 26, 39];

  /// Start cells and star cells: tokens here cannot be captured.
  static const safeIndices = {0, 8, 13, 21, 26, 34, 39, 47};

  static const homeColumns = <List<(int, int)>>[
    [(1, 7), (2, 7), (3, 7), (4, 7), (5, 7)],
    [(7, 1), (7, 2), (7, 3), (7, 4), (7, 5)],
    [(13, 7), (12, 7), (11, 7), (10, 7), (9, 7)],
    [(7, 13), (7, 12), (7, 11), (7, 10), (7, 9)],
  ];

  static const yardOrigins = <(int, int)>[(0, 0), (9, 0), (9, 9), (0, 9)];

  /// Token resting spots inside a 6x6 yard, in cell units.
  static const yardSlots = [
    Offset(3, 1.95),
    Offset(1.75, 3),
    Offset(4.2, 3),
    Offset(3, 4.26),
  ];

  static const _homeSpots = [
    Offset(6.6, 7.5),
    Offset(7.5, 6.6),
    Offset(8.4, 7.5),
    Offset(7.5, 8.4),
  ];

  static int trackIndex(int player, int progress) =>
      (startIndex[player] + progress) % 52;

  static bool isSafe(int player, int progress) =>
      progress > lastTrack || safeIndices.contains(trackIndex(player, progress));

  static bool canMove(int progress, int dice) =>
      progress == yard ? dice == 6 : progress + dice <= home;

  static int destination(int progress, int dice) =>
      progress == yard ? 0 : progress + dice;

  /// Centre of the token's cell, in cell units on the 15x15 grid.
  static Offset position(int player, int tokenIndex, int progress) {
    if (progress < 0) {
      final o = yardOrigins[player];
      return Offset(o.$1.toDouble(), o.$2.toDouble()) + yardSlots[tokenIndex];
    }
    if (progress <= lastTrack) {
      final c = track[trackIndex(player, progress)];
      return Offset(c.$1 + .5, c.$2 + .5);
    }
    if (progress < home) {
      final c = homeColumns[player][progress - lastTrack - 1];
      return Offset(c.$1 + .5, c.$2 + .5);
    }
    // Fan finished tokens out along the base of the home triangle.
    final spread = (tokenIndex - 1.5) * .42;
    final vertical = player.isEven;
    return _homeSpots[player] + Offset(vertical ? 0 : spread, vertical ? spread : 0);
  }
}
