import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/onboarding/role.dart';
import 'package:sts/onboarding/sport.dart';

void main() {
  String? chosen;

  Future<void> pumpScreen(WidgetTester tester) async {
    chosen = null;
    await tester.pumpWidget(MaterialApp(
      home: RoleScreen(
        sport: Sport.pickleball,
        onScore: (_) => chosen = 'score',
        onStream: (_) => chosen = 'stream',
      ),
    ));
  }

  testWidgets('shows the sport and both roles', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Pickleball'), findsOneWidget);
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('Stream'), findsOneWidget);
  });

  testWidgets('tapping Score chooses scoring', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Score'));
    expect(chosen, 'score');
  });

  testWidgets('tapping Stream chooses streaming', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Stream'));
    expect(chosen, 'stream');
  });

  testWidgets('options are wide rectangles, one under the other', (tester) async {
    await pumpScreen(tester);
    for (final card in find.byType(Card).evaluate()) {
      final size = card.size!;
      expect(size.width, greaterThan(size.height));
    }
    expect(tester.getTopLeft(find.text('Stream')).dy, greaterThan(tester.getTopLeft(find.text('Score')).dy));
  });
}
