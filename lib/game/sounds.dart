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
}

abstract final class Sounds {
  /// Turned off in widget tests, where there is no audio plugin.
  static bool enabled = true;
  static final muted = ValueNotifier(false);

  static final _players = <String, AudioPlayer>{};
  static bool _configured = false;

  static Future<void> play(Sfx sfx, [int variant = 0]) async {
    if (!enabled || muted.value) return;
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
