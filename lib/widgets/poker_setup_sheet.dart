import 'package:flutter/material.dart';

import '../game/catalog.dart';
import '../game/coins.dart';
import '../screens/poker_screen.dart';
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

/// Choose how many chips to bring to a table. The rest stays in the
/// account. Returns the amount, or null if cancelled.
Future<int?> showBuyIn(BuildContext context, String table, int smallBlind) {
  final range = buyInRange(smallBlind);
  final bank = PokerWallet.chips;
  final most = bank < range.max ? bank : range.max;
  final step = smallBlind * 20; // ten big blinds
  var amount = range.usual.clamp(range.min, most);
  TextStyle text(double size, [Color colour = Colors.white]) =>
      AppText.title.copyWith(fontSize: size, color: colour);
  return showDialog<int>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setD) {
        void set(num v) {
          var a = v.round();
          // Whole steps, except at the very top.
          if (a < most) a = range.min + ((a - range.min) / step).round() * step;
          setD(() => amount = a.clamp(range.min, most));
        }

        Widget quick(String label, int value) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              key: ValueKey('buyin-$label'),
              onTap: () => set(value),
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: amount == value.clamp(range.min, most)
                      ? const Color(0x44FFC93A)
                      : const Color(0x55000000),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: amount == value.clamp(range.min, most)
                        ? AppColors.goldSoft
                        : const Color(0x66FFFFFF),
                    width: 1.3,
                  ),
                ),
                child: Text(label, style: text(12.5)),
              ),
            ),
          ),
        );
        Widget line(String label, String value, Color colour, Key key) => Row(
          children: [
            Text(label, style: text(13, const Color(0xFFC9B4F0))),
            const Spacer(),
            Text(value, key: key, style: text(15, colour)),
          ],
        );
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF1B8),
                    Color(0xFFE3B341),
                    Color(0xFF9A6A00),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(color: Color(0xCC000000), blurRadius: 24),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF4A1A7A), Color(0xFF1A0832)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'BUY IN',
                      style: text(
                        13,
                        const Color(0xFFC9B4F0),
                      ).copyWith(letterSpacing: 3),
                    ),
                    Text(table, style: text(22, AppColors.goldSoft)),
                    Text(
                      'Blinds ${formatCoins(smallBlind)}/'
                      '${formatCoins(smallBlind * 2)}',
                      style: text(12.5, const Color(0xFFC9B4F0)),
                    ),
                    const SizedBox(height: 14),
                    // The amount, on a felt plate.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF0E4A24), Color(0xFF052412)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.goldTrim,
                          width: 1.4,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'YOU SIT DOWN WITH',
                            style: text(
                              10.5,
                              const Color(0xFFB8E6C4),
                            ).copyWith(letterSpacing: 1.5),
                          ),
                          Text(
                            formatCoins(amount),
                            key: const ValueKey('buyin-amount'),
                            style: text(34, const Color(0xFFFFE28A)),
                          ),
                          Text(
                            '${(amount / (smallBlind * 2)).round()} big blinds',
                            style: text(11.5, const Color(0xFFB8E6C4)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SliderTheme(
                      data: SliderTheme.of(d).copyWith(
                        trackHeight: 7,
                        activeTrackColor: const Color(0xFFFFD45A),
                        inactiveTrackColor: const Color(0x55FFFFFF),
                        thumbColor: const Color(0xFFFFF1B8),
                        overlayColor: const Color(0x33FFD45A),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 12,
                        ),
                      ),
                      child: Slider(
                        key: const ValueKey('buyin-slider'),
                        min: range.min.toDouble(),
                        max: (most > range.min ? most : range.min + 1)
                            .toDouble(),
                        value: amount.toDouble(),
                        onChanged: most > range.min ? set : null,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          formatCoins(range.min),
                          style: text(11, const Color(0xFFC9B4F0)),
                        ),
                        const Spacer(),
                        Text(
                          formatCoins(most),
                          style: text(11, const Color(0xFFC9B4F0)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        quick('MIN', range.min),
                        quick('100 BB', range.usual),
                        quick('MAX', most),
                      ],
                    ),
                    const SizedBox(height: 14),
                    line(
                      'Your account',
                      formatCoins(bank),
                      Colors.white,
                      const ValueKey('buyin-bank'),
                    ),
                    const SizedBox(height: 4),
                    line(
                      'Stays in your account',
                      formatCoins(bank - amount),
                      const Color(0xFF7CFFCB),
                      const ValueKey('buyin-left'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(d),
                            child: Container(
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0x66000000),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0x88FFFFFF),
                                ),
                              ),
                              child: Text('CANCEL', style: text(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            key: const ValueKey('buyin-join'),
                            onTap: () => Navigator.pop(d, amount),
                            child: Container(
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF3FD07A),
                                    Color(0xFF1FA35C),
                                    Color(0xFF0E6B3A),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFFE28A),
                                  width: 1.6,
                                ),
                              ),
                              child: Text('JOIN TABLE', style: text(16)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
