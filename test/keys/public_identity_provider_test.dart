import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/keys/key_manager.dart';
import 'package:shed_mobile/providers.dart';

void main() {
  // Tests run on the host VM, so publicIdentityProvider takes the desktop branch
  // (reads identitiesProvider). We override that with a fake keypair.
  test('exposes only public material derived from the identity', () async {
    final g = KeyManager.generateEd25519(comment: 'prov@test');
    final kp = SSHKeyPair.fromPem(g.privatePem);
    final container = ProviderContainer(
      overrides: [identitiesProvider.overrideWith((ref) async => kp)],
    );
    addTearDown(container.dispose);

    final id = await container.read(publicIdentityProvider.future);
    expect(id, isA<PublicIdentity>());
    expect(id!.fingerprint, g.fingerprint);
    // Public-only: an authorized_keys line, never the PEM.
    expect(id.authorizedKey, startsWith('ssh-ed25519 '));
    expect(id.authorizedKey, isNot(contains('PRIVATE KEY')));
  });

  test('is null when no identity is available', () async {
    final container = ProviderContainer(
      overrides: [
        identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(publicIdentityProvider.future), isNull);
  });
}
