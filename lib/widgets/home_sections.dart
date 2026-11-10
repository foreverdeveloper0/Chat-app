import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../art/icons.dart';
import '../art/pieces.dart';
import '../theme/app_colors.dart';
import 'game_hud.dart' show CrownPainter;
import 'live_board.dart';

typedef Tap = void Function(String label);

const _gold = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: AppColors.goldGradient,
);

/// Shrinks slightly while pressed and gives a light haptic tick on tap.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? .95 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Dark glass card with a thin border, the base of every panel on the hub.
BoxDecoration hubCard({
  double radius = 18,
  Color border = AppColors.cardBorder,
  List<Color>? colors,
  Color? glow,
}) =>
    BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors ?? const [AppColors.cardTop, AppColors.cardBottom],
      ),
      border: Border.all(color: border, width: 1.2),
      boxShadow: [
        if (glow != null) BoxShadow(color: glow, blurRadius: 14),
        const BoxShadow(
            color: Color(0x80020310), blurRadius: 12, offset: Offset(0, 6)),
      ],
    );

// ───────────────────────── Top bar ─────────────────────────

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.onTap});
  final Tap onTap;

  @override
  Widget build(BuildContext context) {
    final num = AppText.title.copyWith(fontSize: 15.5);
    Widget pill(ArtKind art, String value, double size) => Container(
          height: 30,
          padding: const EdgeInsets.only(left: 3, right: 10),
          decoration: BoxDecoration(
            color: AppColors.cardInset,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Art(art, size: size),
              const SizedBox(width: 6),
              Text(value, style: num),
            ],
          ),
        );
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.fromLTRB(5, 0, 8, 0),
            decoration: hubCard(radius: 25),
            child: Row(
              children: [
                Pressable(
                  onTap: () => onTap('Profile'),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(1.6),
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, gradient: _gold),
                        child: const Art(ArtKind.avatar, size: 36),
                      ),
                      const SizedBox(width: 8),
                      Text('Profile',
                          style: AppText.title.copyWith(fontSize: 15.5)),
                    ],
                  ),
                ),
                const Spacer(),
                pill(ArtKind.coin, '1,250', 24),
                const SizedBox(width: 6),
                pill(ArtKind.gem, '80', 20),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Pressable(
          onTap: () => onTap('Settings'),
          child: Container(
            width: 46,
            height: 50,
            decoration: hubCard(radius: 16),
            child: const Icon(Icons.settings_rounded,
                color: AppColors.goldSoft, size: 25),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Brand + hero ─────────────────────────

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CustomPaint(
              size: Size(34, 22), painter: CrownPainter(AppColors.goldSoft)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CustomPaint(
                size: Size(24, 44),
                painter: LaurelPainter(color: AppColors.goldTrim),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22), gradient: _gold),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20.5),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B1235), Color(0xFF1A2A70)],
                    ),
                  ),
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: _gold.createShader,
                    child: Text(
                      'ELITE PLAY BD',
                      style: AppText.title.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const CustomPaint(
                size: Size(24, 44),
                painter: LaurelPainter(mirror: true, color: AppColors.goldTrim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The featured game: gold LUDO title and PLAY NOW beside the live board.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.onPlay});
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final ludo = AppText.title.copyWith(
      fontSize: 50,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      height: 1,
    );
    return Container(
      height: 176,
      padding: const EdgeInsets.all(1.4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFEBCB7A),
            Color(0x333A66F5),
            Color(0xFF3A66F5),
            Color(0xFFB8862B),
          ],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x553A66F5), blurRadius: 22),
          BoxShadow(
              color: Color(0x99020310), blurRadius: 14, offset: Offset(0, 8)),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22.6),
          gradient: const RadialGradient(
            center: Alignment(.6, -.2),
            radius: 1.2,
            colors: [Color(0xFF22339A), Color(0xFF0B1235), Color(0xFF060A20)],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              left: 132,
              right: -14,
              top: -6,
              bottom: -4,
              child: _FloatingBoard(),
            ),
            Positioned(
              left: 14,
              top: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 42),
                    child: CustomPaint(
                        size: Size(26, 17),
                        painter: CrownPainter(AppColors.goldSoft)),
                  ),
                  Stack(
                    children: [
                      Transform.translate(
                        offset: const Offset(0, 4),
                        child: ExcludeSemantics(
                          child: Text('LUDO',
                              style: ludo.copyWith(
                                  color: const Color(0xB3020310))),
                        ),
                      ),
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: _gold.createShader,
                        child: Text('LUDO', style: ludo),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Pressable(
                    onTap: onPlay,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.only(left: 16, right: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(19),
                        gradient: _gold,
                        boxShadow: const [
                          BoxShadow(color: Color(0x80EBCB7A), blurRadius: 12),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PLAY NOW',
                            style: AppText.title.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF3A2500),
                            ),
                          ),
                          const Icon(Icons.play_arrow_rounded,
                              color: Color(0xFF3A2500), size: 22),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live demo board, drifting gently up and down.
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
        offset: Offset(0, math.sin(_c.value * 2 * math.pi) * 3),
        child: child,
      ),
      child: const RepaintBoundary(child: LiveBoard()),
    );
  }
}

// ───────────────────────── Section title ─────────────────────────

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: SizedBox(
        height: 1.4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0x003A66F5), Color(0xFF3A66F5)]),
          ),
        ),
      ),
    );
    return Row(
      children: [
        line,
        const SizedBox(width: 10),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: AppColors.cardInset,
            border: Border.all(color: AppColors.royal, width: 1.3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: AppColors.goldSoft),
              const SizedBox(width: 7),
              Text(label,
                  style: AppText.title.copyWith(
                      fontSize: 14.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: SizedBox(
            height: 1.4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF3A66F5), Color(0x003A66F5)]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Games ─────────────────────────

class GameInfo {
  const GameInfo(this.name, this.colors, {this.art, this.emoji, this.ready = false});
  final String name;
  final List<Color> colors;
  final ArtKind? art;
  final String? emoji;

  /// Only finished games open; the rest are announced as coming soon.
  final bool ready;
}

const games = [
  GameInfo('LUDO', [Color(0xFF3A66F5), Color(0xFF14246E)],
      art: ArtKind.pawnPair, ready: true),
  GameInfo('SNAKE', [Color(0xFF1FA35A), Color(0xFF0B3D2A)], emoji: '🐍'),
  GameInfo('CARROM', [Color(0xFFC7772B), Color(0xFF4A2408)], emoji: '🎯'),
  GameInfo('FRUIT CUT', [Color(0xFFD63A5E), Color(0xFF4A0E2A)], emoji: '🍉'),
  GameInfo('CAR RACING', [Color(0xFF2B8BD6), Color(0xFF0B2A52)], emoji: '🏎️'),
  GameInfo('POKER', [Color(0xFF2E9E57), Color(0xFF0B3A22)], emoji: '🃏'),
];

class GameTile extends StatelessWidget {
  const GameTile({
    super.key,
    required this.game,
    required this.height,
    required this.onTap,
  });
  final GameInfo game;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = height * .5;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(1.3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: game.ready
                ? AppColors.goldGradient
                : [
                    Color.lerp(game.colors[0], Colors.white, .35)!,
                    game.colors[1],
                  ],
          ),
          boxShadow: [
            BoxShadow(
                color: game.colors[0].withValues(alpha: .45), blurRadius: 12),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.7),
            gradient: RadialGradient(
              center: const Alignment(0, -.5),
              radius: 1.1,
              colors: game.colors,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: height * .08,
                child: game.art != null
                    ? Art(game.art!, size: iconSize)
                    : Text(game.emoji ?? '',
                        style: TextStyle(fontSize: iconSize * .82, height: 1.1)),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Container(
                  height: 22,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xCC050818),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: Color.lerp(game.colors[0], Colors.white, .4)!,
                        width: 1),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      game.name,
                      maxLines: 1,
                      style: AppText.title.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ),
              ),
              if (!game.ready)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xCC050818),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('SOON',
                        style: AppText.title.copyWith(
                            fontSize: 8.5,
                            letterSpacing: .8,
                            color: AppColors.goldSoft)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GamesGrid extends StatelessWidget {
  const GamesGrid({super.key, required this.onGame, required this.onMore});
  final ValueChanged<GameInfo> onGame;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    Widget tile(int i, double h) => Expanded(
          child: GameTile(
              game: games[i], height: h, onTap: () => onGame(games[i])),
        );
    const gap = SizedBox(width: 9);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [tile(0, 104), gap, tile(1, 104), gap, tile(2, 104)]),
        const SizedBox(height: 9),
        Row(
          children: [
            tile(3, 92),
            gap,
            tile(4, 92),
            gap,
            tile(5, 92),
            gap,
            Expanded(
              child: Pressable(
                onTap: onMore,
                child: Container(
                  height: 92,
                  decoration: hubCard(
                    colors: const [Color(0xFF4A2BA8), Color(0xFF1B0F52)],
                    border: const Color(0xFF8E6CFF),
                    glow: const Color(0x554A2BA8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sports_esports_rounded,
                          color: Color(0xFFC9B8FF), size: 30),
                      const SizedBox(height: 3),
                      Text('MORE\nGAMES',
                          textAlign: TextAlign.center,
                          style: AppText.title.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              height: 1.15)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────── Features ─────────────────────────

class FeatureInfo {
  const FeatureInfo(this.name, this.colors, {this.art, this.icon});
  final String name;
  final List<Color> colors;
  final ArtKind? art;
  final IconData? icon;
}

/// Shown on the hub itself.
const mainFeatures = [
  FeatureInfo('Daily Bonus', [Color(0xFF4A3BD6), Color(0xFF1B1466)],
      art: ArtKind.calendar),
  FeatureInfo('Coin Earn', [Color(0xFF1E9E63), Color(0xFF0B3D2A)],
      art: ArtKind.coinStack),
  FeatureInfo('Tournament', [Color(0xFF7A3BD6), Color(0xFF2A1466)],
      art: ArtKind.trophy),
];

/// Everything else lives behind the "All features" button.
const moreFeatures = [
  FeatureInfo('Refer & Earn', [Color(0xFF2B6FD6), Color(0xFF0B2A66)],
      art: ArtKind.friends),
  FeatureInfo('Leaderboard', [Color(0xFFB8862B), Color(0xFF4A3008)],
      icon: Icons.leaderboard_rounded),
  FeatureInfo('Live Support', [Color(0xFF2B8BD6), Color(0xFF0B2A52)],
      icon: Icons.headset_mic_rounded),
  FeatureInfo('Friends', [Color(0xFF3A66F5), Color(0xFF14246E)],
      art: ArtKind.friends),
  FeatureInfo('History', [Color(0xFF1E9E63), Color(0xFF0B3D2A)],
      art: ArtKind.history),
  FeatureInfo('Agent', [Color(0xFF4A3BD6), Color(0xFF1B1466)],
      art: ArtKind.agent),
];

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.feature,
    required this.onTap,
    this.height = 62,
  });
  final FeatureInfo feature;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: hubCard(
          radius: 16,
          colors: feature.colors,
          border: Color.lerp(feature.colors[0], Colors.white, .35)!,
          glow: feature.colors[0].withValues(alpha: .35),
        ),
        child: Row(
          children: [
            if (feature.art != null)
              Art(feature.art!, size: height * .52)
            else
              Icon(feature.icon, size: height * .5, color: AppColors.goldSoft),
            const SizedBox(width: 5),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  feature.name.toUpperCase().replaceFirst(' ', '\n'),
                  style: AppText.title.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FeaturesRow extends StatelessWidget {
  const FeaturesRow({super.key, required this.onTap, required this.onAll});
  final Tap onTap;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < mainFeatures.length; i++) ...[
              if (i > 0) const SizedBox(width: 9),
              Expanded(
                child: FeatureCard(
                  feature: mainFeatures[i],
                  onTap: () => onTap(mainFeatures[i].name),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 9),
        Pressable(
          onTap: onAll,
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              gradient: const LinearGradient(
                  colors: [AppColors.royal, AppColors.royalDeep]),
              border: Border.all(color: const Color(0xFF8FA8FF), width: 1.2),
              boxShadow: const [
                BoxShadow(color: Color(0x663A66F5), blurRadius: 14),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.grid_view_rounded,
                    color: Colors.white, size: 19),
                const SizedBox(width: 8),
                Text('ALL FEATURES',
                    style: AppText.title.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Colors.white)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Bottom navigation ─────────────────────────

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const items = [
    (ArtKind.home, 'Home'),
    (ArtKind.dicePair, 'Games'),
    (ArtKind.trophy, 'Tournament'),
    (ArtKind.avatar, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: const EdgeInsets.all(5),
      decoration: hubCard(radius: 26, border: const Color(0xFF3A4BA8)),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(21),
                    gradient: i == index
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x66EBCB7A), Color(0x22B8862B)],
                          )
                        : null,
                    border: Border.all(
                      color: i == index
                          ? AppColors.goldSoft
                          : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        scale: i == index ? 1.1 : 1,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: Art(items[i].$1, size: 30),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].$2,
                        style: AppText.title.copyWith(
                          fontSize: 12.5,
                          color: i == index
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
    );
  }
}
