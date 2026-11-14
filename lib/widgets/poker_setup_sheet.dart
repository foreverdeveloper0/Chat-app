import 'package:flutter/material.dart';

import '../game/catalog.dart';
import '../game/coins.dart';
import '../screens/poker_screen.dart';
import 'poker_buyin.dart';
import '../theme/app_colors.dart';
import 'home_sections.dart' show Pressable, hubCard;

/// Tables: name and small blind. What you bring is chosen on joining.
const _tables = [
  // The usual buy-in is 200 small blinds: 500 crore at the top table.
  ('500 Crore Table', 25000000),
  ('50 Crore Table', 2500000),
  ('1 Crore Table', 50000),
  ('Royal Table', 1000),
  ('Gold Table', 250),
  ('Silver Table', 50),
  ('Starter Table', 10),
];

/// Pick a table and how many sit at it for Texas Hold'em.
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
                "TEXAS HOLD'EM",
                style: AppText.title.copyWith(
                  fontSize: 20,
                  color: AppColors.goldSoft,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your account: ${formatCoins(PokerWallet.chips)}',
                key: const ValueKey('wallet'),
                style: AppText.title.copyWith(fontSize: 14),
              ),
              if (PokerWallet.chips < buyInRange(_tables.last.$2).min)
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
              // The tables scroll, biggest first.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 264),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final (name, boot) in _tables)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Opacity(
                            opacity: PokerWallet.chips >= buyInRange(boot).min
                                ? 1
                                : .45,
                            child: Pressable(
                              onTap: () async {
                                final least = buyInRange(boot).min;
                                if (PokerWallet.chips < least) return;
                                final amount = await showBuyIn(
                                  sheet,
                                  name,
                                  boot,
                                );
                                if (amount == null || !sheet.mounted) return;
                                Navigator.pop(sheet);
                                if (!context.mounted) return;
                                Navigator.of(context).push(
                                  PageRouteBuilder<void>(
                                    transitionDuration: const Duration(
                                      milliseconds: 280,
                                    ),
                                    pageBuilder: (_, _, _) => PokerScreen(
                                      smallBlind: boot,
                                      buyIn: amount,
                                      players: players,
                                      tableName: name,
                                    ),
                                    transitionsBuilder: (_, a, _, child) =>
                                        FadeTransition(
                                          opacity: a,
                                          child: child,
                                        ),
                                  ),
                                );
                              },
                              child: Container(
                                height: 56,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: hubCard(border: AppColors.goldTrim),
                                child: Row(
                                  children: [
                                    Icon(
                                      PokerWallet.chips >= buyInRange(boot).min
                                          ? Icons.style_rounded
                                          : Icons.lock_rounded,
                                      color: AppColors.goldSoft,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: AppText.title.copyWith(
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            // Short, so it stays on one line.
                                            ('Blinds ${formatCoins(boot)}/'
                                                    '${formatCoins(boot * 2)}  ·  '
                                                    'Buy-in '
                                                    '${formatCoins(buyInRange(boot).min)}'
                                                    ' – '
                                                    '${formatCoins(buyInRange(boot).max)}')
                                                .replaceAll(' Crore', ' Cr'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
            ],
          ),
        ),
      ),
    ),
  );
}
