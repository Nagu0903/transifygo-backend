import 'package:flutter_test/flutter_test.dart';
import 'package:transify_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic test to ensure app builds
    await tester.pumpWidget(const TransifyApp());
  });
}
