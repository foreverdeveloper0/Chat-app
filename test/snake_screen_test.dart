import 'dart:io';

import 'package:elite_play_ludo/game/snake_game.dart';
import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/snake_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    Sounds.enabled = false;
    SharedPreferences.setMockInitialValues({});
    final loader = FontLoader('Fredoka');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/Fredoka-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  testWidgets('Snake opens from its tile and plays to a crash and back',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();

    final tile = find.byKey(const ValueKey('game-snake'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('SPEED'), findsOneWidget);
    expect(find.text('ARENA'), findsOneWidget);
    expect(find.text('Best: 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('snake-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final game = SnakeScreen.debugGame!;
    expect(game.steps, 0);
    expect(find.byKey(const ValueKey('countdown')), findsOneWidget);

    // Countdown, then the snake sets off to the right on its own.
    await frames(70);
    expect(find.byKey(const ValueKey('countdown')), findsNothing);
    expect(game.steps, greaterThan(0));
    expect(game.dir, SnakeDir.right);

    // Steer with the pad...
    await tester.tap(find.byKey(const ValueKey('pad-up')));
    await frames(6);
    expect(game.dir, SnakeDir.up);

    // ...pause and resume...
    final stepsAtPause = game.steps;
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await frames(10);
    expect(find.text('Paused'), findsOneWidget);
    expect(game.steps, stepsAtPause);
    await tester.tap(find.text('Resume'));
    await frames(2);

    // ...then straight up into the wall.
    game.food = const Cell(0, 14); // keep fruit out of the way
    for (var i = 0; i < 200 && game.alive; i++) {
      await frames(1);
    }
    expect(game.alive, isFalse);
    expect(game.head.y, 0);
    await frames(30);
    expect(find.text('Game Over'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Play again'));
    await frames(2);
    expect(game.alive, isTrue);
    expect(game.steps, 0);
    expect(game.length, 3);

    // Tear down so the home demo's timers end with their controllers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
