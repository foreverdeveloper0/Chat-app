import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/icons.dart';
import '../art/pieces.dart';
import '../game/coins.dart';
import '../game/ludo_controller.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../theme/board_assets.dart';

String ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };

Color rankColor(int rank) => switch (rank) {
      1 => const Color(0xFFFFD23A),
      2 => const Color(0xFFD5DCEA),
      3 => const Color(0xFFE39A5C),
      _ => const Color(0xFFA9AEDC),
    };

// ───────────────────────── Page backdrop ─────────────────────────

/// Full-page table background: the supplied artwork, slightly darkened
/// in the middle so the board and docks stand out.
class LudoBackdrop extends StatelessWidget {
  const LudoBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(gameBgAsset,
              fit: BoxFit.cover, filterQuality: FilterQuality.medium),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: .8,
                colors: [Color(0x40060720), Color(0x00060720)],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

// ───────────────────────── Header ─────────────────────────

/// Round glass button used at the edges of the header and in the dock.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.lit = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: lit
                ? const [Color(0xFF7BF5C6), Color(0xFF14A873)]
                : const [Color(0xFF4A50A6), Color(0xFF23275E)],
          ),
          border: Border.all(
            color: lit ? const Color(0xFFD6FFF0) : const Color(0xFF7C83CC),
            width: 1.4,
          ),
          boxShadow: [
            if (lit) const BoxShadow(color: Color(0x9945E3A6), blurRadius: 14),
            const BoxShadow(
                color: Color(0x66060720), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Icon(icon,
            size: size * .5, color: lit ? AppColors.ink : AppColors.cream),
      ),
    );
  }
}

/// Top bar: back, a gold-trimmed plaque with prize / room / entry, sound.
class GameHeader extends StatelessWidget {
  const GameHeader({
    super.key,
    required this.prize,
    required this.entry,
    required this.roomId,
    required this.onBack,
  });
  final int prize;
  final int entry;
  final String roomId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, {Color? color, Widget? lead}) =>
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: AppText.title.copyWith(
                      fontSize: 9,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9EA4DC))),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lead != null) ...[lead, const SizedBox(width: 4)],
                    Text(value,
                        maxLines: 1,
                        style: AppText.title.copyWith(
                            fontSize: 15.5, color: color ?? AppColors.cream)),
                  ],
                ),
              ),
            ],
          ),
        );
    const divider = SizedBox(
      width: 1,
      height: 26,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00E3B341), Color(0xAAE3B341), Color(0x00E3B341)],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        children: [
          RoundButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 52,
              padding: const EdgeInsets.all(1.6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF3B8),
                    Color(0xFFE3B341),
                    Color(0xFF8A5E0C),
                    Color(0xFFFFE28A),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x55FFC93A), blurRadius: 12),
                  BoxShadow(
                      color: Color(0x88060720),
                      blurRadius: 10,
                      offset: Offset(0, 5)),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24.4),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2E3380), Color(0xFF12143F)],
                  ),
                ),
                child: Row(
                  children: [
                    stat('PRIZE', formatCoins(prize),
                        color: const Color(0xFFFFE28A),
                        lead: const CustomPaint(
                            size: Size.square(17), painter: CoinPainter())),
                    divider,
                    stat('ROOM', roomId),
                    divider,
                    stat('ENTRY', formatCoins(entry)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder(
            valueListenable: Sounds.muted,
            builder: (_, muted, _) => RoundButton(
              icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              onTap: () => Sounds.muted.value = !muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Voice + message dock ─────────────────────────

const _quick = ['👍', '😂', '😡', '🔥'];

/// Floating dock under the board: mic, one-tap reactions, messages.
class GameDock extends StatelessWidget {
  const GameDock({
    super.key,
    required this.micOn,
    required this.onMic,
    required this.onChat,
    required this.onQuick,
  });
  final bool micOn;
  final VoidCallback onMic;
  final VoidCallback onChat;
  final ValueChanged<String> onQuick;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE62E3380), Color(0xE612143F)],
        ),
        border: Border.all(color: const Color(0xFF5A61AE), width: 1.3),
        boxShadow: const [
          BoxShadow(
              color: Color(0x99060720), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundButton(
            icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            onTap: onMic,
            lit: micOn,
          ),
          const SizedBox(width: 8),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1136),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in _quick)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onQuick(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(e, style: const TextStyle(fontSize: 23)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RoundButton(icon: Icons.chat_bubble_rounded, onTap: onChat),
        ],
      ),
    );
  }
}

const _emojis = [
  '👍', '😂', '😎', '😡', '😭', '🔥', '🎉', '🙏', '😱', '🤝', '💪', '👏',
];
const _phrases = [
  'Hi!',
  'Good luck',
  'Nice move',
  'Oops!',
  'Hurry up',
  'Well played',
  'Thank you',
  'One more game?',
];

Widget _sheetShell({required String title, required List<Widget> children}) =>
    Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF262B70), Color(0xFF12143F)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Color(0xFFE3B341), width: 1.6)),
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
                color: const Color(0xFF5A61AE),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppText.title.copyWith(fontSize: 21)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );

Widget _sectionLabel(String text) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: AppText.title.copyWith(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF9EA4DC))),
      ),
    );

/// Reactions and quick chat lines; returns the chosen text.
Future<String?> showChatSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => _sheetShell(
      title: 'Messages',
      children: [
        _sectionLabel('REACTIONS'),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final e in _emojis)
              GestureDetector(
                onTap: () => Navigator.pop(sheet, e),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3A4096), Color(0xFF1B1E55)],
                    ),
                    border:
                        Border.all(color: const Color(0xFF5A61AE), width: 1),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 25)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel('QUICK CHAT'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 4.2,
          children: [
            for (final p in _phrases)
              GestureDetector(
                onTap: () => Navigator.pop(sheet, p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    // A speech-bubble corner.
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                    ),
                    color: const Color(0xFF0F1136),
                    border:
                        Border.all(color: const Color(0xFF45E3A6), width: 1.1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(p,
                              style: AppText.title.copyWith(fontSize: 14.5)),
                        ),
                      ),
                      const Icon(Icons.send_rounded,
                          size: 15, color: AppColors.mint),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

// ───────────────────────── Player profile ─────────────────────────

/// Demo player id: stable for a seat in a room. Real ids need accounts.
String playerUid(String roomId, int player) {
  final seed = (int.tryParse(roomId) ?? 0) * 31 + (player + 1) * 7919;
  return 'EP${1000000 + seed % 9000000}';
}

/// Profile card with identity, live match stats and coins.
Future<void> showPlayerProfile(
  BuildContext context, {
  required int player,
  required String name,
  required bool isYou,
  required LudoController game,
  required int entry,
  required int prize,
  required String roomId,
}) {
  final color = playerColors[player];
  final isBot = game.isBot(player);
  final tokens = game.tokens[player];
  final home = game.homeCount(player);
  final yard = tokens.where((t) => t.inYard).length;
  final rank = game.rankOf(player);
  final gone = game.left.contains(player);
  final status = gone
      ? 'Left the game'
      : rank > 0
          ? 'Finished ${ordinal(rank)}'
          : (game.current == player ? 'Playing now' : 'Waiting');

  Widget tile(String label, String value, {Color? valueColor, IconData? icon}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF0F1136),
          border: Border.all(color: const Color(0xFF3A4096), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: valueColor ?? AppColors.cream),
                    const SizedBox(width: 4),
                  ],
                  Text(value,
                      maxLines: 1,
                      style: AppText.title.copyWith(
                          fontSize: 17, color: valueColor ?? AppColors.cream)),
                ],
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  style: AppText.title.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9EA4DC))),
            ),
          ],
        ),
      );

  Widget grid(List<Widget> tiles) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.75,
        children: tiles,
      );

  Widget info(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF9EA4DC)),
            const SizedBox(width: 8),
            Text(label,
                style: AppText.title.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF9EA4DC))),
            const Spacer(),
            Text(value, style: AppText.title.copyWith(fontSize: 14)),
          ],
        ),
      );

  const gold = Color(0xFFFFE28A);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => _sheetShell(
      title: 'Player profile',
      children: [
        Row(
          children: [
            PlayerAvatar(
              player: player,
              isBot: isBot,
              isYou: isYou,
              rank: rank,
              timer: null,
              size: 76,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(fontSize: 22)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient:
                          LinearGradient(colors: [color, playerDeep[player]]),
                    ),
                    child: Text(
                      isBot ? 'Computer player' : (isYou ? 'You' : 'Guest player'),
                      style: AppText.title
                          .copyWith(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        info(Icons.badge_rounded, 'UID', playerUid(roomId, player)),
        if (!isBot)
          info(Icons.phone_rounded, 'Number', 'Not linked'),
        info(Icons.circle, 'Status', status),
        const SizedBox(height: 12),
        _sectionLabel('THIS MATCH'),
        grid([
          tile('Home', '$home/4'),
          tile('On board', '${4 - home - yard}'),
          tile('In yard', '$yard'),
          tile('Lives', '${game.lives[player] ?? 0}',
              valueColor: const Color(0xFFFF4D67),
              icon: Icons.favorite_rounded),
          tile('Captures', '${game.captures[player] ?? 0}',
              valueColor: AppColors.mint),
          tile('Pieces lost', '${game.lost[player] ?? 0}'),
        ]),
        const SizedBox(height: 14),
        _sectionLabel('COINS'),
        grid([
          tile('Entry paid', formatCoins(entry), valueColor: gold),
          tile('Prize pool', formatCoins(prize), valueColor: gold),
          tile('Room', roomId),
        ]),
      ],
    ),
  );
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0x55000010), blurRadius: 6),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontFamily: AppText.family,
              fontWeight: FontWeight.w600,
              fontSize: text.runes.length <= 2 ? 22 : 13,
              color: const Color(0xFF1C1B33),
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Avatar + dice socket ─────────────────────────

/// Round player picture with a coloured ring. While the player is on the
/// clock the ring drains, and a finisher gets a small rank badge.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.player,
    required this.isBot,
    required this.isYou,
    required this.rank,
    required this.timer,
    this.size = 46,
  });
  final int player;
  final bool isBot;
  final bool isYou;
  final int rank;

  /// (serial, seconds) while the turn timer runs.
  final (int, int)? timer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = playerColors[player];
    final inner = size - 8;
    final Widget picture = isYou
        ? Art(ArtKind.avatar, size: inner)
        : isBot
            ? Art(ArtKind.robot, size: inner * .78)
            : Image.asset(pawnAssets[player],
                width: inner * .62, height: inner * .86);
    Widget ring(double value, Color c) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(value, c, size * .075),
        );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Color.lerp(color, Colors.white, .25)!.withValues(alpha: .45),
                AppColors.cardInset,
              ]),
            ),
            alignment: Alignment.center,
            child: picture,
          ),
          if (timer == null)
            ring(1, color)
          else
            TweenAnimationBuilder<double>(
              key: ValueKey('timer-${timer!.$1}'),
              tween: Tween(begin: 1, end: 0),
              duration: Duration(seconds: timer!.$2),
              builder: (_, v, _) =>
                  ring(v, v < .3 ? const Color(0xFFFF4D67) : AppColors.mint),
            ),
          if (rank > 0)
            Positioned(
              right: -4,
              top: -5,
              child: Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rankColor(rank),
                  border: Border.all(color: AppColors.cardBottom, width: 1.5),
                ),
                child: Text('$rank',
                    style: AppText.title.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF3A2A00),
                        height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value, this.color, this.stroke);
  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false,
        paint..color = const Color(0xFF14173F));
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false,
        paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

/// The velvet-dark, gold-rimmed tray the dice rests in.
class DiceSocket extends StatelessWidget {
  const DiceSocket({super.key, required this.active, this.child});
  final bool active;
  final Widget? child;

  static const size = 52.0;
  static const diceSize = 41.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? const [Color(0xFFFFF0A8), Color(0xFFE3B341), Color(0xFF9C6B0E)]
              : const [Color(0xFF565CA8), Color(0xFF34397A), Color(0xFF262A60)],
        ),
        boxShadow: [
          if (active)
            const BoxShadow(color: Color(0x80FFC93A), blurRadius: 10),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const RadialGradient(
            radius: .9,
            colors: [Color(0xFF2A2F78), Color(0xFF0F1136)],
          ),
        ),
        alignment: Alignment.center,
        child: child ??
            Opacity(
              opacity: .28,
              child: CustomPaint(
                size: const Size.square(diceSize * .8),
                painter: _GhostDicePainter(),
              ),
            ),
      ),
    );
  }
}

class _GhostDicePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintDice(canvas, Offset.zero & size, 5);

  @override
  bool shouldRepaint(_GhostDicePainter old) => false;
}

// ───────────────────────── Yard badges ─────────────────────────

/// Sits on a player's yard: a crown with their place once they finish, or
/// a "left" marker if they are out of the match.
class YardBadge extends StatelessWidget {
  const YardBadge({
    super.key,
    required this.cell,
    required this.rank,
    required this.left,
  });
  final double cell;
  final int rank;
  final bool left;

  @override
  Widget build(BuildContext context) {
    if (left) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: Color(0x99080920)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: cell * 2.2,
                height: cell * 2.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2A2F78),
                  border: Border.all(color: const Color(0xFFFF8A80), width: 2),
                ),
                child: Icon(Icons.logout_rounded,
                    color: const Color(0xFFFF8A80), size: cell * 1.3),
              ),
              SizedBox(height: cell * .15),
              Text('LEFT',
                  style: AppText.title.copyWith(
                      fontSize: cell * .7,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Colors.white)),
            ],
          ),
        ),
      );
    }
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 550),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: Size(cell * 2.5, cell * 1.8),
              painter: CrownPainter(rankColor(rank)),
            ),
            Text(ordinal(rank),
                style: AppText.title.copyWith(
                  fontSize: cell * .95,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2B2140),
                  height: 1.1,
                )),
          ],
        ),
      ),
    );
  }
}

class CrownPainter extends CustomPainter {
  const CrownPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(color, Colors.black, .35)!;
    final crown = Path()
      ..moveTo(w * .1, h * .78)
      ..lineTo(w * .02, h * .25)
      ..lineTo(w * .28, h * .5)
      ..lineTo(w * .5, h * .06)
      ..lineTo(w * .72, h * .5)
      ..lineTo(w * .98, h * .25)
      ..lineTo(w * .9, h * .78)
      ..close();
    final rect = Offset.zero & size;
    canvas.drawPath(
      crown.shift(Offset(0, h * .05)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * .06),
    );
    canvas.drawPath(
      crown,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .55)!, color, dark],
        ).createShader(rect),
    );
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * .035
        ..strokeJoin = StrokeJoin.round
        ..color = dark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * .1, h * .78, w * .8, h * .17),
          Radius.circular(h * .06)),
      Paint()..color = dark,
    );
    for (final (x, y) in const [(.02, .25), (.5, .06), (.98, .25)]) {
      canvas.drawCircle(Offset(w * x, h * y), h * .07,
          Paint()..color = Color.lerp(color, Colors.white, .6)!);
    }
    canvas.drawCircle(Offset(w * .5, h * .58), h * .08,
        Paint()..color = const Color(0xFFE0182D));
  }

  @override
  bool shouldRepaint(CrownPainter old) => old.color != color;
}

// ───────────────────────── Start banner ─────────────────────────

/// A low, wide ribbon (25px side margins) that sweeps in, holds, and leaves.
class StartBanner extends StatelessWidget {
  const StartBanner({super.key, required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        final t = animation.value;
        if (t <= 0 || t >= 1) return const SizedBox.shrink();
        final enter = Curves.easeOutBack.transform((t / .22).clamp(0, 1));
        final exit = Curves.easeIn.transform(((t - .8) / .2).clamp(0, 1));
        final shine = ((t - .25) / .45).clamp(0.0, 1.0);
        return Center(
          child: Opacity(
            opacity: ((t / .12).clamp(0, 1) * (1 - exit)).toDouble(),
            child: Transform.translate(
              offset: Offset((1 - enter) * -260 + exit * 260, 0),
              child: Container(
                height: 62,
                margin: const EdgeInsets.symmetric(horizontal: 25),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1FBF86),
                      Color(0xFF45E3A6),
                      Color(0xFF1FBF86),
                    ],
                  ),
                  border: Border.all(color: const Color(0xFFFFE28A), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x9945E3A6), blurRadius: 26),
                    BoxShadow(
                        color: Color(0x88000010),
                        blurRadius: 12,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Light sweep.
                    Positioned.fill(
                      child: FractionalTranslation(
                        translation: Offset(-1.2 + shine * 2.4, 0),
                        child: Transform(
                          transform: Matrix4.skewX(-.5),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Color(0x00FFFFFF),
                                Color(0x88FFFFFF),
                                Color(0x00FFFFFF),
                              ], stops: [
                                .35,
                                .5,
                                .65
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CustomPaint(
                            size: Size.square(34), painter: _BannerDice(6)),
                        const SizedBox(width: 12),
                        Text(
                          'GAME START',
                          style: AppText.title.copyWith(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const CustomPaint(
                            size: Size.square(34), painter: _BannerDice(5)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BannerDice extends CustomPainter {
  const _BannerDice(this.value);
  final int value;

  @override
  void paint(Canvas canvas, Size size) =>
      paintDice(canvas, Offset.zero & size, value, angle: value == 6 ? -.2 : .2);

  @override
  bool shouldRepaint(_BannerDice old) => false;
}

// ───────────────────────── Results ─────────────────────────

class ResultOverlay extends StatefulWidget {
  const ResultOverlay({
    super.key,
    required this.order,
    required this.left,
    required this.names,
    required this.prize,
    required this.onAgain,
    required this.onHome,
  });
  final List<int> order;
  final Set<int> left;
  final Map<int, String> names;
  final int prize;
  final VoidCallback onAgain;
  final VoidCallback onHome;

  @override
  State<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<ResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _row(int player, int rank, {bool gone = false}) {
    final name = widget.names[player] ?? 'Player';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 24,
            child: gone
                ? const Icon(Icons.logout_rounded,
                    size: 20, color: Color(0xFFFF8A80))
                : rank <= 3
                    ? CustomPaint(painter: CrownPainter(rankColor(rank)))
                    : null,
          ),
          const SizedBox(width: 8),
          Image.asset(pawnAssets[player], width: 16, height: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(shortName(name, 12),
                maxLines: 1,
                style: AppText.title.copyWith(fontSize: 17)),
          ),
          Text(
            gone
                ? 'Left'
                : rank == 1
                    ? '+${formatCoins(widget.prize)}'
                    : ordinal(rank),
            style: AppText.title.copyWith(
                fontSize: 15,
                color: gone
                    ? const Color(0xFFFF8A80)
                    : (rank == 1 ? const Color(0xFFFFE28A) : rankColor(rank))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final winner = widget.order.isEmpty ? null : widget.order.first;
    final name = winner == null ? '' : (widget.names[winner] ?? 'Player');
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => ColoredBox(
        color: Color.fromRGBO(8, 9, 32, .8 * v.clamp(0, 1)),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ConfettiPainter(_c)),
              ),
            ),
            Center(child: Transform.scale(scale: v, child: child)),
          ],
        ),
      ),
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.cardTop, AppColors.cardBottom],
          ),
          border: Border.all(
            color: winner == null ? AppColors.cardBorder : playerColors[winner],
            width: 2.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Art(ArtKind.trophy, size: 92),
            const SizedBox(height: 6),
            Text(
              '${shortName(name, 12)} ${name == 'You' ? 'win' : 'wins'}!',
              textAlign: TextAlign.center,
              style: AppText.title
                  .copyWith(fontSize: 27, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < widget.order.length; i++)
              _row(widget.order[i], i + 1),
            for (final p in widget.left) _row(p, 0, gone: true),
            const SizedBox(height: 14),
            _WideButton(label: 'Play again', filled: true, onTap: widget.onAgain),
            const SizedBox(height: 10),
            _WideButton(label: 'Home', filled: false, onTap: widget.onHome),
          ],
        ),
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton(
      {required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: filled
              ? const LinearGradient(
                  colors: [Color(0xFF6BF0BD), AppColors.mintDeep])
              : null,
          border: filled
              ? null
              : Border.all(color: AppColors.cardBorder, width: 1.5),
        ),
        child: Text(
          label,
          style: AppText.title.copyWith(
              fontSize: 17, color: filled ? AppColors.ink : AppColors.cream),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  static final _bits = () {
    final r = math.Random(7);
    return [
      for (var i = 0; i < 90; i++)
        (
          x: r.nextDouble(),
          phase: r.nextDouble(),
          speed: .6 + r.nextDouble() * .8,
          sway: r.nextDouble() * 2 * math.pi,
          size: 5 + r.nextDouble() * 6,
          color: [...playerColors, AppColors.mint, Colors.white][r.nextInt(6)],
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final b in _bits) {
      final fall = (t.value * b.speed + b.phase) % 1;
      final x = b.x * size.width + math.sin(fall * 6 + b.sway) * 18;
      final y = fall * (size.height + 40) - 20;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(fall * 12 + b.sway);
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: b.size, height: b.size * .55),
        paint..color = b.color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
