import 'package:flutter/material.dart';

import '../theme/board_assets.dart';
import '../screens/game_screen.dart';
import '../theme/app_colors.dart';
import 'game_card.dart';

/// Dev aid: `--dart-define=LUDO_AUTOPLAY=true` lets bots play every seat.
const _autoplay = bool.fromEnvironment('LUDO_AUTOPLAY');

/// Seats by player count, in turn order. Blue (bottom-left) always plays.
const _seatPlans = {
  2: [3, 1],
  3: [3, 0, 1],
  4: [3, 0, 1, 2],
};

/// Lets the player pick how many seats to fill, then opens the match.
Future<void> showGameSetup(BuildContext context, {required bool vsComputer}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheet) => Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      decoration: const BoxDecoration(
        color: AppColors.bgTop,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              vsComputer ? 'Play vs Computer' : 'Pass & Play',
              style: AppText.title.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 4),
            Text(
              vsComputer ? 'How many opponents?' : 'How many players?',
              style: AppText.title.copyWith(
                  fontSize: 14, color: AppColors.mint, height: 1.3),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final n in const [2, 3, 4]) ...[
                  if (n > 2) const SizedBox(width: 10),
                  Expanded(
                    child: GameCard(
                      height: 104,
                      radius: 18,
                      onTap: () {
                        Navigator.pop(sheet);
                        _open(context, n, vsComputer);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final p in _seatPlans[n]!)
                                if (!vsComputer || p != 3)
                                  Image.asset(pawnAssets[p],
                                      width: 20, height: 32),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            vsComputer
                                ? '${n - 1} ${n == 2 ? 'Bot' : 'Bots'}'
                                : '$n Players',
                            style: AppText.title.copyWith(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void _open(BuildContext context, int players, bool vsComputer) {
  final seats = _seatPlans[players]!;
  final names = <int, String>{};
  for (var i = 0; i < seats.length; i++) {
    names[seats[i]] = vsComputer
        ? (i == 0 ? 'You' : (players == 2 ? 'Computer' : 'Bot $i'))
        : 'Player ${i + 1}';
  }
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => GameScreen(
        title: vsComputer ? 'Play vs Computer' : 'Pass & Play',
        seats: seats,
        bots: _autoplay
            ? seats.toSet()
            : (vsComputer ? seats.skip(1).toSet() : const {}),
        names: names,
      ),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}
