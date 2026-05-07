import 'package:flutter_test/flutter_test.dart';

import 'package:leotok/app.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LeoTokApp());
    // Basic smoke test — the home screen should render without crashing
    expect(find.byType(LeoTokApp), findsOneWidget);
  });
}
