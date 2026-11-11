import 'dart:math';

import 'package:flutter/material.dart';

import '../game/catalog.dart';
import '../game/coins.dart';
import '../screens/race_screen.dart';
import '../theme/app_colors.dart';
import 'home_sections.dart' show Pressable, hubCard;

const _stakes = [500, 1000, 10000, 100000, 1000000];

/// Dev aid: `--dart-define=LUDO_AUTOPLAY=true` drives the player's car too.
const _autoplay = bool.fromEnvironment('LUDO_AUTOPLAY');

/// Pick the entry coins, the field and the laps for Car Racing.
Future<void> showRaceSetup(BuildContext context) {
  var stake = 1000;
  var laps = 3;
  final logo = games.firstWhere((g) => g.key == 'racing').logo;
  const modes = [
    ('4 Car Race', 'You against 3 computer cars', 3),
    ('3 Car Race', 'You against 2 computer cars', 2),
    ('1 vs 1 Duel', 'You against 1 computer car', 1),
  ];
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
          border: Border(
            top: BorderSide(color: AppColors.goldTrim, width: 1.6),
          ),
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
                          horizontal: 13,
                          vertical: 7,
                        ),
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'LAPS',
                    style: AppText.title.copyWith(
                      fontSize: 13,
                      color: const Color(0xFF9EA9DC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final v in const [1, 2, 3, 5])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setSheet(() => laps = v),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 40,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: v == laps
                                ? const Color(0x33FFC93A)
                                : AppColors.cardInset,
                            border: Border.all(
                              color: v == laps
                                  ? AppColors.goldSoft
                                  : AppColors.cardBorder,
                              width: 1.4,
                            ),
                          ),
                          child: Text(
                            '$v',
                            style: AppText.title.copyWith(
                              fontSize: 15,
                              color: v == laps
                                  ? AppColors.goldSoft
                                  : AppColors.cream,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (title, sub, rivals) in modes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    onTap: () {
                      Navigator.pop(sheet);
                      Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          transitionDuration: const Duration(milliseconds: 280),
                          pageBuilder: (_, _, _) => RaceScreen(
                            opponents: rivals,
                            laps: laps,
                            autopilot: _autoplay,
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
                            rivals == 1
                                ? Icons.sports_score_rounded
                                : Icons.directions_car_filled_rounded,
                            color: AppColors.goldSoft,
                            size: 30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: AppText.title.copyWith(fontSize: 16.5),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sub,
                                  style: AppText.title.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFF9EA9DC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.play_circle_fill_rounded,
                            color: AppColors.goldSoft,
                            size: 28,
                          ),
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
