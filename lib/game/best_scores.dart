import 'package:shared_preferences/shared_preferences.dart';

import 'snake_game.dart';

/// Best scores kept on the device, one per Snake speed and arena.
abstract final class BestScores {
  static final _memory = <String, int>{};

  static String _snakeKey(SnakeSpeed speed, bool wrap) =>
      'snake_best_${speed.name}_${wrap ? 'open' : 'walls'}';

  static Future<int> snake(SnakeSpeed speed, bool wrap) async {
    final key = _snakeKey(speed, wrap);
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(key) ?? _memory[key] ?? 0;
    } catch (_) {
      // No storage (tests, odd devices): remember for this run only.
      return _memory[key] ?? 0;
    }
  }

  /// Stores [score] if it beats the old best; returns true when it does.
  static Future<bool> submitSnake(SnakeSpeed speed, bool wrap, int score) async {
    final key = _snakeKey(speed, wrap);
    final old = await snake(speed, wrap);
    if (score <= old) return false;
    _memory[key] = score;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, score);
    } catch (_) {}
    return true;
  }
}
