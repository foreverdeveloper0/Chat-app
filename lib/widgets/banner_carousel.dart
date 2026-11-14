import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../art/pieces.dart';
import '../art/snl_art.dart';
import '../game/catalog.dart';
import '../game/ludo_controller.dart';
import '../game/ludo_rules.dart';
import '../game/snl_controller.dart';
import '../theme/app_colors.dart';
import '../theme/board_assets.dart';

/// Width / height of the banner artwork.
const bannerAspect = 1672 / 941;

/// What the home page shows of it: a short strip, the artwork trimmed a
/// little top and bottom (the live panel keeps its place on the full size).
const bannerShown = 2.7;

/// Where the empty slanted panel sits inside every banner, measured on the
/// artwork as fractions of its size. The panel is a parallelogram whose
/// sides lean left by [_slant] of the width per unit of height.
class BannerPanel {
  BannerPanel(this.size);
  final Size size;

  static const _top = .098, _bottom = .833;
  static const _left = .583, _right = .9835, _slant = .097;

  double get _w => size.width;
  double get _h => size.height;

  /// Horizontal shift per pixel of height.
  double get _shear => -_slant * _w / _h;

  double _xLeft(double y) => (_left - _slant * y / _h) * _w;
  double _xRight(double y) => (_right - _slant * y / _h) * _w;

  Offset get centre {
    final y = (_top + _bottom) / 2 * _h;
    return Offset((_xLeft(y) + _xRight(y)) / 2, y);
  }

  double get width => (_right - _left) * _w;
  double get height => (_bottom - _top) * _h;

  /// Edge of the largest square that fits, leaving the glow border clear.
  double get edge => math.min(width, height) - _w * .026;

  Offset get _origin {
    final c = centre, e = edge;
    return Offset(c.dx - e / 2 - _shear * e / 2, c.dy - e / 2);
  }

  /// Maps a point of the [edge] x [edge] square onto the slanted panel.
  Offset map(Offset p) {
    final o = _origin;
    return Offset(o.dx + p.dx + _shear * p.dy, o.dy + p.dy);
  }

  /// The same mapping as a transform for widgets drawn in the square.
  Matrix4 get matrix {
    final o = _origin;
    return Matrix4(
      1,
      0,
      0,
      0, //
      _shear,
      1,
      0,
      0, //
      0,
      0,
      1,
      0, //
      o.dx,
      o.dy,
      0,
      1,
    );
  }

  /// The panel's inside, with rounded corners, for clipping.
  Path get clip {
    final inset = _w * .012;
    final t = _top * _h + inset, b = _bottom * _h - inset;
    final pts = [
      Offset(_xLeft(t) + inset, t),
      Offset(_xRight(t) - inset, t),
      Offset(_xRight(b) - inset, b),
      Offset(_xLeft(b) + inset, b),
    ];
    final r = _w * .04;
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final p = pts[i], prev = pts[(i + 3) % 4], next = pts[(i + 1) % 4];
      final a = p + (prev - p) / (prev - p).distance * r;
      final c = p + (next - p) / (next - p).distance * r;
      i == 0 ? path.moveTo(a.dx, a.dy) : path.lineTo(a.dx, a.dy);
      path.quadraticBezierTo(p.dx, p.dy, c.dx, c.dy);
    }
    return path..close();
  }
}

/// The hero: every game's banner in an endless auto-sliding carousel, with
/// something alive in each banner's panel — a Ludo match, a Snake run, or
/// the logo of a game that is still on its way.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key, required this.onGame});
  final ValueChanged<GameInfo> onGame;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  static const _dwell = Duration(seconds: 5);
  static const _loop = 1000; // pages before and after, so it never ends

  late final _pages = PageController(initialPage: games.length * _loop);
  late LudoController _ludo = _newLudoMatch();
  Timer? _timer;
  int _page = 0;
  bool _visible = true;
  bool _precached = false;

  /// A match already under way, so the banner is lively from the start.
  static LudoController _newLudoMatch() {
    final rng = math.Random();
    final game = LudoController(
      seats: const [3, 0, 1, 2],
      bots: const {0, 1, 2, 3},
      haptics: false,
      speed: .8,
      random: rng,
    );
    for (final p in game.seats) {
      game.tokens[p][0].progress = 4 + rng.nextInt(40);
      game.tokens[p][1].progress = rng.nextInt(26);
      if (rng.nextBool()) game.tokens[p][2].progress = 51 + rng.nextInt(5);
    }
    return game;
  }

  @override
  void initState() {
    super.initState();
    _ludo
      ..addListener(_onLudo)
      ..start();
    _restartTimer();
  }

  void _onLudo() {
    if (!mounted) return;
    if (_ludo.phase == Phase.gameOver) {
      // The demo match is over: deal a new one.
      final old = _ludo..removeListener(_onLudo);
      Future.microtask(old.dispose);
      _ludo = _newLudoMatch()..addListener(_onLudo);
      _syncLudo();
      _ludo.start();
    }
    if (_showsLudo) setState(() {});
  }

  bool get _showsLudo => games[_page % games.length].key == 'ludo';

  void _syncLudo() => _ludo.paused = !(_visible && _showsLudo);

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_dwell, (_) {
      if (!mounted || !_visible || !_pages.hasClients) return;
      _pages.nextPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold everything still while another page covers the home page.
    _visible = TickerMode.valuesOf(context).enabled;
    _syncLudo();
    if (!_precached) {
      _precached = true;
      // Decode every banner up front so a slide never arrives blank.
      for (final g in games) {
        precacheImage(AssetImage(g.banner), context);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    _ludo
      ..removeListener(_onLudo)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: bannerShown,
          child: Container(
            padding: const EdgeInsets.all(1.6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFF1B8),
                  Color(0xFFB8862B),
                  Color(0xFF3A66F5),
                  Color(0xFFEBCB7A),
                ],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x667B3FE4), blurRadius: 22),
                BoxShadow(
                  color: Color(0x99020310),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.4),
              // A touch keeps the banner where it is; sliding resumes after.
              child: Listener(
                onPointerDown: (_) => _timer?.cancel(),
                onPointerUp: (_) => _restartTimer(),
                onPointerCancel: (_) => _restartTimer(),
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: (i) {
                    setState(() => _page = i % games.length);
                    _syncLudo();
                  },
                  itemBuilder: (context, i) {
                    final game = games[i % games.length];
                    return GestureDetector(
                      key: ValueKey('banner-${game.key}'),
                      onTap: () => widget.onGame(game),
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final h = box.maxWidth / bannerAspect;
                          return ClipRect(
                            child: OverflowBox(
                              minHeight: h,
                              maxHeight: h,
                              alignment: const Alignment(0, -.5),
                              child: SizedBox(
                                width: box.maxWidth,
                                height: h,
                                child: _Slide(game: game, ludo: _ludo),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < games.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _page
                      ? AppColors.goldSoft
                      : const Color(0xFF3A4BA8),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.game, required this.ludo});
  final GameInfo game;
  final LudoController ludo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final panel = BannerPanel(box.biggest);
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              game.banner,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
            switch (game.key) {
              'ludo' => _LudoLive(panel: panel, game: ludo),
              'snake' => _SnakeLive(panel: panel),
              _ => _LogoLive(panel: panel, game: game),
            },
          ],
        );
      },
    );
  }
}

// ───────────────────────── Ludo, live ─────────────────────────

/// The demo match shown on the Ludo banner: the real board laid onto the
/// slanted panel, real pawns standing on it, and the dice beside it.
class _LudoLive extends StatelessWidget {
  const _LudoLive({required this.panel, required this.game});
  final BannerPanel panel;
  final LudoController game;

  @override
  Widget build(BuildContext context) {
    final b = panel.edge;
    final cell = b * gridSize / 15;
    Offset spot(Offset cells) => panel.map(
      Offset(
        (gridInset + gridSize * cells.dx / 15) * b,
        (gridInset + gridSize * cells.dy / 15) * b,
      ),
    );

    // Lay the pawns out, nudging those that share a square apart.
    final sharing = <Offset, int>{};
    final placed = <(Token, Offset)>[];
    for (final p in game.seats) {
      for (final t in game.tokens[p]) {
        var cells = LudoRules.position(t.player, t.index, t.progress);
        if (t.progress >= 0 && !t.isHome) {
          final n = sharing.update(cells, (v) => v + 1, ifAbsent: () => 0);
          cells += Offset(n * .4 - (n > 0 ? .2 : 0), 0);
        }
        placed.add((t, spot(cells)));
      }
    }
    placed.sort((a, b) => a.$2.dy.compareTo(b.$2.dy));

    // Drawn a little oversized so the pieces read at banner size.
    final pw = cell * 1.3, ph = pw / pawnAspect;
    final corner = panel.map(Offset(b * .96, b * .9));
    final dice = b * .3;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: Transform(
            transform: panel.matrix,
            child: Image.asset(
              boardAsset,
              width: b,
              height: b,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        for (final (t, foot) in placed)
          AnimatedPositioned(
            key: ValueKey(t.player * 4 + t.index),
            duration: Duration(milliseconds: t.inYard ? 420 : 150),
            curve: Curves.easeOut,
            left: foot.dx - pw / 2,
            top: foot.dy - ph * .9,
            width: pw,
            height: ph,
            child: _HopPawn(player: t.player, progress: t.progress),
          ),
        Positioned(
          left: corner.dx - dice * .55,
          top: corner.dy - dice * .5,
          child: _DemoDice(
            value: game.dice,
            phase: game.phase,
            color: playerColors[game.current],
            size: dice,
          ),
        ),
      ],
    );
  }
}

/// A pawn that hops each time it advances a square.
class _HopPawn extends StatefulWidget {
  const _HopPawn({required this.player, required this.progress});
  final int player;
  final int progress;

  @override
  State<_HopPawn> createState() => _HopPawnState();
}

class _HopPawnState extends State<_HopPawn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 165),
  );

  @override
  void didUpdateWidget(_HopPawn old) {
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
    return AnimatedBuilder(
      animation: _hop,
      child: Image.asset(
        pawnAssets[widget.player],
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      ),
      builder: (context, child) {
        final h = math.sin(_hop.value * math.pi);
        return FractionalTranslation(
          translation: Offset(0, -h * .32),
          child: Transform.scale(scale: 1 + h * .14, child: child),
        );
      },
    );
  }
}

/// The demo's dice: tossed up, tumbling as a real cube, landing with a
/// bounce on the rolled face, exactly like the dice in a match.
class _DemoDice extends StatefulWidget {
  const _DemoDice({
    required this.value,
    required this.phase,
    required this.color,
    required this.size,
  });
  final int value;
  final Phase phase;
  final Color color;
  final double size;

  @override
  State<_DemoDice> createState() => _DemoDiceState();
}

class _DemoDiceState extends State<_DemoDice>
    with SingleTickerProviderStateMixin {
  static const _airMs = LudoController.rollTicks * LudoController.rollTickMs;
  static const _totalMs = _airMs + LudoController.landMs;
  static const _air = _airMs / _totalMs;

  late final AnimationController _toss = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
    value: 1,
  );

  @override
  void didUpdateWidget(_DemoDice old) {
    super.didUpdateWidget(old);
    if (widget.phase == Phase.rolling && old.phase != Phase.rolling) {
      _toss.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _toss.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _toss,
      builder: (_, _) {
        final t = _toss.value;
        final flying = t < _air;
        final a = flying ? t / _air : 1.0;
        final l = flying ? 0.0 : (t - _air) / (1 - _air);
        final arc = 4 * a * (1 - a);
        final rebound = flying ? 0.0 : math.sin(l * math.pi) * (1 - l) * .2;
        final lift = (flying ? arc : rebound) * size * .9;
        final left = math.pow(1 - a, 1.6).toDouble();
        final squash = flying
            ? 0.0
            : math.sin(l * math.pi * 2.5) * (1 - l) * .18;
        return SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Coloured glow on the ground; it tightens as the dice rises.
              Transform.scale(
                scale: 1 - arc * .35,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: size * .9,
                  height: size * .9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: .8),
                        blurRadius: size * .4,
                      ),
                    ],
                  ),
                ),
              ),
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(0, -lift, 0, 1)
                  ..scaleByDouble(
                    (1 + arc * .3) * (1 + squash),
                    (1 + arc * .3) * (1 - squash),
                    1,
                    1,
                  ),
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _DicePainter(
                    widget.value,
                    rx: left * 4 * math.pi,
                    ry: left * 3 * math.pi,
                    rz: left * math.pi,
                  ),
                ),
              ),
            ],
          ),
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
      paintDice(canvas, Offset.zero & size, value, angle: -.14);
    } else {
      paintDice3D(
        canvas,
        size.center(Offset(0, -size.height * .04)),
        size.width * .78,
        value,
        rx: rx,
        ry: ry,
        rz: rz,
      );
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) =>
      old.value != value || old.rx != rx || old.ry != ry || old.rz != rz;
}

// ───────────────────────── Snakes & Ladders, live ─────────────────────────

/// Four bots racing up the Snakes & Ladders board on the Snake banner.
class _SnakeLive extends StatefulWidget {
  const _SnakeLive({required this.panel});
  final BannerPanel panel;

  @override
  State<_SnakeLive> createState() => _SnakeLiveState();
}

class _SnakeLiveState extends State<_SnakeLive> {
  late SnlController _game;

  @override
  void initState() {
    super.initState();
    _deal();
  }

  void _deal() {
    final rng = math.Random();
    _game = SnlController(
      seats: const [3, 0, 1, 2],
      bots: const {0, 1, 2, 3},
      haptics: false,
      speed: .7,
      random: rng,
    );
    // A race already under way.
    for (final p in _game.seats) {
      _game.position[p] = 6 + rng.nextInt(60);
    }
    _game
      ..addListener(_onChange)
      ..start();
  }

  void _onChange() {
    if (!mounted) return;
    if (_game.phase == Phase.gameOver) {
      final old = _game..removeListener(_onChange);
      Future.microtask(old.dispose);
      _deal();
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game.paused = !TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    _game
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final b = panel.edge;
    // The tall board stands centred in the panel's square.
    final size = Size(b * snlAspect, b);
    final inset = Offset((b - size.width) / 2, 0);
    final g = SnlGeometry(size);
    final pw = g.cellW * 1.15, ph = pw / pawnAspect;
    final slide = _game.slide;
    Offset foot(int square) =>
        panel.map(inset + g.centre(square) + Offset(0, g.cellH * .3));
    final corner = panel.map(Offset(b * .93, b * .9));
    final dice = b * .28;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: Transform(
            transform: panel.matrix,
            child: Padding(
              padding: EdgeInsets.only(left: inset.dx),
              child: RepaintBoundary(
                child: SnlBoardView(layout: _game.layout, size: size),
              ),
            ),
          ),
        ),
        for (final p in _game.seats)
          () {
            // While riding, glide to the far end of the ladder or snake.
            final riding = slide?.player == p;
            final at =
                foot(riding ? slide!.to : _game.position[p]!) +
                Offset((p - 1.5) * g.cellW * .14, 0);
            return AnimatedPositioned(
              key: ValueKey(p),
              duration: Duration(milliseconds: riding ? 600 : 150),
              curve: riding ? Curves.easeInOut : Curves.easeOut,
              left: at.dx - pw / 2,
              top: at.dy - ph * .92,
              width: pw,
              height: ph,
              child: Image.asset(
                pawnAssets[p],
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            );
          }(),
        Positioned(
          left: corner.dx - dice * .5,
          top: corner.dy - dice * .5,
          child: _DemoDice(
            value: _game.dice,
            phase: _game.phase,
            color: playerColors[_game.current],
            size: dice,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Coming soon ─────────────────────────

/// For games that are not built yet: the logo bobbing in the panel.
class _LogoLive extends StatefulWidget {
  const _LogoLive({required this.panel, required this.game});
  final BannerPanel panel;
  final GameInfo game;

  @override
  State<_LogoLive> createState() => _LogoLiveState();
}

class _LogoLiveState extends State<_LogoLive>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final w = panel.width * .86;
    final c = panel.centre;
    return Stack(
      children: [
        Positioned(
          left: c.dx - w / 2,
          top: c.dy - panel.height * .44,
          width: w,
          height: panel.height * .88,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              final wave = math.sin(_c.value * 2 * math.pi);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: Offset(0, wave * 3),
                    child: Transform.rotate(angle: wave * .025, child: child),
                  ),
                  SizedBox(height: panel.height * .05),
                  Opacity(
                    opacity: .75 + .25 * wave.abs(),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: w * .09,
                        vertical: w * .022,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(w * .1),
                        color: const Color(0xD9050818),
                        border: Border.all(color: AppColors.goldSoft, width: 1),
                      ),
                      child: Text(
                        widget.game.ready ? 'PLAY NOW' : 'COMING SOON',
                        style: AppText.title.copyWith(
                          fontSize: w * .085,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: AppColors.goldSoft,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
            child: Image.asset(
              widget.game.logo,
              width: w,
              height: panel.height * .6,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ],
    );
  }
}
