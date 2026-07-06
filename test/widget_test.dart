import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic test to ensure app builds
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LanguageProvider(),
        child: const TransifyApp(),
      ),
    );
    
    // Drain splash screen Future.delayed timer
    await tester.pump(const Duration(seconds: 4));
  });
}
