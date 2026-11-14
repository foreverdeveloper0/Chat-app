import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/coins.dart';
import '../game/poker_wallet.dart';
import '../theme/app_colors.dart';

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
        final short = MediaQuery.sizeOf(d).height < 520;
        final header = Column(
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
          ],
        );
        // The amount, on a felt plate.
        final plate = Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0E4A24), Color(0xFF052412)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.goldTrim, width: 1.4),
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
        );
        final slider = Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(d).copyWith(
                trackHeight: 7,
                activeTrackColor: const Color(0xFFFFD45A),
                inactiveTrackColor: const Color(0x55FFFFFF),
                thumbColor: const Color(0xFFFFF1B8),
                overlayColor: const Color(0x33FFD45A),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              ),
              child: Slider(
                key: const ValueKey('buyin-slider'),
                min: range.min.toDouble(),
                max: (most > range.min ? most : range.min + 1).toDouble(),
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
          ],
        );
        final account = Column(
          children: [
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
          ],
        );
        final buttons = Row(
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
                    border: Border.all(color: const Color(0x88FFFFFF)),
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
        );
        // Upright: one column. Sideways, where there is little height: two
        // columns, the amount on the left and the controls on the right.
        final body = short
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [header, const SizedBox(height: 14), plate],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        slider,
                        const SizedBox(height: 10),
                        account,
                        const SizedBox(height: 10),
                        buttons,
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  const SizedBox(height: 14),
                  plate,
                  const SizedBox(height: 6),
                  slider,
                  const SizedBox(height: 14),
                  account,
                  const SizedBox(height: 14),
                  buttons,
                ],
              );
        final width = short
            ? math.min(MediaQuery.sizeOf(d).width - 32, 600.0)
            : 320.0;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: width,
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
                padding: EdgeInsets.fromLTRB(
                  18,
                  short ? 12 : 16,
                  18,
                  short ? 12 : 16,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF4A1A7A), Color(0xFF1A0832)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: body,
              ),
            ),
          ),
        );
      },
    ),
  );
}
