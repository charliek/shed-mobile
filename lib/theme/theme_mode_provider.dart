import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// The app's light/dark mode, persisted across launches via the cross-platform
/// [secretStoreProvider] (OS keystore on mobile, a 0600 file on desktop — the
/// same KV the rest of the app uses, so no extra dependency). Defaults to
/// [ThemeMode.system] until the stored value loads.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// Non-secret UI preference; namespaced so it can't collide with key material.
  static const storeKey = 'ui.themeMode';

  /// Set once the user picks a mode this session, so a slow initial load can't
  /// overwrite a choice they made before storage answered.
  bool _userChose = false;

  @override
  ThemeMode build() {
    // Fire-and-forget load; updates [state] once storage answers. Starting from
    // `system` means first paint respects the OS until the stored choice lands.
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final raw = await ref.read(secretStoreProvider).read(storeKey);
    // Bail if the provider was disposed mid-read (no setting state after
    // dispose), or the user already chose (don't clobber their pick).
    if (!ref.mounted || _userChose) return;
    final mode = _decode(raw);
    if (mode != null) state = mode;
  }

  /// Set an explicit mode and persist it.
  Future<void> set(ThemeMode mode) async {
    _userChose = true;
    state = mode;
    await ref.read(secretStoreProvider).write(storeKey, mode.name);
  }

  /// Flip to the opposite of what's currently showing. [current] is the
  /// effective brightness (`Theme.of(context).brightness`), so a tap from
  /// `system` resolves against what the user actually sees.
  Future<void> toggle(Brightness current) =>
      set(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  // Maps a stored `ThemeMode.name` back to the value; null for an unknown or
  // null string (uses the enum's own names — no second list to drift).
  static ThemeMode? _decode(String? raw) =>
      raw == null ? null : ThemeMode.values.asNameMap()[raw];
}
