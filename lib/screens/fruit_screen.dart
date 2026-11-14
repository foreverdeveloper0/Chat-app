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
  });

  final FruitMode mode;
  final Blade blade;

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
  String _hudKey = '';

  @override
  void initState() {
    super.initState();
    FruitImages.load();
    _newGame();
    _ticker.start();
  }

  void _newGame() {
    _game = FruitGame(mode: widget.mode);
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
    if (ev.over) _gameOver();
    if (_game.over && !_results) {
      _sinceOver += dt;
      final wait = _game.endedBy == 'bomb' ? 1.4 : .9;
      if (_sinceOver > wait) setState(() => _results = true);
    }
    _trail.removeWhere((p) => _clock - p.$2 > _trailLife);

    // The HUD only rebuilds when something on it changes.
    final key =
        '${_game.score}|${_game.lives}|${_game.timeLeft.ceil()}|'
        '${_game.started}|${_ready > .5}';
    if (key != _hudKey) setState(() => _hudKey = key);
    _frame.value++;
  }

  void _gameOver() {
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
                    Text('BEST ${math.max(best, g.score)}', style: _small),
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
                () => setState(_newGame),
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
    final title = switch (g.endedBy) {
      'bomb' => 'BOOM!',
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
                    () => setState(_newGame),
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
    required Listenable repaint,
  }) : super(repaint: repaint);

  final FruitGame game;
  final List<(Offset, double)> trail;
  final Blade blade;
  final double Function() clock, shake;
  final bool Function() touching;

  @override
  void paint(Canvas canvas, Size size) {
    final g = game, t = clock(), s = shake();
    canvas.save();
    if (s > 0) {
      canvas.translate(math.sin(t * 80) * s * 8, math.cos(t * 65) * s * 6);
    }
    // Juice stains soaking into the board.
    for (final st in g.stains) {
      final a = (1 - st.age / Stain.life).clamp(0.0, 1.0) * .55;
      final paint = Paint()..color = st.colour.withValues(alpha: a);
      final rnd = math.Random(st.seed);
      canvas.drawCircle(st.pos, st.size * .55, paint);
      for (var i = 0; i < 7; i++) {
        final ang = rnd.nextDouble() * math.pi * 2;
        final d = st.size * (.4 + rnd.nextDouble() * .6);
        canvas.drawCircle(
          st.pos + Offset(math.cos(ang), math.sin(ang)) * d,
          st.size * (.08 + rnd.nextDouble() * .16),
          paint,
        );
      }
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
      _image(canvas, img, hf.pos, hf.size * .95, hf.angle, null);
    }
    for (final f in g.flyers) {
      if (f.bomb) {
        _bomb(canvas, f, t);
      } else {
        final img = FruitImages.of(f.kind, 'w');
        _image(
          canvas,
          img,
          f.pos,
          f.radius * 2.15,
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
    _blade(canvas, t);
    for (final p in g.popups) {
      _popup(canvas, p, size.width);
    }
    canvas.restore();
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

  void _blade(Canvas canvas, double t) {
    if (trail.length >= 2) {
      final glow = Paint()..strokeCap = StrokeCap.round;
      final core = Paint()..strokeCap = StrokeCap.round;
      for (var i = 1; i < trail.length; i++) {
        final (a, ta) = trail[i - 1];
        final (b, _) = trail[i];
        final fresh = (1 - (t - ta) / _trailLife).clamp(0.0, 1.0);
        final k = (i / trail.length) * fresh;
        glow
          ..strokeWidth = 4 + 18 * k
          ..color = blade.glow.withValues(alpha: .35 * fresh);
        core
          ..strokeWidth = 2 + 7 * k
          ..color = blade.core.withValues(alpha: fresh);
        canvas.drawLine(a, b, glow);
        canvas.drawLine(a, b, core);
      }
    }
    // The knife itself at the fingertip, pointing along the stroke.
    if (touching() && trail.isNotEmpty) {
      final tip = trail.last.$1;
      var dir = const Offset(1, -1);
      if (trail.length >= 2) {
        final d = tip - trail[trail.length - 2].$1;
        if (d.distance > 1) dir = d;
      }
      final ang = math.atan2(dir.dy, dir.dx);
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(ang);
      canvas.scale(1.6);
      // Blade (pointing forward) and handle behind.
      final bladePath = Path()
        ..moveTo(16, 0)
        ..lineTo(-22, -7)
        ..lineTo(-26, -7)
        ..lineTo(-26, 4)
        ..lineTo(-22, 4)
        ..close();
      canvas.drawPath(
        bladePath,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFB8C2D0), Color(0xFF6E7888)],
          ).createShader(const Rect.fromLTRB(-26, -7, 16, 4)),
      );
      canvas.drawPath(
        bladePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = blade.glow,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(-50, -5, -26, 5),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFF5A2E12),
      );
      for (final x in [-44.0, -36.0]) {
        canvas.drawCircle(
          Offset(x, 0),
          1.6,
          Paint()..color = const Color(0xFFE3B341),
        );
      }
      canvas.restore();
    }
  }

  void _popup(Canvas canvas, Popup p, double width) {
    final k = p.age / Popup.life;
    final tp = TextPainter(
      text: TextSpan(
        text: p.text,
        style: TextStyle(
          fontFamily: AppText.family,
          fontWeight: FontWeight.w700,
          fontSize: p.big ? 26 : 18,
          color:
              (p.text == '✕' || p.text == '-10'
                      ? const Color(0xFFFF4D4D)
                      : const Color(0xFFFFE28A))
                  .withValues(alpha: 1 - k),
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: .7 * (1 - k)),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Keep long messages on the screen.
    final x = p.pos.dx.clamp(
      tp.width / 2 + 8,
      math.max(tp.width / 2 + 8, width - tp.width / 2 - 8),
    );
    tp.paint(
      canvas,
      Offset(
        x - tp.width / 2,
        p.pos.dy - tp.height / 2 - 40 * k - (p.big ? 30 : 0),
      ),
    );
  }

  @override
  bool shouldRepaint(_FruitPainter old) => true;
}
