import 'package:flutter/material.dart';

import '../game/best_scores.dart';
import '../game/catalog.dart';
import '../game/snake_game.dart';
import '../screens/snake_screen.dart';
import '../theme/app_colors.dart';

/// Pick the speed and the arena, see the best score for that pair, start.
Future<void> showSnakeSetup(BuildContext context) {
  var speed = SnakeSpeed.normal;
  var wrap = false;
  final logo = games.firstWhere((g) => g.key == 'snake').logo;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) {
        Widget choice(String label, bool selected, VoidCallback onTap) =>
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: selected
                        ? const Color(0x33EBCB7A)
                        : AppColors.cardInset,
                    border: Border.all(
                      color:
                          selected ? AppColors.goldSoft : AppColors.cardBorder,
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    label,
                    style: AppText.title.copyWith(
                      fontSize: 15,
                      color: selected ? AppColors.goldSoft : AppColors.cream,
                    ),
                  ),
                ),
              ),
            );
        Widget label(String text) => Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 7),
                child: Text(text,
                    style: AppText.title.copyWith(
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF9EA9DC))),
              ),
            );
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF131C4A), AppColors.bgBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border:
                Border(top: BorderSide(color: AppColors.goldTrim, width: 1.6)),
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
                const SizedBox(height: 6),
                Image.asset(logo, height: 92),
                const SizedBox(height: 8),
                label('SPEED'),
                Row(
                  children: [
                    for (final s in SnakeSpeed.values) ...[
                      if (s.index > 0) const SizedBox(width: 8),
                      choice(s.label, s == speed,
                          () => setSheet(() => speed = s)),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                label('ARENA'),
                Row(
                  children: [
                    choice('Walls', !wrap, () => setSheet(() => wrap = false)),
                    const SizedBox(width: 8),
                    choice('Open', wrap, () => setSheet(() => wrap = true)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  wrap
                      ? 'Go through an edge and come back on the other side.'
                      : 'Touch a wall and the game is over.',
                  style: AppText.title.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF9EA9DC)),
                ),
                const SizedBox(height: 12),
                FutureBuilder<int>(
                  key: ValueKey('${speed.name}-$wrap'),
                  future: BestScores.snake(speed, wrap),
                  builder: (_, snap) => Text(
                    'Best: ${snap.data ?? 0}',
                    style: AppText.title
                        .copyWith(fontSize: 16, color: AppColors.goldSoft),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  key: const ValueKey('snake-start'),
                  onTap: () {
                    Navigator.pop(sheet);
                    Navigator.of(context).push(
                      PageRouteBuilder<void>(
                        transitionDuration: const Duration(milliseconds: 280),
                        pageBuilder: (_, _, _) =>
                            SnakeScreen(speed: speed, wrap: wrap),
                        transitionsBuilder: (_, a, _, child) =>
                            FadeTransition(opacity: a, child: child),
                      ),
                    );
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: AppColors.goldGradient,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x80EBCB7A), blurRadius: 12),
                      ],
                    ),
                    child: Text(
                      'START',
                      style: AppText.title.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: const Color(0xFF3A2500),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
