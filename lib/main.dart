import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/storage/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  final container = ProviderContainer(
    overrides: [sessionStoreProvider.overrideWithValue(SessionStore())],
  );
  // Restore the stored session before the first guard runs; the splash screen
  // covers the gap.
  container.read(authProvider).bootstrap();

  runApp(UncontrolledProviderScope(container: container, child: const VeriWorkApp()));
}
