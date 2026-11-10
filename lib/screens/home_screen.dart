import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/home_sections.dart';

/// Everything is laid out on a 390pt-wide design canvas and scaled to the
/// device width, so the page looks identical on every phone.
const double _designWidth = 390;
const double _maxPhoneWidth = 500;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1200),
          backgroundColor: AppColors.cardTop,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Text(
            '$label — coming soon',
            style: AppText.title.copyWith(fontSize: 15),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxPhoneWidth),
              child: LayoutBuilder(
                builder: (context, box) {
                  final scale = box.maxWidth / _designWidth;
                  const navHeight = 78.0 + 16;
                  final bodyHeight = box.maxHeight / scale - navHeight;
                  return Column(
                    children: [
                      Expanded(
                        child: _tab == 0
                            ? SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: _Scaled(
                                  child: _HomeBody(
                                    minHeight: math.max(0, bodyHeight),
                                    onTap: _comingSoon,
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

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.minHeight, required this.onTap});
  final double minHeight;
  final Tap onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // Glow behind the board.
          const Positioned(
            left: 60,
            right: -60,
            top: 130,
            height: 330,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x8C3B43B8), Color(0x003B43B8)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 10, 9, 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TopBar(onTap: onTap),
                const SizedBox(height: 12),
                const LogoHeader(),
                const SizedBox(height: 8),
                HeroSection(onTap: onTap),
                const SizedBox(height: 12),
                ModeGrid(onTap: onTap),
                const SizedBox(height: 10),
                TournamentBanner(onTap: onTap),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
            Text(
              'Coming soon',
              style: AppText.title
                  .copyWith(fontSize: 16, color: AppColors.mint),
            ),
          ],
        ),
      );
}
