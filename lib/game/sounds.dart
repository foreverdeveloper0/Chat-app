import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Sound effects; each name matches a file in `assets/sounds/`.
/// [Sfx.step] has six rising variants: step0.wav .. step5.wav.
enum Sfx {
  start,
  turn,
  diceRoll,
  diceLand,
  step,
  enter,
  capture,
  home,
  rank,
  win,
  lifeLost,
  chat,
  tap,
  // Snakes & Ladders: climbing a ladder, sliding down a snake
  bonus,
  crash,
  // Carrom: pieces knocking together, a piece dropping into a pocket
  hit,
  pocket,
  // Fruit Cut: the blade going through a fruit
  slice,
  // Poker: one sound for each thing that happens at the table
  pokerDeal,
  pokerCard,
  pokerCheck,
  pokerCall,
  pokerRaise,
  pokerAllIn,
  pokerFold,
  pokerTurn,
  pokerTick,
  pokerWin,
  pokerLose,
  pokerChips,
}

/// Poker sounds that have no recording of their own yet borrow another.
/// Drop `assets/sounds/<name>.wav` in and remove its line here.
const _standIns = {
  Sfx.pokerDeal: Sfx.diceRoll,
  Sfx.pokerCard: Sfx.diceLand,
  Sfx.pokerCheck: Sfx.tap,
  Sfx.pokerCall: Sfx.pocket,
  Sfx.pokerRaise: Sfx.bonus,
  Sfx.pokerAllIn: Sfx.crash,
  Sfx.pokerFold: Sfx.step,
  Sfx.pokerTurn: Sfx.turn,
  Sfx.pokerTick: Sfx.tap,
  Sfx.pokerWin: Sfx.win,
  Sfx.pokerLose: Sfx.rank,
  Sfx.pokerChips: Sfx.pocket,
};

abstract final class Sounds {
  /// Turned off in widget tests, where there is no audio plugin.
  static bool enabled = true;
  static final muted = ValueNotifier(false);

  static final _players = <String, AudioPlayer>{};
  static bool _configured = false;

  static Future<void> play(Sfx sfx, [int variant = 0]) async {
    if (!enabled || muted.value) return;
    sfx = _standIns[sfx] ?? sfx;
    final file = sfx == Sfx.step ? 'step${variant % 6}' : sfx.name;
    try {
      if (!_configured) {
        _configured = true;
        // Short game sounds should mix with, not pause, the user's music.
        await AudioPlayer.global.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
              .build(),
        );
      }
      final player = _players[file] ??= AudioPlayer();
      await player.stop();
      await player.play(
        AssetSource('sounds/$file.wav'),
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      // Sound is a nicety; never let it break the game.
    }
  }
}
