// M0 end-to-end (tier c): against a REAL shed. Runs the Rust add-server PREVIEW
// over SSH (_bootstrap, host-key TOFU) to learn the auth mode + TLS pin + https
// port, then lists sheds over pinned TLS via the FRB `BridgeClient` (shed-core).
// Works against a token-mode AND an mtls-mode server: the preview always sends a
// CSR, a token-mode server ignores it, and an mtls server issues a certificate
// that the preview drops (the client below mints its own).
// NOT run in CI.
//
//   dart run tool/e2e_list.dart [user@host:port]   (default shed-mobile-test@localhost:2222)
//
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:shed_mobile/keys/key_manager.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/servers/server_target.dart';
import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/src/rust/api/mint.dart';
import 'package:shed_mobile/src/rust/api/preview.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';
import 'package:shed_mobile/ssh/bootstrap_service.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';

Future<void> main(List<String> args) async {
  final spec = args.isNotEmpty ? args[0] : 'shed-mobile-test@localhost:2222';
  final at = spec.split('@');
  final name = at[0];
  final hp = at[1].split(':');
  final host = hp[0];
  final sshPort = hp.length > 1 ? int.parse(hp[1]) : 22;

  await RustLib.init();

  final bootstrap = BootstrapService(
    KeyManager.defaultDesktopKey(),
    HostKeyStore(), // TOFU for the probe
  );
  final pre = ServerTarget(
    name: name,
    host: host,
    sshPort: sshPort,
    secure: true,
    baseUrl: 'https://$host',
  );

  // Register the app-scoped mint sink BEFORE anything that mints: both the
  // add-server preview and a BridgeClient credential refresh emit a request
  // here, we run the SSH round-trip over dartssh2 — appending the request's
  // extra args (an mtls `csr=…`) VERBATIM — and submit the RAW stdout back for
  // Rust to parse.
  final sub = setMintSink().listen((req) async {
    try {
      final raw = await bootstrap.mintRaw(pre, extraArgs: req.extraArgs);
      await submitMintResult(
        requestId: req.requestId,
        outcome: BridgeMintOutcome.success(rawStdout: raw),
      );
    } catch (_) {
      await submitMintResult(
        requestId: req.requestId,
        outcome: const BridgeMintOutcome.failure(code: 'MINT_FAILED'),
      );
    }
  });

  // Persist the learned mode the way the app does (here: just print it).
  final credentials = setCredentialEventSink().listen(
    (e) => print('  event: $e'),
  );

  print(
    'Previewing over SSH (_bootstrap@$host:$sshPort control shed-mobile)...',
  );
  final preview = await previewAddServer(
    host: host,
    sshPort: sshPort,
    timeoutMs: BigInt.from(20000),
  );
  final mtls = normalizeAuthMode(preview.authMode) == kAuthModeMtls;
  print(
    '  auth=${preview.authMode}  pin=${preview.tlsCertFingerprint}  '
    'https_port=${preview.httpsPort}  '
    'seed=${mtls ? 'none (mtls)' : '${preview.token?.length ?? 0}ch'}',
  );

  final baseUrl = 'https://$host:${preview.httpsPort}';
  print('Listing sheds over pinned TLS ($baseUrl/api/sheds)...');
  final expiry = preview.tokenExpiresAtUnix;
  final client = await BridgeClient.connect(
    baseUrl: baseUrl,
    serverName: name,
    host: host,
    sshPort: sshPort,
    tlsPin: preview.tlsCertFingerprint,
    authMode: preview.authMode,
    seedToken: mtls ? null : preview.token,
    seedExpiryUnix: mtls ? null : expiry,
  );
  final sheds = await client.listSheds();
  print(
    '  ${sheds.length} shed(s): '
    '${sheds.map((s) => '${s.name}=${s.status.name}').join(', ')}',
  );
  client.dispose();
  await sub.cancel();
  shutdownMintSink();
  await credentials.cancel();
  shutdownCredentialEventSink();
  print('\nE2E PASS');
  exit(0);
}
