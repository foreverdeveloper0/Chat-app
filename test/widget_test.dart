import 'dart:io';

import 'package:elite_play_ludo/main.dart';
import 'package:flutter/services.dart';
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

    expect(find.text('LUDO'), findsWidgets);
    expect(find.text('Tournament'), findsOneWidget);
    expect(find.text('Play\nOnline'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Friends'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('LUDO'), findsNothing);
  });
}
