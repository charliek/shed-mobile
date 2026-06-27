// M0 end-to-end (tier c): against a REAL shed. Mints a control token over SSH
// (_bootstrap, host-key-pinned), learns the TLS pin + https port from the
// bundle, then lists sheds over pinned TLS with the bearer token. NOT run in CI.
//
//   dart run tool/e2e_list.dart [user@host:port]   (default shed-mobile-test@localhost:2222)
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/control/token_bundle.dart';
import 'package:shed_mobile/keys/key_manager.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/servers/server_target.dart';
import 'package:shed_mobile/shed/shed_client.dart';
import 'package:shed_mobile/ssh/bootstrap_service.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';

Future<void> main(List<String> args) async {
  final spec = args.isNotEmpty ? args[0] : 'shed-mobile-test@localhost:2222';
  final at = spec.split('@');
  final name = at[0];
  final hp = at[1].split(':');
  final host = hp[0];
  final sshPort = hp.length > 1 ? int.parse(hp[1]) : 22;

  final bootstrap = BootstrapService(
    KeyManager.defaultDesktopKey(),
    HostKeyStore(), // TOFU for the spike
  );

  print('Minting over SSH (_bootstrap@$host:$sshPort control shed-mobile)...');
  final pre = ServerTarget(
    name: name,
    host: host,
    sshPort: sshPort,
    secure: true,
    baseUrl: 'https://$host',
  );
  final bundle = await bootstrap.mint(pre);
  print(
    '  pin=${bundle.tlsCertFingerprint}  https_port=${bundle.httpsPort}  '
    'token=${bundle.token.length}ch  expires=${bundle.expiresAt.toIso8601String()}',
  );

  final target = ServerTarget(
    name: name,
    host: host,
    sshPort: sshPort,
    secure: true,
    baseUrl: 'https://$host:${bundle.httpsPort}',
    tlsCertFingerprint: bundle.tlsCertFingerprint,
    controlToken: bundle.token,
    controlTokenExpiresAt: bundle.expiresAt,
  );
  final http = PinnedHttpClient(
    host: host,
    port: bundle.httpsPort,
    fingerprint: bundle.tlsCertFingerprint,
  );
  final tokens = ControlTokenProvider(
    name,
    resolve: () async => target,
    minter: (t) async {
      final b = await bootstrap.mint(t, expectedPin: t.tlsCertFingerprint);
      return MintedToken(b.token, b.expiresAt);
    },
  );

  print('Listing sheds over pinned TLS (${target.baseUrl}/api/sheds)...');
  final sheds = await ShedClient(http, tokens).listSheds();
  print(
    '  ${sheds.length} shed(s): '
    '${sheds.map((s) => '${s.name}=${s.status}').join(', ')}',
  );
  http.close();
  print('\nE2E PASS');
  exit(0);
}
