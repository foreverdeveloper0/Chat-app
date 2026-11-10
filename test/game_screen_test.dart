import 'dart:io';

import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
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

    await tester.tap(find.text('Pass &\nPlay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('2 Players'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    expect(find.text('Tap to roll'), findsOneWidget);

    // Play both seats: roll when asked, and when there is a real choice tap
    // every piece (only a movable one reacts).
    var rolls = 0;
    for (var i = 0; i < 3000 && rolls < 60; i++) {
      final roll = find.text('Tap to roll');
      if (roll.evaluate().isNotEmpty) {
        await tester.tap(roll);
        rolls++;
      } else if (find.text('Pick a piece').evaluate().isNotEmpty) {
        for (var k = 0; k < 16; k++) {
          final piece = find.byKey(ValueKey(k));
          if (piece.evaluate().isNotEmpty) {
            await tester.tap(piece, warnIfMissed: false);
          }
        }
      }
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(rolls, 60);
    expect(tester.takeException(), isNull);

    // Tear down so pending game timers end with the disposed controller.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
