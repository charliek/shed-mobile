import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/bridge/mint_sink.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/src/rust/api/mint.dart';
import 'package:shed_mobile/storage/secret_store.dart';

const _rec = ServerRecord(
  name: 'mini3',
  host: 'mini3.example',
  sshPort: 2222,
  apiUrl: 'https://mini3.example:8443',
  tlsCertFingerprint: 'sha256:aa',
  hostKeyPin: 'SHA256:pinned-key',
);

BridgeMintRequest _req(
  BridgeMintPurpose purpose, {
  String host = 'mini3.example',
  int sshPort = 2222,
  List<String> extraArgs = const [],
}) => BridgeMintRequest(
  requestId: 'r1',
  purpose: purpose,
  host: host,
  sshPort: sshPort,
  baseUrl: 'https://$host',
  extraArgs: extraArgs,
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(InMemorySecretStore())],
    );
    addTearDown(container.dispose);
  });

  test('a control mint uses the SAVED record’s pinned host key', () async {
    await container.read(serverStoreProvider).add(_rec);
    final trust = await resolveMintTrust(
      container,
      _req(BridgeMintPurpose.controlMint),
    );
    expect(trust.serverName, 'mini3');
    expect(trust.hostKeys.tofu, isFalse);
    expect(trust.hostKeys.pinFor('mini3.example:2222'), 'SHA256:pinned-key');
  });

  test('a control mint for an unknown transport identity fails', () async {
    await container.read(serverStoreProvider).add(_rec);
    await expectLater(
      resolveMintTrust(
        container,
        _req(BridgeMintPurpose.controlMint, sshPort: 2200),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('an add-server preview uses the shared TOFU store', () async {
    // First contact: there is deliberately NO saved record — that is what the
    // preview exists to produce — so a pinned lookup would fail every add.
    final trust = await resolveMintTrust(
      container,
      _req(BridgeMintPurpose.addServerPreview, host: 'new.example'),
    );
    expect(trust.hostKeys.tofu, isTrue);
    // The SAME instance the add-server flow reads the learned fingerprint back
    // from, so the user confirms the key this mint actually saw.
    expect(
      identical(trust.hostKeys, container.read(addHostKeysProvider)),
      isTrue,
    );
  });

  test(
    'a preview never falls back to a saved record for the same host',
    () async {
      await container.read(serverStoreProvider).add(_rec);
      final trust = await resolveMintTrust(
        container,
        _req(BridgeMintPurpose.addServerPreview),
      );
      expect(trust.hostKeys.tofu, isTrue);
      expect(trust.hostKeys.pinFor('mini3.example:2222'), isNull);
    },
  );
}
