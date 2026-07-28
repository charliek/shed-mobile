import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/servers/add_server_flow.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/servers/server_store.dart';
import 'package:shed_mobile/src/rust/api/preview.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/storage/secret_store.dart';

final _pin = 'sha256:${'a' * 64}';

/// The Rust preview, faked: records what it was asked and answers with a DTO of
/// the shape `preview_add_server` produces for that mode.
class _FakePreview {
  _FakePreview(this.dto);

  final BridgeAddServerPreview dto;
  String? host;
  int? sshPort;
  BigInt? timeoutMs;

  Future<BridgeAddServerPreview> call({
    required String host,
    required int sshPort,
    required BigInt timeoutMs,
  }) async {
    this.host = host;
    this.sshPort = sshPort;
    this.timeoutMs = timeoutMs;
    return dto;
  }
}

BridgeAddServerPreview _tokenDto() => BridgeAddServerPreview(
  authMode: 'token',
  tlsCertFingerprint: _pin,
  httpsPort: 8443,
  token: 'seed-tok',
  tokenExpiresAtUnix: BigInt.from(1893456000), // 2030-01-01T00:00:00Z
);

BridgeAddServerPreview _mtlsDto() => BridgeAddServerPreview(
  authMode: 'mtls',
  tlsCertFingerprint: _pin,
  httpsPort: 8443,
);

({AddServerFlow flow, ServerStore store, HostKeyStore keys}) _flow(
  BridgeAddServerPreview dto, {
  String? learnedHostKey = 'SHA256:learned',
}) {
  final store = ServerStore(InMemorySecretStore());
  final keys = HostKeyStore();
  if (learnedHostKey != null) {
    // What the preview's SSH leg pinned on the way through (TOFU).
    keys.setPin('mini3.example:2222', learnedHostKey);
  }
  return (
    flow: AddServerFlow(store, keys, previewFn: _FakePreview(dto).call),
    store: store,
    keys: keys,
  );
}

Future<ServerPreview> _preview(AddServerFlow flow) =>
    flow.preview(host: 'mini3.example', sshPort: 2222);

void main() {
  test('bounds the preview above the 15s SSH leg it drives', () async {
    final fake = _FakePreview(_tokenDto());
    final flow = AddServerFlow(
      ServerStore(InMemorySecretStore()),
      HostKeyStore(),
      previewFn: fake.call,
    );
    await _preview(flow);
    expect(fake.host, 'mini3.example');
    expect(fake.sshPort, 2222);
    expect(fake.timeoutMs, BigInt.from(20000));
    expect(kAddServerPreviewTimeout, const Duration(seconds: 20));
  });

  test('token mode persists the seed exactly as before (§7 P7)', () async {
    final f = _flow(_tokenDto());
    final preview = await _preview(f.flow);
    expect(preview.authMode, kAuthModeToken);
    expect(preview.apiUrl, 'https://mini3.example:8443');
    expect(preview.hostKeyFingerprint, 'SHA256:learned');

    final rec = await f.flow.commit(name: 'mini3', preview: preview);
    expect(rec.authMode, kAuthModeToken);
    // The regression this guards: without the persisted seed EVERY token-mode
    // cold launch would re-mint over SSH.
    expect(rec.controlToken, 'seed-tok');
    expect(rec.controlTokenExpiresAt, DateTime.utc(2030, 1, 1));
    expect((await f.store.get('mini3'))!.controlToken, 'seed-tok');
  });

  test('mtls mode persists the mode and NO credential material', () async {
    final f = _flow(_mtlsDto());
    final preview = await _preview(f.flow);
    expect(preview.authMode, kAuthModeMtls);
    expect(preview.token, isNull);

    final rec = await f.flow.commit(name: 'mini3', preview: preview);
    expect(rec.isMtls, isTrue);
    expect(rec.controlToken, isNull);
    expect(rec.controlTokenExpiresAt, isNull);

    final stored = (await f.store.get('mini3'))!.toJson();
    expect(stored['auth_mode'], 'mtls');
    expect(stored.containsKey('control_token'), isFalse);
  });

  test('an unknown/legacy mode from the wire lands as token', () async {
    // Rust normalizes, but the flow re-normalizes rather than trusting a string
    // it did not produce — the same fail-to-token rule as the record decode.
    final f = _flow(
      BridgeAddServerPreview(
        authMode: 'secure',
        tlsCertFingerprint: _pin,
        httpsPort: 8443,
        token: 't',
      ),
    );
    final rec = await f.flow.commit(
      name: 'mini3',
      preview: await _preview(f.flow),
    );
    expect(rec.authMode, kAuthModeToken);
  });

  test(
    'a host key the store never learned shows as unknown, not empty',
    () async {
      final f = _flow(_tokenDto(), learnedHostKey: null);
      expect((await _preview(f.flow)).hostKeyFingerprint, '(unknown)');
    },
  );
}
