import 'dart:io';

import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/game/ludo_controller.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/game_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

  testWidgets('Pass & Play opens a match and the dice can be rolled',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();

    await tester.tap(find.text('PLAY NOW'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Pass & Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('2 Players'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Board intro, then the "GAME START" banner.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    expect(find.text('2K'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('GAME START'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 100));
    final game = GameScreen.debugController!;
    expect(game.phase, Phase.awaitingRoll);
    expect(find.textContaining('tap the dice'), findsNothing);

    // Tapping a picture opens that player's profile.
    await tester.tap(find.text('Player 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Player profile'), findsOneWidget);
    expect(find.text('UID'), findsOneWidget);
    await tester.tapAt(const Offset(180, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Play both seats through the real widgets: tap the dock of whoever is
    // on turn to roll, and tap a movable piece when there is a choice.
    for (var i = 0; i < 3000 && game.rollTick < 60; i++) {
      if (game.phase == Phase.awaitingRoll) {
        await tester.tap(find.byKey(ValueKey('panel-${game.current}')),
            warnIfMissed: false);
      } else if (game.phase == Phase.choosing && game.movable.isNotEmpty) {
        final t = game.movable.first;
        await tester.tap(find.byKey(ValueKey('token-${t.player * 4 + t.index}')),
            warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(game.rollTick, 60);
    expect(tester.takeException(), isNull);

    // Tear down so pending game timers end with the disposed controller.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
