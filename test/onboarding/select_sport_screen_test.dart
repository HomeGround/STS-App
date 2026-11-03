import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/onboarding/select_sport_screen.dart';
import 'package:sts/onboarding/sport.dart';

void main() {
  Sport? selected;

  Future<void> pumpScreen(WidgetTester tester) async {
    selected = null;
    await tester.pumpWidget(MaterialApp(
      home: SelectSportScreen(onSportSelected: (_, sport) => selected = sport),
    ));
  }

  testWidgets('lists every sport', (tester) async {
    await pumpScreen(tester);
    for (final sport in Sport.values) {
      expect(find.text(sport.label), findsOneWidget);
    }
  });

  testWidgets('tapping pickleball selects it', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Pickleball'));
    expect(selected, Sport.pickleball);
  });

  testWidgets('sports that are not available yet cannot be selected', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Tennis'));
    expect(selected, isNull);
    expect(find.text('Coming soon'), findsNWidgets(3));
  });

  testWidgets('search filters sports by name, ignoring case', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(SearchBar), 'TENN');
    await tester.pump();
    expect(find.text('Tennis'), findsOneWidget);
    expect(find.text('Table Tennis'), findsOneWidget);
    expect(find.text('Pickleball'), findsNothing);
    expect(find.text('Badminton'), findsNothing);
  });
}
