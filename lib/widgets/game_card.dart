import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Raised navy card with a soft border, top sheen and a springy press effect.
class GameCard extends StatefulWidget {
  const GameCard({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    return Semantics(
      button: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? .96 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: Container(
            width: widget.width,
            height: widget.height,
            padding: widget.padding,
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -.3),
                colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.cardTop, AppColors.cardBottom],
              ),
              border: Border.all(color: AppColors.cardBorder, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x59060720),
                  blurRadius: 14,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Short mint underline used beneath card titles.
class MintBar extends StatelessWidget {
  const MintBar({super.key, this.width = 40});
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 3,
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}
