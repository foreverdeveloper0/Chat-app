import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/pieces.dart';
import '../game/coins.dart';
import '../game/ludo_controller.dart';
import '../game/ludo_rules.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../theme/board_assets.dart';
import '../widgets/game_hud.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.title,
    required this.seats,
    required this.bots,
    required this.names,
    this.entry = 1000,
    this.roomId = '000000',
  });

  final String title;
  final List<int> seats;
  final Set<int> bots;
  final Map<int, String> names;

  /// Coins each player puts in; the winner takes entry x players.
  final int entry;
  final String roomId;

  /// The controller of the match on screen, for widget tests.
  @visibleForTesting
  static LudoController? debugController;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const _turnSeconds = 20;

  late LudoController _game;
  late final _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650))
    ..repeat(reverse: true);
  late final _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
  late final _banner = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1700));

  final _bubbles = <int, String>{};
  final _bubbleTimers = <int, Timer>{};
  bool _mic = false;

  int get _prize => widget.entry * widget.seats.length;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    _game = LudoController(
      seats: widget.seats,
      bots: widget.bots,
      turnSeconds: _turnSeconds,
      onSfx: Sounds.play,
      onCapture: _onCapture,
    );
    GameScreen.debugController = _game;
    _banner.value = 0;
    _intro.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      Sounds.play(Sfx.start);
      _banner.forward(from: 0).whenComplete(() {
        if (mounted) _game.start();
      });
    });
  }

  void _restart() {
    final old = _game;
    for (final t in _bubbleTimers.values) {
      t.cancel();
    }
    _bubbles.clear();
    setState(_newGame);
    old.dispose();
  }

  @override
  void dispose() {
    for (final t in _bubbleTimers.values) {
      t.cancel();
    }
    _game.dispose();
    _spin.dispose();
    _pulse.dispose();
    _intro.dispose();
    _banner.dispose();
    super.dispose();
  }

  // ── Chat ──

  void _say(int player, String text) {
    if (!mounted) return;
    _bubbleTimers[player]?.cancel();
    setState(() => _bubbles[player] = text);
    _bubbleTimers[player] = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _bubbles.remove(player));
    });
  }

  /// Bots react when they capture or get captured.
  void _onCapture(int by, int victim) {
    final r = math.Random();
    if (widget.bots.contains(by)) _say(by, const ['😎', '😂', '🔥'][r.nextInt(3)]);
    if (widget.bots.contains(victim)) {
      _say(victim, const ['😡', '😭', '😱'][r.nextInt(3)]);
    }
  }

  /// Who is "speaking" when the chat button is used on this phone.
  int get _speaker => widget.bots.isEmpty
      ? _game.current
      : widget.seats.firstWhere((p) => !widget.bots.contains(p));

  Future<void> _openChat() async {
    final text = await showChatSheet(context);
    if (text == null) return;
    Sounds.play(Sfx.chat);
    _say(_speaker, text);
  }

  void _toggleMic() {
    setState(() => _mic = !_mic);
    Sounds.play(Sfx.tap);
    if (_mic) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
          backgroundColor: AppColors.cardTop,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Text('Mic on — voice is heard in online matches',
              style: AppText.title.copyWith(fontSize: 14)),
        ));
    }
  }

  void _openProfile(int player) {
    Sounds.play(Sfx.tap);
    showPlayerProfile(
      context,
      player: player,
      name: widget.names[player] ?? 'Player',
      isYou: widget.names[player] == 'You',
      game: _game,
      entry: widget.entry,
      prize: _prize,
      roomId: widget.roomId,
    );
  }

  Future<void> _confirmLeave() async {
    if (_game.phase == Phase.gameOver) return Navigator.of(context).pop();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Leave game?', style: AppText.title.copyWith(fontSize: 22)),
        content: Text('Your current match will be lost.',
            style: AppText.title.copyWith(
                fontSize: 15, fontWeight: FontWeight.w400, height: 1.3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay', style: TextStyle(color: AppColors.cream)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: AppColors.mint)),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: LudoBackdrop(
          child: SafeArea(
            child: ListenableBuilder(
              listenable: _game,
              builder: (context, _) => LayoutBuilder(
                builder: (context, box) {
                  final board = math.min(
                      math.min(box.maxWidth, 520.0) - 16, box.maxHeight - 342);
                  return Stack(
                    children: [
                      Column(
                        children: [
                          GameHeader(
                            prize: _prize,
                            entry: widget.entry,
                            roomId: widget.roomId,
                            onBack: _confirmLeave,
                          ),
                          const Spacer(),
                          _panelRow(board, 0, 1),
                          const SizedBox(height: 8),
                          _BoardIntro(
                            intro: _intro,
                            child: _Board(
                              size: board,
                              game: _game,
                              spin: _spin,
                              pulse: _pulse,
                              intro: _intro,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _panelRow(board, 3, 2),
                          const Spacer(),
                          GameDock(
                            micOn: _mic,
                            onMic: _toggleMic,
                            onChat: _openChat,
                            onQuick: (e) {
                              Sounds.play(Sfx.chat);
                              _say(_speaker, e);
                            },
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: StartBanner(animation: _banner),
                        ),
                      ),
                      if (_game.phase == Phase.gameOver)
                        Positioned.fill(
                          child: ResultOverlay(
                            order: _game.finished,
                            left: _game.left,
                            names: widget.names,
                            prize: _prize,
                            onAgain: _restart,
                            onHome: () => Navigator.of(context).pop(),
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

  Widget _panelRow(double width, int left, int right) {
    Widget panel(int p, bool mirrored) => widget.seats.contains(p)
        ? PlayerPanel(
            player: p,
            name: widget.names[p] ?? 'Player',
            isYou: widget.names[p] == 'You',
            game: _game,
            pulse: _pulse,
            mirrored: mirrored,
            bubble: _bubbles[p],
            onProfile: () => _openProfile(p),
          )
        : const SizedBox(width: PlayerPanel.width, height: PlayerPanel.height);
    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [panel(left, false), panel(right, true)],
      ),
    );
  }
}

/// The board drops in with a spin and a small overshoot.
class _BoardIntro extends StatelessWidget {
  const _BoardIntro({required this.intro, required this.child});
  final Animation<double> intro;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
        parent: intro, curve: const Interval(0, .5, curve: Curves.easeOutBack));
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (_, child) => Opacity(
        opacity: (intro.value * 4).clamp(0, 1),
        child: Transform.rotate(
          angle: (1 - curve.value) * -.6,
          child: Transform.scale(scale: .55 + .45 * curve.value, child: child),
        ),
      ),
    );
  }
}

// ───────────────────────── Board + tokens ─────────────────────────

/// Where token [i] of [n] sharing one cell sits (offset in cells) and how
/// big it is, so any number of pawns stays inside the square.
(Offset, double) _stackSlot(int i, int n) {
  if (n == 1) return (Offset.zero, .92);
  final cols = n <= 4 ? 2 : (n <= 9 ? 3 : 4);
  final rows = (n / cols).ceil();
  final scale = switch (cols) { 2 => rows == 1 ? .7 : .54, 3 => .4, _ => .31 };
  final dx = (i % cols - (cols - 1) / 2) * (cols == 2 ? .44 : .92 / cols);
  final dy = rows == 1
      ? 0.0
      : (i ~/ cols - (rows - 1) / 2) * math.min(.36, .84 / rows) + .04;
  return (Offset(dx, dy), scale);
}

class _Board extends StatelessWidget {
  const _Board({
    required this.size,
    required this.game,
    required this.spin,
    required this.pulse,
    required this.intro,
  });
  final double size;
  final LudoController game;
  final Animation<double> spin;
  final Animation<double> pulse;
  final Animation<double> intro;

  @override
  Widget build(BuildContext context) {
    final rim = size * gridInset;
    final cell = size * gridSize / 15;
    final all = [
      for (final p in game.seats)
        if (!game.left.contains(p)) ...game.tokens[p],
    ];

    final groups = <Offset, List<Token>>{};
    for (final t in all) {
      if (t.progress >= 0 && !t.isHome) {
        final pos = LudoRules.position(t.player, t.index, t.progress);
        groups.putIfAbsent(pos, () => []).add(t);
      }
    }

    final placed = <(Token, Offset, double)>[];
    for (final t in all) {
      var pos = LudoRules.position(t.player, t.index, t.progress);
      var scale = t.inYard ? 1.12 : (t.isHome ? .68 : .92);
      final group = groups[pos];
      if (group != null) {
        final (offset, s) = _stackSlot(group.indexOf(t), group.length);
        pos += offset;
        scale = s;
      }
      placed.add((t, pos, scale));
    }
    // Paint back-to-front; movable pawns always end up on top.
    placed.sort((a, b) {
      final ma = game.movable.contains(a.$1), mb = game.movable.contains(b.$1);
      if (ma != mb) return ma ? 1 : -1;
      return a.$2.dy.compareTo(b.$2.dy);
    });

    // One spinning ring per square that holds a movable pawn. It lies on the
    // board around the pawn's base, so it is centred on the base and is a
    // touch wider than it.
    final rings = <Offset, (Offset, double, Color)>{};
    for (final (t, pos, scale) in placed) {
      if (!game.movable.contains(t)) continue;
      final base = LudoRules.position(t.player, t.index, t.progress);
      final crowded = (groups[base]?.length ?? 1) > 1;
      rings.putIfAbsent(
        base,
        () => crowded
            ? (
                Offset(rim + base.dx * cell, rim + (base.dy + .12) * cell),
                cell * .6,
                playerDeep[t.player],
              )
            : (
                Offset(rim + pos.dx * cell,
                    rim + (pos.dy + .16 - .077 * scale) * cell),
                cell * .86 * scale * .64,
                playerDeep[t.player],
              ),
      );
    }

    final bw = cell * 1.6, bh = cell * 2.1;
    final choosing = game.phase == Phase.choosing && game.humanTurn;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .04),
        boxShadow: const [
          BoxShadow(color: Color(0x88000010), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(boardAsset,
                fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _YardPadsPainter(rim: rim, cell: cell),
              ),
            ),
          ),
          // The yard of whoever is on turn breathes with a soft light.
          if (game.phase != Phase.gameOver)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: rim + LudoRules.yardOrigins[game.current].$1 * cell,
              top: rim + LudoRules.yardOrigins[game.current].$2 * cell,
              width: cell * 6,
              height: cell * 6,
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: Tween(begin: .15, end: 1.0).animate(
                      CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.white, width: cell * .16),
                      gradient: const RadialGradient(
                        radius: .75,
                        colors: [Color(0x00FFFFFF), Color(0x66FFFFFF)],
                        stops: [.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          for (final p in game.seats)
            if (game.left.contains(p) || game.rankOf(p) > 0)
              Positioned(
                left: rim + LudoRules.yardOrigins[p].$1 * cell,
                top: rim + LudoRules.yardOrigins[p].$2 * cell,
                width: cell * 6,
                height: cell * 6,
                child: YardBadge(
                  cell: cell,
                  rank: game.rankOf(p),
                  left: game.left.contains(p),
                ),
              ),
          if (rings.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RingsPainter(
                      rings.values.toList(), cell, spin),
                ),
              ),
            ),
          for (final (t, pos, scale) in placed)
            AnimatedPositioned(
              key: ValueKey('token-${t.player * 4 + t.index}'),
              duration: Duration(milliseconds: t.inYard ? 480 : 150),
              curve: t.inYard ? Curves.easeInOutCubic : Curves.easeOut,
              left: rim + pos.dx * cell - bw / 2,
              top: rim + pos.dy * cell + cell * .16 - bh * .72,
              width: bw,
              height: bh,
              child: _TokenView(
                token: t,
                progress: t.progress,
                cell: cell,
                scale: scale,
                order: game.seats.indexOf(t.player) * 4 + t.index,
                intro: intro,
                movable: game.movable.contains(t),
                onTap: choosing && game.movable.contains(t)
                    ? () => game.move(t)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _TokenView extends StatefulWidget {
  const _TokenView({
    required this.token,
    required this.progress,
    required this.cell,
    required this.scale,
    required this.order,
    required this.intro,
    required this.movable,
    required this.onTap,
  });
  final Token token;
  final int progress;
  final double cell;
  final double scale;
  final int order;
  final Animation<double> intro;
  final bool movable;
  final VoidCallback? onTap;

  @override
  State<_TokenView> createState() => _TokenViewState();
}

class _TokenViewState extends State<_TokenView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 165),
  );

  @override
  void didUpdateWidget(_TokenView old) {
    super.didUpdateWidget(old);
    if (widget.progress != old.progress && widget.progress >= 0) {
      _hop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = AnimatedBuilder(
      animation: Listenable.merge(
          [_hop, widget.intro]),
      builder: (_, _) {
        final hop = math.sin(_hop.value * math.pi);
        // Pawns drop into the yards one after another once the board is in.
        final drop = ((widget.intro.value - .45) / .55 * 2.3 -
                widget.order * .08)
            .clamp(0.0, 1.0);
        final landed = Curves.easeOutBack.transform(drop);
        return LayoutBuilder(builder: (_, box) {
          final foot = Offset(box.maxWidth / 2, box.maxHeight * .72);
          final lift =
              hop * widget.cell * .5 + (1 - landed) * widget.cell * 2.2;
          final pw = widget.cell * .86 * widget.scale * (1 + hop * .12);
          final ph = pw / pawnAspect;
          return Opacity(
            opacity: (drop * 3).clamp(0, 1),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: foot.dx - pw * .52,
                  top: foot.dy - pw * .17,
                  width: pw * 1.08,
                  height: pw * .34,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(0, 0, 0, .3 - hop * .15),
                      borderRadius:
                          const BorderRadius.all(Radius.elliptical(40, 14)),
                    ),
                  ),
                ),
                Positioned(
                  left: foot.dx - pw / 2,
                  top: foot.dy - ph * .95 - lift,
                  width: pw,
                  height: ph,
                  child: Image.asset(
                    pawnAssets[widget.token.player],
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
    return GestureDetector(
      behavior: widget.onTap == null
          ? HitTestBehavior.translucent
          : HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: RepaintBoundary(child: view),
    );
  }
}

/// Dashed rings that spin (without resizing) under pawns that can move.
/// Each ring is flattened to the same viewing angle as the pawn artwork, so
/// it reads as lying on the board around the pawn's base.
class _RingsPainter extends CustomPainter {
  _RingsPainter(this.rings, this.cell, this.spin) : super(repaint: spin);
  final List<(Offset, double, Color)> rings;
  final double cell;
  final Animation<double> spin;

  /// Height / width of the pawn image's round base as drawn.
  static const tilt = .4;

  @override
  void paint(Canvas canvas, Size size) {
    const dashes = 10;
    const step = 2 * math.pi / dashes;
    final start = spin.value * 2 * math.pi;
    for (final (centre, radius, color) in rings) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(1, tilt);
      final rect = Rect.fromCircle(center: Offset.zero, radius: radius);
      canvas.drawCircle(Offset.zero, radius,
          Paint()..color = Colors.white.withValues(alpha: .4));
      final under = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = cell * .2
        ..color = Colors.white;
      final over = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = cell * .12
        ..color = color;
      for (final paint in [under, over]) {
        for (var i = 0; i < dashes; i++) {
          canvas.drawArc(rect, start + i * step, step * .52, false, paint);
        }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => true;
}

/// Soft coloured pads in each yard diamond marking where a pawn rests.
class _YardPadsPainter extends CustomPainter {
  const _YardPadsPainter({required this.rim, required this.cell});
  final double rim;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    for (var p = 0; p < 4; p++) {
      final o = LudoRules.yardOrigins[p];
      final origin = Offset(rim + o.$1 * cell, rim + o.$2 * cell);
      for (final slot in LudoRules.yardSlots) {
        final c = origin + slot * cell + Offset(0, cell * .06);
        final pad = Rect.fromCenter(
            center: c, width: cell * 1.25, height: cell * .78);
        canvas.drawOval(
          pad.shift(Offset(0, cell * .05)),
          Paint()..color = playerDeep[p].withValues(alpha: .22),
        );
        canvas.drawOval(
          pad,
          Paint()
            ..shader = RadialGradient(
              colors: [
                playerLight[p].withValues(alpha: .55),
                playerColors[p].withValues(alpha: .28),
              ],
            ).createShader(pad),
        );
        canvas.drawOval(
          pad,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .06
            ..color = playerColors[p].withValues(alpha: .75),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_YardPadsPainter old) =>
      old.cell != cell || old.rim != rim;
}

// ───────────────────────── Player panel ─────────────────────────

/// A compact player dock that sits at a corner of the board: picture and
/// dice tray side by side, the name under the picture and the lives under
/// the tray, inside a thin metal frame that turns gold on the player's turn.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.player,
    required this.name,
    required this.isYou,
    required this.game,
    required this.pulse,
    required this.mirrored,
    required this.bubble,
    required this.onProfile,
  });

  static const width = 126.0;
  static const height = 88.0;
  static const _slot = 56.0;

  final int player;
  final String name;
  final bool isYou;
  final LudoController game;
  final Animation<double> pulse;
  final bool mirrored;
  final String? bubble;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final over = game.phase == Phase.gameOver;
    final gone = game.left.contains(player);
    final rank = game.rankOf(player);
    final active = game.current == player && !over && !gone && rank == 0;
    final canRoll =
        active && game.phase == Phase.awaitingRoll && !game.isBot(player);
    final color = playerColors[player];
    final deep = playerDeep[player];
    final lives = game.lives[player] ?? 0;

    Widget plate({required Widget child, Gradient? gradient, Color? fill}) =>
        Container(
          width: _slot,
          height: 16,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7.5),
            gradient: gradient,
            color: fill,
            border: Border.all(color: const Color(0x55FFFFFF), width: .8),
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        );

    // Tapping the picture opens the player's profile.
    final who = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onProfile,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: _slot,
            height: 54,
            child: Center(
              child: PlayerAvatar(
                player: player,
                isBot: game.isBot(player),
                isYou: isYou,
                rank: rank,
                // The ring drains while a human is on the clock.
                timer: active && game.timerRunning
                    ? (game.turnSerial, game.turnSeconds)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 3),
          plate(
            gradient: LinearGradient(colors: [color, deep]),
            child: Text(
              shortName(name),
              maxLines: 1,
              style: AppText.title.copyWith(
                fontSize: 11.5,
                color: Colors.white,
                height: 1.1,
                shadows: const [Shadow(color: Color(0x88000000), blurRadius: 2)],
              ),
            ),
          ),
        ],
      ),
    );

    final Widget under;
    if (gone) {
      under = Text('LEFT',
          style: AppText.title.copyWith(
              fontSize: 9.5, letterSpacing: 1, color: const Color(0xFFFF8A80)));
    } else if (rank > 0) {
      under = Text('${ordinal(rank)} place',
          style: AppText.title.copyWith(fontSize: 9.5, color: rankColor(rank)));
    } else {
      under = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < LudoController.maxLives; i++)
            Icon(Icons.favorite_rounded,
                size: 9.2,
                color: i < lives
                    ? const Color(0xFFFF4D67)
                    : const Color(0xFF3A3F7A)),
        ],
      );
    }
    final play = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: _slot,
          height: 54,
          child: Center(
            child: DiceSocket(
              active: active,
              child: active
                  ? _Dice(
                      game: game, canRoll: canRoll, pulse: pulse, color: color)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 3),
        plate(fill: const Color(0xD90F1136), child: under),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canRoll
          ? () {
              Sounds.play(Sfx.tap);
              game.roll();
            }
          : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: gone ? .55 : 1,
        child: SizedBox(
          key: ValueKey('panel-$player'),
          width: width,
          height: height,
          // The dock is a cut-corner badge drawn by [_PanelPainter]; the
          // content sits in an unclipped layer so the dice can fly out.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PanelPainter(
                      color: color, deep: deep, mirrored: mirrored, lit: active),
                ),
              ),
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: mirrored ? [play, who] : [who, play],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: -34,
                height: 38,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: bubble == null
                        ? const SizedBox.shrink()
                        : ChatBubble(key: ValueKey(bubble), text: bubble!),
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

/// Paints a player dock as a cut-corner badge: two opposite corners are
/// sliced off, a metal frame follows the outline (gold on the player's
/// turn) and the seat colour sweeps in behind the picture.
class _PanelPainter extends CustomPainter {
  const _PanelPainter({
    required this.color,
    required this.deep,
    required this.mirrored,
    required this.lit,
  });
  final Color color;
  final Color deep;
  final bool mirrored;
  final bool lit;

  /// Outline with the top-inner and bottom-outer corners cut at 45 degrees.
  static Path outline(Size size, double inset) {
    final w = size.width - inset, h = size.height - inset;
    const cut = 20.0, r = 13.0;
    final l = inset, t = inset;
    return Path()
      ..moveTo(l + r, t)
      ..lineTo(w - cut, t)
      ..lineTo(w, t + cut)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(l + cut, h)
      ..lineTo(l, h - cut)
      ..lineTo(l, t + r)
      ..quadraticBezierTo(l, t, l + r, t)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final w = size.width, h = size.height;
    final shape = outline(size, 1.4);

    // Glow on the turn, plain drop shadow otherwise.
    canvas.drawPath(
      lit ? shape : shape.shift(const Offset(0, 4)),
      Paint()
        ..color = lit ? color.withValues(alpha: .85) : const Color(0x88060720)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lit ? 11 : 6),
    );

    canvas.save();
    canvas.clipPath(shape);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F3482), Color(0xFF12143F)],
        ).createShader(rect),
    );
    // Slanted colour band behind the picture.
    final band = Path()
      ..moveTo(0, 0)
      ..lineTo(w * .58, 0)
      ..lineTo(w * .42, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: lit ? .7 : .45),
            deep.withValues(alpha: lit ? .55 : .3),
          ],
        ).createShader(rect),
    );
    final edge = Paint()
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: lit ? .5 : .22);
    canvas.drawLine(Offset(w * .58, 0), Offset(w * .42, h), edge);
    canvas.drawLine(Offset(w * .64, 0), Offset(w * .48, h),
        edge..color = color.withValues(alpha: lit ? .7 : .35));
    // Glass sheen on the top half.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * .45),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
        ).createShader(Rect.fromLTWH(0, 0, w, h * .45)),
    );
    canvas.restore();

    // Metal frame: brushed steel at rest, gold on the turn.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: lit
              ? const [
                  Color(0xFFFFF3B8),
                  Color(0xFFE3B341),
                  Color(0xFFFFE28A),
                  Color(0xFF9C6B0E),
                ]
              : const [
                  Color(0xFF8E95DC),
                  Color(0xFF3A4090),
                  Color(0xFF6A71C0),
                  Color(0xFF262A66),
                ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.lit != lit || old.color != color || old.mirrored != mirrored;
}

/// The dice is tossed a little way up out of its socket, tumbles as a real
/// cube, drops back and lands with a squashy bounce and a burst ring.
class _Dice extends StatefulWidget {
  const _Dice({
    required this.game,
    required this.canRoll,
    required this.pulse,
    required this.color,
  });
  final LudoController game;
  final bool canRoll;
  final Animation<double> pulse;
  final Color color;

  @override
  State<_Dice> createState() => _DiceState();
}

class _DiceState extends State<_Dice> with SingleTickerProviderStateMixin {
  static const _airMs = LudoController.rollTicks * LudoController.rollTickMs;
  static const _totalMs = _airMs + LudoController.landMs;
  static const _air = _airMs / _totalMs; // share of the timeline spent airborne
  static const _height = 54.0;

  late final AnimationController _toss = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
    value: 1,
  );
  Phase? _lastPhase;

  @override
  void didUpdateWidget(_Dice old) {
    super.didUpdateWidget(old);
    final phase = widget.game.phase;
    if (phase == Phase.rolling && _lastPhase != Phase.rolling) {
      _toss.forward(from: 0);
    }
    _lastPhase = phase;
  }

  @override
  void dispose() {
    _toss.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = DiceSocket.diceSize;
    return AnimatedBuilder(
      animation: Listenable.merge([_toss, widget.pulse]),
      builder: (_, _) {
        final t = _toss.value;
        final flying = t < _air;
        final a = flying ? t / _air : 1.0; // 0..1 through the air
        final l = flying ? 0.0 : (t - _air) / (1 - _air); // 0..1 landing

        // Height: one arc, then a small rebound.
        final arc = 4 * a * (1 - a);
        final rebound = flying ? 0.0 : math.sin(l * math.pi) * (1 - l) * .22;
        final lift = (flying ? arc : rebound) * _height;

        // Tumble: spins fast at launch and eases onto the result face.
        final left = math.pow(1 - a, 1.6).toDouble();

        // Squash on impact, then settle.
        final squash =
            flying ? 0.0 : math.sin(l * math.pi * 2.5) * (1 - l) * .18;
        var scale = 1 + arc * .3;
        if (widget.canRoll) scale *= .95 + .1 * widget.pulse.value;

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Impact ring.
            if (!flying && l < 1)
              Transform.scale(
                scale: .7 + l * 1.3,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withValues(alpha: (1 - l) * .9),
                      width: 3 * (1 - l) + .5,
                    ),
                  ),
                ),
              ),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(0, -lift, 0, 1)
                ..scaleByDouble(
                    scale * (1 + squash), scale * (1 - squash), 1, 1),
              child: CustomPaint(
                size: const Size.square(size),
                painter: _DicePainter(
                  widget.game.dice,
                  rx: left * 4 * math.pi,
                  ry: left * 3 * math.pi,
                  rz: left * 1 * math.pi,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DicePainter extends CustomPainter {
  const _DicePainter(this.value, {this.rx = 0, this.ry = 0, this.rz = 0});
  final int value;
  final double rx, ry, rz;

  @override
  void paint(Canvas canvas, Size size) {
    if (rx == 0 && ry == 0 && rz == 0) {
      paintDice(canvas, Offset.zero & size, value);
    } else {
      paintDice3D(canvas, size.center(Offset(0, -size.height * .04)),
          size.width * .78, value, rx: rx, ry: ry, rz: rz);
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) =>
      old.value != value || old.rx != rx || old.ry != ry || old.rz != rz;
}
