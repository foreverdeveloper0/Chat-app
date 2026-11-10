import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/board.dart';
import '../art/icons.dart';
import '../art/pieces.dart';
import '../theme/app_colors.dart';
import 'game_card.dart';

typedef Tap = void Function(String label);

// ───────────────────────── Top bar ─────────────────────────

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.onTap});
  final Tap onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GameCard(
            height: 48,
            radius: 24,
            onTap: () => onTap('Profile'),
            padding: const EdgeInsets.fromLTRB(5, 0, 6, 0),
            child: Row(
              children: [
                const Art(ArtKind.avatar, size: 38),
                const SizedBox(width: 8),
                Text('Profile', style: AppText.title.copyWith(fontSize: 16.5)),
                const Spacer(),
                Container(width: 1, height: 20, color: AppColors.cardBorder),
                const SizedBox(width: 10),
                const _Wallet(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GameCard(
          width: 46,
          height: 48,
          radius: 15,
          onTap: () => onTap('Settings'),
          child: const Icon(Icons.settings_rounded,
              color: Color(0xFFDDE1FF), size: 25),
        ),
      ],
    );
  }
}

class _Wallet extends StatelessWidget {
  const _Wallet();

  @override
  Widget build(BuildContext context) {
    final num = AppText.title.copyWith(fontSize: 16.5);
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 3, right: 12),
      decoration: BoxDecoration(
        color: AppColors.cardInset,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CustomPaint(size: Size.square(28), painter: CoinPainter()),
          const SizedBox(width: 7),
          Text('1,250', style: num),
          const SizedBox(width: 10),
          Container(width: 1, height: 16, color: AppColors.cardBorder),
          const SizedBox(width: 10),
          const CustomPaint(size: Size(22, 20), painter: GemPainter()),
          const SizedBox(width: 7),
          Text('80', style: num),
        ],
      ),
    );
  }
}

// ───────────────────────── Logo ─────────────────────────

class LogoHeader extends StatelessWidget {
  const LogoHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: CustomPaint(size: Size(42, 80), painter: LaurelPainter()),
              ),
              const SizedBox(width: 2),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x331FBF86),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.mint, width: 1.6),
                    ),
                    child: Text(
                      'ELITE PLAY BD',
                      style: AppText.title.copyWith(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const _LudoWord(),
                ],
              ),
              const SizedBox(width: 2),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: CustomPaint(
                    size: Size(42, 80), painter: LaurelPainter(mirror: true)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MintBar(width: 30),
              const SizedBox(width: 10),
              Transform(
                transform: Matrix4.skewX(-.22),
                alignment: Alignment.center,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6BF0BD), AppColors.mint],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Transform(
                    transform: Matrix4.skewX(.22),
                    alignment: Alignment.center,
                    child: Text(
                      'Free to play',
                      style: AppText.title.copyWith(
                        fontSize: 14.5,
                        color: AppColors.ink,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const MintBar(width: 30),
            ],
          ),
        ],
      ),
    );
  }
}

class _LudoWord extends StatelessWidget {
  const _LudoWord();

  @override
  Widget build(BuildContext context) {
    final style = AppText.title.copyWith(
      fontSize: 68,
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
      height: .98,
    );
    return Stack(
      children: [
        ExcludeSemantics(
          child: Transform.translate(
            offset: const Offset(0, 4),
            child: Text('LUDO',
                style: style.copyWith(color: const Color(0x8C0A0B2A))),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFFFE6BC)],
          ).createShader(r),
          child: Text('LUDO', style: style),
        ),
      ],
    );
  }
}

// ───────────────────────── Hero (side tiles + board) ─────────────────────────

class HeroSection extends StatelessWidget {
  const HeroSection({super.key, required this.onTap});
  final Tap onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
              left: 82, right: -18, top: -12, bottom: -6, child: _FloatingBoard()),
          Positioned(
            left: 4,
            top: 6,
            child: _SideTile(
                art: ArtKind.coinStack,
                label: 'Coin Earn',
                onTap: () => onTap('Coin Earn')),
          ),
          Positioned(
            left: 4,
            bottom: 6,
            child: _SideTile(
                art: ArtKind.calendar,
                label: 'Daily Tasks',
                onTap: () => onTap('Daily Tasks')),
          ),
        ],
      ),
    );
  }
}

class _SideTile extends StatelessWidget {
  const _SideTile({required this.art, required this.label, required this.onTap});
  final ArtKind art;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      width: 86,
      height: 86,
      radius: 16,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Art(art, size: 50),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              style: AppText.title.copyWith(fontSize: 12.5, height: 1.2)),
        ],
      ),
    );
  }
}

/// The board is rasterised once; the idle "float" only moves its layer.
class _FloatingBoard extends StatefulWidget {
  const _FloatingBoard();

  @override
  State<_FloatingBoard> createState() => _FloatingBoardState();
}

class _FloatingBoardState extends State<_FloatingBoard>
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, math.sin(_c.value * 2 * math.pi) * 3.5),
        child: child,
      ),
      child: const RepaintBoundary(
        child: CustomPaint(painter: LudoBoardPainter(), size: Size.infinite),
      ),
    );
  }
}

// ───────────────────────── Game modes ─────────────────────────

class ModeGrid extends StatelessWidget {
  const ModeGrid({super.key, required this.onTap});
  final Tap onTap;

  static const _modes = [
    (ArtKind.globe, 'Play\nOnline'),
    (ArtKind.pawnPair, 'Play with\nFriends'),
    (ArtKind.dicePair, 'Pass &\nPlay'),
    (ArtKind.robot, 'Play vs\nComputer'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget card(int i) => Expanded(
          child: _ModeCard(
            art: _modes[i].$1,
            label: _modes[i].$2,
            onTap: () => onTap(_modes[i].$2.replaceAll('\n', ' ')),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [card(0), const SizedBox(width: 9), card(1)]),
        const SizedBox(height: 9),
        Row(children: [card(2), const SizedBox(width: 9), card(3)]),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.art, required this.label, required this.onTap});
  final ArtKind art;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      height: 90,
      radius: 20,
      onTap: onTap,
      padding: const EdgeInsets.only(left: 10, right: 8),
      child: Row(
        children: [
          Art(art, size: 64),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(label,
                      style: AppText.title.copyWith(fontSize: 18.5)),
                ),
                const SizedBox(height: 7),
                const MintBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Tournament ─────────────────────────

class TournamentBanner extends StatelessWidget {
  const TournamentBanner({super.key, required this.onTap});
  final Tap onTap;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      height: 80,
      radius: 20,
      onTap: () => onTap('Tournament'),
      padding: const EdgeInsets.only(left: 22, right: 10),
      child: Row(
        children: [
          const Art(ArtKind.trophy, size: 70),
          const SizedBox(width: 22),
          Container(width: 1, height: 42, color: AppColors.cardBorder),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Tournament',
                  style: AppText.title.copyWith(
                      fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _Hairline(),
                    const SizedBox(width: 9),
                    Text(
                      'Free entry',
                      style: AppText.title.copyWith(
                        fontSize: 14.5,
                        color: AppColors.mint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const _Hairline(),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.mint, size: 38),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(width: 30, height: 1.5, color: AppColors.mint);
}

// ───────────────────────── Bottom navigation ─────────────────────────

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const items = [
    (ArtKind.home, 'Home'),
    (ArtKind.friends, 'Friends'),
    (ArtKind.history, 'History'),
    (ArtKind.agent, 'Agent'),
  ];

  @override
  Widget build(BuildContext context) {
    return GameCard(
      height: 78,
      radius: 24,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 44, color: AppColors.cardBorder),
            Expanded(
              child: _NavItem(
                art: items[i].$1,
                label: items[i].$2,
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.art,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final ArtKind art;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.1 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: Art(art, size: 34),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: AppText.title.copyWith(
                fontSize: 13.5,
                color: selected ? AppColors.mint : AppColors.cream,
              ),
              child: Text(label),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: selected ? 46 : 0,
              height: 3.5,
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
