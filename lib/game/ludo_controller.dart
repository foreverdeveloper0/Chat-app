import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ludo_rules.dart';
import 'sounds.dart';

class Token {
  Token(this.player, this.index);
  final int player;
  final int index;
  int progress = LudoRules.yard;

  bool get inYard => progress == LudoRules.yard;
  bool get isHome => progress == LudoRules.home;
  bool get onTrack => progress >= 0 && progress <= LudoRules.lastTrack;
}

enum Phase { awaitingRoll, rolling, landed, choosing, moving, gameOver }

/// Runs a Ludo match: turn order, dice, moves, captures, bots, turn timer,
/// lives, finishing order and the step-by-step timing the board animates to.
class LudoController extends ChangeNotifier {
  LudoController({
    required this.seats,
    this.bots = const {},
    Random? random,
    this.speed = 1,
    this.turnSeconds = 0,
    this.onSfx,
    this.onCapture,
  })  : assert(seats.length >= 2),
        _rng = random ?? Random(),
        current = seats.first {
    for (final p in seats) {
      lives[p] = maxLives;
    }
  }

  static const maxLives = 5;
  static const rollTicks = 10;
  static const rollTickMs = 70;
  static const landMs = 380;

  /// Player ids in turn order.
  final List<int> seats;
  final Set<int> bots;

  /// Multiplier for every animation delay (0 makes the game instant).
  final double speed;

  /// Seconds a human has to act before losing a life; 0 turns the timer off.
  final int turnSeconds;
  final Random _rng;

  /// Called at each audible moment of the match.
  final void Function(Sfx sfx, int variant)? onSfx;
  final void Function(int by, int victim)? onCapture;

  final tokens = [
    for (var p = 0; p < 4; p++) [for (var i = 0; i < 4; i++) Token(p, i)],
  ];
  final lives = <int, int>{};

  /// Opponent pieces each player has sent home, and pieces they have lost.
  final captures = <int, int>{};
  final lost = <int, int>{};

  /// Players who got all four pieces home, best first.
  final finished = <int>[];

  /// Players who ran out of lives or quit.
  final left = <int>{};

  int current;
  Phase phase = Phase.awaitingRoll;
  int dice = 6;
  int rollTick = 0;
  int sixes = 0;
  List<Token> movable = const [];
  int? winner;
  String message = '';

  /// Changes every time the turn timer restarts.
  int turnSerial = 0;
  bool timerRunning = false;
  Timer? _timer;
  bool _autoPlay = false;
  bool _disposed = false;

  bool isBot(int player) => bots.contains(player);
  bool get humanTurn => !isBot(current);
  int homeCount(int player) => tokens[player].where((t) => t.isHome).length;
  bool isActive(int p) => !finished.contains(p) && !left.contains(p);
  List<int> get active => [for (final p in seats) if (isActive(p)) p];

  /// 1 for the first finisher, 0 while still playing.
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
    return !_disposed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    timerRunning = false;
  }

  void _armTimer() {
    _stopTimer();
    if (turnSeconds <= 0 || !humanTurn) return;
    turnSerial++;
    timerRunning = true;
    _timer = Timer(Duration(seconds: turnSeconds), _onTimeout);
  }

  void _onTimeout() {
    if (_disposed || phase == Phase.gameOver) return;
    timerRunning = false;
    final p = current;
    lives[p] = (lives[p] ?? 1) - 1;
    _sfx(Sfx.lifeLost);
    if (lives[p]! <= 0) {
      leave(p);
      return;
    }
    // Play the turn for them.
    _autoPlay = true;
    if (phase == Phase.awaitingRoll) {
      roll();
    } else if (phase == Phase.choosing && movable.isNotEmpty) {
      move(_botPick());
    } else {
      _notify();
    }
  }

  Future<void> _beginTurn() async {
    phase = Phase.awaitingRoll;
    movable = const [];
    _autoPlay = false;
    if (isBot(current)) {
      _stopTimer();
      _notify();
      if (!await _wait(650)) return;
      await roll();
    } else {
      _armTimer();
      _sfx(Sfx.turn);
      _notify();
    }
  }

  Future<void> _nextPlayer() {
    sixes = 0;
    var i = seats.indexOf(current);
    do {
      i = (i + 1) % seats.length;
    } while (!isActive(seats[i]));
    current = seats[i];
    return _beginTurn();
  }

  void _endGame() {
    _stopTimer();
    // Whoever is still playing takes the next place.
    finished.addAll(active);
    winner = finished.isEmpty ? null : finished.first;
    phase = Phase.gameOver;
    movable = const [];
    _sfx(Sfx.win);
    _notify();
  }

  /// Removes a player from the match (out of lives or quit).
  void leave(int player) {
    if (!isActive(player) || phase == Phase.gameOver) return;
    left.add(player);
    for (final t in tokens[player]) {
      t.progress = LudoRules.yard;
    }
    if (active.length <= 1) return _endGame();
    if (player == current) {
      _stopTimer();
      _nextPlayer();
    } else {
      _notify();
    }
  }

  Future<void> roll({int? forced}) async {
    if (phase != Phase.awaitingRoll) return;
    _stopTimer();
    phase = Phase.rolling;
    message = '';
    _sfx(Sfx.diceRoll);
    // The result is fixed at the throw so the 3D dice can tumble towards it;
    // it stays in the air for rollTicks * rollTickMs.
    dice = forced ?? 1 + _rng.nextInt(6);
    rollTick++;
    _notify();
    if (!await _wait(rollTicks * rollTickMs)) return;
    HapticFeedback.mediumImpact();
    _sfx(Sfx.diceLand);
    // Let the landing bounce finish before anything moves.
    phase = Phase.landed;
    _notify();
    if (!await _wait(landMs)) return;

    if (dice == 6) {
      sixes++;
      if (sixes == 3) {
        message = 'Three sixes — turn lost';
        _notify();
        if (!await _wait(900)) return;
        return _nextPlayer();
      }
    } else {
      sixes = 0;
    }

    movable = [
      for (final t in tokens[current])
        if (LudoRules.canMove(t.progress, dice)) t,
    ];
    phase = Phase.choosing;

    if (movable.isEmpty) {
      message = 'No move';
      _notify();
      if (!await _wait(800)) return;
      return dice == 6 ? _beginTurn() : _nextPlayer();
    }
    _notify();

    if (isBot(current) || _autoPlay) {
      if (!await _wait(550)) return;
      return move(_botPick());
    }
    // Nothing to choose when every option is equivalent.
    if (movable.map((t) => t.progress).toSet().length == 1) {
      if (!await _wait(320)) return;
      // The player may already have tapped a piece during the pause.
      if (phase == Phase.choosing && movable.isNotEmpty) {
        return move(movable.first);
      }
      return;
    }
    _armTimer();
    _notify();
  }

  Future<void> move(Token token) async {
    if (phase != Phase.choosing || !movable.contains(token)) return;
    _stopTimer();
    phase = Phase.moving;
    movable = const [];
    final leaving = token.inYard;
    final steps = leaving ? 1 : dice;
    for (var i = 0; i < steps; i++) {
      token.progress++;
      HapticFeedback.selectionClick();
      leaving ? _sfx(Sfx.enter) : _sfx(Sfx.step, i);
      _notify();
      if (!await _wait(170)) return;
    }

    var captured = false;
    if (token.onTrack && !LudoRules.isSafe(token.player, token.progress)) {
      final cell = LudoRules.trackIndex(token.player, token.progress);
      for (final p in active) {
        if (p == token.player) continue;
        for (final other in tokens[p]) {
          if (other.onTrack && LudoRules.trackIndex(p, other.progress) == cell) {
            other.progress = LudoRules.yard;
            captured = true;
            captures[token.player] = (captures[token.player] ?? 0) + 1;
            lost[p] = (lost[p] ?? 0) + 1;
            onCapture?.call(token.player, p);
          }
        }
      }
    }
    if (token.isHome) _sfx(Sfx.home);
    if (captured) {
      HapticFeedback.heavyImpact();
      _sfx(Sfx.capture);
      _notify();
      if (!await _wait(520)) return;
    }

    if (homeCount(current) == 4) {
      finished.add(current);
      if (active.length <= 1) return _endGame();
      _sfx(Sfx.rank);
      _notify();
      if (!await _wait(600)) return;
      return _nextPlayer();
    }
    final again = dice == 6 || captured || token.isHome;
    return again ? _beginTurn() : _nextPlayer();
  }

  /// True when an opponent sits 1-6 cells behind [progress] on the track.
  bool _threatened(int player, int progress) {
    if (progress < 0 || LudoRules.isSafe(player, progress)) return false;
    final cell = LudoRules.trackIndex(player, progress);
    for (final p in active) {
      if (p == player) continue;
      for (final o in tokens[p]) {
        if (!o.onTrack) continue;
        final gap = (cell - LudoRules.trackIndex(p, o.progress)) % 52;
        if (gap >= 1 && gap <= 6 && o.progress + gap <= LudoRules.lastTrack) {
          return true;
        }
      }
    }
    return false;
  }

  Token _botPick() {
    Token? best;
    var bestScore = double.negativeInfinity;
    for (final t in movable) {
      final dest = LudoRules.destination(t.progress, dice);
      var score = dest * .6 + _rng.nextDouble();
      if (t.inYard) score += 45;
      if (dest == LudoRules.home) score += 80;
      if (dest > LudoRules.lastTrack && t.progress <= LudoRules.lastTrack) {
        score += 25;
      }
      if (dest <= LudoRules.lastTrack) {
        if (!LudoRules.isSafe(t.player, dest)) {
          final cell = LudoRules.trackIndex(t.player, dest);
          for (final p in active) {
            if (p == t.player) continue;
            for (final o in tokens[p]) {
              if (o.onTrack && LudoRules.trackIndex(p, o.progress) == cell) {
                score += 100 + o.progress;
              }
            }
          }
        } else {
          score += 22;
        }
        if (_threatened(t.player, dest)) score -= 28;
      }
      if (_threatened(t.player, t.progress)) score += 30;
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best!;
  }
}
