import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'dice_game.dart';
import 'snl_layout.dart';
import 'sounds.dart';

/// Snakes & Ladders on the classic 10x10 board.
///
/// Everyone starts on square 1 and races to 100. Landing on the foot of a
/// ladder climbs it; landing on a snake's head slides down to its tail. A 6
/// earns another roll, and the last roll must land exactly on 100.
class SnlController extends DiceGame {
  SnlController({
    required this.seats,
    this.bots = const {},
    Random? random,
    this.speed = 1,
    this.turnSeconds = 0,
    this.haptics = true,
    this.onSfx,
    SnlLayout? layout,
  })  : assert(seats.length >= 2),
        _rng = random ?? Random(),
        layout = layout ?? SnlLayout.random(random),
        current = seats.first {
    for (final p in seats) {
      lives[p] = DiceGame.maxLives;
      position[p] = 1;
    }
  }

  static const goal = 100;

  /// Where this match's ladders and snakes are.
  final SnlLayout layout;

  @override
  final List<int> seats;
  final Set<int> bots;
  final double speed;
  @override
  final int turnSeconds;
  final bool haptics;
  final Random _rng;
  final void Function(Sfx sfx, int variant)? onSfx;

  /// While true the match holds still (the home demo pauses when hidden).
  bool paused = false;

  /// Square each player stands on.
  final position = <int, int>{};
  @override
  final lives = <int, int>{};
  final finished = <int>[];
  @override
  final left = <int>{};

  /// Ladders climbed and snakes hit, for the profile and results.
  final climbs = <int, int>{};
  final bites = <int, int>{};

  @override
  int current;
  @override
  Phase phase = Phase.awaitingRoll;
  @override
  int dice = 6;
  int? winner;
  String message = '';

  /// A piece riding a ladder or a snake right now.
  ({int player, int from, int to, bool snake})? slide;

  @override
  int turnSerial = 0;
  @override
  bool timerRunning = false;
  Timer? _timer;
  bool _disposed = false;

  @override
  bool isBot(int player) => bots.contains(player);
  bool get humanTurn => !isBot(current);
  bool isActive(int p) => !finished.contains(p) && !left.contains(p);
  List<int> get active => [for (final p in seats) if (isActive(p)) p];
  @override
  int rankOf(int player) => finished.indexOf(player) + 1;

  void start() => _beginTurn();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  void _sfx(Sfx s, [int variant = 0]) => onSfx?.call(s, variant);

  Future<bool> _wait(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: (ms * speed).round()));
    while (paused && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return !_disposed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    timerRunning = false;
  }

  void _onTimeout() {
    if (_disposed || phase != Phase.awaitingRoll) return;
    timerRunning = false;
    final p = current;
    lives[p] = (lives[p] ?? 1) - 1;
    _sfx(Sfx.lifeLost);
    lives[p]! <= 0 ? leave(p) : roll();
  }

  Future<void> _beginTurn() async {
    phase = Phase.awaitingRoll;
    _stopTimer();
    if (isBot(current)) {
      _notify();
      if (!await _wait(650)) return;
      await roll();
    } else {
      if (turnSeconds > 0) {
        turnSerial++;
        timerRunning = true;
        _timer = Timer(Duration(seconds: turnSeconds), _onTimeout);
      }
      _sfx(Sfx.turn);
      _notify();
    }
  }

  Future<void> _nextPlayer() {
    var i = seats.indexOf(current);
    do {
      i = (i + 1) % seats.length;
    } while (!isActive(seats[i]));
    current = seats[i];
    return _beginTurn();
  }

  void _endGame() {
    _stopTimer();
    finished.addAll(active);
    winner = finished.isEmpty ? null : finished.first;
    phase = Phase.gameOver;
    _sfx(Sfx.win);
    _notify();
  }

  /// Removes a player from the match (out of lives).
  void leave(int player) {
    if (!isActive(player) || phase == Phase.gameOver) return;
    left.add(player);
    if (active.length <= 1) return _endGame();
    if (player == current) {
      _stopTimer();
      _nextPlayer();
    } else {
      _notify();
    }
  }

  @override
  Future<void> roll({int? forced}) async {
    if (phase != Phase.awaitingRoll) return;
    _stopTimer();
    phase = Phase.rolling;
    message = '';
    _sfx(Sfx.diceRoll);
    dice = forced ?? 1 + _rng.nextInt(6);
    _notify();
    if (!await _wait(DiceGame.rollTicks * DiceGame.rollTickMs)) return;
    if (haptics) HapticFeedback.mediumImpact();
    _sfx(Sfx.diceLand);
    phase = Phase.landed;
    _notify();
    if (!await _wait(DiceGame.landMs)) return;

    final p = current;
    final from = position[p]!;
    if (from + dice > goal) {
      // The last roll has to land exactly on 100.
      message = 'Need ${goal - from} to finish';
      _notify();
      if (!await _wait(800)) return;
      return dice == 6 ? _beginTurn() : _nextPlayer();
    }

    phase = Phase.moving;
    for (var i = 0; i < dice; i++) {
      position[p] = position[p]! + 1;
      if (haptics) HapticFeedback.selectionClick();
      _sfx(Sfx.step, i);
      _notify();
      if (!await _wait(190)) return;
    }

    final here = position[p]!;
    final up = layout.ladders[here], down = layout.snakes[here];
    if (up != null || down != null) {
      if (!await _wait(180)) return;
      final snake = down != null;
      slide = (player: p, from: here, to: up ?? down!, snake: snake);
      if (snake) {
        bites[p] = (bites[p] ?? 0) + 1;
        if (haptics) HapticFeedback.heavyImpact();
        _sfx(Sfx.crash);
      } else {
        climbs[p] = (climbs[p] ?? 0) + 1;
        _sfx(Sfx.bonus);
      }
      _notify();
      if (!await _wait(900)) return;
      position[p] = up ?? down!;
      slide = null;
      _notify();
      if (!await _wait(150)) return;
    }

    if (position[p] == goal) {
      finished.add(p);
      if (active.length <= 1) return _endGame();
      _sfx(Sfx.rank);
      _notify();
      if (!await _wait(600)) return;
      return _nextPlayer();
    }
    return dice == 6 ? _beginTurn() : _nextPlayer();
  }
}
