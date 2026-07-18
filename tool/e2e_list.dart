// M0 end-to-end (tier c): against a REAL shed. Mints a control token over SSH
// (_bootstrap, host-key-pinned), learns the TLS pin + https port from the
// bundle, then lists sheds over pinned TLS via the FRB `BridgeClient` (shed-core).
// NOT run in CI.
//
//   dart run tool/e2e_list.dart [user@host:port]   (default shed-mobile-test@localhost:2222)
//
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:shed_mobile/keys/key_manager.dart';
import 'package:shed_mobile/servers/server_target.dart';
import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/src/rust/api/mint.dart';
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

  // Register the app-scoped mint sink BEFORE constructing the client: a
  // BridgeClient token refresh emits a need-token request, we run the same SSH
  // mint over dartssh2 and submit the RAW stdout (parsed in Rust).
  final sub = setMintSink().listen((req) async {
    try {
      final raw = await bootstrap.mintRaw(pre);
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

  print('Minting over SSH (_bootstrap@$host:$sshPort control shed-mobile)...');
  final bundle = await bootstrap.mint(pre);
  print(
    '  pin=${bundle.tlsCertFingerprint}  https_port=${bundle.httpsPort}  '
    'token=${bundle.token.length}ch  expires=${bundle.expiresAt.toIso8601String()}',
  );

  final baseUrl = 'https://$host:${bundle.httpsPort}';
  print('Listing sheds over pinned TLS ($baseUrl/api/sheds)...');
  final client = await BridgeClient.connect(
    baseUrl: baseUrl,
    serverName: name,
    host: host,
    sshPort: sshPort,
    tlsPin: bundle.tlsCertFingerprint,
    seedToken: bundle.token,
    seedExpiryUnix: BigInt.from(
      bundle.expiresAt.millisecondsSinceEpoch ~/ 1000,
    ),
  );
  final sheds = await client.listSheds();
  print(
    '  ${sheds.length} shed(s): '
    '${sheds.map((s) => '${s.name}=${s.status.name}').join(', ')}',
  );
  client.dispose();
  await sub.cancel();
  shutdownMintSink();
  print('\nE2E PASS');
  exit(0);
}
