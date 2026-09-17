import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecoloop/app.dart';
import 'package:ecoloop/core/api_client.dart';
import 'package:ecoloop/providers/providers.dart';
import 'package:shared/shared.dart';

import 'helpers.dart';

/// Backend-unreachable auth: a stored token exists but the server is down.
/// This MUST surface an honest error — never a silent offline/demo fallback.
class _UnreachableAuthRepository extends FakeAuthRepository {
  @override
  Future<String?> restoreToken() async => 'stored-token';

  @override
  Future<AppUser> fetchMe() async {
    throw ApiException('Connection refused');
  }
}

void main() {
  testWidgets('backend unreachable surfaces the error screen, no demo fallback',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_UnreachableAuthRepository()),
        ],
        child: const RecycleVisionApp(),
      ),
    );

    // Splash frame, then bootstrap resolves to SessionStatus.error.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Cannot connect'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The app must NOT silently drop into a demo/offline home shell.
    expect(find.text('Home'), findsNothing);
    expect(find.text('DEMO'), findsNothing);
  });
}
