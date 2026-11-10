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
    // Board intro, then the "GAME START" banner.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    expect(find.textContaining('Prize 2K'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('GAME START'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('tap the dice'), findsOneWidget);

    // Play both seats: roll when asked, and when there is a real choice tap
    // every piece (only a movable one reacts).
    var rolls = 0;
    for (var i = 0; i < 3000 && rolls < 60; i++) {
      if (find.textContaining('tap the dice').evaluate().isNotEmpty) {
        for (final p in [1, 3]) {
          await tester.tap(find.byKey(ValueKey('panel-$p')),
              warnIfMissed: false);
        }
        rolls++;
      } else if (find.textContaining('pick a piece').evaluate().isNotEmpty) {
        for (var k = 0; k < 16; k++) {
          final piece = find.byKey(ValueKey('token-$k'));
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
