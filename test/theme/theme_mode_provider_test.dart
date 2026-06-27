import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/storage/secret_store.dart';
import 'package:shed_mobile/theme/theme_mode_provider.dart';

/// Let the fire-and-forget `_load()` microtasks settle.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  ProviderContainer containerWith(SecretStore store) {
    final c = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('defaults to system when nothing is stored', () async {
    final c = containerWith(InMemorySecretStore());
    expect(c.read(themeModeProvider), ThemeMode.system);
    await _settle();
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('loads the persisted mode on build', () async {
    final store = InMemorySecretStore();
    await store.write(ThemeModeNotifier.storeKey, 'dark');
    final c = containerWith(store);
    // Starts at system, then settles to the stored value.
    expect(c.read(themeModeProvider), ThemeMode.system);
    await _settle();
    expect(c.read(themeModeProvider), ThemeMode.dark);
  });

  test('an unrecognized stored value is ignored', () async {
    final store = InMemorySecretStore();
    await store.write(ThemeModeNotifier.storeKey, 'chartreuse');
    final c = containerWith(store);
    await _settle();
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('set persists and updates state', () async {
    final store = InMemorySecretStore();
    final c = containerWith(store);
    await c.read(themeModeProvider.notifier).set(ThemeMode.light);
    expect(c.read(themeModeProvider), ThemeMode.light);
    expect(await store.read(ThemeModeNotifier.storeKey), 'light');
  });

  test('a choice made during the initial load wins over storage', () async {
    // _StuckRead always reports an old persisted 'dark'; the user picks light
    // before that read resolves. The pick must survive.
    final c = containerWith(_StuckRead());
    await c.read(themeModeProvider.notifier).set(ThemeMode.light);
    await _settle();
    expect(c.read(themeModeProvider), ThemeMode.light);
  });

  test('disposing during the initial load does not throw', () async {
    final store = InMemorySecretStore();
    await store.write(ThemeModeNotifier.storeKey, 'dark');
    final c = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(store)],
    );
    c.read(themeModeProvider); // kicks off the async load
    c.dispose(); // ...then disposes before it resolves
    await _settle(); // load completes post-dispose; must not set state / throw
  });

  test('toggle flips against the currently-shown brightness', () async {
    final store = InMemorySecretStore();
    final c = containerWith(store);
    final n = c.read(themeModeProvider.notifier);

    await n.toggle(Brightness.dark); // showing dark -> go light
    expect(c.read(themeModeProvider), ThemeMode.light);
    expect(await store.read(ThemeModeNotifier.storeKey), 'light');

    await n.toggle(Brightness.light); // showing light -> go dark
    expect(c.read(themeModeProvider), ThemeMode.dark);
    expect(await store.read(ThemeModeNotifier.storeKey), 'dark');
  });
}

/// A store whose read always reports a stale persisted 'dark' (and ignores
/// writes) — used to prove a same-session user choice isn't clobbered by the
/// load that resolves afterward.
class _StuckRead implements SecretStore {
  @override
  Future<String?> read(String key) async => 'dark';
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}
