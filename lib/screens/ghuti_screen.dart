import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../art/icons.dart';
import '../game/coins.dart';
import '../game/ghuti_game.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../widgets/game_hud.dart';

const _boardAsset = 'assets/images/ghuti/board.png';
const _boardAspect = 620 / 1148;
const _pieceAsset = ['assets/images/ghuti/red.png', 'assets/images/ghuti/black.png'];

/// A game of 16 Ghuti. Tap one of your pieces, then a glowing point.
class GhutiScreen extends StatefulWidget {
  const GhutiScreen({
    super.key,
    required this.bots,
    required this.names,
    this.entry = 1000,
    this.roomId = '000000',
  });

  final Set<int> bots;
  final Map<int, String> names;
  final int entry;
  final String roomId;

  /// The game on screen, for widget tests.
  @visibleForTesting
  static GhutiGame? debugGame;

  @override
  State<GhutiScreen> createState() => _GhutiScreenState();
}

class _GhutiScreenState extends State<GhutiScreen>
    with SingleTickerProviderStateMixin {
  late GhutiGame _game;
  Pt? _selected;
  Timer? _botTimer;

  /// Pieces just taken, fading out where they stood: point, owner, when.
  final _fading = <(Pt, int, DateTime)>[];

  /// Each piece's identity follows it around the board so it can slide.
  final _ids = <Pt, int>{};

  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800))
    ..repeat(reverse: true);

  int get _prize => widget.entry * 2;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    _botTimer?.cancel();
    _game = GhutiGame(bots: widget.bots);
    GhutiScreen.debugGame = _game;
    _ids
      ..clear()
      ..addAll({
        for (final (i, p) in _game.board.keys.indexed) p: i,
      });
    _selected = null;
    _fading.clear();
    Sounds.play(Sfx.start);
    _afterMove();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  bool get _over => _game.winner != null || _game.draw;
  bool get _humanTurn => !_over && !_game.isBot(_game.current);

  void _move(Pt from, Pt to) {
    final id = _ids.remove(from)!;
    final owner = _game.current;
    final taken = _game.play(from, to);
    _ids[to] = id;
    if (taken != null) {
      _ids.remove(taken);
      _fading.add((taken, 1 - owner, DateTime.now()));
      Sounds.play(Sfx.capture);
      HapticFeedback.mediumImpact();
      Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _fading.removeWhere(
            (f) => DateTime.now().difference(f.$3).inMilliseconds >= 550));
      });
    } else {
      Sounds.play(Sfx.step, 2);
      HapticFeedback.selectionClick();
    }
    // A piece that can keep jumping stays selected.
    _selected = _game.chaining;
    if (_over) Sounds.play(Sfx.win);
    _afterMove();
  }

  void _afterMove() {
    if (mounted) setState(() {});
    _botTimer?.cancel();
    if (!_over && _game.isBot(_game.current)) {
      _botTimer = Timer(const Duration(milliseconds: 650), _botPlay);
    }
  }

  void _botPlay() {
    if (!mounted || _over) return;
    final m = _game.botMove();
    var i = 1;
    void next() {
      if (!mounted || _over) return;
      _move(m.path[i - 1], m.path[i]);
      i++;
      if (i < m.path.length) {
        _botTimer = Timer(const Duration(milliseconds: 420), next);
      } else if (_game.chaining != null) {
        _game.endTurn();
        _selected = null;
        _afterMove();
      }
    }

    _selected = m.from;
    setState(() {});
    _botTimer = Timer(const Duration(milliseconds: 280), next);
  }

  void _tapPoint(Pt p) {
    if (!_humanTurn) return;
    final target = _selected == null
        ? null
        : _game.targets(_selected!).where((t) => t.$1 == p).firstOrNull;
    if (target != null) return _move(_selected!, p);
    if (_game.board[p] == _game.current &&
        (_game.chaining == null || _game.chaining == p)) {
      Sounds.play(Sfx.tap);
      setState(() => _selected = _selected == p ? null : p);
    }
  }

  void _endChain() {
    _game.endTurn();
    _selected = null;
    _afterMove();
  }

  Future<void> _confirmLeave() async {
    if (_over) return Navigator.of(context).pop();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Leave game?', style: AppText.title.copyWith(fontSize: 22)),
        content: Text('Your current game will be lost.',
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
            child: LayoutBuilder(builder: (context, box) {
              final h = math.min(box.maxHeight - 210,
                  (math.min(box.maxWidth, 520.0) - 24) / _boardAspect);
              final size = Size(h * _boardAspect, h);
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
                      const SizedBox(height: 6),
                      _playerBar(1),
                      const Spacer(),
                      _board(size),
                      const Spacer(),
                      _playerBar(0),
                      const SizedBox(height: 10),
                    ],
                  ),
                  if (_over) Positioned.fill(child: _result()),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _playerBar(int player) {
    final active = _game.current == player && !_over;
    final name = widget.names[player] ?? 'Player';
    final left = _game.count(player), lost = 16 - _game.count(1 - player);
    final note = !active
        ? ''
        : _game.chaining != null
            ? 'Jump again!'
            : _game.isBot(player)
                ? 'Thinking…'
                : 'Your move';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xE62E3380), Color(0xE612143F)],
          ),
          border: Border.all(
            color: active ? AppColors.goldSoft : const Color(0xFF5A61AE),
            width: active ? 2 : 1.2,
          ),
          boxShadow: [
            if (active)
              const BoxShadow(color: Color(0x99EBCB7A), blurRadius: 14),
          ],
        ),
        child: Row(
          children: [
            Image.asset(_pieceAsset[player], width: 38, height: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shortName(name, 12),
                      style: AppText.title.copyWith(fontSize: 16)),
                  Text(
                    note.isEmpty ? '$left pieces left' : note,
                    style: AppText.title.copyWith(
                      fontSize: 12,
                      color: note.isEmpty
                          ? const Color(0xFF9EA9DC)
                          : AppColors.goldSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (active && _game.chaining != null && _humanTurn)
              GestureDetector(
                onTap: _endChain,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: AppColors.goldGradient,
                    ),
                  ),
                  child: Text('End turn',
                      style: AppText.title.copyWith(
                          fontSize: 13.5, color: const Color(0xFF3A2500))),
                ),
              )
            else
              Row(
                children: [
                  Image.asset(_pieceAsset[1 - player], width: 22, height: 22),
                  const SizedBox(width: 4),
                  Text('×$lost',
                      style: AppText.title.copyWith(fontSize: 17)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _board(Size size) {
    final piece = size.width * .095;
    // Taps land on a bigger circle than the piece, so small pieces are
    // still easy to hit.
    final hit = size.width * .17;
    Offset at(Pt p) {
      final f = GhutiGame.spot(p);
      return Offset(f.dx * size.width, f.dy * size.height);
    }

    final targets = _selected == null ? const <(Pt, Pt?)>[] : _game.targets(_selected!);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(_boardAsset,
                fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
          // Where the selected piece can go: green for a step, red for a jump.
          for (final (to, over) in targets)
            Positioned(
              left: at(to).dx - piece / 2,
              top: at(to).dy - piece / 2,
              width: piece,
              height: piece,
              child: IgnorePointer(
                child: ScaleTransition(
                  scale: Tween(begin: .7, end: 1.0).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (over == null
                              ? const Color(0xFF45E3A6)
                              : const Color(0xFFFF4D4D))
                          .withValues(alpha: .35),
                      border: Border.all(
                        color: over == null
                            ? const Color(0xFF45E3A6)
                            : const Color(0xFFFF4D4D),
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Pieces being taken shrink and fade where they stood.
          for (final (p, owner, at0) in _fading)
            Positioned(
              key: ValueKey('fade-$p-$at0'),
              left: at(p).dx - piece / 2,
              top: at(p).dy - piece / 2,
              width: piece,
              height: piece,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1, end: 0),
                  duration: const Duration(milliseconds: 500),
                  builder: (_, v, child) => Opacity(
                    opacity: v,
                    child: Transform.scale(scale: .4 + .6 * v, child: child),
                  ),
                  child: Image.asset(_pieceAsset[owner]),
                ),
              ),
            ),
          for (final MapEntry(key: p, value: owner) in _game.board.entries)
            AnimatedPositioned(
              key: ValueKey('ghuti-${_ids[p]}'),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: at(p).dx - piece / 2,
              top: at(p).dy - piece / 2,
              width: piece,
              height: piece,
              child: AnimatedScale(
                scale: _selected == p ? 1.18 : 1,
                duration: const Duration(milliseconds: 160),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _selected == p
                            ? const Color(0xCCFFE28A)
                            : const Color(0x66000000),
                        blurRadius: _selected == p ? 14 : 5,
                        offset: _selected == p
                            ? Offset.zero
                            : const Offset(1, 3),
                      ),
                    ],
                  ),
                  child: Image.asset(_pieceAsset[owner],
                      filterQuality: FilterQuality.medium),
                ),
              ),
            ),
          // Tap targets on every point (on top, so pieces and spots both work).
          for (final p in GhutiGame.points)
            Positioned(
              left: at(p).dx - hit / 2,
              top: at(p).dy - hit / 2,
              width: hit,
              height: hit,
              child: GestureDetector(
                key: ValueKey('pt-${p.x},${p.y}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapPoint(p),
              ),
            ),
        ],
      ),
    );
  }

  Widget _result() {
    final w = _game.winner;
    final title = w == null
        ? 'Draw!'
        : widget.names[w] == 'You'
            ? 'You win!'
            : '${shortName(widget.names[w] ?? 'Player', 12)} wins!';
    return ColoredBox(
      color: const Color(0xC7080920),
      child: Center(
        child: Container(
          width: 290,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.cardTop, AppColors.cardBottom],
            ),
            border: Border.all(color: AppColors.goldSoft, width: 2.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Art(ArtKind.trophy, size: 92),
              const SizedBox(height: 6),
              Text(title,
                  style: AppText.title
                      .copyWith(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Pieces left: ${_game.count(0)} – ${_game.count(1)}',
                style: AppText.title
                    .copyWith(fontSize: 14.5, color: const Color(0xFFC9CFF5)),
              ),
              if (w != null) ...[
                const SizedBox(height: 4),
                Text('+${formatCoins(_prize)}',
                    style: AppText.title.copyWith(
                        fontSize: 20, color: const Color(0xFFFFE28A))),
              ],
              const SizedBox(height: 14),
              _wide('Play again', true, () => setState(_newGame)),
              const SizedBox(height: 10),
              _wide('Home', false, () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wide(String label, bool filled, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: filled
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: AppColors.goldGradient,
                  )
                : null,
            border: filled
                ? null
                : Border.all(color: AppColors.cardBorder, width: 1.5),
          ),
          child: Text(label,
              style: AppText.title.copyWith(
                  fontSize: 16.5,
                  color: filled ? const Color(0xFF3A2500) : AppColors.cream)),
        ),
      );
}
