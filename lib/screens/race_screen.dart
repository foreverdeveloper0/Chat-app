import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../art/race_art.dart';
import '../game/race_game.dart';
import '../game/sounds.dart';
import '../theme/app_colors.dart';
import '../widgets/game_hud.dart';

const _rivalNames = ['Blaze', 'Turbo', 'Viper'];

/// Dev aid: `--dart-define=LUDO_AUTOPLAY=true` drives the player's car too.
const _autoplay = bool.fromEnvironment('LUDO_AUTOPLAY');

/// The car race: the player against up to three computer cars.
class RaceScreen extends StatefulWidget {
  const RaceScreen({
    super.key,
    this.opponents = 3,
    this.laps = 3,
    required this.entry,
    required this.roomId,
    this.autopilot = _autoplay,
  });

  final int opponents, laps, entry;
  final String roomId;
  final bool autopilot;

  @visibleForTesting
  static RaceGame? debugGame;

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen>
    with SingleTickerProviderStateMixin {
  late RaceGame _game;
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier(0);
  final _input = RaceInput();
  final _focus = FocusNode();
  Duration _last = Duration.zero;
  double _clock = 0, _sky = 0, _shake = 0, _camX = 0;

  /// Seconds until the lights go green; negative once racing.
  double _countdown = 3.5;
  int _lastCount = 4;
  double _sinceFinish = 0;
  bool _results = false;
  String? _flash;
  double _flashT = 0;

  Map<int, String> get _names => {
    0: 'You',
    for (var i = 1; i <= widget.opponents; i++) i: _rivalNames[i - 1],
  };

  @override
  void initState() {
    super.initState();
    _newRace();
    RaceSprites.load();
    _ticker.start();
  }

  void _newRace() {
    _game = RaceGame(opponents: widget.opponents, laps: widget.laps);
    RaceScreen.debugGame = _game;
    _countdown = 3.5;
    _lastCount = 4;
    _sinceFinish = 0;
    _results = false;
    _flash = null;
    _shake = 0;
    _camX = _game.player.x;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = math.min(1 / 20, (now - _last).inMicroseconds / 1e6);
    _last = now;
    if (dt <= 0) return;
    _clock += dt;
    _shake = math.max(0, _shake - dt * 2.5);
    _flashT = math.max(0, _flashT - dt);

    if (!_game.started) {
      _countdown -= dt;
      final c = _countdown.ceil();
      if (c < _lastCount && c >= 1 && c <= 3) {
        Sounds.play(Sfx.diceLand);
        HapticFeedback.selectionClick();
      }
      _lastCount = c;
      if (_countdown <= 0) {
        _game.started = true;
        _flash = 'GO!';
        _flashT = 1;
        Sounds.play(Sfx.start);
      }
    }

    final input = widget.autopilot || _game.over ? _game.autopilot() : _input;
    if (_game.over) input.nitro = false;
    final ev = _game.update(dt, input);
    final p = _game.player;
    // The camera glides after the car instead of being bolted to it.
    _camX += (p.x - _camX) * (1 - math.exp(-5 * dt));
    _sky +=
        _game.segmentAt(p.z).curve * (p.speed / RaceGame.maxSpeed) * dt * .4;

    if (ev.crash) {
      _shake = 1;
      Sounds.play(Sfx.crash);
      HapticFeedback.heavyImpact();
    } else if (ev.bump) {
      _shake = math.max(_shake, .4);
      Sounds.play(Sfx.hit);
      HapticFeedback.lightImpact();
    }
    if (ev.finished) {
      final pos = _game.positionOf(p);
      _flash = pos == 1 ? 'WINNER!' : 'FINISH  P$pos';
      _flashT = 2.5;
      Sounds.play(pos == 1 ? Sfx.win : Sfx.rank);
    } else if (ev.lap) {
      _flash = p.lap == widget.laps - 1 ? 'FINAL LAP' : 'LAP ${p.lap + 1}';
      _flashT = 1.6;
      Sounds.play(Sfx.bonus);
    }
    if (_game.over && !_results) {
      _sinceFinish += dt;
      if (_sinceFinish > 2.6) setState(() => _results = true);
    }
    _frame.value++;
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    final down = e is! KeyUpEvent;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _input.left = down;
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.keyD) {
      _input.right = down;
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.keyS ||
        k == LogicalKeyboardKey.space) {
      _input.brake = down;
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.shiftLeft ||
        k == LogicalKeyboardKey.keyW) {
      _input.nitro = down;
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final standings = _game.standings;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: RaceScenePainter(
                  game: _game,
                  skyOffset: () => _sky,
                  cameraX: () => _camX,
                  time: () => _clock,
                  shake: () => _shake,
                  repaint: _frame,
                ),
              ),
            ),
            SafeArea(
              child: ValueListenableBuilder(
                valueListenable: _frame,
                builder: (context, _, _) => _hud(),
              ),
            ),
            SafeArea(child: _controls()),
            if (_results)
              ResultOverlay(
                order: [for (final r in standings) r.id],
                left: const {},
                names: _names,
                prize: widget.entry * (widget.opponents + 1),
                onAgain: () => setState(_newRace),
                onHome: () => Navigator.of(context).pop(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hud() {
    final g = _game, p = g.player;
    final pos = g.positionOf(p);
    final lap = (p.lap + 1).clamp(1, widget.laps);
    final kmh = (p.speed / RaceGame.maxSpeed * 240).round();
    final t = g.time;
    String clock(double s) =>
        '${(s ~/ 60)}:${(s % 60).floor().toString().padLeft(2, '0')}.${((s * 10) % 10).floor()}';
    return Stack(
      children: [
        // Keep the HUD full-screen even when nothing else fills it.
        const SizedBox.expand(),
        Padding(
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('POS', style: _small),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$pos', style: _big),
                          TextSpan(
                            text: '/${g.racers.length}',
                            style: _big.copyWith(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _panel(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LAP', style: _small),
                    Text(
                      '$lap/${widget.laps}',
                      style: _big.copyWith(fontSize: 24),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _panel(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TIME', style: _small),
                    Text(clock(t), style: _big.copyWith(fontSize: 20)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Standings down the left.
        Positioned(
          left: 10,
          top: 84,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, r) in g.standings.indexed)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: r.isPlayer
                        ? const Color(0xCC2A1F7A)
                        : const Color(0x99000000),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: r.isPlayer
                          ? AppColors.goldSoft
                          : const Color(0x33FFFFFF),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${i + 1}',
                        style: _small.copyWith(
                          color: AppColors.goldSoft,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: carColours[r.colour % carColours.length].$1,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _names[r.id]!,
                        style: _small.copyWith(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      if (r.finishTime != null) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.flag_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Speed and nitro, centre bottom above the pedals.
        Positioned(
          right: 10,
          top: 76,
          child: Align(
            alignment: Alignment.topRight,
            child: _panel(
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$kmh',
                    key: const ValueKey('speed'),
                    style: _big.copyWith(
                      fontSize: 30,
                      color: p.boosting
                          ? const Color(0xFF7FD8FF)
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('km/h', style: _small),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NITRO', style: _small.copyWith(fontSize: 10)),
                      const SizedBox(height: 3),
                      Container(
                        width: 90,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0x55000000),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0x55FFFFFF)),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: g.nitro.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2E7BFF), Color(0xFF7FD8FF)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!g.started) Center(child: _lights()),
        if (g.started && _flash != null && _flashT > 0)
          Align(
            alignment: const Alignment(0, -.35),
            child: Opacity(
              opacity: _flashT.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1 + (1 - _flashT.clamp(0.0, 1.0)) * .3,
                child: _bigWord(_flash!),
              ),
            ),
          ),
      ],
    );
  }

  Widget _lights() {
    final c = _countdown.ceil().clamp(1, 3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xEE15151C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.goldTrim, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 3; i >= 1; i--)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c <= i && _countdown < 3
                        ? const Color(0xFFFF3030)
                        : const Color(0xFF3A1010),
                    boxShadow: [
                      if (c <= i && _countdown < 3)
                        const BoxShadow(
                          color: Color(0xAAFF3030),
                          blurRadius: 16,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _bigWord(_countdown < 3 ? '$c' : 'GET READY'),
      ],
    );
  }

  Widget _bigWord(String s) => Stack(
    children: [
      Text(
        s,
        style: _big.copyWith(
          fontSize: 54,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..color = const Color(0xFF2A1F7A),
        ),
      ),
      Text(
        s,
        style: _big.copyWith(fontSize: 54, color: const Color(0xFFFFE28A)),
      ),
    ],
  );

  Widget _controls() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _Pedal('left', 78, (v) => _input.left = v),
            const SizedBox(width: 10),
            _Pedal('right', 78, (v) => _input.right = v),
            const Spacer(),
            _Pedal('nitro', 68, (v) => _input.nitro = v, 'NITRO'),
            const SizedBox(width: 8),
            _Pedal('brake', 84, (v) => _input.brake = v, 'BRAKE'),
          ],
        ),
      ),
    );
  }

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

/// A round control that is held down: steering, brake or nitro.
class _Pedal extends StatefulWidget {
  _Pedal(this.name, this.size, this.onHold, [this.label])
    : super(key: ValueKey(name));
  final String? label;
  final String name;
  final double size;
  final void Function(bool) onHold;

  @override
  State<_Pedal> createState() => _PedalState();
}

class _PedalState extends State<_Pedal> {
  bool _down = false;

  void _set(bool v) {
    widget.onHold(v);
    if (mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? .9 : 1,
        duration: const Duration(milliseconds: 70),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x77000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Image.asset(
                'assets/images/race/btn_${widget.name}.png',
                width: widget.size,
                height: widget.size,
                opacity: AlwaysStoppedAnimation(_down ? 1 : .93),
              ),
              if (widget.label != null)
                Positioned(
                  bottom: -15,
                  child: Text(
                    widget.label!,
                    style: const TextStyle(
                      fontFamily: AppText.family,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 1,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
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
