import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../art/icons.dart';
import '../art/pieces.dart';
import '../game/catalog.dart';
import '../theme/app_colors.dart';

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
}) => BoxDecoration(
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
      color: Color(0x80020310),
      blurRadius: 12,
      offset: Offset(0, 6),
    ),
  ],
);

// ───────────────────────── Top bar ─────────────────────────

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.onTap});
  final Tap onTap;

  @override
  Widget build(BuildContext context) {
    final num = AppText.title.copyWith(fontSize: 15);
    Widget pill(ArtKind art, String value, double size) => Container(
      height: 30,
      padding: const EdgeInsets.only(left: 3, right: 9),
      decoration: BoxDecoration(
        color: AppColors.cardInset,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Art(art, size: size),
          const SizedBox(width: 5),
          Text(value, style: num),
        ],
      ),
    );
    Widget round(IconData icon, String label, {bool dot = false}) => Pressable(
      onTap: () => onTap(label),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cardInset,
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Icon(icon, color: AppColors.goldSoft, size: 22),
            ),
            if (dot)
              Positioned(
                top: 0,
                right: 1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF3B3B),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    // One gold-edged bar: you on the left, money, then bell and settings.
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      decoration: hubCard(radius: 27, border: AppColors.goldTrim),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onTap: () => onTap('Profile'),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(1.6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _gold,
                          ),
                          child: const Art(ArtKind.avatar, size: 38),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2EDB6A),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.cardBorder),
          const SizedBox(width: 7),
          pill(ArtKind.coin, '1,250', 24),
          const SizedBox(width: 5),
          pill(ArtKind.gem, '80', 20),
          const SizedBox(width: 4),
          round(Icons.notifications_rounded, 'Notifications', dot: true),
          round(Icons.settings_rounded, 'Settings'),
        ],
      ),
    );
  }
}

// ───────────────────────── Brand ─────────────────────────

/// Gold "ELITE PLAY BD" plaque between two laurel branches.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CustomPaint(
            size: Size(22, 40),
            painter: LaurelPainter(color: AppColors.goldTrim),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: _gold,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                    fontSize: 21,
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
            size: Size(22, 40),
            painter: LaurelPainter(mirror: true, color: AppColors.goldTrim),
          ),
        ],
      ),
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
              colors: [Color(0x003A66F5), Color(0xFF3A66F5)],
            ),
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
              Text(
                label,
                style: AppText.title.copyWith(
                  fontSize: 14.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
                  colors: [Color(0xFF3A66F5), Color(0x003A66F5)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Games ─────────────────────────

/// A game's logo on a dark glass tile; unfinished games carry a SOON tag.
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
    return Pressable(
      key: ValueKey('game-${game.key}'),
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
                : const [Color(0xFF5A6BD6), Color(0xFF1B2666)],
          ),
          boxShadow: [
            BoxShadow(
              color: game.ready
                  ? const Color(0x66EBCB7A)
                  : const Color(0x553A66F5),
              blurRadius: 12,
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.7),
            gradient: const RadialGradient(
              center: Alignment(0, -.3),
              radius: 1.1,
              colors: [Color(0xFF2A1F7A), Color(0xFF0B1235)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  game.logo,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              if (!game.ready)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE6050818),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.goldTrim, width: .8),
                    ),
                    child: Text(
                      'SOON',
                      style: AppText.title.copyWith(
                        fontSize: 8.5,
                        letterSpacing: .8,
                        color: AppColors.goldSoft,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three large tiles over four smaller ones.
class GamesGrid extends StatelessWidget {
  const GamesGrid({super.key, required this.onGame});
  final ValueChanged<GameInfo> onGame;

  @override
  Widget build(BuildContext context) {
    Widget row(Iterable<GameInfo> items, double height) => Row(
      children: [
        for (final (i, g) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 9),
          Expanded(
            child: GameTile(game: g, height: height, onTap: () => onGame(g)),
          ),
        ],
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(games.take(3), 98),
        const SizedBox(height: 9),
        row(games.skip(3), 76),
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
  FeatureInfo('Daily Bonus', [
    Color(0xFF4A3BD6),
    Color(0xFF1B1466),
  ], art: ArtKind.calendar),
  FeatureInfo('Coin Earn', [
    Color(0xFF1E9E63),
    Color(0xFF0B3D2A),
  ], art: ArtKind.coinStack),
  FeatureInfo('Tournament', [
    Color(0xFF7A3BD6),
    Color(0xFF2A1466),
  ], art: ArtKind.trophy),
];

/// Everything else lives behind the "All features" button.
const moreFeatures = [
  FeatureInfo('Refer & Earn', [
    Color(0xFF2B6FD6),
    Color(0xFF0B2A66),
  ], art: ArtKind.friends),
  FeatureInfo('Leaderboard', [
    Color(0xFFB8862B),
    Color(0xFF4A3008),
  ], icon: Icons.leaderboard_rounded),
  FeatureInfo('Live Support', [
    Color(0xFF2B8BD6),
    Color(0xFF0B2A52),
  ], icon: Icons.headset_mic_rounded),
  FeatureInfo('Friends', [
    Color(0xFF3A66F5),
    Color(0xFF14246E),
  ], art: ArtKind.friends),
  FeatureInfo('History', [
    Color(0xFF1E9E63),
    Color(0xFF0B3D2A),
  ], art: ArtKind.history),
  FeatureInfo('Agent', [
    Color(0xFF4A3BD6),
    Color(0xFF1B1466),
  ], art: ArtKind.agent),
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
                    height: 1.15,
                  ),
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
                colors: [AppColors.royal, AppColors.royalDeep],
              ),
              border: Border.all(color: const Color(0xFF8FA8FF), width: 1.2),
              boxShadow: const [
                BoxShadow(color: Color(0x663A66F5), blurRadius: 14),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.grid_view_rounded,
                  color: Colors.white,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Text(
                  'ALL FEATURES',
                  style: AppText.title.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 22,
                ),
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

  /// The middle one, Games, is the home page and stands proud of the bar.
  static const items = [
    (Icons.bolt_rounded, 'Quick Match'),
    (Icons.account_balance_wallet_rounded, 'Wallet'),
    (Icons.sports_esports_rounded, 'Games'),
    (Icons.history_rounded, 'History'),
    (Icons.person_rounded, 'Profile'),
  ];
  static const home = 2;

  @override
  Widget build(BuildContext context) {
    const bar = 66.0, lift = 20.0;
    Widget side(int i) {
      final on = i == index;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: on ? 1.12 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(
                  items[i].$1,
                  size: 30,
                  color: on ? AppColors.goldSoft : const Color(0xFFFFC93A),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    items[i].$2,
                    maxLines: 1,
                    softWrap: false,
                    style: AppText.title.copyWith(
                      fontSize: 12.5,
                      color: on ? AppColors.goldSoft : AppColors.cream,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget divider() => Container(
      width: 1,
      height: 38,
      color: AppColors.cardBorder.withValues(alpha: .7),
    );
    final on = index == home;
    return SizedBox(
      height: bar + lift,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bar,
            child: Container(
              decoration: hubCard(radius: 30, border: AppColors.goldTrim),
              child: Row(
                children: [
                  side(0),
                  divider(),
                  side(1),
                  const SizedBox(width: 92),
                  side(3),
                  divider(),
                  side(4),
                ],
              ),
            ),
          ),
          // Games: raised, gold-ringed.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(home),
                child: Container(
                  width: 92,
                  height: bar + lift - 2,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: _gold,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.goldTrim.withValues(
                          alpha: on ? .55 : .25,
                        ),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF5A2BC0), Color(0xFF2A1070)],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[home].$1,
                          size: 38,
                          color: AppColors.goldSoft,
                        ),
                        Text(
                          items[home].$2,
                          style: AppText.title.copyWith(
                            fontSize: 14,
                            color: AppColors.goldSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The round Support button that floats over the home page.
class SupportFab extends StatelessWidget {
  const SupportFab({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _gold,
                boxShadow: const [
                  BoxShadow(color: Color(0x88FFC93A), blurRadius: 14),
                  BoxShadow(color: Color(0x99000000), blurRadius: 8),
                ],
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF3A1F8A), Color(0xFF150A3A)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.headset_mic_rounded,
                      size: 24,
                      color: AppColors.goldSoft,
                    ),
                    Text(
                      'Support',
                      style: AppText.title.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF3B3B),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
