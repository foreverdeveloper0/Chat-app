import 'dart:io';

import 'package:elite_play_ludo/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  final loader = FontLoader('Fredoka');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Fredoka-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('home page renders and tabs switch', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();

    expect(find.text('ELITE PLAY BD'), findsOneWidget);
    expect(find.text('OUR GAMES'), findsOneWidget);
    // The carousel opens on the Ludo banner; every game has a logo tile.
    expect(find.byKey(const ValueKey('banner-ludo')), findsOneWidget);
    for (final key in ['ludo', 'snake', 'carrom', 'ghuti', 'racing', 'fruit', 'poker']) {
      expect(find.byKey(ValueKey('game-$key')), findsOneWidget);
    }
    expect(find.text('ALL FEATURES'), findsOneWidget);
    expect(find.textContaining('Wallet'), findsNothing);
    expect(tester.takeException(), isNull);

    // The rest of the features sit behind one button.
    await tester.ensureVisible(find.text('ALL FEATURES'));
    await tester.pump();
    await tester.tap(find.text('ALL FEATURES'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('All features'), findsOneWidget);
    expect(find.text('LEADERBOARD'), findsOneWidget);
    expect(find.text('LIVE\nSUPPORT'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Games'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('OUR GAMES'), findsNothing);

    // Tear down so the live demo board's timers end with its controller.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
