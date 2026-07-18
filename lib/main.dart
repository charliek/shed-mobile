// The original content is temporarily commented out to allow generating a self-contained demo - feel free to uncomment later.

// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:stridelabs_drive/stridelabs_drive.dart';
// 
// import 'app/app_shell.dart';
// import 'features/onboarding/onboarding_screen.dart';
// import 'providers.dart';
// import 'theme/shed_theme.dart';
// import 'theme/theme_mode_provider.dart';
// 
// void main() {
//   if (kDebugMode) initMarionetteDriver();
//   runApp(const ProviderScope(child: ShedMobileApp()));
// }
// 
// class ShedMobileApp extends ConsumerWidget {
//   const ShedMobileApp({super.key});
// 
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return MaterialApp(
//       title: 'Shed',
//       debugShowCheckedModeBanner: false,
//       theme: shedLightTheme,
//       darkTheme: shedDarkTheme,
//       themeMode: ref.watch(themeModeProvider),
//       home: const _Home(),
//     );
//   }
// }
// 
// /// On mobile, route to keygen onboarding until a device key exists; then (and
// /// always on desktop) show the server list.
// class _Home extends ConsumerWidget {
//   const _Home();
// 
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final needsOnboarding = ref.watch(needsOnboardingProvider);
//     return needsOnboarding.when(
//       loading: () =>
//           const Scaffold(body: Center(child: CircularProgressIndicator())),
//       // On error, fall through to the app shell, which surfaces the real key
//       // error when a connection is attempted.
//       error: (_, _) => const AppShell(),
//       data: (needs) => needs ? const OnboardingScreen() : const AppShell(),
//     );
//   }
// }
// 

import 'package:flutter/material.dart';
import 'package:shed_mobile/src/rust/api/simple.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_rust_bridge quickstart')),
        body: Center(
          child: Text(
              'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom")}`'),
        ),
      ),
    );
  }
}
