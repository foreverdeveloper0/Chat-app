import 'package:flutter/material.dart';

import '../game/catalog.dart';
import '../game/fruit_game.dart';
import '../screens/fruit_screen.dart';
import '../theme/app_colors.dart';
import 'home_sections.dart' show Pressable, hubCard;

/// Pick a blade and a mode for Fruit Cut.
Future<void> showFruitSetup(BuildContext context) {
  var blade = Blade.silver;
  final logo = games.firstWhere((g) => g.key == 'fruit').logo;
  const modes = [
    (
      'Classic',
      'Three lives. Don\'t drop fruit, never cut a bomb',
      FruitMode.classic,
      Icons.favorite_rounded,
    ),
    (
      '60 Seconds',
      'Cut all you can before time runs out',
      FruitMode.timed,
      Icons.timer_rounded,
    ),
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
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'BLADE',
                    style: AppText.title.copyWith(
                      fontSize: 13,
                      color: const Color(0xFF9EA9DC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final b in Blade.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        key: ValueKey('blade-${b.name}'),
                        onTap: () => setSheet(() => blade = b),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: b == blade
                                ? const Color(0x33FFC93A)
                                : AppColors.cardInset,
                            border: Border.all(
                              color: b == blade
                                  ? AppColors.goldSoft
                                  : AppColors.cardBorder,
                              width: 1.4,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 18,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: b.core,
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: [
                                    BoxShadow(color: b.glow, blurRadius: 6),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                b.label,
                                style: AppText.title.copyWith(
                                  fontSize: 13.5,
                                  color: b == blade
                                      ? AppColors.goldSoft
                                      : AppColors.cream,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (title, sub, mode, icon) in modes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    onTap: () {
                      Navigator.pop(sheet);
                      Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          transitionDuration: const Duration(milliseconds: 280),
                          pageBuilder: (_, _, _) =>
                              FruitScreen(mode: mode, blade: blade),
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
                          Icon(icon, color: AppColors.goldSoft, size: 30),
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
