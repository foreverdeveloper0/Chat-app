import 'dart:io';

import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/fruit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    Sounds.enabled = false;
    final loader = FontLoader('Fredoka');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/Fredoka-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  testWidgets('Fruit Cut: swipe a fruit, pause, cut a bomb', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();
    final tile = find.byKey(const ValueKey('game-fruit'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('blade-fire')));
    await tester.pump();
    await tester.tap(find.text('Classic'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final game = FruitScreen.debugGame!;
    expect(find.text('READY?'), findsWidgets);
    // Frames are capped at 1/30 s, so pump in small steps.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 34));
    }
    expect(game.started, isTrue);
    game.flyers.clear();

    // A watermelon hanging in the middle of the board.
    final mid = Offset(game.size.width / 2, game.size.height / 2);
    final f = game.launch(23, x: mid.dx, apex: mid.dy)
      ..pos = mid
      ..vel = Offset.zero;
    final swipe = await tester.startGesture(mid - const Offset(120, 0));
    for (var i = 1; i <= 8; i++) {
      await swipe.moveTo(f.pos - const Offset(120, 0) + Offset(30.0 * i, 0));
    }
    await swipe.up();
    await tester.pump();
    expect(game.cut, 1);
    expect(game.halves.length, 2);
    expect(find.byKey(const ValueKey('score')), findsOneWidget);

    // Pause stops the game.
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    final frozen = game.time;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.time, frozen);
    await tester.tap(find.text('RESUME'));
    await tester.pump();

    // A bomb ends a classic game, and the results follow.
    game.flyers.clear();
    final b = game.launch(-1, x: mid.dx, apex: mid.dy)
      ..pos = mid
      ..vel = Offset.zero;
    final cut = await tester.startGesture(b.pos - const Offset(100, 0));
    for (var i = 1; i <= 8; i++) {
      await cut.moveTo(b.pos - const Offset(100, 0) + Offset(25.0 * i, 0));
    }
    await cut.up();
    expect(game.over, isTrue);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 34));
    }
    expect(find.text('BOOM!'), findsOneWidget);
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
