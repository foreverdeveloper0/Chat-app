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

/// Runs a Ludo match: turn order, dice, moves, captures, bots and the
/// step-by-step timing that the board animates against.
class LudoController extends ChangeNotifier {
  LudoController({
    required this.seats,
    this.bots = const {},
    Random? random,
    this.speed = 1,
    this.onSfx,
  })  : assert(seats.length >= 2),
        _rng = random ?? Random(),
        current = seats.first;

  /// Active player ids in turn order.
  final List<int> seats;
  final Set<int> bots;

  /// Multiplier for every animation delay (0 makes the game instant).
  final double speed;
  final Random _rng;

  /// Called at each audible moment of the match.
  final void Function(Sfx)? onSfx;

  final tokens = [
    for (var p = 0; p < 4; p++) [for (var i = 0; i < 4; i++) Token(p, i)],
  ];

  static const rollTicks = 12;
  static const rollTickMs = 70;
  static const landMs = 380;

  int current;
  Phase phase = Phase.awaitingRoll;
  int dice = 6;
  int rollTick = 0;
  int sixes = 0;
  List<Token> movable = const [];
  int? winner;
  String message = '';
  bool _disposed = false;

  bool isBot(int player) => bots.contains(player);
  bool get humanTurn => !isBot(current);
  int homeCount(int player) => tokens[player].where((t) => t.isHome).length;

  void start() => _beginTurn();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<bool> _wait(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: (ms * speed).round()));
    return !_disposed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _beginTurn() async {
    phase = Phase.awaitingRoll;
    movable = const [];
    _notify();
    if (isBot(current)) {
      if (!await _wait(650)) return;
      await roll();
    }
  }

  Future<void> _nextPlayer() {
    sixes = 0;
    current = seats[(seats.indexOf(current) + 1) % seats.length];
    return _beginTurn();
  }

  Future<void> roll({int? forced}) async {
    if (phase != Phase.awaitingRoll) return;
    phase = Phase.rolling;
    message = '';
    onSfx?.call(Sfx.diceRoll);
    // The result is fixed at the throw so the 3D dice can tumble towards it;
    // it stays in the air for rollTicks * rollTickMs.
    dice = forced ?? 1 + _rng.nextInt(6);
    rollTick++;
    _notify();
    if (!await _wait(rollTicks * rollTickMs)) return;
    HapticFeedback.mediumImpact();
    onSfx?.call(Sfx.diceLand);
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

    if (isBot(current)) {
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
    }
  }

  Future<void> move(Token token) async {
    if (phase != Phase.choosing || !movable.contains(token)) return;
    phase = Phase.moving;
    movable = const [];
    final leaving = token.inYard;
    final steps = leaving ? 1 : dice;
    for (var i = 0; i < steps; i++) {
      token.progress++;
      HapticFeedback.selectionClick();
      onSfx?.call(leaving ? Sfx.enter : Sfx.step);
      _notify();
      if (!await _wait(170)) return;
    }

    var captured = false;
    if (token.onTrack && !LudoRules.isSafe(token.player, token.progress)) {
      final cell = LudoRules.trackIndex(token.player, token.progress);
      for (final p in seats) {
        if (p == token.player) continue;
        for (final other in tokens[p]) {
          if (other.onTrack && LudoRules.trackIndex(p, other.progress) == cell) {
            other.progress = LudoRules.yard;
            captured = true;
          }
        }
      }
    }
    if (token.isHome) onSfx?.call(Sfx.home);
    if (captured) {
      HapticFeedback.heavyImpact();
      onSfx?.call(Sfx.capture);
      _notify();
      if (!await _wait(520)) return;
    }

    if (homeCount(current) == 4) {
      winner = current;
      phase = Phase.gameOver;
      onSfx?.call(Sfx.win);
      _notify();
      return;
    }
    final again = dice == 6 || captured || token.isHome;
    return again ? _beginTurn() : _nextPlayer();
  }

  /// True when an opponent sits 1-6 cells behind [progress] on the track.
  bool _threatened(int player, int progress) {
    if (progress < 0 || LudoRules.isSafe(player, progress)) return false;
    final cell = LudoRules.trackIndex(player, progress);
    for (final p in seats) {
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
          for (final p in seats) {
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
