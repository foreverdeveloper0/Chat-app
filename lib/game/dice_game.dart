import 'package:flutter/foundation.dart';

enum Phase { awaitingRoll, rolling, landed, choosing, moving, gameOver }

/// What the shared match UI (player docks, dice) needs from any turn-based
/// dice game: whose turn it is, the dice, lives, the turn clock and results.
abstract class DiceGame extends ChangeNotifier {
  static const maxLives = 5;
  static const rollTicks = 10;
  static const rollTickMs = 70;
  static const landMs = 380;

  List<int> get seats;
  int get current;
  Phase get phase;
  int get dice;

  int get turnSerial;
  bool get timerRunning;
  int get turnSeconds;

  Map<int, int> get lives;
  Set<int> get left;

  bool isBot(int player);

  /// 1 for the first finisher, 0 while still playing.
  int rankOf(int player);

  Future<void> roll();
}
