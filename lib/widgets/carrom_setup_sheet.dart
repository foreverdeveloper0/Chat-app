import 'dart:math';

import 'package:flutter/material.dart';

import '../game/catalog.dart';
import '../game/coins.dart';
import '../screens/carrom_screen.dart';
import '../theme/app_colors.dart';
import 'home_sections.dart' show Pressable, hubCard;

const _stakes = [500, 1000, 10000, 100000, 1000000];

/// (title, subtitle, seats, bots, names)
const _modes = [
  ('1 vs Computer', 'You against the computer', [0, 2], {2},
      {0: 'You', 2: 'Computer'}),
  ('1 vs 1', 'Two players on this phone', [0, 2], <int>{},
      {0: 'Player 1', 2: 'Player 2'}),
  ('2 vs 2 with Computer', 'You and a partner bot against two bots',
      [0, 1, 2, 3], {1, 2, 3},
      {0: 'You', 1: 'Bot 1', 2: 'Partner', 3: 'Bot 2'}),
  ('2 vs 2 Team', 'Four players on this phone, two teams', [0, 1, 2, 3],
      <int>{}, {0: 'Player 1', 1: 'Player 2', 2: 'Player 3', 3: 'Player 4'}),
];

/// Dev aid: `--dart-define=LUDO_AUTOPLAY=true` lets bots play every seat.
const _autoplay = bool.fromEnvironment('LUDO_AUTOPLAY');

/// Pick the entry coins and how to play carrom.
Future<void> showCarromSetup(BuildContext context) {
  var stake = 1000;
  final logo = games.firstWhere((g) => g.key == 'carrom').logo;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF131C4A), AppColors.bgBottom],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: AppColors.goldTrim, width: 1.6)),
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
              Image.asset(logo, height: 84),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final v in _stakes)
                    GestureDetector(
                      onTap: () => setSheet(() => stake = v),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: v == stake
                              ? const Color(0x33FFC93A)
                              : AppColors.cardInset,
                          border: Border.all(
                            color: v == stake
                                ? AppColors.goldSoft
                                : AppColors.cardBorder,
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          formatCoins(v),
                          style: AppText.title.copyWith(
                            fontSize: 13.5,
                            color: v == stake
                                ? AppColors.goldSoft
                                : AppColors.cream,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (title, sub, seats, bots, names) in _modes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    onTap: () {
                      Navigator.pop(sheet);
                      Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          transitionDuration:
                              const Duration(milliseconds: 280),
                          pageBuilder: (_, _, _) => CarromScreen(
                            seats: seats,
                            bots: _autoplay ? seats.toSet() : bots,
                            names: names,
                            entry: stake,
                            roomId: '${100000 + Random().nextInt(900000)}',
                          ),
                          transitionsBuilder: (_, a, _, child) =>
                              FadeTransition(opacity: a, child: child),
                        ),
                      );
                    },
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: hubCard(border: AppColors.goldTrim),
                      child: Row(
                        children: [
                          Icon(
                            seats.length == 2
                                ? Icons.person_rounded
                                : Icons.groups_rounded,
                            color: AppColors.goldSoft,
                            size: 30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    style: AppText.title
                                        .copyWith(fontSize: 16.5)),
                                const SizedBox(height: 2),
                                Text(sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.title.copyWith(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w400,
                                        color: const Color(0xFF9EA9DC))),
                              ],
                            ),
                          ),
                          const Icon(Icons.play_circle_fill_rounded,
                              color: AppColors.goldSoft, size: 28),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
