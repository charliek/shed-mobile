import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/onboarding/onboarding_screen.dart';
import 'features/servers/server_list_screen.dart';
import 'marionette/marionette_init.dart';
import 'providers.dart';

void main() {
  if (kDebugMode) initMarionetteDriver();
  runApp(const ProviderScope(child: ShedMobileApp()));
}

class ShedMobileApp extends StatelessWidget {
  const ShedMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const _Home(),
    );
  }
}

/// On mobile, route to keygen onboarding until a device key exists; then (and
/// always on desktop) show the server list.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsOnboarding = ref.watch(needsOnboardingProvider);
    return needsOnboarding.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // On error, fall through to the server list, which surfaces the real key
      // error when a connection is attempted.
      error: (_, _) => const ServerListScreen(),
      data: (needs) =>
          needs ? const OnboardingScreen() : const ServerListScreen(),
    );
  }
}
