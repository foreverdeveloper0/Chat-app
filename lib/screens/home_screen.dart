import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/icons.dart';
import '../theme/app_colors.dart';
import '../widgets/game_setup_sheet.dart';
import '../widgets/home_sections.dart';
import '../widgets/update_ui.dart';

/// Everything is laid out on a 390pt-wide design canvas and scaled to the
/// device width, so the page looks identical on every phone.
const double _designWidth = 390;
const double _maxPhoneWidth = 500;

const _pageBackground = BoxDecoration(
  gradient: RadialGradient(
    center: Alignment(0, -.55),
    radius: 1.25,
    colors: [Color(0xFF15226A), AppColors.bgTop, AppColors.bgBottom],
    stops: [0, .45, 1],
  ),
);

void showComingSoon(BuildContext context, String label) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
        backgroundColor: AppColors.cardTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text('$label — coming soon',
            style: AppText.title.copyWith(fontSize: 15)),
      ),
    );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) autoCheckForUpdate(context);
    });
  }

  void _onTap(String label) {
    if (label == 'Settings') {
      showSettingsSheet(context);
    } else {
      showComingSoon(context, label);
    }
  }

  void _onGame(GameInfo game) {
    if (game.name == 'LUDO') {
      showLudoModes(context);
    } else {
      showComingSoon(context, game.name[0] + game.name.substring(1).toLowerCase());
    }
  }

  void _openFeatures() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FeaturesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: DecoratedBox(
        decoration: _pageBackground,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxPhoneWidth),
              child: LayoutBuilder(
                builder: (context, box) {
                  final scale = box.maxWidth / _designWidth;
                  const navHeight = 74.0 + 16;
                  final bodyHeight = box.maxHeight / scale - navHeight;
                  return Column(
                    children: [
                      Expanded(
                        child: _tab == 0
                            ? SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: _Scaled(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minHeight: math.max(0, bodyHeight)),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          10, 10, 10, 8),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          TopBar(onTap: _onTap),
                                          const SizedBox(height: 8),
                                          const BrandHeader(),
                                          const SizedBox(height: 10),
                                          HeroCard(
                                              onPlay: () =>
                                                  showLudoModes(context)),
                                          const SizedBox(height: 14),
                                          const SectionTitle(
                                              icon:
                                                  Icons.sports_esports_rounded,
                                              label: 'OUR GAMES'),
                                          const SizedBox(height: 10),
                                          GamesGrid(
                                            onGame: _onGame,
                                            onMore: () => showComingSoon(
                                                context, 'More games'),
                                          ),
                                          const SizedBox(height: 14),
                                          const SectionTitle(
                                              icon: Icons.bolt_rounded,
                                              label: 'FEATURES'),
                                          const SizedBox(height: 10),
                                          FeaturesRow(
                                              onTap: _onTap,
                                              onAll: _openFeatures),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : _Placeholder(BottomNav.items[_tab].$2),
                      ),
                      _Scaled(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                          child: BottomNav(
                            index: _tab,
                            onChanged: (i) => setState(() => _tab = i),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Scaled extends StatelessWidget {
  const _Scaled({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.fitWidth,
        child: SizedBox(width: _designWidth, child: child),
      );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppText.title.copyWith(fontSize: 30)),
            const SizedBox(height: 6),
            Text('Coming soon',
                style: AppText.title
                    .copyWith(fontSize: 16, color: AppColors.goldSoft)),
          ],
        ),
      );
}

// ───────────────────────── Ludo modes ─────────────────────────

/// How to play Ludo: the two finished modes open a table, the online ones
/// are announced as coming soon.
Future<void> showLudoModes(BuildContext context) {
  const modes = [
    (ArtKind.robot, 'Play vs Computer', 'You against 1 to 3 bots', true),
    (ArtKind.dicePair, 'Pass & Play', '2 to 4 players on this phone', true),
    (ArtKind.globe, 'Play Online', 'Match with real players', false),
    (ArtKind.pawnPair, 'Play with Friends', 'Private room with a code', false),
  ];
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF131C4A), AppColors.bgBottom],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: AppColors.goldTrim, width: 1.6)),
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
            const SizedBox(height: 12),
            Text('Ludo', style: AppText.title.copyWith(fontSize: 24)),
            const SizedBox(height: 2),
            Text('Choose how to play',
                style: AppText.title
                    .copyWith(fontSize: 13.5, color: AppColors.goldSoft)),
            const SizedBox(height: 14),
            for (final (art, title, sub, ready) in modes)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Pressable(
                  onTap: () {
                    Navigator.pop(sheet);
                    if (ready) {
                      showGameSetup(context,
                          vsComputer: title == 'Play vs Computer');
                    } else {
                      showComingSoon(context, title);
                    }
                  },
                  child: Container(
                    height: 66,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: hubCard(
                      border:
                          ready ? AppColors.goldTrim : AppColors.cardBorder,
                    ),
                    child: Row(
                      children: [
                        Art(art, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style:
                                      AppText.title.copyWith(fontSize: 17)),
                              const SizedBox(height: 3),
                              Text(sub,
                                  style: AppText.title.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: const Color(0xFF9EA9DC))),
                            ],
                          ),
                        ),
                        if (ready)
                          const Icon(Icons.play_circle_fill_rounded,
                              color: AppColors.goldSoft, size: 30)
                        else
                          Text('SOON',
                              style: AppText.title.copyWith(
                                  fontSize: 11,
                                  letterSpacing: 1,
                                  color: const Color(0xFF9EA9DC))),
                      ],
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

// ───────────────────────── All features ─────────────────────────

/// Every feature in one place; the hub only shows the first three.
class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final all = [...mainFeatures, ...moreFeatures];
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: DecoratedBox(
        decoration: _pageBackground,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxPhoneWidth),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        Pressable(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: hubCard(radius: 22),
                            child: const Icon(Icons.arrow_back_rounded,
                                color: AppColors.cream),
                          ),
                        ),
                        Expanded(
                          child: Text('All features',
                              textAlign: TextAlign.center,
                              style: AppText.title.copyWith(fontSize: 22)),
                        ),
                        const SizedBox(width: 44),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      padding: const EdgeInsets.all(12),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.3,
                      children: [
                        for (final f in all)
                          FeatureCard(
                            feature: f,
                            height: 72,
                            onTap: () => showComingSoon(context, f.name),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
