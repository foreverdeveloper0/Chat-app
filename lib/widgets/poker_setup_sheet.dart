import 'package:flutter/material.dart';

import '../game/catalog.dart';
import '../game/coins.dart';
import '../screens/teen_patti_screen.dart';
import '../theme/app_colors.dart';
import 'home_sections.dart' show Pressable, hubCard;

/// Tables: name, boot, and the chips you bring to it.
const _tables = [
  ('Starter Table', 10, 1000),
  ('Silver Table', 100, 10000),
  ('Gold Table', 500, 50000),
  ('Royal Table', 2000, 200000),
];

/// Pick a table and how many sit at it for Teen Patti.
Future<void> showPokerSetup(BuildContext context) {
  var players = 5;
  final logo = games.firstWhere((g) => g.key == 'poker').logo;
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
            colors: [Color(0xFF3A0F6B), Color(0xFF14052B)],
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
              const SizedBox(height: 4),
              Text(
                'TEEN PATTI',
                style: AppText.title.copyWith(
                  fontSize: 20,
                  color: AppColors.goldSoft,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your chips: ${formatCoins(PokerWallet.chips)}',
                key: const ValueKey('wallet'),
                style: AppText.title.copyWith(fontSize: 14),
              ),
              if (PokerWallet.chips < _tables.first.$3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    key: const ValueKey('free-chips'),
                    onTap: () => setSheet(
                      () => PokerWallet.chips += PokerWallet.freeChips,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1FA35C),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.goldSoft),
                      ),
                      child: Text(
                        'GET ${formatCoins(PokerWallet.freeChips)} FREE CHIPS',
                        style: AppText.title.copyWith(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'PLAYERS',
                    style: AppText.title.copyWith(
                      fontSize: 13,
                      color: const Color(0xFFC9B4F0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final n in const [2, 3, 4, 5])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        key: ValueKey('players-$n'),
                        onTap: () => setSheet(() => players = n),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 44,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: n == players
                                ? const Color(0x33FFC93A)
                                : const Color(0x55000000),
                            border: Border.all(
                              color: n == players
                                  ? AppColors.goldSoft
                                  : const Color(0x55FFFFFF),
                              width: 1.4,
                            ),
                          ),
                          child: Text(
                            '$n',
                            style: AppText.title.copyWith(
                              fontSize: 15,
                              color: n == players
                                  ? AppColors.goldSoft
                                  : AppColors.cream,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (final (name, boot, buyIn) in _tables)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Opacity(
                    opacity: PokerWallet.chips >= buyIn ? 1 : .45,
                    child: Pressable(
                      onTap: () {
                        if (PokerWallet.chips < buyIn) return;
                        Navigator.pop(sheet);
                        Navigator.of(context).push(
                          PageRouteBuilder<void>(
                            transitionDuration: const Duration(
                              milliseconds: 280,
                            ),
                            pageBuilder: (_, _, _) => TeenPattiScreen(
                              boot: boot,
                              buyIn: buyIn,
                              players: players,
                            ),
                            transitionsBuilder: (_, a, _, child) =>
                                FadeTransition(opacity: a, child: child),
                          ),
                        );
                      },
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: hubCard(border: AppColors.goldTrim),
                        child: Row(
                          children: [
                            Icon(
                              PokerWallet.chips >= buyIn
                                  ? Icons.style_rounded
                                  : Icons.lock_rounded,
                              color: AppColors.goldSoft,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: AppText.title.copyWith(fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Boot ${formatCoins(boot)}  ·  '
                                    'Buy-in ${formatCoins(buyIn)}',
                                    style: AppText.title.copyWith(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w400,
                                      color: const Color(0xFFC9B4F0),
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
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
