import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/app.dart';
import 'package:recycle_vision/core/formatters.dart';
import 'package:recycle_vision/offline/offline_backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('offline mode boots the app with demo data and no backend',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: offlineOverrides(),
        child: const RecycleVisionApp(),
      ),
    );

    // Splash frame.
    await tester.pump();
    // Post-frame session bootstrap resolves asynchronously.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('DEMO'), findsOneWidget);
    expect(
      find.text('${greetingFor(DateTime.now())}, Demo!'),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
  });
}