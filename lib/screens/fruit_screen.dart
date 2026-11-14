import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/fruit_game.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../widgets/game_hud.dart';

/// How long a point of the blade's trail lingers, in seconds.
const _trailLife = .22;

/// The look of the blade's trail: its glow and its bright core.
enum Blade {
  silver('Silver', Color(0xFF7FD8FF), Colors.white),
  fire('Fire', Color(0xFFFF6A1A), Color(0xFFFFE28A)),
  neon('Neon', Color(0xFFB04BFF), Color(0xFF7CFFCB));

  const Blade(this.label, this.glow, this.core);
  final String label;
  final Color glow, core;
}

/// The fruit pictures: whole, left half and right half of each.
abstract final class FruitImages {
  static final _images = <String, ui.Image>{};
  static Future<void>? _loading;

  static ui.Image? of(int kind, String part) =>
      _images['${fruitKinds[kind].$1}_$part'];

  static Future<void> load() => _loading ??= Future.wait([
    for (final (name, _) in fruitKinds)
      for (final part in const ['w', 'l', 'r'])
        () async {
          try {
            final data = await rootBundle.load(
              'assets/images/fruit/${name}_$part.png',
            );
            final codec = await ui.instantiateImageCodec(
              data.buffer.asUint8List(),
            );
            _images['${name}_$part'] = (await codec.getNextFrame()).image;
          } catch (_) {
            // A missing picture is drawn as a plain ball instead.
          }
        }(),
  ]);
}

/// Fruit Cut: swipe to cut the fruit thrown up onto the board.
class FruitScreen extends StatefulWidget {
  const FruitScreen({
    super.key,
    this.mode = FruitMode.classic,
    this.blade = Blade.silver,
    this.rivals = 0,
    this.humans = 1,
  });

  final FruitMode mode;
  final Blade blade;

  /// Computer players to cut against (versus).
  final int rivals;

  /// People taking turns on this phone (pass and play), 1 for solo.
  final int humans;

  /// Best scores this session, per mode.
  static final best = <FruitMode, int>{};

  @visibleForTesting
  static FruitGame? debugGame;

  @override
  State<FruitScreen> createState() => _FruitScreenState();
}

class _FruitScreenState extends State<FruitScreen>
    with SingleTickerProviderStateMixin {
  late FruitGame _game;
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _clock = 0, _shake = 0, _ready = 0, _sinceOver = 0;
  double _lastSlice = -1;
  bool _paused = false, _results = false, _newBest = false;

  /// Recent blade positions and when they were made.
  final _trail = <(Offset, double)>[];
  int? _pointer;
  double _knifeAngle = -math.pi / 4, _knifePop = 0;
  String _hudKey = '';

  @override
  void initState() {
    super.initState();
    FruitImages.load();
    _newGame();
    _ticker.start();
  }

  /// Whose turn it is in pass and play, and the scores so far.
  int _turn = 0;
  final _turnScores = <int>[];

  bool get _passPlay => widget.humans > 1;
  String get _youName => _passPlay ? 'Player ${_turn + 1}' : 'You';

  /// Start again from the first player.
  void _restart() {
    _turn = 0;
    _turnScores.clear();
    _newGame();
  }

  void _nextTurn() {
    _turn++;
    _newGame();
  }

  void _newGame() {
    _game = FruitGame(
      mode: widget.mode,
      rivals: widget.rivals,
      you: _youName,
      yourColour: widget.blade.glow,
    );
    FruitScreen.debugGame = _game;
    _ready = 1.4;
    _sinceOver = 0;
    _results = false;
    _paused = false;
    _newBest = false;
    _trail.clear();
    _pointer = null;
    Sounds.play(Sfx.start);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = math.min(1 / 30, (now - _last).inMicroseconds / 1e6);
    _last = now;
    if (dt <= 0 || _paused) return;
    _clock += dt;
    _shake = math.max(0, _shake - dt * 3);
    if (!_game.started && !_game.over) {
      _ready -= dt;
      if (_ready <= 0) _game.started = true;
    }
    final ev = _game.update(dt);
    if (ev.missed > 0) {
      Sounds.play(Sfx.lifeLost);
      HapticFeedback.mediumImpact();
    }
    // The computer players' cuts and mistakes.
    if (ev.botCut > 0 && _clock - _lastSlice > .12) {
      _lastSlice = _clock;
      Sounds.play(Sfx.slice);
    }
    if (ev.bomb) {
      _shake = math.max(_shake, .6);
      Sounds.play(Sfx.crash);
    }
    if (ev.poison) Sounds.play(Sfx.hit);
    if (ev.over) _gameOver();
    if (_game.over && !_results) {
      _sinceOver += dt;
      final wait = _game.endedBy == 'bomb' ? 1.4 : .9;
      if (_sinceOver > wait) setState(() => _results = true);
    }
    _trail.removeWhere((p) => _clock - p.$2 > _trailLife);
    _knifePop = _pointer == null
        ? math.max(0, _knifePop - dt * 6)
        : math.min(1, _knifePop + dt * 9);

    // The HUD only rebuilds when something on it changes.
    final key =
        '${_game.players.map((p) => p.score).join(',')}|${_game.lives}|'
        '${_game.timeLeft.ceil()}|${_game.started}|${_ready > .5}';
    if (key != _hudKey) setState(() => _hudKey = key);
    _frame.value++;
  }

  void _gameOver() {
    if (_passPlay) _turnScores.add(_game.score);
    final best = FruitScreen.best[widget.mode] ?? 0;
    _newBest = _game.score > best;
    if (_newBest) FruitScreen.best[widget.mode] = _game.score;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) Sounds.play(_newBest ? Sfx.win : Sfx.rank);
    });
  }

  // ── The blade ──

  void _down(PointerDownEvent e) {
    if (_pointer != null || _paused || _results) return;
    _pointer = e.pointer;
    _trail.add((e.localPosition, _clock));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final from = _trail.isEmpty ? e.localPosition : _trail.last.$1;
    final to = e.localPosition;
    _trail.add((to, _clock));
    // The knife turns smoothly to follow the stroke.
    final d = to - from;
    if (d.distance > 2) {
      var target = math.atan2(d.dy, d.dx);
      var diff = target - _knifeAngle;
      while (diff > math.pi) {
        diff -= math.pi * 2;
      }
      while (diff < -math.pi) {
        diff += math.pi * 2;
      }
      _knifeAngle += diff * .45;
    }
    final ev = _game.slice(from, to);
    if (ev.cut > 0) {
      if (_clock - _lastSlice > .05) Sounds.play(Sfx.slice);
      _lastSlice = _clock;
      HapticFeedback.lightImpact();
    }
    if (ev.bomb) {
      _shake = 1;
      Sounds.play(Sfx.crash);
      HapticFeedback.heavyImpact();
      if (_game.over) _gameOver();
    }
    if (ev.poison) {
      _shake = math.max(_shake, .5);
      Sounds.play(Sfx.lifeLost);
      HapticFeedback.heavyImpact();
      if (_game.over) _gameOver();
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final ev = _game.endSwipe();
    if (ev.combo > 0) {
      Sounds.play(Sfx.bonus);
      HapticFeedback.mediumImpact();
    }
  }

  void _togglePause() {
    if (_game.over) return;
    _pointer = null;
    _trail.clear();
    setState(() => _paused = !_paused);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3A2414),
      body: LayoutBuilder(
        builder: (context, box) {
          _game.resize(box.biggest);
          return Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _BoardPainter()),
                ),
              ),
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: CustomPaint(
                    painter: _FruitPainter(
                      game: _game,
                      trail: _trail,
                      blade: widget.blade,
                      clock: () => _clock,
                      shake: () => _shake,
                      touching: () => _pointer != null,
                      knife: () => (_knifeAngle, _knifePop),
                      pixelRatio: MediaQuery.devicePixelRatioOf(context),
                      repaint: _frame,
                    ),
                  ),
                ),
              ),
              SafeArea(child: _hud()),
              if (!_game.started && !_game.over)
                Center(child: _bigWord(_ready > .5 ? 'READY?' : 'GO!')),
              if (_paused && !_results) _pauseCard(),
              if (_results) _resultCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _hud() {
    final g = _game;
    final best = FruitScreen.best[widget.mode] ?? 0;
    final top = _topBar(g, best);
    if (g.players.length < 2) return top;
    // Everyone's score, leader first.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        top,
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, p) in g.standings.indexed)
                Container(
                  key: ValueKey('chip-${p.name}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: p.bot
                        ? const Color(0xAA0E1440)
                        : const Color(0xDD2A1F7A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.bot ? p.colour : AppColors.goldSoft,
                      width: 1.4,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 0 && p.score > 0) ...[
                        const Icon(
                          Icons.emoji_events_rounded,
                          size: 14,
                          color: AppColors.goldSoft,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: p.colour,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${p.name}  ${p.score}',
                        style: _small.copyWith(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar(FruitGame g, int best) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoundButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          _panel(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/fruit/watermelon_l.png',
                  width: 30,
                  height: 30,
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${g.score}',
                      key: const ValueKey('score'),
                      style: _big.copyWith(fontSize: 26),
                    ),
                    Text(
                      _passPlay
                          ? _youName.toUpperCase()
                          : 'BEST ${math.max(best, g.score)}',
                      style: _small,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          if (widget.mode == FruitMode.classic)
            _panel(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 26,
                        color: i < 3 - g.lives
                            ? const Color(0xFFFF4D4D)
                            : const Color(0x55FFFFFF),
                      ),
                    ),
                ],
              ),
            )
          else
            _panel(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timer_rounded,
                    color: AppColors.goldSoft,
                    size: 22,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${g.timeLeft.ceil()}',
                    style: _big.copyWith(
                      fontSize: 24,
                      color: g.timeLeft <= 10
                          ? const Color(0xFFFF6B6B)
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          RoundButton(
            key: const ValueKey('pause'),
            icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: _togglePause,
          ),
        ],
      ),
    );
  }

  Widget _pauseCard() => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xAA0A0604),
      child: Center(
        child: _card(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PAUSED', style: _big.copyWith(fontSize: 30)),
              const SizedBox(height: 16),
              _button('RESUME', const Color(0xFF1FA35C), _togglePause),
              _button(
                'RESTART',
                const Color(0xFF2E6BE0),
                () => setState(_restart),
              ),
              _button(
                'QUIT',
                const Color(0xFFC0392B),
                () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _resultCard() {
    final g = _game;
    if (_passPlay && _turn < widget.humans - 1) return _turnCard();
    if (_passPlay) {
      return _rankingCard([
        for (var i = 0; i < _turnScores.length; i++)
          ('Player ${i + 1}', AppColors.goldSoft, _turnScores[i], false),
      ], youWon: null);
    }
    if (g.players.length > 1) {
      final order = g.standings;
      return _rankingCard([
        for (final p in order) (p.name, p.colour, p.score, !p.bot),
      ], youWon: order.first == g.you);
    }
    final title = switch (g.endedBy) {
      'bomb' => 'BOOM!',
      'poison' => 'POISONED!',
      'time' => 'TIME UP!',
      _ => 'GAME OVER',
    };
    Widget stat(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: _small.copyWith(fontSize: 14)),
          const Spacer(),
          Text(value, style: _big.copyWith(fontSize: 18)),
        ],
      ),
    );
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB00A0604),
        child: Center(
          child: _card(
            SizedBox(
              width: 250,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: _big.copyWith(
                      fontSize: 32,
                      color: const Color(0xFFFFE28A),
                    ),
                  ),
                  if (_newBest)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE02A2A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'NEW BEST!',
                        style: _big.copyWith(fontSize: 14),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    '${g.score}',
                    key: const ValueKey('final-score'),
                    style: _big.copyWith(fontSize: 56),
                  ),
                  Text('SCORE', style: _small),
                  const SizedBox(height: 12),
                  stat('Fruits cut', '${g.cut}'),
                  stat('Best combo', '${g.bestCombo}'),
                  stat('Best score', '${FruitScreen.best[widget.mode] ?? 0}'),
                  const SizedBox(height: 14),
                  _button(
                    'PLAY AGAIN',
                    const Color(0xFF1FA35C),
                    () => setState(_restart),
                  ),
                  _button(
                    'HOME',
                    const Color(0xFF2A3A9A),
                    () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Between turns in pass and play: this player's score, then hand over.
  Widget _turnCard() {
    final next = _turn + 2;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB00A0604),
        child: Center(
          child: _card(
            SizedBox(
              width: 250,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TIME UP!',
                    style: _big.copyWith(
                      fontSize: 30,
                      color: const Color(0xFFFFE28A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_youName, style: _small.copyWith(fontSize: 14)),
                  Text('${_game.score}', style: _big.copyWith(fontSize: 52)),
                  const SizedBox(height: 10),
                  Text(
                    'Pass the phone to Player $next',
                    textAlign: TextAlign.center,
                    style: _small.copyWith(fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  _button(
                    'PLAYER $next  START',
                    const Color(0xFF1FA35C),
                    () => setState(_nextTurn),
                  ),
                  _button(
                    'QUIT',
                    const Color(0xFF2A3A9A),
                    () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Final places: name, colour, score, and whether it is the person
  /// playing (highlighted).
  Widget _rankingCard(
    List<(String, Color, int, bool)> rows, {
    required bool? youWon,
  }) {
    rows = [...rows]..sort((a, b) => b.$3.compareTo(a.$3));
    final title = switch (youWon) {
      true => 'YOU WIN!',
      false => '${rows.first.$1.toUpperCase()} WINS',
      null => '${rows.first.$1.toUpperCase()} WINS!',
    };
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB00A0604),
        child: Center(
          child: _card(
            SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    size: 44,
                    color: AppColors.goldSoft,
                  ),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: _big.copyWith(
                      fontSize: 28,
                      color: const Color(0xFFFFE28A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final (i, (name, colour, score, you)) in rows.indexed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: you
                            ? const Color(0x553A2AA0)
                            : const Color(0x33000000),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: i == 0
                              ? AppColors.goldSoft
                              : const Color(0x33FFFFFF),
                          width: i == 0 ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}',
                            style: _big.copyWith(
                              fontSize: 18,
                              color: AppColors.goldSoft,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colour,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: _big.copyWith(fontSize: 16),
                            ),
                          ),
                          Text('$score', style: _big.copyWith(fontSize: 20)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  _button(
                    'PLAY AGAIN',
                    const Color(0xFF1FA35C),
                    () => setState(_restart),
                  ),
                  _button(
                    'HOME',
                    const Color(0xFF2A3A9A),
                    () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(String label, Color colour, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.goldSoft, width: 1.6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text(label, style: _big.copyWith(fontSize: 17)),
      ),
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xF21B2470), Color(0xF20E1440)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.goldTrim, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 20)],
    ),
    child: child,
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xDD1B2470), Color(0xDD0E1440)],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.goldTrim, width: 1.4),
    ),
    child: child,
  );

  Widget _bigWord(String s) => Stack(
    children: [
      Text(
        s,
        style: _big.copyWith(
          fontSize: 56,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..color = const Color(0xFF3A1A08),
        ),
      ),
      Text(
        s,
        style: _big.copyWith(fontSize: 56, color: const Color(0xFFFFE28A)),
      ),
    ],
  );

  static const _small = TextStyle(
    fontFamily: AppText.family,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1,
    color: Color(0xFFB8C2F0),
  );
  static const _big = TextStyle(
    fontFamily: AppText.family,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    height: 1.05,
    color: Colors.white,
  );
}

/// A wooden cutting board: planks with grain, knots and a warm light.
class _BoardPainter extends CustomPainter {
  const _BoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rnd = math.Random(11);
    const planks = 5;
    final pw = w / planks;
    const tones = [
      Color(0xFFB0703A),
      Color(0xFFA5642F),
      Color(0xFFB87A42),
      Color(0xFF9E5E2C),
      Color(0xFFAD6C36),
    ];
    for (var i = 0; i < planks; i++) {
      final r = Rect.fromLTWH(i * pw, 0, pw, h);
      final c = tones[i % tones.length];
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Color.lerp(c, Colors.black, .12)!,
              Color.lerp(c, Colors.white, .06)!,
              c,
              Color.lerp(c, Colors.black, .15)!,
            ],
            stops: const [0, .3, .7, 1],
          ).createShader(r),
      );
      // Grain: long wavy lines down the plank.
      final grain = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (var k = 0; k < 9; k++) {
        final x0 = r.left + pw * (.08 + k * .105);
        final amp = 2 + rnd.nextDouble() * 5;
        final freq = .006 + rnd.nextDouble() * .01;
        final phase = rnd.nextDouble() * 6;
        grain.color = Color.fromRGBO(70, 35, 12, .12 + rnd.nextDouble() * .14);
        final path = Path()..moveTo(x0, 0);
        for (var y = 0.0; y <= h; y += 12) {
          path.lineTo(x0 + amp * math.sin(y * freq + phase), y);
        }
        canvas.drawPath(path, grain);
      }
      // A knot or two.
      for (var k = 0; k < 2; k++) {
        if (rnd.nextDouble() < .4) continue;
        final c0 = Offset(
          r.left + pw * (.25 + rnd.nextDouble() * .5),
          h * rnd.nextDouble(),
        );
        for (var ring = 3; ring >= 1; ring--) {
          canvas.drawOval(
            Rect.fromCenter(
              center: c0,
              width: pw * .12 * ring,
              height: pw * .26 * ring,
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = const Color(0x33502008),
          );
        }
        canvas.drawOval(
          Rect.fromCenter(center: c0, width: pw * .08, height: pw * .16),
          Paint()..color = const Color(0x55502008),
        );
      }
      // The gap between planks.
      canvas.drawRect(
        Rect.fromLTWH(r.left - 1.5, 0, 3, h),
        Paint()..color = const Color(0xFF4A2810),
      );
      canvas.drawRect(
        Rect.fromLTWH(r.left + 1.5, 0, 1.2, h),
        Paint()..color = const Color(0x33FFE0B0),
      );
    }
    // Warm light from above and dark corners.
    final all = Offset.zero & size;
    canvas.drawRect(
      all,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.35),
          radius: 1.05,
          colors: const [
            Color(0x22FFE6B0),
            Color(0x00000000),
            Color(0x99140802),
          ],
          stops: const [0, .55, 1],
        ).createShader(all),
    );
  }

  @override
  bool shouldRepaint(_BoardPainter old) => false;
}

/// Fruit, halves, juice, the blade and floating scores.
class _FruitPainter extends CustomPainter {
  _FruitPainter({
    required this.game,
    required this.trail,
    required this.blade,
    required this.clock,
    required this.shake,
    required this.touching,
    required this.knife,
    required this.pixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final FruitGame game;
  final List<(Offset, double)> trail;
  final Blade blade;
  final double Function() clock, shake;
  final bool Function() touching;

  /// The knife's heading and how far it has popped in (0..1).
  final (double, double) Function() knife;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final g = game, t = clock(), s = shake();
    canvas.save();
    if (s > 0) {
      canvas.translate(math.sin(t * 80) * s * 8, math.cos(t * 65) * s * 6);
    }
    // Juice splashed over the board.
    _forget(_stainCache, g.stains);
    for (final st in g.stains) {
      _blitStain(canvas, st);
    }
    // Shadows on the board, then the fruit above them.
    final shadow = Paint()..color = const Color(0x33000000);
    for (final f in g.flyers) {
      canvas.drawOval(
        Rect.fromCenter(
          center: f.pos + Offset(f.radius * .3, f.radius * .5),
          width: f.radius * 1.9,
          height: f.radius * 1.3,
        ),
        shadow,
      );
    }
    for (final hf in g.halves) {
      final img = FruitImages.of(hf.kind, hf.right ? 'r' : 'l');
      _image(canvas, img, hf.pos, hf.size, hf.angle, null);
    }
    for (final f in g.flyers) {
      if (f.bomb) {
        _bomb(canvas, f, t);
      } else if (f.poison) {
        _poison(canvas, f, t);
      } else {
        final img = FruitImages.of(f.kind, 'w');
        _image(
          canvas,
          img,
          f.pos,
          f.radius * 2.3,
          f.angle,
          fruitKinds[f.kind].$2,
        );
      }
    }
    final drop = Paint();
    for (final d in g.drops) {
      drop.color = d.colour.withValues(alpha: 1 - d.age / d.life);
      canvas.drawCircle(d.pos, d.size * (1 - d.age / d.life * .5), drop);
    }
    _slashes(canvas);
    _blade(canvas, t);
    _forget(_popupCache, g.popups);
    for (final p in g.popups) {
      _popup(canvas, p, size.width);
    }
    canvas.restore();
    // A sickly green wash when poison is cut.
    if (g.sincePoison < .7) {
      final k = 1 - g.sincePoison / .7;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(70, 220, 40, .35 * k),
      );
    }
    // The flash of a bomb going off.
    if (g.sinceBomb < .6) {
      final k = 1 - g.sinceBomb / .6;
      canvas.drawCircle(
        g.bombAt,
        size.shortestSide * (.2 + (1 - k) * 1.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18 * k
          ..color = Color.fromRGBO(255, 210, 120, k),
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 250, 235, .85 * k * k),
      );
    }
  }

  void _image(
    Canvas canvas,
    ui.Image? img,
    Offset at,
    double size,
    double angle,
    Color? fallback,
  ) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    if (img == null) {
      canvas.drawCircle(
        Offset.zero,
        size / 2,
        Paint()..color = fallback ?? const Color(0xFFFFC233),
      );
    } else {
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final k = size / math.max(iw, ih);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, iw, ih),
        Rect.fromCenter(center: Offset.zero, width: iw * k, height: ih * k),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();
  }

  void _bomb(Canvas canvas, Flyer f, double t) {
    final r = f.radius;
    canvas.save();
    canvas.translate(f.pos.dx, f.pos.dy);
    canvas.rotate(f.angle * .4);
    // A red danger halo, pulsing.
    final pulse = .5 + .5 * math.sin(t * 10);
    canvas.drawCircle(
      Offset.zero,
      r * (1.25 + .1 * pulse),
      Paint()..color = Color.fromRGBO(255, 40, 40, .22 + .12 * pulse),
    );
    final ball = Rect.fromCircle(center: Offset.zero, radius: r);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.4),
          colors: [Color(0xFF5A5A66), Color(0xFF1A1A20), Color(0xFF050507)],
          stops: [0, .55, 1],
        ).createShader(ball),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * .35, -r * .4),
        width: r * .5,
        height: r * .3,
      ),
      Paint()..color = const Color(0x55FFFFFF),
    );
    // Cap and fuse.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -r * .98),
          width: r * .5,
          height: r * .3,
        ),
        Radius.circular(r * .06),
      ),
      Paint()..color = const Color(0xFF8A8F9C),
    );
    final tip = Offset(r * .45, -r * 1.55);
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 1.1)
        ..quadraticBezierTo(r * .05, -r * 1.55, tip.dx, tip.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .1
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFC9A26B),
    );
    // The burning spark.
    final flick = .7 + .3 * math.sin(t * 40);
    canvas.drawCircle(
      tip,
      r * .32 * flick,
      Paint()..color = const Color(0x88FFB020),
    );
    canvas.drawCircle(tip, r * .14, Paint()..color = const Color(0xFFFFF4C0));
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + t * 9;
      canvas.drawLine(
        tip,
        tip + Offset(math.cos(a), math.sin(a)) * r * .38 * flick,
        Paint()
          ..strokeWidth = 2
          ..color = const Color(0xFFFFD25A),
      );
    }
    canvas.restore();
  }

  /// A splash of juice: a wet blob with a darker rim, spray thrown along
  /// the cut, droplets, and drips that creep down the board.
  // Stains and popups are each drawn once into a picture and then only
  // copied to the screen, so a board full of juice costs almost nothing.
  static final _stainCache = <Stain, (ui.Image, double)>{};
  static final _popupCache = <Popup, (ui.Image, double)>{};

  /// Drops cached pictures for things that are gone.
  static void _forget<T>(Map<T, (ui.Image, double)> cache, List<T> live) {
    final alive = live.toSet();
    cache.removeWhere((key, v) {
      if (alive.contains(key)) return false;
      v.$1.dispose();
      return true;
    });
  }

  void _blitStain(Canvas canvas, Stain st) {
    final k = st.strength;
    if (k <= 0) return;
    final (img, half) = _stainCache[st] ??= () {
      final half = st.size * 2.4;
      final ratio = pixelRatio.clamp(1.0, 2.5);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(ratio);
      _stain(c, st, Offset(half, half));
      final side = (half * 2 * ratio).ceil();
      return (rec.endRecording().toImageSync(side, side), half);
    }();
    // Splats in fast, then sits.
    final pop = Curves.easeOutBack.transform((st.age / .18).clamp(0.0, 1.0));
    final h = half * (.6 + .4 * pop);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: st.pos, width: h * 2, height: h * 2),
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, k)
        ..filterQuality = FilterQuality.low,
    );
  }

  static void _stain(Canvas canvas, Stain st, Offset at) {
    const k = 1.0;
    final rnd = math.Random(st.seed);
    final r = st.size;
    final base = st.colour;
    final rim = Color.lerp(base, Colors.black, .35)!;
    // Irregular main blob.
    // A smooth wobbly outline through points at random distances.
    const points = 14;
    final pts = [
      for (var i = 0; i < points; i++)
        at +
            Offset(
                  math.cos(i / points * math.pi * 2),
                  math.sin(i / points * math.pi * 2),
                ) *
                (r * (.42 + rnd.nextDouble() * .2)),
    ];
    final blob = Path();
    for (var i = 0; i <= points; i++) {
      final p = pts[i % points], q = pts[(i + 1) % points];
      final mid = Offset.lerp(p, q, .5)!;
      if (i == 0) {
        blob.moveTo(mid.dx, mid.dy);
      } else {
        blob.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
      }
    }
    blob.close();
    canvas.drawPath(
      blob,
      Paint()
        ..color = rim.withValues(alpha: .55 * k)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .08
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(blob, Paint()..color = base.withValues(alpha: .62 * k));
    // Spray thrown along the blade's path, both ways.
    final spray = Paint()..color = base.withValues(alpha: .6 * k);
    for (var i = 0; i < 9; i++) {
      final dir =
          st.angle +
          (rnd.nextBool() ? 0 : math.pi) +
          (rnd.nextDouble() - .5) * .9;
      final dist = r * (.55 + rnd.nextDouble() * 1.1);
      final c = at + Offset(math.cos(dir), math.sin(dir)) * dist;
      final len = r * (.12 + rnd.nextDouble() * .2);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(dir);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: len * 2, height: len * .7),
        spray,
      );
      canvas.restore();
    }
    // Loose droplets all round.
    for (var i = 0; i < 12; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = r * (.5 + rnd.nextDouble() * 1.3);
      canvas.drawCircle(
        at + Offset(math.cos(a), math.sin(a)) * d,
        r * (.03 + rnd.nextDouble() * .07),
        spray,
      );
    }
    // Drips running down the board, growing for a few seconds.
    const grow = 1.0;
    final drip = Paint()
      ..color = base.withValues(alpha: .55 * k)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final x = at.dx + (rnd.nextDouble() - .5) * r * .8;
      final top = at.dy + r * .3;
      final len = r * (.4 + rnd.nextDouble() * 1.2) * grow;
      final w = r * (.06 + rnd.nextDouble() * .05);
      drip.strokeWidth = w;
      canvas.drawLine(Offset(x, top), Offset(x, top + len), drip);
      canvas.drawCircle(Offset(x, top + len), w * .9, drip);
    }
    // A wet shine.
    canvas.drawOval(
      Rect.fromCenter(
        center: at + Offset(-r * .15, -r * .18),
        width: r * .3,
        height: r * .14,
      ),
      Paint()..color = Colors.white.withValues(alpha: .28 * k),
    );
  }

  /// Smooths the trail with a Catmull-Rom curve through its points.
  List<(Offset, double)> _smooth(List<(Offset, double)> trail) {
    if (trail.length < 3) return trail;
    final out = <(Offset, double)>[];
    for (var i = 0; i < trail.length - 1; i++) {
      final p0 = trail[math.max(0, i - 1)].$1, p1 = trail[i].$1;
      final p2 = trail[i + 1].$1,
          p3 = trail[math.min(trail.length - 1, i + 2)].$1;
      final t1 = trail[i].$2, t2 = trail[i + 1].$2;
      for (var k = 0; k < 4; k++) {
        final u = k / 4, u2 = u * u, u3 = u2 * u;
        final p =
            (p1 * 2 +
                (p2 - p0) * u +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2 +
                (p1 * 3 - p0 - p2 * 3 + p3) * u3) *
            .5;
        out.add((p, t1 + (t2 - t1) * u));
      }
    }
    out.add(trail.last);
    return out;
  }

  /// A tapered ribbon along [pts]: a point at the tail, widest at the
  /// blade, fading as its points age past [now].
  void _ribbon(
    Canvas canvas,
    List<(Offset, double)> pts,
    double now,
    Color glowColour,
    Color coreColour,
    double width,
  ) {
    final t = now;
    if (pts.length >= 2) {
      // A tapered ribbon: a point at the tail, widest at the blade.
      final left = <Offset>[], right = <Offset>[];
      final outerL = <Offset>[], outerR = <Offset>[];
      for (var i = 0; i < pts.length; i++) {
        final a = pts[math.max(0, i - 1)].$1,
            b = pts[math.min(pts.length - 1, i + 1)].$1;
        var d = b - a;
        if (d.distance < .001) d = const Offset(1, 0);
        final n = Offset(-d.dy, d.dx) / d.distance;
        final fresh = (1 - (t - pts[i].$2) / _trailLife).clamp(0.0, 1.0);
        final w = width * math.sqrt(i / (pts.length - 1)) * fresh;
        left.add(pts[i].$1 + n * w);
        right.add(pts[i].$1 - n * w);
        outerL.add(pts[i].$1 + n * (w * 2.2));
        outerR.add(pts[i].$1 - n * (w * 2.2));
      }
      final ribbon = Path()..addPolygon([...left, ...right.reversed], true);
      canvas.drawPath(
        Path()..addPolygon([...outerL, ...outerR.reversed], true),
        Paint()..color = glowColour.withValues(alpha: .3),
      );
      canvas.drawPath(ribbon, Paint()..color = glowColour);
      final core = Path()
        ..addPolygon([
          for (var i = 0; i < pts.length; i++)
            Offset.lerp(left[i], right[i], .3)!,
          for (var i = pts.length - 1; i >= 0; i--)
            Offset.lerp(left[i], right[i], .7)!,
        ], true);
      canvas.drawPath(core, Paint()..color = coreColour);
      // Glints scattered along the stroke.
      final rnd = math.Random((t * 24).floor());
      final glint = Paint()..color = coreColour;
      for (var i = 0; i < 5; i++) {
        final p = pts[rnd.nextInt(pts.length)];
        final fresh = (1 - (t - p.$2) / _trailLife).clamp(0.0, 1.0);
        if (fresh < .2) continue;
        final c =
            p.$1 + Offset(rnd.nextDouble() - .5, rnd.nextDouble() - .5) * 26;
        final r = 2 + rnd.nextDouble() * 4 * fresh;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r * 2)
            ..lineTo(c.dx + r * .45, c.dy)
            ..lineTo(c.dx, c.dy + r * 2)
            ..lineTo(c.dx - r * .45, c.dy)
            ..close()
            ..moveTo(c.dx - r * 2, c.dy)
            ..lineTo(c.dx, c.dy + r * .45)
            ..lineTo(c.dx + r * 2, c.dy)
            ..lineTo(c.dx, c.dy - r * .45)
            ..close(),
          glint,
        );
      }
    }
  }

  void _blade(Canvas canvas, double t) {
    // The computer players' blades, in their colours.
    for (final b in game.players) {
      if (b.bot) {
        _ribbon(canvas, _smooth(b.trail), game.time, b.colour, Colors.white, 6);
      }
    }
    _ribbon(canvas, _smooth(trail), t, blade.glow, blade.core, 9);
    final (angle, pop) = knife();
    if (pop > 0 && trail.isNotEmpty) {
      _knife(canvas, trail.last.$1, angle, pop, t);
    }
  }

  /// A chef's knife held at the fingertip, its point leading the stroke.
  void _knife(Canvas canvas, Offset tip, double angle, double pop, double t) {
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    // Pops in with a little overshoot.
    final s = Curves.easeOutBack.transform(pop.clamp(0.0, 1.0));
    canvas.scale(s);
    // Shadow on the board.
    canvas.save();
    canvas.translate(6, 10);
    canvas.drawPath(_bladeShape(), Paint()..color = const Color(0x40000000));
    canvas.restore();
    // Steel blade: bright at the edge, darker at the spine.
    final bladeRect = const Rect.fromLTRB(-78, -15, 8, 7);
    canvas.drawPath(
      _bladeShape(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF8792A3),
            Color(0xFFE9EEF5),
            Color(0xFFFFFFFF),
            Color(0xFFB4BECC),
          ],
          stops: [0, .35, .6, 1],
        ).createShader(bladeRect),
    );
    canvas.drawPath(
      _bladeShape(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF5E6878),
    );
    // The honed edge, catching the light.
    canvas.drawPath(
      Path()
        ..moveTo(4, 1)
        ..quadraticBezierTo(-30, 7, -76, 6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = blade.glow.withValues(alpha: .9),
    );
    // A glint sliding along the steel.
    final g = -70 + ((t * 1.6) % 1) * 80;
    canvas.save();
    canvas.clipPath(_bladeShape());
    canvas.drawRect(
      Rect.fromLTWH(g, -16, 7, 26),
      Paint()..color = const Color(0x99FFFFFF),
    );
    canvas.restore();
    // Bolster and handle with brass rivets.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-84, -13, -76, 7),
        const Radius.circular(2),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFDDE3EA), Color(0xFF8D96A4)],
        ).createShader(const Rect.fromLTRB(-84, -13, -76, 7)),
    );
    final handle = RRect.fromRectAndCorners(
      const Rect.fromLTRB(-128, -11, -84, 5),
      topLeft: const Radius.circular(7),
      bottomLeft: const Radius.circular(7),
    );
    canvas.drawRRect(
      handle,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6B3A1C), Color(0xFF3A1C0A)],
        ).createShader(handle.outerRect),
    );
    canvas.drawLine(
      const Offset(-124, -8),
      const Offset(-87, -8),
      Paint()
        ..strokeWidth = 1.4
        ..color = const Color(0x55FFD9A0),
    );
    for (final x in [-118.0, -106.0, -94.0]) {
      canvas.drawCircle(
        Offset(x, -3),
        2.6,
        Paint()..color = const Color(0xFFB8862B),
      );
      canvas.drawCircle(
        Offset(x - .7, -3.7),
        1,
        Paint()..color = const Color(0xFFFFE6A0),
      );
    }
    canvas.restore();
  }

  /// The blade's outline: a straight spine and a curved edge to the point.
  static Path _bladeShape() => Path()
    ..moveTo(8, 0)
    ..quadraticBezierTo(-10, -12, -40, -15)
    ..lineTo(-78, -15)
    ..lineTo(-78, 7)
    ..quadraticBezierTo(-30, 8, 8, 0)
    ..close();

  /// The bright streak left across a fruit the moment it is cut.
  void _slashes(Canvas canvas) {
    for (final sl in game.slashes) {
      final k = sl.age / Slash.life;
      final len = sl.length * (.6 + .4 * k);
      canvas.save();
      canvas.translate(sl.pos.dx, sl.pos.dy);
      canvas.rotate(sl.angle);
      final r = Rect.fromCenter(
        center: Offset.zero,
        width: len,
        height: 10 * (1 - k) + 1,
      );
      canvas.drawOval(
        r.inflate(6),
        Paint()..color = blade.glow.withValues(alpha: .4 * (1 - k)),
      );
      canvas.drawOval(
        r,
        Paint()..color = Colors.white.withValues(alpha: 1 - k),
      );
      canvas.restore();
    }
  }

  /// A round glass flask of glowing green poison with a skull on it.
  void _poison(Canvas canvas, Flyer f, double t) {
    final r = f.radius;
    canvas.save();
    canvas.translate(f.pos.dx, f.pos.dy);
    canvas.rotate(f.angle * .5);
    final pulse = .5 + .5 * math.sin(t * 8);
    canvas.drawCircle(
      Offset(0, r * .15),
      r * (1.2 + .08 * pulse),
      Paint()..color = Color.fromRGBO(90, 255, 60, .18 + .1 * pulse),
    );
    final body = Rect.fromCircle(center: Offset(0, r * .15), radius: r * .88);
    // Glass with poison inside, sloshing a little.
    canvas.drawCircle(
      body.center,
      body.width / 2,
      Paint()..color = const Color(0x6630203A),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(body));
    final level = body.top + body.height * (.32 + .04 * math.sin(t * 5));
    canvas.drawRect(
      Rect.fromLTRB(body.left, level, body.right, body.bottom),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB6FF5A), Color(0xFF3BC82A), Color(0xFF1A7A1A)],
        ).createShader(body),
    );
    // Bubbles rising.
    for (var i = 0; i < 4; i++) {
      final y = body.bottom - ((t * 40 + i * 23) % body.height * .6);
      canvas.drawCircle(
        Offset(body.left + body.width * (.3 + .15 * i), y),
        r * .05,
        Paint()..color = const Color(0x99E8FFD0),
      );
    }
    canvas.restore();
    canvas.drawCircle(
      body.center,
      body.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .07
        ..color = const Color(0xCCD8F0FF),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * .35, -r * .2),
        width: r * .3,
        height: r * .5,
      ),
      Paint()..color = const Color(0x66FFFFFF),
    );
    // Neck and cork.
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, -r * .82),
        width: r * .38,
        height: r * .3,
      ),
      Paint()..color = const Color(0xCCD8F0FF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -r * 1.02),
          width: r * .44,
          height: r * .26,
        ),
        Radius.circular(r * .06),
      ),
      Paint()..color = const Color(0xFFA0703A),
    );
    // Skull and crossbones.
    final bone = Paint()
      ..color = Colors.white
      ..strokeWidth = r * .1
      ..strokeCap = StrokeCap.round;
    final c = Offset(0, r * .28);
    canvas.drawLine(
      c + Offset(-r * .34, r * .3),
      c + Offset(r * .34, -r * .02),
      bone,
    );
    canvas.drawLine(
      c + Offset(r * .34, r * .3),
      c + Offset(-r * .34, -r * .02),
      bone,
    );
    canvas.drawCircle(c, r * .26, Paint()..color = Colors.white);
    canvas.drawRect(
      Rect.fromCenter(
        center: c + Offset(0, r * .2),
        width: r * .3,
        height: r * .16,
      ),
      Paint()..color = Colors.white,
    );
    final eye = Paint()..color = const Color(0xFF1A3A12);
    canvas.drawCircle(c + Offset(-r * .1, -r * .02), r * .07, eye);
    canvas.drawCircle(c + Offset(r * .1, -r * .02), r * .07, eye);
    canvas.restore();
  }

  void _popup(Canvas canvas, Popup p, double width) {
    final k = p.age / Popup.life;
    final (img, w) = _popupCache[p] ??= () {
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w700,
            fontSize: p.text == 'BOOM!' ? 44 : (p.big ? 26 : 18),
            color:
                p.colour ??
                (p.text.startsWith('POISON')
                    ? const Color(0xFF8CFF4A)
                    : p.text == 'BOOM!'
                    ? const Color(0xFFFF7A1A)
                    : p.text == '✕' || p.text == '-10'
                    ? const Color(0xFFFF4D4D)
                    : const Color(0xFFFFE28A)),
            shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final ratio = pixelRatio.clamp(1.0, 2.5);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(ratio);
      tp.paint(c, const Offset(4, 4));
      final img = rec.endRecording().toImageSync(
        ((tp.width + 8) * ratio).ceil(),
        ((tp.height + 8) * ratio).ceil(),
      );
      return (img, tp.width + 8);
    }();
    final h = w * img.height / img.width;
    // Keep long messages on the screen.
    final double x = p.pos.dx.clamp(
      w / 2 + 4,
      math.max(w / 2 + 4, width - w / 2 - 4),
    );
    final y = p.pos.dy - 40 * k - (p.big ? 30 : 0);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset(x, y), width: w, height: h),
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, (1 - k).clamp(0.0, 1.0))
        ..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_FruitPainter old) => true;
}
