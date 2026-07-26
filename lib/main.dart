import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import 'app/app_shell.dart';
import 'bridge/credential_sink.dart';
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

  // One app-scoped container shared by the widget tree AND both app-scoped
  // bridge listeners. BOTH MUST be registered before any BridgeClient is built
  // (listener-before-client, plan §3.2) — so wire them here, then hand the SAME
  // container to the widget tree via UncontrolledProviderScope.
  //
  // Credentials first: a mint can only be emitted once the mint sink exists, and
  // the credential event it produces has nowhere to go if that listener isn't up
  // yet (Rust drops events with no sink), which would silently lose the learned
  // auth mode for that launch.
  final container = ProviderContainer();
  final credentialSink = CredentialSink.register(container);
  final mintSink = MintSink.register(container);
  WidgetsBinding.instance.addObserver(
    _BridgeSinkLifecycle(mintSink, credentialSink),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ShedMobileApp(),
    ),
  );
}

/// Tears both bridge sinks down when the app process is detached (Rust-side
/// shutdown + Dart unsubscribe). They are otherwise app-lifetime (one listener
/// each). Mints first: resolving every parked mint can produce a final credential
/// event, which the credential listener should still be up to persist.
class _BridgeSinkLifecycle with WidgetsBindingObserver {
  _BridgeSinkLifecycle(this._mint, this._credentials);

  final MintSink _mint;
  final CredentialSink _credentials;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Fire-and-forget: the process is going away; best-effort clean teardown.
      _mint.dispose().whenComplete(_credentials.dispose);
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
