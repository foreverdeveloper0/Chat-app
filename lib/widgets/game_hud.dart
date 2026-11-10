import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/icons.dart';
import '../art/pieces.dart';
import '../game/coins.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../theme/board_assets.dart';
import 'game_card.dart';

String ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };

Color rankColor(int rank) => switch (rank) {
      1 => const Color(0xFFFFD23A),
      2 => const Color(0xFFD5DCEA),
      3 => const Color(0xFFE39A5C),
      _ => const Color(0xFFA9AEDC),
    };

// ───────────────────────── Header ─────────────────────────

/// Back button, prize pool with room details, and the sound toggle.
class GameHeader extends StatelessWidget {
  const GameHeader({
    super.key,
    required this.prize,
    required this.entry,
    required this.roomId,
    required this.status,
    required this.onBack,
  });
  final int prize;
  final int entry;
  final String roomId;
  final String status;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final small = AppText.title.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: const Color(0xFFB9BEEA),
        height: 1.2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GameCard(
                width: 44,
                height: 44,
                radius: 14,
                onTap: onBack,
                child:
                    const Icon(Icons.arrow_back_rounded, color: AppColors.cream),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 30,
                      padding: const EdgeInsets.only(left: 3, right: 12),
                      decoration: BoxDecoration(
                        color: AppColors.cardInset,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                            color: const Color(0xFFE3B341), width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CustomPaint(
                              size: Size.square(24), painter: CoinPainter()),
                          const SizedBox(width: 6),
                          Text('Prize ${formatCoins(prize)}',
                              style: AppText.title.copyWith(
                                  fontSize: 15,
                                  color: const Color(0xFFFFE28A))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Room $roomId  •  Entry ${formatCoins(entry)}',
                        style: small),
                  ],
                ),
              ),
              ValueListenableBuilder(
                valueListenable: Sounds.muted,
                builder: (_, muted, _) => GameCard(
                  width: 44,
                  height: 44,
                  radius: 14,
                  onTap: () => Sounds.muted.value = !muted,
                  child: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: muted ? const Color(0xFFA9AEDC) : AppColors.cream,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 18,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                status,
                key: ValueKey(status),
                maxLines: 1,
                style: AppText.title
                    .copyWith(fontSize: 13.5, color: AppColors.mint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Voice + chat bar ─────────────────────────

class GameBottomBar extends StatelessWidget {
  const GameBottomBar({
    super.key,
    required this.micOn,
    required this.onMic,
    required this.onChat,
  });
  final bool micOn;
  final VoidCallback onMic;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback onTap, bool lit) =>
        GameCard(
          height: 44,
          radius: 22,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 21, color: lit ? AppColors.mint : AppColors.cream),
              const SizedBox(width: 7),
              Text(label,
                  style: AppText.title.copyWith(
                      fontSize: 14.5,
                      color: lit ? AppColors.mint : AppColors.cream)),
            ],
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        button(micOn ? Icons.mic_rounded : Icons.mic_off_rounded, 'Voice',
            onMic, micOn),
        const SizedBox(width: 12),
        button(Icons.chat_bubble_rounded, 'Message', onChat, false),
      ],
    );
  }
}

const _emojis = ['👍', '😂', '😎', '😡', '😭', '🔥', '🎉', '🙏'];
const _phrases = [
  'Hi!',
  'Good luck',
  'Nice move',
  'Oops!',
  'Hurry up',
  'Well played',
];

/// Quick messages; returns the chosen text.
Future<String?> showChatSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheet) => Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
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
            Text('Send a message', style: AppText.title.copyWith(fontSize: 20)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final e in _emojis)
                  GestureDetector(
                    onTap: () => Navigator.pop(sheet, e),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in _phrases)
                  GameCard(
                    height: 40,
                    radius: 20,
                    onTap: () => Navigator.pop(sheet, p),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p, style: AppText.title.copyWith(fontSize: 15)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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
  });
  final int player;
  final bool isBot;
  final bool isYou;
  final int rank;

  /// (serial, seconds) while the turn timer runs.
  final (int, int)? timer;

  static const size = 42.0;

  @override
  Widget build(BuildContext context) {
    final color = playerColors[player];
    final Widget picture = isYou
        ? const Art(ArtKind.avatar, size: 34)
        : isBot
            ? const Art(ArtKind.robot, size: 27)
            : Image.asset(pawnAssets[player], width: 22, height: 30);
    Widget ring(double value, Color c) => CustomPaint(
          size: const Size.square(size),
          painter: _RingPainter(value, c),
        );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
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
              key: ValueKey(timer!.$1),
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
  const _RingPainter(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.75);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
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
  static const diceSize = 38.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(14),
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
