import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/servers/server_list_screen.dart';
import 'marionette/marionette_init.dart';

void main() {
  if (kDebugMode) initMarionetteDriver();
  runApp(const ProviderScope(child: ShedMobileApp()));
}

class ShedMobileApp extends StatelessWidget {
  const ShedMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shed-mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const ServerListScreen(),
    );
  }
}
