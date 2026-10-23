import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veriwork_mobile/app.dart';
import 'package:veriwork_mobile/core/providers.dart';
import 'package:veriwork_mobile/core/storage/session_store.dart';
import 'package:veriwork_mobile/features/landing/welcome_screen.dart';

void main() {
  testWidgets('a signed-out launch lands on the welcome screen', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer(overrides: [sessionStoreProvider.overrideWithValue(SessionStore())]);
    addTearDown(container.dispose);

    await container.read(authProvider).bootstrap();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const VeriWorkApp()));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
