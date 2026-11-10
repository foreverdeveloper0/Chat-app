import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Sound effects; each name matches a file in `assets/sounds/<name>.wav`.
enum Sfx { diceRoll, diceLand, step, enter, capture, home, win, tap }

abstract final class Sounds {
  /// Turned off in widget tests, where there is no audio plugin.
  static bool enabled = true;
  static final muted = ValueNotifier(false);

  static final _players = <Sfx, AudioPlayer>{};
  static bool _configured = false;

  static Future<void> play(Sfx sfx) async {
    if (!enabled || muted.value) return;
    try {
      if (!_configured) {
        _configured = true;
        // Short game sounds should mix with, not pause, the user's music.
        await AudioPlayer.global.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
              .build(),
        );
      }
      final player = _players[sfx] ??= AudioPlayer();
      await player.stop();
      await player.play(
        AssetSource('sounds/${sfx.name}.wav'),
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      // Sound is a nicety; never let it break the game.
    }
  }
}
