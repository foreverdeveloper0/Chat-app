import 'package:flutter/material.dart';

/// The app's illustrated icons (supplied artwork in `assets/images/icons`).
enum ArtKind {
  avatar('avatar'),
  coin('coin'),
  gem('gem'),
  coinStack('coin_earn'),
  calendar('daily_tasks'),
  globe('play_online'),
  pawnPair('play_friends'),
  dicePair('pass_play'),
  robot('vs_computer'),
  trophy('tournament'),
  home('nav_home'),
  friends('nav_friends'),
  history('nav_history'),
  agent('nav_agent');

  const ArtKind(this.file);
  final String file;

  String get asset => 'assets/images/icons/$file.png';
}

class Art extends StatelessWidget {
  const Art(this.kind, {super.key, required this.size});
  final ArtKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        kind.asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Decode near the drawn size instead of the full 256px source.
        cacheWidth: (size * 3).round().clamp(48, 256),
        gaplessPlayback: true,
      );
}
