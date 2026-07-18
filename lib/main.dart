import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import 'app/app_shell.dart';
import 'bridge/mint_sink.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'providers.dart';
import 'src/rust/frb_generated.dart';
import 'theme/shed_theme.dart';
import 'theme/theme_mode_provider.dart';

Future<void> main() async {
  // Establish the binding FIRST. In debug, the Marionette driver installs its
  // own WidgetsFlutterBinding subclass, so it must run before any other
  // `ensureInitialized` (else it asserts "Binding is already initialized").
  if (kDebugMode) {
    initMarionetteDriver();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  // Load the Rust core (shed-core over FRB) before anything touches the bridge.
  await RustLib.init();

  // One app-scoped container shared by the widget tree AND the app-scoped mint
  // sink. The mint listener MUST be registered before any BridgeClient is built
  // (listener-before-client, plan §3.2) — so wire it here, then hand the SAME
  // container to the widget tree via UncontrolledProviderScope.
  final container = ProviderContainer();
  final mintSink = MintSink.register(container);
  WidgetsBinding.instance.addObserver(_MintSinkLifecycle(mintSink));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ShedMobileApp(),
    ),
  );
}

/// Tears the mint sink down when the app process is detached (Rust-side shutdown
/// + Dart unsubscribe). The sink is otherwise app-lifetime (one listener).
class _MintSinkLifecycle with WidgetsBindingObserver {
  _MintSinkLifecycle(this._sink);

  final MintSink _sink;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Fire-and-forget: the process is going away; best-effort clean teardown.
      _sink.dispose();
    }
  }
}

class ShedMobileApp extends ConsumerWidget {
  const ShedMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Shed',
      debugShowCheckedModeBanner: false,
      theme: shedLightTheme,
      darkTheme: shedDarkTheme,
      themeMode: ref.watch(themeModeProvider),
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
      // On error, fall through to the app shell, which surfaces the real key
      // error when a connection is attempted.
      error: (_, _) => const AppShell(),
      data: (needs) => needs ? const OnboardingScreen() : const AppShell(),
    );
  }
}
