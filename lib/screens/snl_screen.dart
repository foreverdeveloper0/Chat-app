import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/snl_art.dart';
import '../game/snl_controller.dart';
import '../game/dice_game.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../theme/board_assets.dart';
import '../widgets/game_hud.dart';
import 'game_screen.dart' show PlayerPanel;

/// A Snakes & Ladders match: same table, docks and dice as Ludo.
class SnlScreen extends StatefulWidget {
  const SnlScreen({
    super.key,
    required this.seats,
    required this.bots,
    required this.names,
    this.entry = 1000,
    this.roomId = '000000',
  });

  final List<int> seats;
  final Set<int> bots;
  final Map<int, String> names;
  final int entry;
  final String roomId;

  /// The controller of the match on screen, for widget tests.
  @visibleForTesting
  static SnlController? debugController;

  @override
  State<SnlScreen> createState() => _SnlScreenState();
}

class _SnlScreenState extends State<SnlScreen> with TickerProviderStateMixin {
  late SnlController _game;
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650))
    ..repeat(reverse: true);
  late final _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
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
    _game = SnlController(
      seats: widget.seats,
      bots: widget.bots,
      turnSeconds: 20,
      onSfx: Sounds.play,
    );
    SnlScreen.debugController = _game;
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
    setState(_newGame);
    old.dispose();
  }

  @override
  void dispose() {
    for (final t in _bubbleTimers.values) {
      t.cancel();
    }
    _game.dispose();
    _pulse.dispose();
    _intro.dispose();
    _banner.dispose();
    super.dispose();
  }

  void _say(int player, String text) {
    _bubbleTimers[player]?.cancel();
    setState(() => _bubbles[player] = text);
    _bubbleTimers[player] = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _bubbles.remove(player));
    });
  }

  int get _speaker => widget.bots.isEmpty
      ? _game.current
      : widget.seats.firstWhere((p) => !widget.bots.contains(p));

  Future<void> _openChat() async {
    final text = await showChatSheet(context);
    if (text == null) return;
    Sounds.play(Sfx.chat);
    _say(_speaker, text);
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
            child:
                const Text('Leave', style: TextStyle(color: AppColors.goldSoft)),
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
                      math.min(box.maxWidth, 520.0) - 16, box.maxHeight - 350);
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
                          ScaleTransition(
                            scale: CurvedAnimation(
                                parent: _intro, curve: Curves.easeOutBack),
                            child: _SnlBoard(size: board, game: _game),
                          ),
                          const SizedBox(height: 8),
                          _panelRow(board, 3, 2),
                          const Spacer(),
                          GameDock(
                            micOn: _mic,
                            onMic: () => setState(() => _mic = !_mic),
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
            onProfile: () {},
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

/// The board with every player's pawn on its square. A pawn that lands on
/// a ladder or a snake rides along it.
class _SnlBoard extends StatelessWidget {
  const _SnlBoard({required this.size, required this.game});
  final double size;
  final SnlController game;

  @override
  Widget build(BuildContext context) {
    final rim = size * snlRim;
    final cell = (size - rim * 2) / 10;
    final pw = cell * .62, ph = pw / pawnAspect;
    Offset foot(Offset cells) =>
        Offset(rim + cells.dx * cell, rim + cells.dy * cell + cell * .3);

    // Pawns sharing a square stand side by side.
    final players = [
      for (final p in game.seats)
        if (!game.left.contains(p)) p,
    ];
    Offset spot(int p) {
      final here = [
        for (final q in players)
          if (game.position[q] == game.position[p]) q,
      ];
      final i = here.indexOf(p), n = here.length;
      return snlCentre(game.position[p]!) +
          Offset((i - (n - 1) / 2) * (n > 2 ? .22 : .3), 0);
    }

    Widget pawn(int p) => Image.asset(pawnAssets[p],
        fit: BoxFit.fill, filterQuality: FilterQuality.medium);
    final slide = game.slide;

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
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: SnlBoardPainter()),
            ),
          ),
          for (final p in players)
            if (slide?.player != p)
              AnimatedPositioned(
                key: ValueKey('snl-pawn-$p'),
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOut,
                left: foot(spot(p)).dx - pw / 2,
                top: foot(spot(p)).dy - ph * .95,
                width: pw,
                height: ph,
                child: _Hopper(square: game.position[p]!, child: pawn(p)),
              ),
          if (slide != null)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('ride-${slide.player}-${slide.from}'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeInOut,
                builder: (_, t, _) {
                  final path =
                      snlRide(slide.from, slide.to, snake: slide.snake);
                  final f = t * (path.length - 1);
                  final i = f.floor().clamp(0, path.length - 2);
                  final at =
                      foot(Offset.lerp(path[i], path[i + 1], f - i)!);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: at.dx - pw / 2,
                        top: at.dy - ph * .95,
                        width: pw,
                        height: ph,
                        // A snake ride wobbles; a climb stays upright.
                        child: Transform.rotate(
                          angle: slide.snake ? math.sin(t * 14) * .25 : 0,
                          child: pawn(slide.player),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Makes its child hop whenever [square] changes.
class _Hopper extends StatefulWidget {
  const _Hopper({required this.square, required this.child});
  final int square;
  final Widget child;

  @override
  State<_Hopper> createState() => _HopperState();
}

class _HopperState extends State<_Hopper> with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void didUpdateWidget(_Hopper old) {
    super.didUpdateWidget(old);
    if (widget.square != old.square) _hop.forward(from: 0);
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _hop,
      child: widget.child,
      builder: (_, child) {
        final h = math.sin(_hop.value * math.pi);
        return FractionalTranslation(
          translation: Offset(0, -h * .3),
          child: Transform.scale(scale: 1 + h * .12, child: child),
        );
      },
    );
  }
}
